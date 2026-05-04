# /generate — DDD Entity Scaffolding
<!-- tokens: ~1200 | loads: coder.md, stacks/<stack>/generate.yml -->

**Agent:** Coder (read `.hive/.agents/coder.md`)
**Usage:**
```
/generate <EntityName>                         # scaffold all DDD layers for this entity
/generate <EntityName> --area backend          # backend layers only
/generate <EntityName> --area frontend         # frontend layers only
/generate <EntityName> --dry-run               # list files that would be created, no writes
/generate <EntityName> --skill <skill-name>    # use a specific custom skill template
/generate --skills                             # list available custom skills in .hive/.skills/
```

**Token efficiency:** Step 0.5 calls `hive-generate.sh` to create all boilerplate for zero LLM tokens.
The agent only fills in what the script cannot: entity fields, business logic, test cases.
Total token cost is ~60% lower than manual generation.

---

## Process

### Step 0: Read configuration
Read `.hive/AGENTS.local.md`:
- `stack` — determines which template set to use
- `vcs.default_base_branch` — for branch creation
- autonomy level — determines whether to pause before writing

Check `.hive/sessions/focus.md` — if it exists, all generated files must be inside the focused path.

Check `.hive/AGENTS.local.md` `legacy.protected_paths` — generated files must not overlap with protected paths.

### Step 0.5: Run hive-generate.sh (zero LLM tokens)

Before generating any file content manually, call the scaffold script:

```bash
bash .hive/scripts/hive-generate.sh <EntityName> [--area <backend|frontend>] [--dry-run] [--skill <name>]
```

The script:
1. Reads `.hive/generate.yml` (or the matching skill file from `.hive/.skills/`)
2. Resolves all naming variants (PascalCase, camelCase, snake_case, kebab-case)
3. Creates directories and writes template-based stubs for every DDD layer
4. Produces a manifest of created files

**If the script succeeds:** skip Steps 1–4 (file path resolution and stub writing). Go directly to Step 5 (report), then instruct the user to fill in entity fields, use case methods, and test cases.

**If the script fails** (no `generate.yml`, python3 unavailable, etc.): fall through to manual Steps 1–4.

**If `--dry-run` was passed:** call the script with `--dry-run`, report the file list to the user, stop.

---

### Step 1: Resolve entity naming
From `<EntityName>` (e.g. `Employee`, `PaymentOrder`, `UserProfile`):
- `PascalCase`: `Employee` — used in class/struct/type names
- `camelCase`: `employee` — used in variable names, function params
- `snake_case`: `employee` — used in file names (Python, Go), DB columns
- `kebab-case`: `employee` — used in URL paths
- `SCREAMING_SNAKE`: `EMPLOYEE` — used in constants (rare)
- `plural`: `employees` — used in route paths, collection names

Derive all forms. Confirm entity name with user if it contains more than 2 words.

### Step 2: Determine files to generate

Resolution order — first match wins:

**1. Project-level custom skill (`.hive/.skills/`)**

Check `.hive/.skills/` for a matching skill file:
- If `--skill <name>` was passed → load `.hive/.skills/<name>.yml` (fail if not found)
- Else → look for `.hive/.skills/<EntityName>.yml` (entity-specific override)
- Else → look for any `.hive/.skills/*.yml` whose `matches:` pattern matches the entity name

If found → use as the authoritative file mapping. Skip steps 2 and 3.

Custom skill files follow the same schema as `generate.yml` with an additional optional `matches:` key:
```yaml
# .hive/.skills/aggregate.yml — applies to entities matching ".*Aggregate"
matches: ".*Aggregate"   # optional regex; if absent, match by filename only
entity_files:
  domain:
    - path: "..."
      template: "..."
naming:
  entity: pascal
  file:   kebab
  var:    camel
```

**2. Stack-level generate.yml (`.hive/generate.yml`)**

Check if `.hive/` has a `generate.yml` (synced from the stack by `sync-standards.sh`). If it exists, use it as the authoritative file mapping — skip STACK.md parsing for file paths.

If `generate.yml` does not exist → fall back to parsing `.hive/STACK.md` as described below.

**3. STACK.md parsing (fallback)**

Read `.hive/STACK.md` — the authoritative source for the project's file structure.

Find the **Project Layout** section (usually a directory tree). From it, identify:
1. **Domain layer path** — where entities, value objects, domain errors live
2. **Application layer path** — where services and use cases live
3. **Infrastructure layer path** — where repository implementations, DB clients, external adapters live
4. **Presentation layer path** — where controllers, handlers, routes, resolvers live
5. **Test paths** — co-located (same directory) or separate (`tests/`, `*_test.go`, `*.test.ts`)

For each identified layer, derive the correct file to create for `<EntityName>`:
- Use the naming conventions defined in `.hive/standards/backend.mdc` or `.hive/standards/frontend.mdc`
- The standards file specifies: file naming pattern, class/struct naming, test file convention
- If the stack uses co-located tests (e.g. Go `_test.go`, Jest `.test.ts`) → generate test alongside source
- If tests are in a separate directory → generate test in the correct test path

**Generate exactly one file per layer** unless the standards explicitly define multiple files per layer for that entity (e.g. separate Command and Query files in CQRS stacks — this will be specified in backend.mdc).

If `.hive/STACK.md` does not exist or has no Project Layout section:
→ Warn: "STACK.md not found or has no project layout. Run /assess or configure .hive/STACK.md first."
→ STOP

If `--area backend` → generate only domain + application + infrastructure + backend tests
If `--area frontend` → generate only presentation + frontend component/hook files (read frontend.mdc for structure)

### Step 3: Generate stubs (template-guided)

For EACH file, follow the exact patterns from `.hive/standards/backend.mdc` or `.hive/standards/frontend.mdc`. Do NOT invent patterns — instantiate the ones defined in the standards.

**Stub rules:**
- Complete type signatures on all methods (no `any`, no untyped params)
- Method body: `throw new Error("Not implemented")` / `panic("not implemented")` / `raise NotImplementedError` / `TODO()` — appropriate for the language
- Tests: correct structure (table-driven for Go, describe/it for Jest, pytest functions) with 2-3 example cases as `// TODO: implement` stubs
- Imports: only what the stub actually references
- No placeholder comments like `// Add your logic here` — use the language's "not implemented" convention

### Step 4: Write files

`--dry-run`: list all file paths that would be created. Do not write.

`supervised` or standard: present the file list, confirm before writing.

`balanced` / `autonomous`: write immediately.

For each file written:
- Create parent directories if needed
- Skip and warn if file already exists (never overwrite)
- Log to `.hive/events.jsonl` if autonomy is `autonomous`

### Step 5: Report

**If `--skills` was passed:**
```
Available custom skills in .hive/.skills/:

  aggregate.yml     matches: .*Aggregate   (event-sourced aggregate)
  value-object.yml  matches: .*Value       (value object pattern)
  saga.yml          (no match pattern — use with --skill saga)

Usage: /generate <EntityName> --skill <skill-name>
```

**Otherwise — list every file created with its layer:**
```
✓ domain/employee.go              [domain]
✓ domain/employee_test.go         [test — red phase stub]
✓ application/employee_service.go [application]
✓ ...

Skill used: .hive/.skills/aggregate.yml  (or: stacks/<stack>/generate.yml)

Next step: /tdd PROJ-123 — write failing tests from acceptance criteria
           /dev-be PROJ-123 — implement the logic
```

---

## Rules
- Never overwrite existing files — skip with warning
- Always follow the standards in `.hive/standards/backend.mdc` or `frontend.mdc`
- Generated stubs must pass typecheck and lint with only "not implemented" errors
- Focus scope from `focus.md` must be respected — do not write outside it
- If `legacy.protected_paths` contains any of the target paths → STOP and report
