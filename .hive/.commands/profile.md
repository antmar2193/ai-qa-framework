# /profile — Model Profile Management
<!-- tokens: ~1600 | loads: orchestrator.md -->

**Agent:** Orchestrator (read `.hive/.agents/orchestrator.md`)
**Usage:**
```
/profile                        # show active profile and all defined profiles
/profile switch <name>          # activate a named profile
/profile list                   # list profiles with model assignments
/profile create <name>          # interactively define a new profile
/profile delete <name>          # remove a profile (cannot delete "default")
```

**Purpose:** Switch cost/quality trade-offs between pipeline runs without editing config manually.
Profiles are defined in `AGENTS.local.md` under `model_profiles:`. The active profile determines which model handles each phase (planning, implementation, review).

---

## Process

### /profile (no args) — show status

Read `AGENTS.local.md`:
- `active_profile` — currently active
- `model_profiles.*` — all defined profiles

Output:
```
Active profile: quality

Profiles:
  default   planning=null  implementation=null  review=null  (session model for all)
  quality ✓ planning=<model>  implementation=<model>  review=<model>
  fast      planning=<model>  implementation=<model>  review=<model>
```

---

### /profile list

Same as no-args output. Marks active profile with `✓`.

---

### /profile switch <name>

1. Verify `<name>` exists in `model_profiles` → fail if not found, list available names
2. Update `active_profile: "<name>"` in `.hive/AGENTS.local.md`
3. Report:
   ```
   Switched to profile: <name>
   planning:       <model or "session default">
   implementation: <model or "session default">
   review:         <model or "session default">
   ```

The next command that reads `AGENTS.local.md` will pick up the new profile automatically.

---

### /profile create <name>

Interactive — ask for each phase:

```
Creating profile: <name>

Planning model (most capable available from your provider — press Enter for session default):
> _

Implementation model (mid-tier or fastest available — press Enter for session default):
> _

Review model (mid-tier — press Enter for session default):
> _
```

Append the new profile to `model_profiles:` in `.hive/AGENTS.local.md`.

Confirm:
```
Profile '<name>' created and saved.
Activate now? (y/N)
```
If y → run `/profile switch <name>`.

---

### /profile delete <name>

- If `<name>` is `"default"` → fail: "The default profile cannot be deleted."
- If `<name>` is the active profile → fail: "Switch to another profile first before deleting this one."
- Remove from `model_profiles:` in `.hive/AGENTS.local.md`

---

## How model_profiles is read by agents

Every command that performs planning, implementation, or review reads:

```
active_profile → look up model_profiles[active_profile]
  .planning       → model to use for /plan-be, /plan-fe, /enrich, /kickoff
  .implementation → model to use for /dev-be, /dev-fe, /tdd, /generate
  .review         → model to use for /review, /judgment-day, pre-commit review

null value → use the session's default model (whatever the user has open)
```

If `model_profiles` or `active_profile` are absent → behave as if all phases use `null` (session default).

---

## Built-in profile suggestions

When running `/profile create`, suggest these as starting points if the user asks:

| Profile name | Typical use | Planning | Implementation | Review |
|---|---|---|---|---|
| `quality` | Critical features, public APIs | Most capable available | Mid-tier | Mid-tier |
| `fast` | Hotfixes, small tasks, CI runs | Mid-tier | Fastest available | Fastest available |
| `balanced` | Standard sprints | Mid-tier | Mid-tier | Mid-tier |

Never hardcode specific model IDs in suggestions — describe by capability tier. The user fills in their provider's model.

---

## Rules
- Never delete or rename the `default` profile
- `active_profile` must always refer to an existing profile name
- Profile names are lowercase, alphanumeric + hyphens only
- The `default` profile always has `null` for all phases unless the user explicitly changes it
