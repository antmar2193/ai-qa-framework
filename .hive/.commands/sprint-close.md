# /sprint-close — Sprint Close & Transition
<!-- tokens: ~1200 | loads: orchestrator.md -->

**Agent:** Orchestrator (read `.hive/.agents/orchestrator.md`)
**Usage:** `/sprint-close [sprint-id]`
**Interactive:** Yes — confirms before closing

Closes the current sprint in the ticket tool, handles incomplete tickets according to
`sprint_lifecycle` config, optionally tags the repository, and optionally opens the
next sprint. Run manually at end of sprint, or triggered automatically by `/run --sprint`.

---

## Process

### Step 1: Read configuration

Read `.hive/AGENTS.local.md`:
- `sprint_lifecycle.auto_open_next` — open the next sprint after closing this one
- `sprint_lifecycle.incomplete_tickets` — `move_to_next` | `move_to_backlog` | `keep`
- `sprint_lifecycle.tag_on_close` — create a git tag (sprint-N)
- `sprint_lifecycle.notify_on_close` and `notify_on_open`

If `ticket_provider.tool` is `"none"`: skip all MCP calls; manage sprint state locally
via `.hive/specs/SPEC.md` and notes only.

### Step 2: Inventory the sprint

Call `ticket_list_sprint("active")` via hive-tickets MCP. Categorize:

- **Done**: status matches `done` in `ticket_provider.statuses`
- **Incomplete**: everything else (`in_progress`, `in_review`, `blocked`, `refined`, `backlog`)

Show summary and ask for confirmation:

```
Sprint: {sprint-name}

  ✓ Done ({n}):       PROJ-1, PROJ-2, PROJ-3
  ○ Incomplete ({n}): PROJ-4 [In Review], PROJ-5 [In Progress]

  Action on incomplete: {move_to_next | move_to_backlog | keep}

Close sprint and continue? [Y/n]
```

If **0 done tickets**: warn explicitly before proceeding.
```
⚠  No tickets are marked Done. Close anyway? [y/N]
```

### Step 3: Handle incomplete tickets

**`move_to_next`** (default): add a comment to each incomplete ticket noting it was deferred.
Sprint re-assignment must happen in the ticket tool after the next sprint is created.
```
ticket_update(ticket_id, comment="Carried over to next sprint — not completed in {sprint-name}")
```

**`move_to_backlog`**: move each incomplete ticket to backlog status.
```
ticket_update(ticket_id, status="{statuses.backlog}", comment="Moved to backlog on sprint close")
```

**`keep`**: do nothing — tickets remain associated with the closed sprint in the tool.

### Step 4: Close the sprint

Call `sprint_close("active")` via hive-tickets MCP.

Expected output: `Sprint {name} closed.`

### Step 5: Git tag

If `sprint_lifecycle.tag_on_close: true`:
```bash
git tag -a "sprint-{N}" -m "Sprint {N} complete — {done}/{total} tickets"
git push origin "sprint-{N}"
```

Extract the sprint number from the sprint name (e.g. "Sprint 3" → N=3).

### Step 6: Close notification

If `sprint_lifecycle.notify_on_close: true`:
```bash
bash .hive/scripts/hive-notify.sh \
  --event sprint_close \
  --message "Sprint {N} closed. {done}/{total} tickets done. {incomplete} carried over." \
  --status success
```

### Step 7: Open next sprint

If `sprint_lifecycle.auto_open_next: true`:

Determine next sprint name: increment the sprint number ("Sprint 1" → "Sprint 2").

Call `sprint_open("{next-name}")` via hive-tickets MCP.

If `sprint_lifecycle.notify_on_open: true`:
```bash
bash .hive/scripts/hive-notify.sh \
  --event sprint_open \
  --message "Sprint {N+1} opened. Run /sprint-setup to select tickets." \
  --status info
```

### Step 8: Output summary

```
Sprint {N} closed.
  ✓ Done:      {done}/{total} tickets
  ○ Incomplete: {incomplete} tickets {moved to next sprint | moved to backlog | kept}

  git tag:     sprint-{N} pushed ✓
  Next sprint: {name} opened ✓ (or: run /sprint-setup to configure)

Next steps:
  /sprint-setup    — select tickets for sprint {N+1} and regenerate SPEC.md
  /sync            — pull the new sprint's tickets into SPEC.md
```

---

## Rules

- Always confirm before closing — sprint close is irreversible in most ticket tools
- Never close a sprint with 0 done tickets without explicit confirmation
- If the ticket tool is `none` (local): skip all MCP calls, show manual next steps only
- If `auto_open_next: false`: always print the manual open command — `sprint_open "Sprint {N+1}"`
- Do not create git tags if there are uncommitted changes — warn and ask
