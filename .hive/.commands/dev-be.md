# /dev-be — Backend Implementation
<!-- tokens: ~1800 | loads: coder.md, standards/backend.mdc, .hive/changes/{ticket}_backend.md -->

**Agent:** Coder (read `.hive/.agents/coder.md`)
**Usage:** `/dev-be <ticket-id>`
**Autonomy checkpoints:** See `autonomy.level` in `AGENTS.local.md`

---

## Process

### Pre-flight: Legacy and focus checks

**If `legacy.is_legacy: true` in `AGENTS.local.md`:**

1. Read `.hive/specs/LEGACY_CONTEXT.md` — understand the existing architecture
2. Read `.hive/specs/COEXISTENCE_RULES.md` — patterns to respect
3. Read `legacy.protected_paths` from `AGENTS.local.md`
4. Identify every backend file this task requires creating or modifying
5. If ANY of those files is inside a `protected_path` → **STOP**:
   ```
   ⚠️ Protected path conflict: {file} is in {protected_path}
   Reason for protection: review AGENTS.local.md → legacy.protected_paths
   Options:
     a) Adjust the implementation to avoid touching the protected path
     b) Ask the Tech Lead to remove the protection if appropriate
     c) Proceed with only non-protected files (partial implementation)
   ```

**If `.hive/sessions/focus.md` exists:**

6. Read the focus scope from `.hive/sessions/focus.md`
7. If any proposed backend file is outside the focus module → **STOP** and report scope violation before writing

**If neither applies:** continue normally.

---

### Step 0.5: Load machine-readable plan

Check if `.hive/changes/{ticket}_backend.yml` exists.

**If YES:**
- Read it — do NOT regenerate the plan
- Use `files` list as the authoritative list of files to create/modify
- Use `steps` list as the implementation order
- If `dependencies.new_packages` is not empty → install them now before coding
- If `dependencies.migrations: true` → remind the developer to run migrations after implementation

**If NO:**
- Warn: "No machine-readable plan found for {ticket}. Run /plan-be first."
- Check if `.hive/changes/{ticket}_backend.md` exists as fallback
- If neither exists → **STOP** and tell the user to run `/plan-be`

---

### Step 0.6: Load TDD evidence table

Check for `.hive/changes/{ticket}_tdd_evidence.md`.

**If found:**
- Read it — these are the tests that must pass
- After each test is made to pass → update the corresponding row: RED ✅, GREEN ✅
- Use HIVE_SKIP_HOOKS=1 only if explicitly told to by the user
- After all rows are GREEN ✅ → the implementation phase is complete

**If not found:**
- Warn: "No TDD evidence table found. Run /tdd first to ensure tests exist."
- Check if test files exist as fallback

---

### Step 0.7: Load cross-session memory

Via `hive-memory` MCP:
- `mem_search(query="{ticket-id}")` — retrieve prior work on this ticket
- `mem_search(query="{domain}")` — retrieve architectural decisions for this domain
- If results found: incorporate constraints/decisions into the implementation

Fallback (MCP unavailable): `bash .hive/scripts/hive-memory.sh search "{ticket-id}"`

---

### 1. Read context (mandatory before touching any code)
- `.hive/AGENTS.local.md` — verify_commands, stack, vcs config
- Implementation plan: `.hive/changes/<ticket-id>_backend.yml` (or `_backend.md` fallback)
- `.hive/standards/core.mdc`
- `.hive/standards/backend.mdc` — stack-specific patterns and conventions
- Failing tests already committed by `/tdd`

### 2. Verify branch
Read `vcs.branch_pattern` from `.hive/AGENTS.local.md`.
Confirm you are on the correct backend feature branch.
If not → create it before any changes.

### 3. Confirm library APIs via Context7 (before every external call)
```
resolve-library-id('<library>') → query-docs(id, '<method or feature>')
```
Never rely on training-data memory for library API signatures.
This applies to every framework, ORM, validation library, or utility used.

### 4. Implement following the plan
Execute subtasks in the exact order specified in the plan.
After each subtask: run tests, confirm still passing or now passing.

### 5. TDD discipline
- Green phase: write the minimum code to pass the failing test
- Refactor phase: clean up without breaking tests
- Never write code not tested by an existing failing test
- Never modify test files to make them pass — surface the conflict instead

### 6. After implementation
Read `verify_commands` from `.hive/AGENTS.local.md` and run each in order.
Skip any command set to `null`.

```
verify_commands.test        → all tests must pass
verify_commands.typecheck   → zero type errors (skip if null)
verify_commands.lint        → zero warnings (skip if null)
verify_commands.coverage    → coverage threshold met (skip if null)
```

Do not proceed to commit if any command fails.

### 7. Update documentation
Run `/update-docs` before committing:
- Identify which docs changed: data-model, api-spec, backend standards
- Update each affected file in the same commit

### 8. Save to memory

If any non-obvious decisions were made during implementation, persist them now:

**MCP:** `mem_save(title="...", content="...", topic_key="plan/{ticket-id}", type="plan")`
**Bash:** `bash .hive/scripts/hive-memory.sh save --topic-key "plan/{ticket-id}" --content "..."`

Examples worth saving: chosen approach when alternatives existed, discovered constraints, performance decisions, security choices.

### 9. Commit
Follow `/commit` — do not proceed to PR if any check fails.

## Rules
- Implement one subtask at a time — run tests between each
- Never modify test files to make them pass — surface the conflict instead
- Respect domain boundaries — services never reach into another domain's data
- No untyped code — use the type system the stack provides
- All library API signatures confirmed via Context7 before use
- No debug logging in production paths — use the project's logger (defined in backend.md)
- All inputs validated at the boundary before reaching business logic
