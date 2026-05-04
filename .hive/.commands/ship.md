# /ship — Ticket Implementation Pipeline
<!-- tokens: ~2800 | loads: orchestrator.md → analyst.md, architect.md, coder.md, tester.md, reviewer.md -->

**Agent:** Orchestrator (read `.hive/.agents/orchestrator.md`)
**Usage:** `/ship <ticket-id> [--auto] [--from <phase>] [--dry-run]`
**Autonomy checkpoints:** Governed by `autonomy.level` in `AGENTS.local.md` — overridden by `--auto`

Runs the full implementation pipeline for a single ticket.
Replaces running `/enrich → /plan-be → /plan-fe → /tdd → /dev-be → /dev-fe → /update-docs → /commit` separately.

**Prerequisite:** ticket must exist in the board and `.hive/specs/SPEC.md` must be current.

### Flags

| Flag | Effect |
|---|---|
| `--auto` | Session-scoped override: forces `autonomy=autonomous` + `auto_merge_pr=true` for this run only. Does NOT modify `AGENTS.local.md`. Outputs an execution plan before starting, then runs without prompts. |
| `--from <phase>` | Start from a specific phase (enrich, plan-be, plan-fe, tdd, dev-be, dev-fe, docs, commit). Useful to re-run a phase without starting over. |
| `--dry-run` | Enrich and plan only — no files written, no commits, no PR. Shows what would happen. |

### `--auto` execution plan

When `--auto` is passed, after Stage 1 (enrich + size check) and Stage 2 (plan), output a plan before any implementation begins:

```
Execution plan — {ticket-id}: {title}
  Size:        {S|M|L}
  Path:        {fast|full SDD}
  Autonomy:    autonomous (--auto override)
  Auto-merge:  enabled

  Phases:      {list of phases that will run}

  Files to modify:
    {layer}: {file-path} — {what changes}
    ...

  Tests to write: {N}
  Estimated PRs:  1

Proceeding in 3s… (Ctrl-C to abort)
```

Wait 3 seconds, then execute all remaining phases autonomously with no further prompts.

---

## Step 0: Check for interrupted session

Before reading any context, check `.hive/sessions/{ticket-id}_state.json`.

**If found:**
```
Found interrupted pipeline for {ticket-id}:
  Path:      {fast | full SDD}
  Branch:    {branch}
  Stopped:   {last_updated_at}
  Completed: {completed_phases}
  Next:      {next_phase}

Resume from {next_phase}? (Y/n)
```
- `supervised`: prompt user
- `balanced` / `autonomous`: resume automatically

If resuming → skip to the `next_phase` stage. If not → delete state file and start fresh.
For forced resume from a specific phase → use `/resume {ticket-id} --from {phase}`.

**If not found:** continue normally.

---

## Mandatory reading before starting

**Cross-session memory (first):**
- `mem_context()` via `hive-memory` MCP — restore prior session awareness, then `mem_search(query="{ticket-id}")`
- Fallback (MCP unavailable): `bash .hive/scripts/hive-memory.sh context`

**Then:**
1. `.hive/AGENTS.local.md` — all config
2. `.hive/specs/SPEC.md` — sprint context
3. `.hive/specs/ARCHITECTURE.md` — system structure
4. `.hive/specs/data-model.md` — data model

---

## Pipeline Routing (SDD — size-based)

After enrichment (Stage 1), the pipeline branches based on ticket size:

| Size | Path | Phases |
|---|---|---|
| **S, M** | Fast path | enrich → branch → dev (inline plan) → docs → commit |
| **L, XL** | Full SDD | enrich → plan-be/fe → tdd → dev → docs → commit |

The fast path skips explicit `/plan-be`, `/plan-fe`, and `/tdd` phases — the Coder plans inline during implementation and writes tests as part of the dev step. Use for small, well-understood tasks.

State is written to `.hive/sessions/{ticket-id}_state.json` after each stage. If the session is interrupted, run `/resume {ticket-id}` to continue.

---

## Pipeline

### Stage 1 — Enrich + Size Check (Analyst)

**Load ticket:**
- `ticket_get("{ticket-id}")` via `hive-tickets` MCP
- Fallback: use `ticket_provider.mcp_name` MCP as configured in `AGENTS.local.md`

**Enrich if needed** — check whether the ticket already has Given/When/Then acceptance criteria:
- **Already enriched** (has Given/When/Then + technical scope): read existing content, validate completeness, continue. Do not overwrite.
- **Not yet enriched** (raw description only): apply the full `/enrich` process — Given/When/Then, endpoints, files, validation rules, out-of-scope. Write enriched content back to ticket.

Do NOT move ticket status yet — wait until implementation starts.

**After enrichment — size gate:**

| Size | Action |
|---|---|
| **S / M** | Continue to checkpoint / next stage |
| **L** | `supervised`/`balanced`: present split option (see below). `autonomous`: split automatically via `/split`, then stop |
| **XL** | Always run `/split`. Stop this pipeline. Do not implement. |

**If splitting (L in autonomous, or any XL):**
1. Run the full `/split` process for this ticket
2. Output the list of sub-tickets created
3. **Stop the `/ship` pipeline** — do not proceed to plan or implementation
4. Output:
   ```
   Ticket {ID} ({size}) has been split.
   Sub-tickets created: {list}
   Run: hive run {sub-ticket-ids}
   Or:  /ship {first-sub-ticket}
   ```

**If L in supervised/balanced — offer the choice:**
```
Ticket {ID} is sized L (full day). Recommended: split into smaller tickets.

Options:
  [S] Split into sub-tickets now (recommended)
  [P] Proceed with full SDD path as-is

Reply S or P:
```
- If S → run `/split`, stop pipeline
- If P → continue with full SDD path, note the risk of hitting token circuit breaker

Output summary (only when continuing to implementation):
```
Ticket: {ID} — {title}
Size: S/M/L
Path: fast | full SDD
Layers affected: domain / application / infrastructure / presentation / frontend
Estimated steps: {N}
```

→ Write state: `{"ticket":"{id}","size":"{S|M|L|XL}","path":"{fast|full}","current_phase":"enrich","completed_phases":["enrich"],"next_phase":"{plan-be|dev-be}"}`

---

### ⏸ CHECKPOINT — Human reviews enriched ticket

**Applies when:** `autonomy.level` is `supervised`
**Skipped when:** `autonomy.level` is `balanced` or `autonomous`, or `--auto` flag is set (log to `.hive/changes/` and continue)

```
Ticket {ID} has been enriched. Review the acceptance criteria:
[show Given/When/Then criteria]

Are these criteria correct and complete?
Reply with corrections or type "approved" to continue.
```

**Do not proceed until human approves (if checkpoint applies).**

---

### Stage 2 — Plan + Start (Architect) — Full SDD only

**Skipped on fast path (S/M tickets).** On fast path: create branch, then jump to Stage 4.

**Transition ticket to in_progress:**
- `ticket_update("{ticket-id}", status="{statuses.in_progress}")` via `hive-tickets` MCP
- Fallback: use `ticket_provider.mcp_name` MCP

Load: `.hive/standards/core.mdc` + relevant area standards (backend/frontend/both)

Run `/plan-be` and/or `/plan-fe` based on layers affected.
Save plans to:
- `.hive/changes/{ticket-id}_backend.md`
- `.hive/changes/{ticket-id}_frontend.md`

Verify library versions via Context7 before finalizing plan.

Output summary:
```
Backend plan: {N} subtasks, {layers}
Frontend plan: {N} subtasks, {components}
Estimated tests to write: {N}
```

→ Write state: update `current_phase` to `"plan-be"` (or `"plan-fe"`), add to `completed_phases`, set `next_phase` to `"tdd"`.

---

### Stage 3 — Tests (Tester) — Full SDD only

**Skipped on fast path (S/M tickets).**

Load: `.hive/changes/{ticket-id}_backend.md` + relevant test standards

Run `/tdd` process: write failing tests for all acceptance criteria.
Tests are committed to the **feature branch** (same branch as implementation — never a separate branch).

Confirm tests fail for the right reason (not syntax errors):
```
Tests written: {N}
All failing: ✓ (confirmed — implementation does not exist yet)
Committed to: feature/{ticket-id}-{description}
```

→ Write state: update `current_phase` to `"tdd"`, add to `completed_phases`, set `next_phase` to `"dev-be"`.

---

### Stage 4 — Implement (Coder)

Load: failing tests + implementation plan + relevant standards

Run `/dev-be` and/or `/dev-fe`.
Execute subtasks in DDD layer order.
After each subtask: run `verify_commands.test` — confirm passing.

Progress tracking:
```
[ ] Step 1: {description} — {status}
[ ] Step 2: {description} — {status}
...
```

Stop immediately if a test fails unexpectedly — surface the conflict, do not modify the test.

→ Write state: update `current_phase` to `"dev-be"` (or `"dev-fe"`), add to `completed_phases`, set `next_phase` to `"update-docs"`.

---

### ⏸ CHECKPOINT — Human reviews implementation

**Applies when:** `autonomy.level` is `supervised` or `balanced`
**Skipped when:** `autonomy.level` is `autonomous`, or `--auto` flag is set (auto-commit if all checks pass)

```
Implementation complete. All tests passing.
Verification results:
  tests:     ✓ {N}/{N} passing
  typecheck: ✓ / ✗ {errors}
  lint:      ✓ / ✗ {warnings}
  coverage:  {%}

Changed files:
{list of files modified}

Review the changes. Reply with corrections or type "approved" to commit.
```

**Do not commit until human approves (if checkpoint applies).**

---

### Stage 5 — Docs + Commit (Coder)

Run `/update-docs`: identify and update affected docs.
Run `/commit`: stage, commit, push, create PR.

**Save session memory:**
- `mem_session_summary(content="Completed {ticket-id}: {brief summary of what was implemented, key decisions, and next steps}")` via `hive-memory` MCP
- Fallback: `bash .hive/scripts/hive-memory.sh session-summary --content "..."`

Final output:
```
✓ Docs updated: {list}
✓ Committed: {commit message}
✓ PR created: {URL}
✓ Ticket moved to: {statuses.in_review}
✓ Session summary saved to .hive/memory/

Next: run /ship {next-ticket-id} or /review to review this PR.
```

→ Delete `.hive/sessions/{ticket-id}_state.json` — pipeline complete.

---

## Abort conditions

**Batch context (called from `/run`):** NEVER pause or ask. Convert every condition below into a circuit_breaker trip — log the reason to the batch session file and return control to `/run`. The batch continues with the next ticket. Do not output a question or request.

**Interactive context (called directly as `/ship`):** Stop the pipeline and ask the human if:
- Acceptance criteria are ambiguous after enrichment
- A test fails for an unexpected reason (not missing implementation)
- A library API cannot be confirmed via Context7
- A DDD boundary violation would be required to implement the ticket
- The implementation requires touching more than 15 files

<!-- Context loading strategy per stage is defined in AGENTS.md "Token Budget" section. -->
