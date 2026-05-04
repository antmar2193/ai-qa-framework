# /sprint-setup — Sprint Initialization
<!-- tokens: ~500 | loads: orchestrator.md, analyst.md -->

**Agent:** Orchestrator (read `.hive/.agents/orchestrator.md`) + Analyst (read `.hive/.agents/analyst.md`)
**Usage:** `/sprint-setup [sprint-number]`

Creates or validates all tickets for a sprint and generates SPEC.md.
Runs after `/kickoff` for subsequent sprints.

---

## Process

### 1. Read current state
- `.hive/AGENTS.local.md` — board URL, ticket tool, statuses
- `.hive/specs/PRD.md` — feature backlog
- `.hive/specs/ARCHITECTURE.md` — technical constraints

### 2. Identify sprint scope
If sprint-number provided → use that sprint's tickets.
If not → ask which epics/features to include.

### 3. Validate tickets exist
Check if tickets for the sprint already exist in the board via MCP.
- If missing → propose ticket list and ask confirmation before creating
- If exist → validate they have proper descriptions

### 4. Create missing tickets
For each missing ticket:
- Title: `[Verb] [Entity] [context]` in English
- Description: functional scope from PRD
- Link to epic

### 5. Generate SPEC.md
Run `/sync` process → write `.hive/specs/SPEC.md`

### 6. Output
```
Sprint {N} setup complete:
- Tickets verified/created: {N}
- SPEC.md updated: ✓
- Ready for: /ship {first-ticket-id}
```
