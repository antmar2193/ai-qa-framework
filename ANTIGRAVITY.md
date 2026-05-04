<!-- hive:managed -->
# ANTIGRAVITY.md

> This file is read by **Antigravity** IDE on session startup.
> It provides Antigravity-specific configuration on top of `AGENTS.md`.
> For the full agent protocol, read `AGENTS.md` first.

---

## HIVE Detection

This project uses **HIVE** (AI-Native Software Factory framework).

On session start, confirm detection:
```
[HIVE detected] {project.name} · {stack} · autonomy: {autonomy.level}
Reading: AGENTS.md → .hive/AGENTS.local.md
Memory: mem_context() via hive-memory MCP
Ready for HIVE commands.
```

---

## Execution Model

Antigravity operates in a single-agent inline execution model.
Use **file-based state management** to simulate multi-phase SDD workflows:

1. At each phase transition → write current state to `.hive/sessions/{ticket}_state.json`
2. Before starting a phase → read state file to confirm prior phases completed
3. If context is lost mid-session → run `/resume {ticket-id}` to reload state

This mirrors the finite-state-machine pattern described in the HIVE `/resume` command.

---

## HIVE Commands

Use the slash commands defined in `.hive/.commands/`:

| Command | Description |
|---|---|
| `/ship <ticket>` | Full pipeline (routes to fast or full SDD by ticket size) |
| `/plan-be <ticket>` | Backend DDD plan |
| `/dev-be <ticket>` | Backend implementation |
| `/generate <Entity>` | Scaffold DDD stubs |
| `/review` | Code review |
| `/resume <ticket>` | Resume interrupted pipeline |

For Antigravity's single-threaded model, prefer `/ship` with full path enabled — it handles phase transitions and state writing automatically.

---

## Context Loading

Read files in this order — stop loading once you have what you need for the current task:

1. `AGENTS.md` — universal rules
2. `.hive/AGENTS.local.md` — project config
3. `.hive/.agents/<role>.md` — role for current command only
4. `.hive/standards/core.mdc` — always
5. `.hive/standards/backend.mdc` OR `frontend.mdc` — area-specific only
6. `.hive/specs/SPEC.md` — sprint context

**Never** load all agents and all standards at once.

---

## State Management Pattern

Antigravity lacks native sub-agent support. Use this pattern for multi-phase work:

```
Phase start  → Announce: "Beginning phase: {phase-name}"
Phase end    → Write state to .hive/sessions/{ticket}_state.json
               Announce: "Phase {phase-name} complete. Next: {next-phase}"
Resume       → Read state file → announce resume point → continue
```

---

## MCP Integration

Configure in Antigravity settings (if supported):
```
hive-memory:  command = "hive-memory"
hive-tickets: command = "hive-tickets"
```

If MCPs are not available in Antigravity → use bash fallbacks:
- Memory: `bash .hive/scripts/hive-memory.sh <search|save|context>`
- Tickets: read from `.hive/changes/{ticket-id}_context.md`

<!-- /hive:managed -->
