# /review — Code Review
<!-- tokens: ~1300 | loads: reviewer.md -->

**Agent:** Reviewer (read `.hive/.agents/reviewer.md`)
**Usage:** `/review [pr-number | branch-name]`
If no argument → review the current branch diff vs `vcs.default_base_branch`.

---

## Process

### Step 0: TDD Compliance Check

Before reviewing code quality, verify TDD was followed:

1. Check `.hive/changes/{ticket}_tdd_evidence.md` exists
2. All rows must have RED ✅ confirmed and GREEN ✅ confirmed
3. If any row is ⬜ pending or ❌ failed → **STOP**: report "TDD evidence incomplete for {test name}"
4. If file does not exist → **STOP**: report "TDD evidence table missing — run /tdd before /review"

This check cannot be bypassed. It is the difference between "code that works" and "code that was proven to work."

### 1. Get the diff
- With GitHub MCP: `gh pr diff <pr-number>`
- Without MCP: `git diff {vcs.default_base_branch}...HEAD`

### 2. Get the ticket
Retrieve the linked ticket (from PR title or branch name):
- `ticket_get("{ticket-id}")` via `hive-tickets` MCP
- Fallback: use `ticket_provider.mcp_name` MCP (Atlassian, Linear, etc.) as configured in `AGENTS.local.md`
- Fallback: ask the user for the acceptance criteria

### 3. Run the review checklist

#### Correctness
- [ ] Every acceptance criterion from the ticket is addressed
- [ ] Every criterion has at least one test
- [ ] Edge cases handled (null inputs, empty collections, concurrent writes)

#### TDD compliance
- [ ] TDD evidence table exists: `.hive/changes/{ticket}_tdd_evidence.md`
      All rows must show RED ✅ and GREEN ✅
      If table is absent or has pending/failed rows → BLOCK: TDD compliance not demonstrated
- [ ] Test commits predate implementation commits (check git log)
- [ ] No implementation without a corresponding test

#### Architecture (DDD)
- [ ] Code is in the correct layer
- [ ] No business logic in controllers
- [ ] No cross-domain direct data access
- [ ] Aggregate root enforces invariants

#### SOLID
- [ ] Functions ≤ 20 lines
- [ ] Classes have single responsibility
- [ ] Dependencies are on abstractions, not concretions

#### Type safety
- [ ] No `any`
- [ ] No non-null assertions `!` without justification
- [ ] All exported function return types explicit

#### Security
- [ ] All inputs validated before use
- [ ] No secrets or PII in logs
- [ ] Auth verified before data access
- [ ] No string concatenation in queries

#### Test quality
- [ ] Tests use AAA pattern
- [ ] Test names read as specifications
- [ ] No `test.only`, `test.skip`, `xit`, `fit`
- [ ] Coverage ≥ 90% on new backend code

#### Documentation
- [ ] Docs updated alongside code changes
- [ ] `api-spec.yml` updated if API changed
- [ ] `data-model.md` updated if schema changed

### 4. Post findings

Severity levels:
- 🔴 **CRITICAL** — blocks merge: security issue, missing test, DDD violation
- 🟡 **WARNING** — should fix: naming, type safety, SOLID
- 🔵 **SUGGESTION** — optional: style improvement, future consideration

Output format:
```
## Review: [APPROVE | REQUEST_CHANGES | COMMENT]

### 🔴 Critical
- `src/controllers/employee.ts:42` — Business logic in controller.
  Move email uniqueness check to EmployeeService.

### 🟡 Warnings
- `src/services/employee.ts:88` — `any` type on error catch.
  Use `unknown` and narrow.

### 🔵 Suggestions
- Consider extracting email normalization into an Email value object.

### Verdict
REQUEST_CHANGES — 1 critical issue must be resolved before merge.
```

If using GitHub MCP → post review as PR comment.
If not → output to chat.
