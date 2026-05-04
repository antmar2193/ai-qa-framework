# /commit — Commit and PR
<!-- tokens: ~2500 | loads: coder.md -->

**Agent:** Coder (read `.hive/.agents/coder.md`)
**Usage:**
```
/commit                        # stage all, commit, push, create PR
/commit <ticket-id>            # scope to changes for this ticket only
/commit --dry-run              # show plan + message, no git operations
/commit --no-pr                # commit and push, skip PR creation
```

---

---

## Process

### Step 0: Read configuration
Read `.hive/AGENTS.local.md`:
- `autonomy.level` — "supervised" | "balanced" | "autonomous"
- `language.communication` — language for commit messages and PR descriptions
- `verify_commands.*` — commands to run before committing
- `vcs.pr_tool` — "gh" | "glab" | null
- `vcs.default_base_branch` — base branch; all ticket branches originate from here
- `vcs.branch_pattern` — pattern for naming ticket branches
- `vcs.ai_trailer` — true | false — whether to append AI attribution trailer
- `ticket_provider.id_format` — how to reference ticket in title
- `ticket_provider.board_url` — for PR description link
- `ticket_provider.statuses.in_review` — status after PR creation
- `ticket_provider.statuses.done` — status after PR merge
- `ticket_provider.mcp_name` — MCP to call for status transitions
- `ticket_provider.ticket_transitions.auto_merge_pr` — true | false

### Step 1: Dry-run check
If `--dry-run` was requested:
- Perform only steps 2–4 (inspect, scope, write message)
- Do NOT run any git or VCS commands
- Output: list of files to stage + proposed commit message
- Stop

### Step 2: Run verification commands
Run each configured command in order. Skip commands set to `null`.

```
1. verify_commands.test         → must pass
2. verify_commands.typecheck    → zero errors (skip if null)
3. verify_commands.lint         → zero warnings (skip if null)
```

If any command fails → stop, report the failure, do not commit.

### Step 2.5: Verify API docs (mandatory if api_docs.enabled)
Read `api_docs.enabled` from `.hive/AGENTS.local.md`.
If `true`:
1. Check if any controller, route, or endpoint file was modified
2. If yes → verify that `api-spec.yml` was also modified in this changeset
3. If `api-spec.yml` was NOT updated → **stop**, run `/update-docs` first
4. The API spec must always reflect the current state of all endpoints

### Step 3: Inspect current state
```bash
git status
git diff
git diff --staged
```

Confirm you are on a feature branch (pattern from `vcs.branch_pattern`).
If on `vcs.default_base_branch` or `main` → create a ticket branch first:
```bash
git checkout <vcs.default_base_branch>
git pull origin <vcs.default_base_branch>
git checkout -b <branch-name>   # following vcs.branch_pattern
```

**supervised:** Pause — confirm branch name before creating it.
**balanced / autonomous:** Create branch automatically.

### Step 4: Resolve scope

**No ticket argument:** stage all relevant changes (exclude secrets, build artifacts, local config).

**With ticket-id:** stage only files/hunks belonging to that ticket.
- Use `git add -p` for files with mixed changes
- Leave unrelated changes unstaged
- If nothing matches → report and stop

### Step 5: Write commit message

```
<type>(<scope>): <description>

[optional body — what changed and why]

Refs: <ticket-id>
[AI-assistant: <tool> v<version> (<model> · <tier>)]
```

- Subject and body: written in `language.communication` from AGENTS.local.md
- Subject: imperative mood, lowercase, no period, ≤ 72 chars
- Always include the ticket reference using `ticket_provider.id_format`
- Body: explain WHY when not obvious from the diff
- If `vcs.ai_trailer` is `true` (or absent/unset): append an AI attribution trailer as the last line. Fill in from your own context: `tool` (e.g. `Claude Code`, `Cursor`, `Windsurf`, `Copilot`), `version` (run `claude --version` or equivalent — omit `v<version>` entirely if unavailable), `model` (e.g. `Sonnet 4.6`, `GPT-4o`), `tier` (e.g. `Claude Pro`, `Cursor Pro`). Examples: `AI-assistant: Claude Code v2.1.81 (Sonnet 4.6 · Claude Pro)` · `AI-assistant: Copilot (GPT-4o · GitHub Copilot Business)`.
- If `vcs.ai_trailer` is `false`: omit the trailer entirely

### Step 6: Commit and push

**supervised:** Show the staged files and the proposed commit message. Pause — wait for explicit approval before running any git command.
**balanced / autonomous:** Proceed without confirmation.

```bash
git commit -m "<message>"
git push origin <branch>    # -u on first push
```

### Step 7: Create PR (unless --no-pr)

PR title and body must be written in `language.communication` from AGENTS.local.md.

**supervised:** Show the PR title and body draft. Pause — wait for explicit approval before creating the PR.
**balanced / autonomous:** Create PR immediately.

**If `gh` (GitHub CLI):**
```bash
gh pr create \
  --title "[<ticket-id>] type: description" \
  --body "..." \
  --base <vcs.default_base_branch>
```

**If `glab` (GitLab CLI):**
```bash
glab mr create \
  --title "[<ticket-id>] type: description" \
  --description "..." \
  --target-branch <vcs.default_base_branch>
```

**If `null`:**
Output the PR title and body for the user to create manually.
Tell them the target branch.

### Step 8: Ticket status after PR creation

**supervised / balanced:** Follow `ticket_transitions.mode`:
- `minimal` → no transition yet
- `standard` / `verbose` → move ticket to `statuses.in_review`:
  - `ticket_update("{ticket-id}", status="{statuses.in_review}", comment="PR created: {PR-URL}")` via `hive-tickets` MCP
  - Fallback: use `ticket_provider.mcp_name` MCP as configured in `AGENTS.local.md`
  - Fallback: skip silently and remind user to update the ticket manually

**autonomous:** No transition here — the only transition happens in Step 10 (after merge).

### Step 9: Merge PR (autonomous only)

**supervised / balanced:** Stop here. The human reviews and merges the PR manually.

**autonomous** (only if `auto_merge_pr: true`):
Wait for all CI checks to pass, then:
```bash
gh pr merge <PR-number> --merge --delete-branch
# or --squash / --rebase if vcs.merge_strategy specifies it
```
If CI fails → stop, log to `.hive/events.jsonl`, notify in chat. Do NOT merge.

### Step 10: Post-merge cleanup (autonomous only)

**supervised / balanced:** Skip — human manages branch cleanup and navigation.

**autonomous** (after Step 9 succeeds):
```bash
git checkout <vcs.default_base_branch>
git pull origin <vcs.default_base_branch>
git branch -d <ticket-branch>       # delete local branch
# remote branch already deleted by --delete-branch in Step 9
```
If remote branch was not deleted automatically:
```bash
git push origin --delete <ticket-branch>
```

### Step 11: Ticket → Done (autonomous only)

**supervised / balanced:** Follow `ticket_transitions.mode` — Done transition is handled by CI on merge or manually.

**autonomous:** Move ticket to `ticket_provider.statuses.done` exactly **once**, after merge confirms success (regardless of `ticket_transitions.mode`):
- `ticket_update("{ticket-id}", status="{statuses.done}")` via `hive-tickets` MCP
- Fallback: use `ticket_provider.mcp_name` MCP as configured in `AGENTS.local.md`
- Fallback: if `mcp_name` is `"none"` → skip silently

### Step 12: Report
- Files committed and scope
- If ticket-scoped: which files were included, which were left unstaged
- PR URL (or instructions to create manually)
- **supervised / balanced:** Reminder that merge, branch deletion, and return to base are pending human action
- **autonomous:** Confirm merge hash, branch deleted, back on `<vcs.default_base_branch>`, ticket moved to Done

---

## Rules
- Never `git push --force` unless explicitly requested by the user
- Do not commit: secrets, `.env`, build artifacts, `node_modules`, debug code
- If push is rejected → report the situation, suggest rebase, do not force-push
- All verification commands must pass before commit (no exceptions)
- If `pr_tool` is null → provide complete PR info for manual creation, do not fail
