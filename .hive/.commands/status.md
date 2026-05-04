# /status — Project Status
<!-- tokens: ~50 | shell script — no LLM output generation needed -->

**Purpose:** Show the current HIVE project configuration at any point during a session.

---

## When to use

Run `/status` at any moment to get a snapshot of:
- Project identity and stack
- Active autonomy level and model profile
- Pending interrupted pipelines
- Circuit breaker thresholds
- Key paths

---

## Output format

```
[HIVE {version}] {project.name} · {stack} · autonomy: {level} · profile: {active_profile} · persona: {style}

Project   : {project.name}
Stack     : {stack}
Autonomy  : {level}
Profile   : {active_profile}
Persona   : {style}
Version   : {hive_version}

Verify commands:
  typecheck : {verify_commands.typecheck}
  lint      : {verify_commands.lint}
  test      : {verify_commands.test}

Circuit breakers:
  max_test_retries      : {max_test_retries}
  max_new_files         : {max_new_files}
  max_tokens_per_ticket : {max_tokens_per_ticket}

Interrupted pipelines : {count} — run /resume --list for details
```

---

## Steps

1. Run the shell script — it reads all config and prints the full snapshot with zero LLM generation:
   ```bash
   bash .hive/scripts/hive-status.sh
   ```
   Or from the factory: `bash /path/to/hive/scripts/hive-status.sh`

2. Present the output verbatim. Do not regenerate or reformat it.

3. If the script is not found (project predates this feature), fall back to reading `.hive/AGENTS.local.md` and printing the output format shown above manually.

---

## Rules

- Read-only — no files written, no state changed
- Always reads fresh from disk (never from session memory)
- Works at any pipeline stage without interrupting flow
