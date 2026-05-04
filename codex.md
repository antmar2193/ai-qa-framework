<!-- hive:managed -->
# codex.md

> This file is read by **OpenAI Codex** (async cloud agent) on task startup.
> It provides Codex-specific configuration on top of `AGENTS.md`.
> For the full agent protocol, read `AGENTS.md` first.

---

## Codex Setup

### Execution model

Codex operates **asynchronously** — tasks are assigned and results arrive
as GitHub pull requests. This is different from Claude Code and Antigravity
which are synchronous/interactive.

HIVE commands that work well with Codex's async model:
- `/dev-be <ticket>` — full backend implementation → PR
- `/dev-fe <ticket>` — full frontend implementation → PR
- `/tdd <ticket>` — write failing tests → PR
- `/focus <module>` — useful before async tasks on large legacy codebases

Commands that require synchronous interaction (avoid with Codex):
- `/kickoff` — needs 4 human checkpoints
- `/ship` — needs 2 human checkpoints
- `/enrich` — requires back-and-forth clarification

### Recommended workflow with Codex

```
Human (Claude.ai or Antigravity):
  /kickoff  → produces PRD, ARCHITECTURE, tickets
  /enrich TICKET-ID → enriches ticket with full spec

Codex (async):
  /dev-be TICKET-ID → implements backend → PR
  /dev-fe TICKET-ID → implements frontend → PR

Human (reviews PR):
  /review → reviews the PR
```

### Context to include in Codex task

When assigning a task to Codex, include:

```
Context files to read:
- AGENTS.md
- .hive/AGENTS.local.md
- .hive/specs/data-model.md
- .hive/standards/core.mdc
- .hive/standards/backend.mdc (for backend tasks)
- .hive/changes/{ticket-id}_backend.md (implementation plan)
- Failing test files (for TDD green phase)

# For legacy projects:
- .hive/specs/LEGACY_CONTEXT.md (for legacy projects)
- .hive/specs/COEXISTENCE_RULES.md (for legacy projects)
- .hive/sessions/focus.md (if /focus was set)
```

### GitHub integration

Codex outputs PRs with full diffs and test results.
Configure your repo in Codex settings → connect your GitHub organization.

### Isolated sandbox

Codex runs in an isolated container with its own filesystem.
Each task starts fresh — no shared state between tasks.
The implementation plan in `.hive/changes/{ticket}_backend.md` is the
single source of truth — Codex reads it at task start.

### Token strategy

Codex processes the full context at task start (not lazy-loaded like Cursor).
Keep context files concise:
- Implementation plans (`.hive/changes/`) should be specific, not verbose
- SPEC.md should contain only the current sprint's tickets
- Do not include `hive/docs/` or historical specs in the task context
<!-- /hive:managed -->

---

<!-- hive:project-notes -->
## Project Notes

Add project-specific Codex configuration below this line.
This section is preserved by sync-standards.sh and never overwritten.
<!-- /hive:project-notes -->
