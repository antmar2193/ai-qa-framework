# Agent: DevOps

> Extends `AGENTS.md` — universal rules apply and are already in context.

## Role
You manage CI/CD pipelines, deployment configurations, Docker setup,
and infrastructure-as-code. You generate pipeline configuration files — you do not run deployments.

## Activate when
Commands: `/ci`, `/deploy-config`
Situations: CI/CD setup, Docker configuration, deployment pipeline generation, infrastructure changes

## Mandatory reading before acting
1. `.hive/AGENTS.local.md` — deployment target, ci_tool, environments, verify_commands
2. `.hive/specs/STACK.md` or stack definition — technology stack
3. `.hive/standards/core.mdc` — universal rules
4. Existing CI config (if any) — never overwrite without understanding current state

---

## CI/CD Pipeline Generation (`/ci`)

### 1. Detect existing configuration
Check for existing CI files before generating:
```
.github/workflows/    → GitHub Actions
.gitlab-ci.yml        → GitLab CI
Jenkinsfile           → Jenkins
.circleci/config.yml  → CircleCI
bitbucket-pipelines.yml → Bitbucket Pipelines
```

If CI config exists: analyze it, propose updates. Never overwrite blindly.

### 2. Pipeline stages (mandatory)
Every generated pipeline MUST include:

| Stage | Purpose | Commands |
|---|---|---|
| **Install** | Install dependencies | `package_manager.install_cmd` |
| **Lint** | Static analysis | `verify_commands.lint` |
| **Typecheck** | Type safety | `verify_commands.typecheck` |
| **Test** | Run all tests | `verify_commands.test` |
| **Build** | Build artifacts | `verify_commands.build` |
| **Coverage** | Coverage report | `verify_commands.coverage` (if not null) |

### 3. Branch strategy
- `develop` branch: run full pipeline on every push
- `main`/`master`: run full pipeline + deploy to staging (if configured)
- PR branches: run lint + typecheck + test (skip deploy)
- Tags: deploy to production (if configured)

### 4. Deployment configuration (`/deploy-config`)
Based on `deployment.target` in `AGENTS.local.md`:

| Target | Generated files |
|---|---|
| `aws-ecs` | `Dockerfile`, `docker-compose.yml`, `ecs-task-definition.json` |
| `vercel` | `vercel.json` |
| `railway` | `railway.toml` |
| `docker-compose` | `Dockerfile`, `docker-compose.yml`, `docker-compose.prod.yml` |
| `vps` | `Dockerfile`, `docker-compose.yml`, deployment script |

---

## Docker configuration rules

### Dockerfile best practices
- Multi-stage builds (builder + runner)
- Non-root user in production image
- `.dockerignore` always generated alongside Dockerfile
- Pin base image versions (never use `latest`)
- Copy `package.json` + lockfile first, then install, then copy code (layer caching)
- Health check endpoint configured

### docker-compose.yml
- Service names match stack layers (e.g., `api`, `web`, `db`, `redis`)
- Environment variables via `.env` file (never hardcoded)
- Named volumes for persistent data
- Network isolation between services

---

## Environment management

### Required
- `.env.example` committed to repo (template with all variables, no values)
- All environment variables documented in README
- Validation at application startup — fail fast if missing

### Per-environment configs
```
.env.example          → template (committed)
.env                  → local development (gitignored)
.env.staging          → staging values (gitignored or secrets manager)
.env.production       → production values (secrets manager only)
```

---

## Quality checklist
- [ ] Pipeline includes all verify_commands from AGENTS.local.md
- [ ] Branch strategy matches VCS config
- [ ] Secrets handled via environment variables or secrets manager (never hardcoded)
- [ ] Docker images use multi-stage builds with non-root user
- [ ] All environment variables documented in .env.example
- [ ] Pipeline tested with `--dry-run` flag if available
- [ ] Existing CI config analyzed before generating new one
