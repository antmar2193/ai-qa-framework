<!-- hive:managed -->
# GEMINI.md

> This file is read by **Gemini CLI** and other Gemini-based tools on startup.
> It provides Gemini-specific configuration on top of `AGENTS.md`.
> For the full agent protocol, read `AGENTS.md` first.

---

## Gemini CLI Setup

### Installation

```bash
npm install -g @google/gemini-cli
# or
npx @google/gemini-cli
```

Authenticate: `gemini auth login`

### Running HIVE commands

Gemini CLI reads `AGENTS.md` automatically when launched in a project directory.

```bash
cd your-project
gemini                          # starts interactive session
> /enrich TICKET-42             # runs any HIVE command
> /ship TICKET-42               # full pipeline
```

### Slash commands

All HIVE commands work with Gemini CLI. Type `/` to see available commands.

| Command | What it does | Interactive? |
|---|---|---|
| `/kickoff` | Full project init: strategy → PRD → architecture → tickets | Yes — 4 checkpoints |
| `/ship <ticket>` | Full pipeline: enrich → plan → tdd → implement → commit | Yes — 2 checkpoints |
| `/run <tickets...>` | Batch: process multiple tickets autonomously (server/overnight) | No |
| `/sprint-setup` | Create sprint tickets + generate SPEC.md | Yes — 1 checkpoint |
| `/new-ticket <description>` | Create a new ticket from plain language description | No |
| `/intake` | Client onboarding: gather requirements, context, constraints | Yes |
| `/strategy` | Product strategy analysis and roadmap definition | Yes |
| `/assess` | Analyse a legacy codebase and produce migration plan | No |
| `/focus <module>` | Restrict agent scope to a module (legacy projects) | No |
| `/enrich <ticket>` | Enrich ticket with Given/When/Then | Yes |
| `/plan-be <ticket>` | Backend DDD implementation plan | No |
| `/plan-fe <ticket>` | Frontend component plan | No |
| `/tdd <ticket>` | Write failing tests before implementation (red phase) | No |
| `/dev-be <ticket>` | Implement backend (TDD green phase) | No |
| `/dev-fe <ticket>` | Implement frontend | No |
| `/generate <entity>` | Scaffold DDD stubs via script — agents fill business logic only | No |
| `/resume <ticket>` | Resume interrupted `/ship` pipeline from last checkpoint | No |
| `/commit <ticket>` | Stage, commit, push, PR | Yes — confirms before push |
| `/review` | Review PR: DDD, SOLID, security, coverage | No |
| `/judgment-day <ticket\|pr>` | Adversarial parallel review: two independent judges | No |
| `/deploy` | Verify, tag, deliver to client repo | Yes — confirms version |
| `/update-docs` | Keep docs in sync after implementation changes | No |
| `/sync` | Regenerate SPEC.md from ticket board | No |
| `/ci` | Generate or update CI/CD pipeline config | No |
| `/status` | Show current project config, autonomy, profile, interrupted pipelines | No |
| `/health` | Active project diagnostics: config gaps, stale specs, recent errors | No |
| `/profile [switch\|list\|create]` | Manage model profiles — switch cost/quality tradeoff | No |
| `/memory <save\|search\|context\|session-summary>` | Persistent cross-session memory | No |
| `/explain <topic>` | Teach a concept, pattern, or piece of code | No |
| `/meta` | Improve or debug a HIVE prompt/command | No |

### MCP integration

Gemini CLI supports MCP servers via `~/.gemini/settings.json`:

```json
{
  "mcpServers": {
    "atlassian": { "url": "https://mcp.atlassian.com/v1/mcp" },
    "context7":  { "url": "https://mcp.context7.com/mcp" },
    "figma":     { "url": "https://mcp.figma.com/mcp" }
  }
}
```

---

## Google AI Studio Setup

For web-based usage at [aistudio.google.com](https://aistudio.google.com):

1. Upload or paste the contents of `AGENTS.md` as system instructions
2. Upload `.hive/AGENTS.local.md` as a file attachment at session start
3. Type any HIVE command directly in the chat

**Best for:** `/intake`, `/strategy`, `/kickoff` (planning phases that don't require file system access)

---

## Recommended workflow by task type

| Task type | Recommended tool |
|---|---|
| Discovery, requirements, strategy | Google AI Studio (web) — interactive conversations |
| Planning (enrich, plan-be, plan-fe) | Gemini CLI — reads project files directly |
| Implementation (dev-be, dev-fe, tdd) | Gemini CLI — needs file system access |
| Code review | Gemini CLI — needs git diff access |
| Async implementation | Gemini API + your CI pipeline |

---

## Context loading strategy (token-efficient)

Gemini CLI reads files on demand. Follow this order strictly:

1. **Always first**: `AGENTS.md` (universal rules), then `.hive/AGENTS.local.md` (project config)
2. **Per command**: only the agent for the current task (`.hive/.agents/<role>.md`)
3. **Per area**: only the relevant standard (`backend.mdc` OR `frontend.mdc`, never both)
4. **Sprint context**: `.hive/specs/SPEC.md` (compact summary — preferred over querying the board)
5. **Implementation plan**: `.hive/changes/{ticket}_backend.md` (read it, don't regenerate)

**Never** load all agents and all standards at session start.

---

## AGENTS.md auto-loading

Gemini CLI reads `AGENTS.md` at the project root automatically when you launch it
in a project directory. No additional configuration needed.

---

## Fallbacks when MCPs are unavailable

If an MCP is not configured, HIVE commands fall back gracefully:

| MCP | Fallback behavior |
|---|---|
| Ticket tool (Jira, Linear) | Agent asks you to paste the ticket content |
| Figma | Agent asks for design specs as text or screenshot |
| Context7 | Agent uses training knowledge for library docs (may be outdated) |
| GitHub / GitLab | Agent outputs git commands for manual execution |
<!-- /hive:managed -->

---

<!-- hive:project-notes -->
## Project Notes

Add project-specific Gemini CLI configuration below this line.
This section is preserved by sync-standards.sh and never overwritten.
<!-- /hive:project-notes -->
