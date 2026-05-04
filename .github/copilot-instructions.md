# GitHub Copilot Instructions

This project uses **HIVE** — an AI-native software factory framework.

## Before suggesting any code

1. Read `AGENTS.md` at the project root — universal rules and architecture authority
2. Read `.hive/AGENTS.local.md` — project config (stack, ticket tool, autonomy level, verify commands)
3. Read `.hive/standards/core.mdc` — non-negotiable coding standards
4. For backend work → read `.hive/standards/backend.mdc`
5. For frontend work → read `.hive/standards/frontend.mdc`

## Non-negotiable rules

- **TDD first** — failing test before any implementation
- **DDD layer order** — Domain → Application → Infrastructure → Presentation (never invert)
- **No cross-layer imports** — domain must not import infrastructure or presentation
- **Full type safety** — no `any`, no untyped parameters
- **English only** — code, comments, docs, variable names

## Context loading (token-efficient)

Load only what you need for the current task:
- Backend task → `backend.mdc` only (not frontend)
- Frontend task → `frontend.mdc` only (not backend)
- Never load all standards at once

## HIVE commands

Run these slash commands from your AI tool to invoke the full pipeline:
- `/ship <ticket-id>` — full implementation pipeline
- `/plan-be <ticket-id>` — backend DDD plan
- `/dev-be <ticket-id>` — backend implementation (after /tdd)
- `/review` — code review against HIVE standards
- `/generate <EntityName>` — scaffold DDD stubs for a new entity

Full reference: `.hive/.commands/` or `docs/commands.md`
