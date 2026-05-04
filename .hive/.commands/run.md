# /run — Batch Ticket Pipeline
<!-- tokens: ~2000 | loads: orchestrator.md -->

**Agent:** Orchestrator (read `.hive/.agents/orchestrator.md`)
**Usage:** `/run <ticket-id> [<ticket-id>...] [--dry-run] [--from <phase>] [--sprint <name|"current">]`
**Interactive:** No — forces `autonomous` execution for the entire batch

Processes a list of tickets sequentially using the full `/ship` pipeline.
Designed for unattended server execution — no checkpoints, no prompts.
When `--sprint` is given, ticket IDs are loaded from the ticket tool automatically.

---

## Execution model — two entry points

### 1. Direct (in-session): `/run PAY-42 PAY-43`
Typed directly in an AI tool. One AI session processes all tickets inline.
Good for small batches (2–5 tickets) where you're present to monitor.
The orchestrator reads `/ship` for each ticket and runs all phases within the same context window.

### 2. Shell (server/overnight): `hive run PAY-42 PAY-43`
Calls `hive-run.sh`, which runs **one separate AI session per ticket**:
```
hive run PAY-42 PAY-43
  └─ claude --output-format stream-json -p "/ship PAY-42"   → merge PR → log cost
  └─ claude --output-format stream-json -p "/ship PAY-43"   → merge PR → log cost
```
Each ticket gets a fresh context window. Cost and duration are captured from the AI CLI's
JSON output and written to `.hive/events.jsonl`. If interrupted mid-batch, use
`hive run --resume BATCH_ID` to continue from the first incomplete ticket.

**For all overnight / server / CI use, always use the shell entry point (`hive run`).**

---

---

## Process

### Step 0: Read configuration

Read `.hive/AGENTS.local.md`:
- `autonomy.level` — noted but overridden to `autonomous` for this batch
- `notifications.webhook` — used for start/complete/failure notifications
- `circuit_breaker.*` — respected; a trip stops **that ticket**, not the entire batch

### Step 1: Parse arguments

```
/run PAY-42 PAY-43 PAY-44
/run PAY-42 PAY-43 --dry-run          # plan only, no files written
/run PAY-42 --from tdd                # start each ticket from a specific phase
/run --file .hive/sessions/batch.txt  # read ticket list from file (one per line)
/run --sprint current                 # all actionable tickets in the active sprint
/run --sprint "Sprint 2"             # all actionable tickets in a named sprint
```

Extract:
- `tickets[]` — list of explicit ticket IDs (may be empty if `--sprint` is used)
- `sprint` — sprint name or `"current"` (optional)
- `dry_run` — if true, print what would be done without writing
- `from_phase` — optional phase to start each ticket from

**If `--sprint` is given**, call `ticket_list_sprint(sprint)` via hive-tickets MCP to populate `tickets[]`. Filter to only actionable statuses — exclude `done`, `closed`, `cancelled`. If the resolved list is empty, abort:
```
No actionable tickets in sprint "{sprint}". All done — consider running /sprint-close.
```

### Step 2: Pre-flight

For each ticket in `tickets[]`:
- Confirm it's accessible via MCP or `.hive/specs/TICKETS.md`
- If not found: log as SKIP, continue

Check `.hive/specs/SPEC.md` exists and is ≤ 14 days old.
If missing or stale: warn but continue.

Write batch session file to `.hive/sessions/batch_{timestamp}.json`:

```json
{
  "started_at": "{ISO timestamp}",
  "tickets": ["PAY-42", "PAY-43", "PAY-44"],
  "dry_run": false,
  "results": {}
}
```

Send start notification if `notifications.webhook` is configured:
```
bash .hive/scripts/hive-notify.sh \
  --event batch_start \
  --message "Batch started: {n} tickets — {ticket-list}" \
  --status info
```

### Step 3: Process each ticket

For each ticket, run the full `/ship` pipeline with `autonomy` forced to `autonomous`.

**BATCH MODE — zero tolerance for interactive pauses.** All `/ship` behaviors that would normally stop and ask are suppressed:

| Behavior in `/ship` | Batch override |
|---|---|
| Stage 1 checkpoint (enrichment review) | Auto-approved — log acceptance criteria and continue |
| Stage 4 checkpoint (implementation review) | Auto-approved when all verify checks pass |
| Any abort condition | Treated as a `circuit_breaker` trip — log reason, continue to next ticket |

Never generate a question, confirmation request, or interactive prompt during a batch. If something would normally require human input, log it as `circuit_breaker` and move on.

```
Processing {i}/{n}: {ticket-id}
  Branch: {branch}
  Size: {S|M|L}
  Phases: enrich → plan → tdd → implement → commit → PR
```

**If `/ship` splits a ticket (L/XL):**
- The `/ship` session returns a `ticket_split` event instead of `ticket_complete`
- Read the `sub_tickets` list from the event
- Insert sub-tickets **at the current position** in the batch queue (process them next, in order)
- Log the original ticket as `split` status in the batch session file:
  ```json
  {"status": "split", "sub_tickets": ["PAY-42a", "PAY-42b", "PAY-42c"]}
  ```
- Continue the batch with the first sub-ticket

**On success:**
- Log `{ticket-id}: ✓ completed` to batch session file
- Update `events.jsonl`:
  ```jsonl
  {"ts":"...","cmd":"run","ticket":"{id}","event":"ticket_complete","status":"ok","duration_s":<n>,"cost_usd":<n>}
  ```

**Critical — merge PR before starting the next ticket:**
After each successful `/ship`, verify that the PR was merged before branching for the next ticket.
If `auto_merge_pr: true` and the CI passes, `/commit` handles this automatically.
If CI is still pending when `/ship` completes, wait (up to 10 minutes) for CI to complete and merge.
Proceeding to the next ticket before merge causes branch divergence and merge conflicts.

**On circuit breaker trip:**
- Log `{ticket-id}: ✗ circuit_breaker — {reason}` to batch session file
- Update `events.jsonl`:
  ```jsonl
  {"ts":"...","cmd":"run","ticket":"{id}","event":"ticket_complete","status":"failed","detail":"{reason}","duration_s":<n>}
  ```
- Send failure notification:
  ```
  bash .hive/scripts/hive-notify.sh \
    --event circuit_breaker \
    --message "{ticket-id} stopped: {reason}. Resume: hive run --resume {batch-id}." \
    --status error
  ```
- **Continue with next ticket** — one failure does not abort the batch

**On any unhandled error:**
- Log error and continue

### Step 4: Summary

After all tickets are processed, output a summary table:

```
┌─────────────────────────────────────────────┐
│  Batch complete — {duration}                │
├─────────────┬──────────┬────────────────────┤
│ Ticket      │ Result   │ Notes              │
├─────────────┼──────────┼────────────────────┤
│ PAY-42      │ ✓        │ PR #87 opened      │
│ PAY-43      │ ✓        │ PR #88 opened      │
│ PAY-44      │ ✗        │ Circuit breaker:   │
│             │          │ test_retries > 3   │
└─────────────┴──────────┴────────────────────┘

Passed: 2/3   Failed: 1/3

To review failures: hive analytics --ticket PAY-44
To resume:          /resume PAY-44
```

Send completion notification:
```
bash .hive/scripts/hive-notify.sh \
  --event batch_complete \
  --message "Batch done: {passed}/{n} tickets completed. {failed} failures." \
  --status {success|warning}
```

Update batch session file with final results.

### Step 4.5: Sprint lifecycle (only when `--sprint` was used)

Read `sprint_lifecycle` from `.hive/AGENTS.local.md`.

**If `sprint_lifecycle.auto_close_on_batch_complete: true`** AND there were no circuit-breaker failures:

1. Call `sprint_close("active")` via hive-tickets MCP to close the sprint in the ticket tool.

2. If `sprint_lifecycle.tag_on_close: true`:
   ```bash
   git tag -a "sprint-{N}" -m "Sprint {N} complete — {passed}/{n} tickets"
   git push origin "sprint-{N}"
   ```

3. If `sprint_lifecycle.notify_on_close: true`:
   ```bash
   bash .hive/scripts/hive-notify.sh --event sprint_close \
     --message "Sprint {N} closed. {passed}/{n} tickets done." --status success
   ```

4. If `sprint_lifecycle.auto_open_next: true`:
   - Determine next sprint name by incrementing the sprint number (e.g. "Sprint 1" → "Sprint 2").
   - Call `sprint_open("{next-name}")` via hive-tickets MCP.
   - Run `/sync` to regenerate SPEC.md from the new sprint.
   - If `sprint_lifecycle.notify_on_open: true`:
     ```bash
     bash .hive/scripts/hive-notify.sh --event sprint_open \
       --message "Sprint {N+1} opened. Run /sprint-setup to select tickets." --status info
     ```

**If `sprint_lifecycle.auto_close_on_batch_complete: false`** (default) — skip the above and print:
```
Sprint not auto-closed (auto_close_on_batch_complete: false).
To close manually: /sprint-close
```

---

## Rules

- Autonomy is always `autonomous` in a batch — never ask for approval
- A circuit breaker on one ticket does **not** stop the batch
- `--dry-run` produces plans but writes no files and opens no PRs
- If SPEC.md is missing, the agent continues but notes reduced context quality
- Maximum batch size: 20 tickets per run (token budget protection)
- Always send a completion notification, even on full failure
