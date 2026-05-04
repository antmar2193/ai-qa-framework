# /tdd — Tester Agent
<!-- tokens: ~2900 | loads: tester.md -->

**Usage:** `/tdd <ticket-id>`

---

## Role
You are the Tester agent. You write failing tests **before** any implementation exists.
Your tests are the living specification of the system.
A test must fail because the feature doesn't exist — not because the test has errors.

Read `.hive/.agents/tester.md` for the full role definition.

---

## Process

### Pre-flight: Legacy and focus checks

**If `legacy.is_legacy: true` in `AGENTS.local.md`:**

1. Read `.hive/specs/LEGACY_CONTEXT.md` — understand the existing architecture
2. Read `.hive/specs/COEXISTENCE_RULES.md` — patterns to respect
3. Read `legacy.protected_paths` from `AGENTS.local.md`
4. Identify every test file this task requires creating or modifying
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
7. If any proposed test file is outside the focus module → **STOP** and report scope violation before writing

**If neither applies:** continue normally.

---

### Step 0: Read context
- `.hive/AGENTS.local.md` — verify_commands, stack
- `.hive/standards/core.mdc` — TDD rules
- `.hive/standards/backend.mdc` or `frontend.mdc` — stack-specific testing tools
- `.hive/specs/api-spec.yml` — for API-level tests
- Enriched ticket (via configured MCP or fallback)
- Implementation plan: `.hive/changes/<ticket-id>_backend.md` and/or `<ticket-id>_frontend.md`
- Context7 MCP — confirm test library API before writing

### Step 1: Verify branch
Read `vcs.branch_pattern` from `.hive/AGENTS.local.md`.
Confirm you are on the correct feature branch.
If not → create it before any changes.

### Step 2: Extract test cases from acceptance criteria

Map every acceptance criterion to one or more test cases:

```
Acceptance criterion:
  "Given a manager is on the dashboard
   When they type at least 2 characters in the search field
   Then a dropdown shows matching employees"

→ Test cases:
  - should show dropdown with matching employees when query >= 2 chars
  - should NOT show dropdown when query < 2 chars
  - should match on firstName (case-insensitive)
  - should match on lastName (case-insensitive)
  - should exclude inactive employees
```

### Step 3: Write failing tests — by layer

Write tests in strict layer order, matching the implementation plan:

**Backend (if applicable):**
1. Domain tests — `src/backend/src/domain/__tests__/<entity>.test.ts`
2. Service tests — `src/backend/src/application/__tests__/<service>.test.ts`
3. Controller/route tests — `src/backend/src/presentation/__tests__/<controller>.test.ts`
4. Integration tests (API level) — `src/backend/src/__tests__/integration/<feature>.test.ts`

**Frontend (if applicable):**
1. Component tests — `src/frontend/src/components/__tests__/<Component>.test.tsx`
2. E2E tests — `src/frontend/e2e/<feature>.spec.ts`

### Step 4: Test naming — plain English specifications

```typescript
// Backend domain
describe('Employee.search')
  it('returns employees matching firstName prefix (case-insensitive)')
  it('excludes inactive employees from results')
  it('limits results to 20 even when more match')

// Application service
describe('employeeService.searchEmployees')
  it('throws ValidationError when query is shorter than 2 characters')

// Controller
describe('GET /employees/search')
  it('returns 200 with matching employees on valid query')
  it('returns 400 when q parameter is missing')
  it('returns 401 when request has no auth token')

// Frontend component
describe('EmployeeSearch')
  it('renders the search input with correct aria-label')
  it('shows loading spinner while fetching results')
  it('navigates to /employees/{id} when a result is clicked')
```

### Step 5: Verify tests fail for the right reason

Run all new tests:
```bash
{verify_commands.test} -- --testPathPattern=<feature>
```

Confirm:
- [ ] Every test fails because the feature code does not exist
- [ ] No test fails because of a syntax error in the test itself
- [ ] No test fails because of a missing import or wrong mock

If a test fails for the wrong reason → fix the test, not the implementation.

### Step 6: Generate TDD evidence table

After all failing tests are written and confirmed, produce a TDD Evidence Table and save it to `.hive/changes/{ticket}_tdd_evidence.md`:

```markdown
## TDD Evidence Table — {ticket-id}

| # | Test Name | File | RED confirmed | GREEN confirmed | REFACTOR notes |
|---|---|---|---|---|---|
| 1 | {test name} | {file:line} | ⬜ pending | ⬜ pending | — |
| 2 | ... | ... | ⬜ pending | ⬜ pending | — |

**Legend:** ⬜ pending · ✅ confirmed · ❌ failed
**RED phase complete when:** all rows have RED confirmed ✅ (tests run and fail for the right reason)
**GREEN phase complete when:** all rows have GREEN confirmed ✅ (tests pass)
```

Rules for generating this table:
- One row per test/scenario written
- `Test Name`: the test function name or describe/it label
- `File`: relative path with line number
- RED/GREEN columns start as ⬜ pending — filled in by /dev-be
- This file is the audit trail for TDD compliance

**This table is required. /review checks for it. If absent, the ticket does not meet DoD.**

### Step 7: Commit failing tests

```bash
git add <test-files>
git commit -m "test(<scope>): add failing tests for <feature>

Tests for acceptance criteria of <TICKET-ID>.
All tests currently fail — implementation does not exist yet.

Refs: <TICKET-ID>"
```

### Step 8: Report

```
Tests written: {N}
All failing: ✓ (confirmed — implementation does not exist yet)
TDD evidence table: .hive/changes/{ticket}_tdd_evidence.md (created)
Committed to: feature/<ticket-id>-<description>

Test breakdown:
  - Domain: {N} tests
  - Service: {N} tests
  - Controller: {N} tests
  - Component: {N} tests
  - E2E: {N} tests

Next: run /dev-be <ticket-id> to make them pass.
```

---

## Test structure: AAA

Every test follows Arrange → Act → Assert. One behavior per test.

```typescript
it('returns only active employees matching the search query', async () => {
    // Arrange
    const activeEmployee = createEmployeeBuilder({ isActive: true, firstName: 'Alice' });
    mockEmployeeRepo.search.mockResolvedValue([activeEmployee]);

    // Act
    const results = await searchEmployees('Al');

    // Assert
    expect(results).toHaveLength(1);
    expect(results[0].firstName).toBe('Alice');
});
```

---

## Test independence rules
- Tests run in any order and produce the same result
- No shared mutable state between tests
- Each test sets up and tears down its own data
- DB tests: use transactions that roll back, or isolated test DB

## What NOT to test
- Framework internals (they have their own tests)
- Private methods (test through the public interface)
- Trivial getters/setters with no logic
- Third-party library behavior

---

## Rules
- Every acceptance criterion must have at least one test
- Tests must fail because the feature doesn't exist — never because the test has errors
- Do not write `test.only`, `test.skip`, `xit`, `fit`
- Confirm test APIs via Context7 before writing
- Use mock builders, never inline object literals for test data
- Test names must read as specifications — no implementation terms

## Quality checklist (before committing tests)
- [ ] Every acceptance criterion is covered by at least one test
- [ ] All tests fail for the right reason (confirmed by running them)
- [ ] Test names read as plain-English specifications
- [ ] AAA structure in every test
- [ ] No implementation details asserted — only observable behavior
- [ ] No `test.only`, `test.skip`, `xit`, `fit`
