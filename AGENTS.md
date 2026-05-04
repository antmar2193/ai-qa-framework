<!-- hive:managed -->
# AGENTS.md — HIVE

> **Universal entry point for all AI agents.**
> Part of HIVE (Harkos Intelligent Virtual Engine) — AI-Native Software Factory framework.
> Read by Claude, Cursor, Codex, Gemini, Copilot — any AI that reads project context.
> Tool-agnostic. Stack-agnostic. Language-agnostic.

---

## 0. Session Initialization

### Detection

When starting a session in any directory — check for `.hive/AGENTS.local.md`.

**If found → HIVE project detected.** Execute the startup sequence below.
**If not found → not a HIVE project.** Proceed normally without this protocol.

### Startup sequence (every HIVE session)

```
1. Check .hive/sessions/*_state.json     → if found, offer /resume <ticket>
2. mem_context() via hive-memory MCP     → restore cross-session memory
   Fallback: bash .hive/scripts/hive-memory.sh context
3. Read this file (AGENTS.md)            → universal rules
4. Read .hive/AGENTS.local.md            → project config
5. Print status banner (see below)
```

### Status banner

Print once at session start — one line:

```
[HIVE {version}] {project.name} · {stack} · autonomy: {level} · profile: {active_profile} · persona: {style}
```

Example: `[HIVE 1.2.0] PaymentAPI · go · autonomy: balanced · profile: quality · persona: neutral`

If `AGENTS.local.md` has unfilled TODO items → append: `⚠ setup incomplete — run validate-setup.sh`

### Tool-specific detection files

Each AI tool reads its own startup file. All of them point back to this protocol:

| Tool | File read on startup |
|---|---|
| Claude Code | `CLAUDE.md` |
| Gemini CLI | `GEMINI.md` |
| OpenAI Codex | `codex.md` |
| Cursor | `.cursor/rules/hive-rules.mdc` |
| GitHub Copilot | `.github/copilot-instructions.md` |
| Windsurf | `.windsurfrules` |
| Antigravity | `ANTIGRAVITY.md` |
| Any LLM (Ollama etc.) | `.hive/system-prompt.md` |
| Shell (any CLI tool) | `source scripts/hive-shell-hook.sh` in `~/.zshrc` |

---

## 0.1 Mandatory Reading Order

Before any action, read these files in order:

1. **This file** — universal rules and command map
2. **`.hive/AGENTS.local.md`** — project configuration (ticket tool, stack, commands, statuses)
3. **Your role file** — `.hive/.agents/<role>.md` ← extends this file; does NOT redefine its rules
4. **Core standards** — `.hive/standards/core.mdc`
5. **Area standards** — `.hive/standards/<area>.mdc` (only for the area you're working in)
6. **Sprint context** — `.hive/specs/SPEC.md`

**Authority hierarchy — when the same rule appears in multiple files, the higher file wins:**
```
AGENTS.md  >  core.mdc  >  <area>.mdc  >  <role>.md
```
`AGENTS.local.md` is **configuration**, not rules — it is always authoritative for what it configures
(ticket tool, status names, verify_commands, VCS, autonomy level). It never overrides behavioral rules.

If a rule in a role file or command file contradicts this file or `core.mdc`, this file wins.

**`AGENTS.local.md` is the source of truth for:**
- Which ticket tool to use (Jira, Linear, GitHub Issues, etc.)
- Which MCP name to call
- Which status names exist on the board
- Which commands to run for tests, lint, typecheck
- Which package manager and VCS platform
- Autonomy level and circuit breaker thresholds

Never assume a tool, command, or status name. Always read it from `AGENTS.local.md`.

---

## 1. Non-Negotiable Rules

| Rule | Detail |
|---|---|
| **English only** | Code, comments, docs, commits, tickets — no exceptions |
| **Baby steps** | One task at a time. Stop and surface blockers. Never skip ahead. |
| **TDD first** | Failing test before implementation. Every time. |
| **No assumptions** | Ambiguous requirement → ask, don't invent |
| **Type safety** | Fully typed where the language supports it |
| **No silent failures** | Every error caught, logged with context, surfaced to caller |
| **SOLID** | Single responsibility, Open/closed, Liskov, Interface segregation, DI |
| **DDD boundaries** | Services never reach into other domain's data directly |
| **Feedback loop** | After user feedback → propose rule update, await approval, then apply |
| **Living docs** | Every code change ships with its documentation update in the **same commit**. Schema change → `data-model.md`. API change → `api-spec.yml`. Behavior change → relevant `.md`. Run `/update-docs` before `/commit` — always. |
| **Delegate to tools** | Before writing repetitive, pattern-based content manually, check if a script can do it. `/generate` calls `hive-generate.sh` first — zero LLM tokens for boilerplate. Scripts are always cheaper than tokens. |
| **Commit format** | Every commit must follow the format in `.claude/commands/commit.md` — enforced by `.githooks/commit-msg` |
| **TDD evidence** | `/tdd` writes evidence table. `/dev-be` updates it. `/review` and `/judgment-day` block if absent or incomplete |

---

## 2. How Agents Use AGENTS.local.md

### Reading ticket tool config

```
# From AGENTS.local.md:
ticket_provider.tool        → which MCP to call (or "none")
ticket_provider.mcp_name    → exact MCP name in Claude integrations
ticket_provider.statuses.*  → exact status names on the board
ticket_provider.board_url   → link for SPEC.md and PRs
```

### Reading verify commands

```
# From AGENTS.local.md:
verify_commands.test        → run before every commit
verify_commands.typecheck   → run before every commit (skip if null)
verify_commands.lint        → run before every commit (skip if null)
verify_commands.coverage    → run when checking quality gate (skip if null)
```

### Reading VCS config

```
vcs.pr_tool          → "gh" | "glab" | null (manual PR)
vcs.branch_pattern   → how to name branches
vcs.default_base_branch → base for new feature branches
```

### Reading autonomy config

```
autonomy.level                        → "supervised" | "balanced" | "autonomous"
autonomy.circuit_breaker.max_test_retries   → stop after N consecutive test failures
autonomy.circuit_breaker.max_new_files      → checkpoint if creating more than N files
autonomy.circuit_breaker.max_tokens_per_ticket → stop if token budget exceeded
```

**Autonomy level behavior — full Git workflow:**

| Action | `supervised` | `balanced` | `autonomous` |
|---|---|---|---|
| **Create ticket branch** | Pause — confirm branch name and base branch | Automatic | Automatic |
| **Commit + push** | Pause — show diff and message, wait for approval | Automatic | Automatic |
| **Create PR** | Pause — show title and body draft, wait for approval | Automatic | Automatic |
| **Merge PR** | ✗ Human merges manually | ✗ Human merges manually | ✓ Auto-merge when CI green (requires `auto_merge_pr: true`) |
| **Delete branch** | ✗ Human deletes manually | ✗ Human deletes manually | ✓ Automatic after merge |
| **Return to base branch** | ✗ Human manages | ✗ Human manages | ✓ Automatic after cleanup |
| **Plan approval** | Pause & present | Log to `.hive/changes/` & continue | Log & continue |
| **Ambiguous decisions** | Pause & ask | Pause & ask | Best judgment, log decision |
| **Ticket → Done** | Per `ticket_transitions.mode` | Per `ticket_transitions.mode` | Always exactly 1 transition: → Done after merge, regardless of configured mode (skip if `mcp_name` is `"none"`) |

Commit messages and PR descriptions are written in the language defined by `language.communication` in `AGENTS.local.md`.

**Circuit breakers apply at ALL levels** — even `autonomous` stops when:
- A test fails `max_test_retries` times consecutively
- More than `max_new_files` new files need to be created
- Token usage exceeds `max_tokens_per_ticket`

### Reading persona config

```
persona.style → "verbose" | "neutral" | "terse"
```

Apply to all agent outputs in the session:

| Style | Behavior |
|---|---|
| `verbose` | Step-by-step explanations, alternatives considered, reasoning shown — good for onboarding or learning |
| `neutral` | Concise summaries: what was done and why (default) |
| `terse` | Diffs, status lines, and errors only — no prose or explanations |

If `persona` is absent → default to `neutral`.

### Reading model profile config

```
active_profile                          → name of the active profile
model_profiles[active_profile].planning       → model for planning phases
model_profiles[active_profile].implementation → model for implementation phases
model_profiles[active_profile].review         → model for review phases
```

Use the specified model when calling sub-agents or switching context for that phase.
`null` → use whatever model the session currently has active.
If `model_profiles` or `active_profile` absent → treat all phases as `null`.

Switch profiles with `/profile switch <name>`.

### Reading ticket transition config

```
ticket_provider.ticket_transitions.mode        → "minimal" | "standard" | "verbose"
ticket_provider.ticket_transitions.auto_merge_pr → true | false
```

**Transition behavior by mode:**

| Mode | Transitions | When | Token cost |
|---|---|---|---|
| `minimal` (default) | 1 | Ticket → Done on PR merge | Lowest |
| `standard` | 2 | → In Progress on start + → Done on merge | Low |
| `verbose` | 3+ | → In Progress on start + → In Review on PR open + → Done on merge | Normal |

If `auto_merge_pr: true` and autonomy is `autonomous`: PR is merged automatically when all CI checks pass.

### Reading autonomous mode requirements

```
autonomy.level = "autonomous"  → audit log is MANDATORY
```

In `autonomous` mode, the agent MUST log every significant action to `.hive/events.jsonl`:
- Every file created or modified
- Every test run (pass/fail)
- Every commit and push
- Every decision made without human approval

```jsonl
{"ts":"<ISO>","cmd":"<pipeline>","ticket":"<id>","stage":"<name>","event":"action","detail":"<description>","tokens":<n>}
```

---

## 3. Agent Roles

| Agent | File | Commands |
|---|---|---|
| **Analyst** | `.hive/.agents/analyst.md` | `/enrich`, `/sync`, `/new-ticket`, `/focus` |
| **Architect** | `.hive/.agents/architect.md` | `/plan-be`, `/plan-fe` |
| **Coder** | `.hive/.agents/coder.md` | `/dev-be`, `/dev-fe`, `/commit`, `/generate` |
| **Tester** | `.hive/.agents/tester.md` | `/tdd` |
| **Reviewer** | `.hive/.agents/reviewer.md` | `/review`, `/judgment-day` |
| **Product Strategist** | `.hive/.agents/product-strategist.md` | `/strategy` |
| **Explainer** | `.hive/.agents/explainer.md` | `/explain` |
| **Orchestrator** | `.hive/.agents/orchestrator.md` | `/ship`, `/kickoff`, `/sprint-setup`, `/profile`, `/resume` |
| **DevOps** | `.hive/.agents/devops.md` | `/ci`, `/deploy`, `/deploy-config` |

---

## 4. Slash Commands

```
/intake                     → Product Strategist: capture client requirements
/strategy <idea>            → Product Strategist: analyze idea, define users + value prop
/kickoff                    → All agents: full project setup wizard (strategy → PRD → arch → tickets)
/sprint-setup [sprint]      → Analyst: create/validate sprint tickets + SPEC.md
/new-ticket <description>   → Analyst: create ticket from plain text, assign ID, save to TICKETS.md
/enrich   <ticket>          → Analyst: enrich ticket with full technical detail
/plan-be  <ticket>          → Architect: backend implementation plan
/plan-fe  <ticket> [design] → Architect: frontend implementation plan
/tdd      <ticket>          → Tester: write failing tests from acceptance criteria
/dev-be   <ticket>          → Coder: implement backend (TDD green phase)
/dev-fe   <ticket> [design] → Coder: implement frontend
/generate <EntityName> [--area backend|frontend] [--dry-run] → Coder: scaffold all DDD layer stubs for an entity
/ship     <ticket> [--dry-run] → All agents: full ticket pipeline (enrich → plan → tdd → dev → commit)
/commit   [ticket|--dry-run]   → Coder: stage, commit, push, create PR
/review   [pr|branch]       → Reviewer: review against standards
/judgment-day <ticket|pr|branch> [--quick] → Reviewer: adversarial parallel review (two independent judges)
/sync                       → Analyst: regenerate SPEC.md from ticket board
/update-docs               → Review and update all docs after code changes
/memory <save|search|context|session-summary> → Any agent: read/write persistent cross-session memory
/assess                    → Architect: analyze legacy codebase structure and patterns
/focus    <module-path>    → Analyst: restrict agent scope to a specific module (legacy projects)
/ci       [--generate]     → DevOps: generate CI/CD pipeline from config
/deploy   [--dry-run] [--env <staging|production>] → DevOps: verify, tag, deliver to client repo
/explain  <topic>           → Explainer: teach concept with mental model + quiz
/meta     <prompt>          → Improve a prompt using prompt engineering best practices
```

Full spec for each: `.hive/.commands/`

---

## 5. MCP Integration (configured per project in AGENTS.local.md)

HIVE ships two native MCP servers (`hive-memory`, `hive-tickets`) that are the **default interface** for all memory and ticket operations. Fallbacks exist for environments where the MCPs are not installed — use them only when the MCP call fails or the server is absent.

| Purpose | MCP | Used by |
|---|---|---|
| **Memory** (HIVE native) | `hive-memory` | All commands — mem_context at start, mem_save after key decisions, mem_session_summary at end |
| **Tickets** (HIVE native) | `hive-tickets` | /enrich /plan-be /plan-fe /commit /review /judgment-day |
| Tickets (project-specific) | Atlassian, Linear, GitHub | Fallback when hive-tickets unavailable |
| Design | Figma | /dev-fe /plan-fe |
| Library docs | Context7 | /plan-be /dev-be /dev-fe /tdd |
| Code hosting | GitHub, GitLab | /commit /review |

**hive-memory — call order (all commands):**
1. **Session start** — `mem_context()` then `mem_search("{ticket-id}")` before reading plan files
2. **After architectural decision** — `mem_save(topic_key="arch/{feature}", type="architecture")`
3. **After implementation plan** — `mem_save(topic_key="plan/{ticket-id}", type="plan")`
4. **Session end (long sessions)** — `mem_session_summary(content="...")`
- **Fallback** (MCP unavailable): `bash .hive/scripts/hive-memory.sh context|save|search`

**hive-tickets — call order:**
1. `ticket_get` / `ticket_update` / `ticket_list_sprint` via `hive-tickets` MCP ← **default**
2. Fallback → `ticket_provider.mcp_name` from `AGENTS.local.md` (Atlassian, Linear, GitHub MCPs)
3. Fallback → read from `.hive/changes/{ticket}_backend.md` or ask the user

If the MCP server is unavailable → use the fallback chain above, in order.

---

## 6. Definition of Done

A task is DONE only when all applicable items pass (skip items marked `null` in config):

- [ ] Failing test written before implementation (TDD)
- [ ] All acceptance criteria from the ticket pass
- [ ] Unit tests pass (`verify_commands.test`)
- [ ] Integration / E2E tests pass (if applicable)
- [ ] Type check passes (`verify_commands.typecheck`, skip if null)
- [ ] Linter passes (`verify_commands.lint`, skip if null)
- [ ] No debug artifacts in production paths
- [ ] No hardcoded values — all via environment variables
- [ ] PR created with ticket reference, CI green
- [ ] Ticket moved to `statuses.in_review` on the board
- [ ] Technical docs updated (`/update-docs` run)

---

## Token Budget — Context Loading Rules

**Load only what the current task requires.**

This table is the single source of truth for context loading. Command files do not redefine it.

| Task | Load | Skip |
|---|---|---|
| `/kickoff` or `/strategy` | functional context doc | all standards, all agents |
| `/enrich` | `analyst.md` + ticket | standards, other agents |
| `/plan-be` | `architect.md` + `core.mdc` + `backend.mdc` | frontend.mdc, other agents |
| `/plan-fe` | `architect.md` + `core.mdc` + `frontend.mdc` | backend.mdc, other agents |
| `/tdd` | `tester.md` + plan file + test standard | other agents, other standards |
| `/dev-be` | `coder.md` + test files + `backend.mdc` | frontend.mdc, other agents |
| `/dev-fe` | `coder.md` + test files + `frontend.mdc` | backend.mdc, other agents |
| `/review` | `reviewer.md` + both standards + diff | agents, spec files |

**Rules:**
- Never load all agents at once — load only the agent for the current command
- Never load all standards — load only the standard for the current area
- `SPEC.md` is a compact sprint summary — use it instead of querying Jira for context
- `.hive/changes/{ticket}_backend.md` is the authoritative plan — read it, don't regenerate
- If a file was read in a previous step of the same session, it is already in context — do not reload
- **Prompt cache awareness**: place stable content first (AGENTS.md, core.mdc, stack standard) and variable content last (ticket details, diff). Providers with prompt caching (Claude, Gemini) cache stable prefixes automatically — this order maximizes cache hits.
- **Cross-command deduplication**: if `/plan-be` and `/dev-be` run in the same session, `core.mdc` and `backend.mdc` are already in context — skip reloading them. Check before loading, not after.
- **Use scripts for mechanical work**: before generating boilerplate, file structure, or notifications manually, check if a `.hive/scripts/` tool can do it for zero tokens. Key examples: `hive-generate.sh` for DDD scaffolding, `hive-notify.sh` for webhooks, `hive-analytics.sh` for cost reporting.

**Approximate sizes (tokens):** `AGENTS.md` ~3.5K · `AGENTS.local.md` ~5K · each agent ~1.5K · `core.mdc` ~3.5K · each stack standard ~2K.
For models with ≤ 16K context: load `AGENTS.md` + `AGENTS.local.md` + one agent file + one standard only.
For models with ≥ 32K context: full stage loading as defined above is safe.


---

## 7. Feedback Loop (mandatory)

After any user correction, feedback, or new information:

1. Identify which rule or standard should be updated
2. Quote the specific section to change
3. Propose exact new wording
4. State: *"Awaiting your approval before modifying any rule file."*
5. Only after explicit approval → apply the change and confirm

Never modify rule files without approval.

---

## 8. Full Development Lifecycle

This table maps each lifecycle phase to the responsible role and command.
Use it to understand who does what and in which order.

### New Project

| Phase | Role | Command / Script | Output |
|---|---|---|---|
| Discovery | PM / Product Owner | `/intake` | `functional-context.md` |
| Strategy | PM / Product Owner | `/strategy` | Strategy analysis |
| Project setup | PM | `new-project.sh` | Workspace, AGENTS.local.md |
| ⏸ Strategy approval | PM + Tech Lead | — | Validated strategy |
| Full kickoff | PM + Tech Lead | `/kickoff` | PRD + ARCHITECTURE + Tickets |
| ⏸ Architecture approval | Tech Lead | — | Validated ARCHITECTURE.md |
| ⏸ Dev team handoff | Tech Lead | — | Team briefed on project |
| CI/CD setup | DevOps | `/ci` | Pipeline config |
| Validate setup | Tech Lead | `validate-setup.sh` | All checks green |
| Sprint planning | PM / Analyst | `/sprint-setup` | SPEC.md |
| Ticket enrichment | Analyst / Tech Lead | `/enrich` | Full ticket spec |
| Backend plan | Architect / Tech Lead | `/plan-be` | `changes/{ticket}_backend.md` |
| Frontend plan | Architect / Tech Lead | `/plan-fe` | `changes/{ticket}_frontend.md` |
| Write failing tests | Developer | `/tdd` | Failing test files |
| Implement | Developer | `/dev-be` or `/dev-fe` | Working code + passing tests |
| PR | Developer | `/commit` | PR on board |
| Code review | Senior Dev / Tech Lead | `/review` | Review comments / approval |
| ⏸ Merge | Human | — | Code merged |
| Release & delivery | DevOps | `/deploy` | Tag + client repo updated |

### Legacy Project (addendum — runs before first sprint)

| Phase | Role | Command / Script | Output |
|---|---|---|---|
| Inject HIVE | Tech Lead | `inject-factory.sh` | `.hive/` added to repo |
| Validate injection | Tech Lead | `validate-setup.sh` | Config validated |
| Assess codebase | Tech Lead / Architect | `/assess` | LEGACY_CONTEXT, TECH_DEBT, COEXISTENCE_RULES |
| Configure rules | Tech Lead | Edit `AGENTS.local.md` | `protected_paths`, `existing_patterns` set |
| Commit AI layer | Tech Lead | `git commit` | Team has AI layer |
| → Continue from Sprint planning above | | | |
<!-- /hive:managed -->

---

<!-- hive:project-notes -->
## Project Notes

Add project-specific agent configuration below this line.
This section is preserved by sync-standards.sh and never overwritten.
<!-- /hive:project-notes -->
