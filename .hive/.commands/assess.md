# /assess — Legacy Project Assessment
<!-- tokens: ~3500 | loads: architect.md -->

**Agent:** Architect (read `.hive/.agents/architect.md`)
**Usage:** `/assess`

Analyzes an existing codebase to understand its structure, patterns, and constraints
before starting new development. Essential for legacy projects injected with HIVE.

**Who runs it:** Tech Lead
**When:** After `inject-factory.sh`, before `/kickoff` or `/sprint-setup`

---

## Output files (all generated automatically)

| File | Purpose |
|---|---|
| `.hive/specs/LEGACY_CONTEXT.md` | Structured analysis ALL agents read before acting |
| `.hive/specs/TECH_DEBT.md` | Prioritized technical debt register |
| `.hive/specs/COEXISTENCE_RULES.md` | Rules for the transition period |
| `.hive/specs/ARCHITECTURE.md` | Updated architecture document |

---

## Process

### Step 1: Read project structure
Scan the project filesystem to understand:
- Directory structure and organization pattern
- Key configuration files (package.json, pom.xml, .csproj, requirements.txt, go.mod)
- Framework and library versions
- Existing test setup (if any)
- Database configuration and ORM setup
- CI/CD configuration (if any)
- Environment variable inventory (from `.env.example` or code scanning)

### Step 2: Detect project characteristics

Run expanded detection across all areas. The table below is a **starting point, not an exhaustive list**.
Detect and document anything found in the actual code — if a pattern, tool, or framework exists but is not listed here, document it anyway.

| Detection area | Common patterns to look for |
|---|---|
| **Monorepo** | `pnpm-workspace.yaml`, `lerna.json`, `nx.json`, `turbo.json`, `bun.workspace` |
| **Frontend framework** | `next.config.*`, `nuxt.config.*`, `angular.json`, `vite.config.*`, `remix.config.*`, CRA setup |
| **ORM / DB access** | `prisma/`, TypeORM config, Sequelize, `drizzle.config.*`, Knex, SQLAlchemy, Hibernate |
| **Test runner** | `jest.config.*`, `vitest.config.*`, `.mocharc.*`, `karma.conf.*`, `pytest.ini`, `rspec` |
| **CI pipeline** | `.github/workflows/`, `.gitlab-ci.yml`, `Jenkinsfile`, `.circleci/`, `bitbucket-pipelines.yml` |
| **Docker** | `Dockerfile`, `docker-compose.yml`, `.dockerignore` |
| **Auth mechanism** | Passport, NextAuth, Auth0, Firebase Auth, JWT middleware, OAuth2, SAML, session-based |
| **API style** | REST routes, GraphQL schema, gRPC proto files, tRPC router, REST Framework (Django/DRF) |
| **State management** | Redux, MobX, Zustand, Context API, Pinia, Vuex, Jotai, Recoil |
| **Runtime / package manager** | Node/npm/yarn/pnpm, Bun, Deno, Poetry, pip, Cargo, Go modules |
| **Any other pattern found** | Document it — do not ignore unknown tools or conventions |
| **Styling** | Tailwind, CSS Modules, styled-components, Sass, Bootstrap |

### Step 2.5: Security and vulnerability scan

Run security checks appropriate for the detected stack. Document all findings — do not skip even if the project "seems secure."

#### Dependency vulnerability check

Run the appropriate command based on detected stack:

| Stack | Command |
|---|---|
| Node.js | `npm audit --json` or `npx audit-ci --moderate` |
| Python | `pip-audit` or `safety check` (install if needed: `pip install pip-audit`) |
| Java/Maven | `mvn dependency:check -DfailBuildOnCVSS=7` |
| .NET | `dotnet list package --vulnerable` |
| Go | `govulncheck ./...` (install: `go install golang.org/x/vuln/cmd/govulncheck@latest`) |

If the command is not installed → note it as "not checked — install {tool} to scan."

#### Code pattern scan

Search for common security anti-patterns using grep/search across the codebase:

| Pattern | What to look for | Risk |
|---|---|---|
| Hardcoded secrets | `password\s*=\s*["'][^"']+["']`, `secret\s*=\s*["']`, `api_key\s*=` in source files (not .env.example) | Critical |
| SQL injection | String concatenation in SQL queries: `"SELECT * FROM" + `, f-string SQL | Critical |
| Insecure HTTP | `http://` in API client configs (not localhost/test) | High |
| JWT without expiry | JWT creation without `exp` claim | High |
| Disabled SSL verify | `verify=False`, `InsecureRequestWarning`, `rejectUnauthorized: false` | High |
| Debug mode in prod config | `DEBUG=True`, `debug: true` in production config files | Medium |
| Outdated auth | MD5/SHA1 for passwords (not bcrypt/argon2/scrypt) | Critical |
| Missing rate limiting | No rate limit middleware on auth endpoints | Medium |

#### Environment variable audit

- Check `.env.example` for variables that look like they should be secrets but might be committed with real values
- Check if `.env` is in `.gitignore` — if not, flag as Critical

#### Document findings in TECH_DEBT.md security section

For each vulnerability found, add to TECH_DEBT.md with category "Security" and appropriate severity.

---

### Step 3: Identify architectural patterns
Determine the current architecture:
- **MVC** — controllers, models, views
- **Layered/DDD** — domain, application, infrastructure, presentation
- **Monolith** — single app, mixed concerns
- **Microservices** — multiple services, API gateway
- **Other** — describe what exists

### Step 4: Identify conventions already in place
Document existing patterns that agents must follow:
- Naming conventions (file names, function names, variable names)
- Error handling patterns
- Logging patterns
- Authentication/authorization approach
- API response format
- Database access patterns
- Component patterns (class vs functional, state management)

### Step 5: Generate LEGACY_CONTEXT.md

Save to: `.hive/specs/LEGACY_CONTEXT.md`

This file is read by ALL agents before any action on the project:

```markdown
# Legacy Context — {Project Name}
_Assessment date: {date}_

## Architecture Pattern
{MVC | Layered | DDD | Monolith | Microservices | Other}
{Description of how code is organized}

## Directory Structure
```
{actual directory tree with responsibility labels}
```

## Framework & Library Inventory
| Library | Version | Purpose | Status |
|---|---|---|---|
| {name} | {version} | {purpose} | current / outdated / deprecated / vulnerable |

## Database
- **ORM/Access:** {Prisma | TypeORM | Sequelize | Drizzle | Knex | raw SQL | none}
- **Database:** {PostgreSQL | MySQL | MongoDB | SQLite | etc.}
- **Schema summary:** {N models, key relationships}
- **Migrations:** {tool and status}

## API Surface
| Method | Endpoint | Description | Auth |
|---|---|---|---|
| {GET} | {/api/users} | {List users} | {JWT / API key / none} |

## Auth Mechanism
{Description of how auth works — JWT, sessions, OAuth, etc.}

## CI/CD Pipeline
{Description of existing CI or "none detected"}

## Environment Variables
| Variable | Purpose | Required |
|---|---|---|
| {name} | {purpose} | yes/no |

## Test Coverage
- **Framework:** {Jest | Vitest | Mocha | pytest | none}
- **Current coverage:** {percentage or "unknown"}
- **Test patterns:** {describe what exists}
```

### Step 6: Generate TECH_DEBT.md

Save to: `.hive/specs/TECH_DEBT.md`

```markdown
# Technical Debt Register — {Project Name}
_Assessment date: {date}_

| ID | Category | Severity | Description | Effort | Recommendation |
|----|----------|----------|-------------|--------|----------------|
| TD-01 | {Testing/Types/Security/Architecture/Dependencies/Performance} | {Critical/High/Medium/Low} | {description} | {S/M/L/XL} | {actionable recommendation} |
```

Severity guide:
- **Critical** — active security vulnerability (CVE, exposed secrets, SQL injection) — fix before next sprint
- **High** — security risk, data integrity, or blocking new development
- **Medium** — maintainability concern, developer friction
- **Low** — cosmetic, nice-to-have improvement

Effort guide: S (≤2h), M (half day), L (full day), XL (multi-day, must split)

### Step 7: Generate COEXISTENCE_RULES.md

Save to: `.hive/specs/COEXISTENCE_RULES.md`

```markdown
# Coexistence Rules — {Project Name}
_Assessment date: {date}_

## Guiding Principle
Existing files maintain current patterns. New files follow HIVE standards.

## Existing Patterns to Respect
- **Components:** {class | functional | mixed} — do not convert existing files
- **State management:** {redux | context | mobx | zustand | none}
- **Styling:** {css-modules | styled-components | tailwind | sass | bootstrap}
- **Testing:** {jest | vitest | mocha | none} — use existing runner for existing tests
- **ORM:** {prisma | typeorm | sequelize | drizzle | knex} — use existing ORM
- **API style:** {rest | graphql | grpc | mixed}

## Migration Limits
- Max files converted to new patterns per sprint: 2
- Migration must be a separate ticket — never mix migration with feature work

## Protected Paths (DO NOT MODIFY)
- {path}: {reason}

## New Code Rules
- New files follow HIVE stack standards (`.hive/standards/`)
- New tests use the project's existing test runner
- New components use the new pattern (functional + hooks if React)
- New API endpoints follow the existing response format
```

### Step 8: Update AGENTS.local.md legacy section

Propose additions to the `legacy` section of `.hive/AGENTS.local.md`:

```yaml
legacy:
  is_legacy: true
  protected_paths:
    - "{detected protected paths}"
  existing_patterns:
    components: "{detected}"
    state_management: "{detected}"
    styling: "{detected}"
    testing: "{detected}"
    orm: "{detected}"
    api_style: "{detected}"
  migration:
    enabled: true
    strategy: "strangler-fig"
    new_code_standard: "hive"
    max_migrations_per_sprint: 2
  required_reading:
    - ".hive/specs/LEGACY_CONTEXT.md"
    - ".hive/specs/COEXISTENCE_RULES.md"
```

**Ask the tech lead to review and approve before saving.**

### Step 9: Update ARCHITECTURE.md

Update `.hive/specs/ARCHITECTURE.md` with detected architecture, same as v1 format.

### Step 10: Report

```
Assessment complete:
  - Architecture: {pattern}
  - Stack: {summary}
  - Technical debt items: {N} ({high}H / {medium}M / {low}L)
  - Constraints documented: {N}
  - Protected paths: {N}

Generated files:
  - .hive/specs/LEGACY_CONTEXT.md     ← ALL agents read this
  - .hive/specs/TECH_DEBT.md          ← prioritized debt register
  - .hive/specs/COEXISTENCE_RULES.md  ← transition rules
  - .hive/specs/ARCHITECTURE.md       ← system structure

Proposed AGENTS.local.md legacy config shown above.
Review and approve to save.

Next steps:
  1. Review and approve the legacy config
  2. Fill in .hive/specs/PRD.md with new feature requirements
  3. Run /kickoff or /sprint-setup to start development
```

---

## Rules
- Never assume patterns — analyze actual code
- Document constraints conservatively — when in doubt, restrict
- Do not propose changes to existing code during assessment
- Flag security concerns immediately, even during assessment
- Be specific about file paths and function names in conventions
- Generate ALL output files — LEGACY_CONTEXT.md, TECH_DEBT.md, COEXISTENCE_RULES.md, ARCHITECTURE.md
- Always ask for approval before writing to AGENTS.local.md
