# /resume — Resume Interrupted Pipeline
<!-- tokens: ~1350 | loads: orchestrator.md, .hive/sessions/{ticket}_state.json -->

**Agent:** Orchestrator (read `.hive/.agents/orchestrator.md`)
**Usage:**
```
/resume <ticket-id>      # resume from last checkpoint
/resume <ticket-id> --from <phase>   # force restart from a specific phase
/resume --list           # list all tickets with saved state
```

**When to use:** When a `/ship` pipeline was interrupted mid-way (context window exhausted, manual stop, error, session closed). HIVE saves a state file at each phase transition — this command reads it and continues from where it left off.

---

## Process

### Step 1: Load state

Read `.hive/sessions/{ticket-id}_state.json`.

If file does not exist:
```
No saved state for {ticket-id}.
Run /ship {ticket-id} to start the pipeline.
```

State file schema:
```json
{
  "ticket":            "<ticket-id>",
  "size":              "S | M | L | XL",
  "path":              "fast | full",
  "started_at":        "<ISO timestamp>",
  "last_updated_at":   "<ISO timestamp>",
  "current_phase":     "<phase-name>",
  "completed_phases":  ["<phase>", "..."],
  "next_phase":        "<phase-name>",
  "branch":            "<branch-name>",
  "notes":             "<any agent notes saved at checkpoint>"
}
```

### Step 2: Present status

```
Interrupted pipeline found: {ticket-id}

Path:      {fast | full SDD}
Branch:    {branch-name}
Started:   {started_at}
Stopped:   {last_updated_at}

Completed phases:
  ✓ enrich
  ✓ plan-be
  ✗ tdd   ← stopped here

Next phase: tdd
```

If `--from <phase>` was passed → override `next_phase` with the specified phase and warn if it means re-running completed phases.

### Step 3: Confirm and resume

In `supervised` mode: ask "Resume from {next_phase}? (Y/n)"
In `balanced` / `autonomous`: proceed immediately.

### Step 4: Continue pipeline

Resume `/ship` from `next_phase`. Skip all phases in `completed_phases`.

At each phase completion → update the state file with the new `current_phase`, `completed_phases`, `last_updated_at`.

When the full pipeline completes → delete `.hive/sessions/{ticket-id}_state.json`.

---

### /resume --list

Scan `.hive/sessions/` for `*_state.json` files.

Output:
```
Interrupted pipelines:

  PROJ-42    tdd          stopped 2h ago   (branch: feature/PROJ-42-payment-flow-backend)
  PROJ-38    dev-be       stopped 1d ago   (branch: feature/PROJ-38-user-auth-backend)

Run /resume <ticket-id> to continue any of these.
```

---

## Phase names (valid values for --from)

| Phase name | Description |
|---|---|
| `enrich` | Ticket enrichment with Given/When/Then |
| `plan-be` | Backend DDD plan |
| `plan-fe` | Frontend component plan |
| `tdd` | Write failing tests (red phase) |
| `dev-be` | Backend implementation (green phase) |
| `dev-fe` | Frontend implementation |
| `update-docs` | Documentation sync |
| `commit` | Stage, commit, push, PR |

---

## Rules
- Never re-run a completed phase unless `--from` explicitly requests it
- If the branch in the state file no longer exists → warn and ask user to confirm before creating a new one
- State file is deleted only after the pipeline fully completes (not on error)
- If state file is corrupted (missing required fields) → report and ask the user to run `/ship {ticket-id}` fresh
