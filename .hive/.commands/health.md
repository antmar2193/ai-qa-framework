<!-- tokens: ~50 | shell script — no LLM output generation needed -->
# /health — Project Health Check

**Purpose:** Active diagnostics for the current HIVE project — surfaces misconfigurations,
stale state, and risk signals without modifying any file.

---

## When to use

Run `/health` at the start of a sprint, after onboarding, or when something feels off:
- Is the project config fully filled in?
- Is SPEC.md stale?
- Are there recent circuit breaker events?
- Are there unmerged stale branches?

---

## Steps

1. Run the shell script — it performs all 8 checks and prints the formatted report with zero LLM generation:
   ```bash
   bash .hive/scripts/hive-health.sh
   ```
   Or from the factory: `bash /path/to/hive/scripts/hive-health.sh`

2. Present the output verbatim. Do not regenerate or reformat it.

3. If the script is not found (project predates this feature), fall back to running each diagnostic check below manually.

---

## Diagnostic checks

### 1. Config completeness
Scan `.hive/AGENTS.local.md` for any field still set to a `TODO:` value.

| Severity | Condition |
|---|---|
| FAIL | Critical fields have TODO: `name`, `stack`, `tech_lead`, `communication`, `test` command |
| WARN | Non-critical fields have TODO: `board_url`, `design_tool`, `deployment.target` |
| OK | No TODO values found |

### 2. Circuit breaker config
Check that `circuit_breaker` values are within safe ranges.

| Severity | Condition |
|---|---|
| WARN | `max_tokens_per_ticket` not set or > 500,000 (unusually high budget) |
| WARN | `max_test_retries` not set or > 5 |
| WARN | `max_new_files` not set or > 20 |
| OK | All values present and within recommended range |

### 3. SPEC.md freshness
Check `.hive/specs/SPEC.md` last modified date.

| Severity | Condition |
|---|---|
| WARN | File missing (no SPEC.md yet) |
| WARN | Last modified > 14 days ago |
| OK | File exists and was modified within 14 days |

### 4. Recent events.jsonl errors
If `.hive/events.jsonl` exists, scan last 50 entries for failures.

| Severity | Condition |
|---|---|
| FAIL | Any entry with `"event":"circuit_breaker"` in the last 50 events |
| WARN | Any entry with `"status":"failed"` in the last 50 events |
| OK | No failures in recent events |

Report the most recent 3 failures if any exist: timestamp, ticket, detail.

### 5. Interrupted pipelines
Check `.hive/sessions/` for `*_state.json` files older than 24h.

| Severity | Condition |
|---|---|
| WARN | Any `*_state.json` older than 24h exists |
| INFO | Stale sessions found — list them (ticket, age, last stage) |
| OK | No stale sessions |

### 6. Branch staleness (if git available)
Run `git branch --list` and check for local branches with no commits in 7+ days.

| Severity | Condition |
|---|---|
| INFO | Branches older than 7 days with no merge — list them |
| OK | All branches are recent or merged |

### 7. Verify commands reachable
For each `verify_commands` entry that is not `null`, check that the first token of the command exists as an executable (`command -v`).

| Severity | Condition |
|---|---|
| WARN | Command binary not found in PATH (e.g. `mvn`, `dotnet`, `go`) |
| OK | All configured commands are available |

### 8. Hooks installed
Check that `.git/hooks/pre-commit` exists and references HIVE.

| Severity | Condition |
|---|---|
| WARN | `.git/hooks/pre-commit` missing — DDD checks and secret scanning won't run |
| OK | Hook file exists |

---

## Output format

```
╔══════════════════════════════════════════════╗
║   HIVE /health — {project.name}              ║
╚══════════════════════════════════════════════╝

  ✓  Config completeness        — all required fields filled
  ✓  Circuit breakers           — thresholds within range
  ⚠  SPEC.md freshness          — last modified 18 days ago
  ✗  Recent events errors       — circuit_breaker triggered on PROJ-31 (2026-04-01)
  ✓  Interrupted pipelines      — none
  ℹ  Branch staleness           — feature/PROJ-28-old-feature (12 days)
  ✓  Verify commands            — all binaries found
  ⚠  Hooks not installed        — run: bash .hive/scripts/install-hooks.sh

────────────────────────────────────────────────
  2 issue(s) found — run /status for full config
```

### Status icons
- `✓` OK — no action needed
- `⚠` WARN — worth investigating, won't block pipeline
- `✗` FAIL — should be fixed before starting sprint work
- `ℹ` INFO — informational, no action required

---

## Rules

- Read-only — no files written, no state changed, no tickets touched
- `git` commands are allowed as read-only (`git branch`, `git log --oneline`)
- Never call external APIs or MCPs
- If a check cannot run (e.g. no events.jsonl, no git), skip gracefully with `ℹ skipped`
- Total output should fit in one screen (~40 lines)
