# AGENTS.local.md — AI-QA-FRAMEWORK
# Injected: 2026-04-20 from hive | Stack detected: python-playwright (corrected 2026-04-30)
#
# Especially: set the correct status names from your none board.

---

## Project Identity

```yaml
name: "AI-QA-FRAMEWORK"
tech_lead: "Antonio"
stack: "python-playwright"
```

---

## Autonomy

```yaml
autonomy:
  # supervised (default): checkpoints on plan, commit, and ambiguous decisions
  # balanced: checkpoint only on plan; commit, tests, docs are autonomous
  # autonomous: zero checkpoints; agent executes full pipeline without stopping
  level: "supervised"

  circuit_breaker:
    max_test_retries: 3
    max_new_files: 5
    max_tokens_per_ticket: 200000
```

---

## Ticket Provider

```yaml
ticket_provider:
  tool: "none"
  mcp_name: "none"
  board_url: ""
  id_format: "PROJ-{number}"

  statuses:
    backlog:     "backlog"
    to_refine:   "to_refine"
    refined:     "refined"
    in_progress: "in_progress"
    in_review:   "in_review"
    done:        "done"
    blocked:     "blocked"

  auto_transition_after_enrich: true
```

---

## Build & Verification Commands

# Auto-detected from project files. Verify these match your project's scripts.

```yaml
verify_commands:
  test:      "pytest"
  typecheck: "mypy src/"
  lint:      "ruff check ."
  coverage:  "pytest --cov=src --cov-report=term-missing --cov-fail-under=50"
  build:     "null"
```

---

## Package Manager

```yaml
package_manager:
  tool: "pip"
```

---

## Version Control

```yaml
vcs:
  platform:            "github"
  mcp_name:            "GitHub"
  default_base_branch: "main"
  branch_pattern:      "feature/{ticket-id}-{description}"
  pr_tool:             "gh"
  ai_trailer:          true
```

---

## Design Tool

```yaml
design_tool:
  tool:     "none"
  mcp_name: "none"
```

---

## Fallbacks

```yaml
fallbacks:
  ticket_unavailable: "ask"
  design_unavailable: "ask"
  ticket_paste_format: |
    Please paste the ticket content:
    ---
    ID: <ticket-id>
    Title: <title>
    Description: <full description>
    Acceptance Criteria:
    - <criterion 1>
    Current Status: <status>
    ---
```

---

## Project-Specific Rules

# Legacy project context — add notes for agents about existing patterns,
# conventions already in place, or things that should NOT be changed.
# Example: "This project uses class components — do not convert to functional"
# Example: "Authentication is handled by an external SSO — do not implement locally"

---

## Legacy

```yaml
legacy:
  is_legacy: true

  # Detected characteristics — verify and adjust
  detected:
    monorepo: "none"
    frontend_framework: "none"
    orm: "none"
    test_runner: "pytest"
    ci: "github-actions"
    docker: false
    auth: "none"

  # Files/directories agents must NOT modify
  protected_paths: []
    # - "src/auth/"
    # - "src/payments/"

  # Patterns to respect in existing code (even if they violate HIVE standards)
  existing_patterns:
    components: "mixed"       # class | functional | mixed
    state_management: "none"
    styling: "none"
    testing: "pytest"
    orm: "none"
    api_style: "rest"        # rest | graphql | grpc | mixed

  # Gradual migration strategy
  migration:
    enabled: true
    strategy: "strangler-fig"     # strangler-fig | big-bang | module-by-module
    new_code_standard: "hive"     # new files follow HIVE standards
    max_migrations_per_sprint: 2  # limit refactoring scope

  # Context files agents must read before any action
  required_reading:
    - ".hive/specs/LEGACY_CONTEXT.md"
    - ".hive/specs/COEXISTENCE_RULES.md"
```
