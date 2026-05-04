# /focus — Restrict Agent Scope to a Module
<!-- tokens: ~1100 | loads: .hive/sessions/focus.md (reads/writes) -->

**Agent:** Any (reads current focus from `.hive/sessions/focus.md` before acting)
**Usage:** `/focus <module-path-or-name>`
**Clear focus:** `/focus --clear`

Restricts all subsequent agent actions in this session to a specific module or
directory. Essential for large legacy codebases where you want to work on one
area without agents proposing changes elsewhere.

**Who runs it:** Developer / Tech Lead
**When:** Before working on a specific module in a large legacy project

---

## Process

### /focus <module-path>

**Step 1: Validate the path**
- Confirm the path exists in the project: `ls <module-path>`
- Read `legacy.protected_paths` from `.hive/AGENTS.local.md`
- If the focus path is INSIDE a protected path → warn and ask for confirmation

**Step 2: Check for conflicts**
- If `.hive/sessions/focus.md` already exists → show current focus and ask to confirm override

**Step 3: Write focus scope**
Save to `.hive/sessions/focus.md`:
```markdown
# Active Focus Scope
_Set: {ISO datetime}_

## Module
{module-path}

## Scope Rules (enforced for this session)
- Agents MAY read any file for context
- Agents MAY ONLY write/modify files under: {module-path}
- Agents MUST NOT create files outside: {module-path}
- If a fix requires touching files outside the focus → stop and report to user

## Protected paths still active
{list from legacy.protected_paths — these are never writable regardless of focus}

## Clear focus
Run `/focus --clear` to remove this restriction.
```

**Step 4: Confirm**
```
Focus set: {module-path}

All agent writes restricted to this module.
Agents can still READ any file for context.

Active protected paths (always enforced):
  {list}

To clear: /focus --clear
```

---

### /focus --clear

**Step 1:** Delete `.hive/sessions/focus.md` if it exists
**Step 2:** Confirm:
```
Focus cleared. Agents can now write to any non-protected path.
```

---

## How agents use the focus scope

Every command that writes files MUST check `.hive/sessions/focus.md` before proceeding:

1. If `.hive/sessions/focus.md` exists → read the `Module` field
2. Before writing any file, verify the file path starts with the focus module path
3. If a proposed file is outside the focus → stop and report:
   ```
   ⚠️ Focus scope violation: {file-path} is outside the current focus ({module-path})
   Run /focus --clear if you want to expand scope, or adjust your request.
   ```

---

## Rules
- `/focus` does not change what agents can READ — only what they can WRITE
- Protected paths from `AGENTS.local.md` always apply regardless of focus
- Focus is session-scoped — it clears when you start a new session
- Use `/focus --clear` explicitly if you need to work across modules in the same session
- If unsure whether a fix needs cross-module changes → ask before expanding scope
