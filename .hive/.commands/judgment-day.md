# /judgment-day — Adversarial Parallel Review
<!-- tokens: ~1300 | loads: reviewer.md (×2 independent instances) -->

**Agent:** Reviewer (read `.hive/.agents/reviewer.md`)
**Usage:**
```
/judgment-day <ticket>          # adversarial review of ticket implementation
/judgment-day <pr|branch>       # adversarial review of a PR or branch
/judgment-day --quick           # single-pass synthesis (no parallel agents, lower cost)
```

**Token cost:** High (two parallel review passes + synthesis). Use before merging critical changes.

---

## Process

### Step 0: Read configuration
Read `.hive/AGENTS.local.md`: stack, autonomy level, default base branch.

### Step 1: Gather context
Collect:
- All files changed in the ticket/PR/branch
- `.hive/changes/{ticket}_backend.yml` or `_frontend.yml` (the plan)
- `.hive/changes/{ticket}_tdd_evidence.md` (TDD compliance)
- The relevant standards (`core.mdc` + stack standard)
- Git diff against base branch
- **Ticket (acceptance criteria):**
  - `ticket_get("{ticket-id}")` via `hive-tickets` MCP
  - Fallback: `ticket_provider.mcp_name` MCP as configured in `AGENTS.local.md`
- **Prior architectural decisions:**
  - `mem_search(query="{feature domain}")` via `hive-memory` MCP
  - Fallback: `bash .hive/scripts/hive-memory.sh search "{feature domain}"`

If `.hive/changes/{ticket}_tdd_evidence.md` is missing → **BLOCKED immediately**: report "TDD evidence table missing — run /tdd before /judgment-day"

### Step 2: Two independent review passes

Run two review passes **independently** — the second pass must not see the first pass's output.

**Judge A — Architecture lens:**
Review for:
- DDD layer violations (domain importing infrastructure, etc.)
- SOLID principle violations
- Missing abstractions or over-abstraction
- Dependency direction errors
- API contract issues

**Judge B — Quality lens:**
Review for:
- Code that works but is fragile (missing edge cases, race conditions)
- Test quality (tests that pass but don't actually test behavior)
- Security issues (injection, secrets, insecure defaults)
- Performance concerns for hot paths
- Missing error handling

Each judge produces a structured report:
```
VERDICT: APPROVED | CONDITIONAL | BLOCKED
SEVERITY: CRITICAL | WARNING | SUGGESTION
Issues:
  - [CRITICAL] {file}:{line} — {description} — {fix}
  - [WARNING]  {file}:{line} — {description} — {fix}
```

### Step 3: Synthesize

Merge both verdicts:
- Any CRITICAL from either judge → overall BLOCKED
- CONDITIONAL from both → overall CONDITIONAL
- Deduplicate overlapping issues
- Rank remaining issues by severity

### Step 4: Iteration (if BLOCKED or CONDITIONAL)

If issues exist and autonomy is `autonomous`:
- Present issues to Fix Agent with exact locations and required fixes
- Fix Agent implements corrections
- Re-run both judges on changed files only (not full review)
- Max 2 iterations

If `supervised` or `balanced`: present issues to developer, stop.

### Step 5: Report

```
JUDGMENT: APPROVED | CONDITIONAL | BLOCKED
Iterations: N

Judge A (Architecture): {N} issues
Judge B (Quality): {N} issues
Merged: {N} unique issues

{issue list by severity}

{if APPROVED} → Safe to merge
{if CONDITIONAL} → Merge after addressing warnings
{if BLOCKED} → Do not merge — fix CRITICAL issues first
```

---

## Rules
- Judge B never sees Judge A's output before writing its own verdict
- CRITICAL issues always block — no exceptions
- This command is more expensive than /review — use it for critical paths, security-sensitive code, or public APIs
- TDD evidence table is checked as part of Step 1 — if missing, BLOCKED immediately
