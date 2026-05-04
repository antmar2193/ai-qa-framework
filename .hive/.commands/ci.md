# /ci — CI/CD Pipeline Generation
<!-- tokens: ~1400 | loads: devops.md -->

**Agent:** DevOps (read `.hive/.agents/devops.md`)
**Usage:** `/ci [--generate | --update]`

Generates or updates CI/CD pipeline configuration from the project's
`.hive/AGENTS.local.md` configuration.

**Who runs it:** DevOps / Tech Lead
**When:** After project setup or when deployment targets change

---

## Process

### Step 1: Read configuration
From `.hive/AGENTS.local.md`:
- `verify_commands.*` — test, typecheck, lint, coverage, build
- `vcs.platform` — github | gitlab
- `deployment.target` — aws-ecs | vercel | railway | vps | docker-compose | none
- `deployment.environments.*` — staging, production URLs
- `deployment.ci_tool` — github-actions | gitlab-ci
- `ticket_provider.*` — for auto-transition on merge
- `tagging.*` — for deploy tagging

### Step 2: Generate CI workflow

**GitHub Actions** → `.github/workflows/ci.yml`
**GitLab CI** → `.gitlab-ci.yml`

The generated pipeline must include:

#### On Push to feature branch
```yaml
steps:
  - Install dependencies
  - Run: verify_commands.test
  - Run: verify_commands.typecheck (if not null)
  - Run: verify_commands.lint (if not null)
  - Run: verify_commands.coverage (if not null)
```

#### On PR merged to develop
```yaml
steps:
  - All verification steps above
  - Auto-transition ticket to statuses.done (if ticket_provider.auto_transition_on_merge)
  - Delete source branch (if ticket_provider.auto_delete_branch)
```

#### On deploy (if deployment.target is configured)
```yaml
steps:
  - Run: verify_commands.build
  - Deploy to target environment
  - Create git tag: deploy-{env}-v{version}-{date}
  - Notify (optional)
```

### Step 3: Generate deployment-specific configuration

Read the deployment template from `stacks/<stack>/ci/` if it exists.
Customize with project-specific values from AGENTS.local.md.

### Step 4: Auto-transition logic (PR merge → Done)

Include this in the CI pipeline for PR merge events:

```yaml
# Extract ticket ID from PR title: [TICKET-ID] ...
# Call ticket provider API to transition to statuses.done
```

For Jira: use Atlassian API or Jira automation webhook
For GitHub Issues: use GitHub API to close the issue
For Linear: use Linear API to update status

### Step 5: Sprint tagging

When `/sync` generates a new SPEC.md (sprint change detected):
```bash
git tag -a v{sprint}.0 -m "Sprint {N} complete — {date}"
git push origin v{sprint}.0
```

When deploying to an environment:
```bash
git tag -a deploy-{env}-v{version}-{date} -m "Deploy to {env}"
git push origin deploy-{env}-v{version}-{date}
```

### Step 6: Report

```
CI/CD pipeline generated:
  - File: .github/workflows/ci.yml (or .gitlab-ci.yml)
  - Verification: test + typecheck + lint + coverage
  - Auto-transition on merge: {enabled/disabled}
  - Branch cleanup on merge: {enabled/disabled}
  - Deploy target: {target}
  - Deploy tagging: {enabled/disabled}

Review the generated file and commit:
  git add .github/workflows/ci.yml
  git commit -m "ci: add CI/CD pipeline from HIVE config"
```

---

## Rules
- Never hardcode secrets — use CI platform's secret management
- Always include all configured verify_commands in the pipeline
- Deploy steps must never run without all verification passing
- Tag format must be consistent: `deploy-{env}-v{version}-{date}`
- Test the generated pipeline with a dry-run if possible
