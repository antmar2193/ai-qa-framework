# /deploy — Release and Client Delivery
<!-- tokens: ~1300 | loads: devops.md -->

**Agent:** DevOps (read `.hive/.agents/devops.md`)
**Usage:** `/deploy [--dry-run] [--env <staging|production>]`

Orchestrates the full release process: verify, tag, deliver to client repo.
Run at sprint end or when a production delivery is needed.

**Who runs it:** DevOps / Tech Lead
**When:** After all sprint PRs are merged to `{vcs.default_base_branch}`

---

## Pre-flight checks

Before starting, read from `AGENTS.local.md`:
- `vcs.default_base_branch` — must be clean and CI green
- `verify_commands.*` — all commands to run
- `deployment.target` — where to deploy
- `deployment.ci_tool` — CI/CD tool in use
- `delivery.client_repo_url` — destination for client delivery
- `tagging.on_deploy` — whether to create a git tag

---

## Process

### Step 1: Verify working state
- Confirm you are on `{vcs.default_base_branch}` and it is up to date with remote
- Confirm no uncommitted changes: `git status`
- Confirm CI is green on the latest commit

If `--dry-run`: report what would happen, then stop.

### Step 2: Run full verification suite
Run all commands from `verify_commands` in this order:
1. `verify_commands.typecheck` (skip if null)
2. `verify_commands.lint` (skip if null)
3. `verify_commands.test`
4. `verify_commands.build` (skip if null)

If any command fails → stop and report the failure. Do not proceed.

### Step 3: Determine release version
Read current tags: `git tag --sort=-version:refname | head -5`

Propose next version following semver:
- Sprint release: bump patch (v1.2.3 → v1.2.4)
- Feature release: bump minor (v1.2.3 → v1.3.0)
- Breaking change: bump major (v1.2.3 → v2.0.0)

Show proposed tag to user. Wait for confirmation (or use proposed if `autonomy.level` is `autonomous`).

### Step 4: Create release tag
```bash
git tag -a v{version} -m "release: v{version} — {sprint or feature description}"
git push origin v{version}
```

### Step 5: Deliver to client repo
If `delivery.client_repo_url` is set → run delivery.

For `--env staging` or first run:
```bash
./scripts/deliver.sh --update {delivery.client_repo_url}
```

If `delivery.client_repo_url` is empty → print instructions for manual delivery.

### Step 6: Report
```
Deployment complete:

  Version   : v{version}
  Tag       : ✓ pushed to origin
  Client    : ✓ {client_repo_url} updated (or: manual delivery needed)
  Timestamp : {ISO datetime}

What was delivered:
  - All source code from {vcs.default_base_branch}
  - CI/CD workflows, README, .env.example

What was NOT delivered:
  - .hive/ (AI layer — internal only)
  - AGENTS.md, CLAUDE.md, factory scripts

Next step: notify the client of the new release.
```

---

## Flags

| Flag | Effect |
|---|---|
| `--dry-run` | Run checks, show what would be tagged/delivered, but make no changes |
| `--env staging` | Label the tag as staging: `v{version}-staging` |
| `--env production` | Default behavior — production release tag |

---

## Rules
- Never deploy with failing tests — Step 2 is a hard gate
- Always tag before delivering — the tag is the audit trail
- Never push `.hive/`, `AGENTS.md`, or factory scripts to client repo
- In `supervised` mode: always confirm the version tag before creating it
- In `autonomous` mode: use proposed version if CI is green, log to `.hive/events.jsonl`
