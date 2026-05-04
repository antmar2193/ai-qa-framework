# /update-docs — Documentation Lifecycle
<!-- tokens: ~750 | loads: none -->

**Usage:** `/update-docs`

Run before every commit. Mandatory final step in every implementation command.
Any agent can trigger it. The Coder runs it before `/commit`.

---

## Role
You review all recent code changes and update the technical documentation
that is affected. Documentation lives alongside code — not behind it.

---

## Process

### 1. Identify changed files
```bash
git diff HEAD          # unstaged changes
git diff --staged      # staged changes
git diff HEAD~1 HEAD   # last commit (if already committed)
```

### 2. Map changes to documentation

| If you changed... | Update this file |
|---|---|
| DB schema / Prisma model | `.hive/specs/data-model.md` |
| API endpoint (add/modify/delete) | `.hive/specs/api-spec.yml` |
| New library or dependency | `.hive/standards/backend.mdc` or `frontend.mdc` |
| Environment variable | `README.md` → Environment Variables table + `.env.example` |
| Setup process / install steps | `.hive/specs/development_guide.md` |
| New architectural pattern | `.hive/specs/ARCHITECTURE.md` |
| Significant tech decision | New ADR in `docs/adr/ADR-NNN-title.md` |
| New test pattern introduced | `.hive/standards/backend.mdc` or `frontend.mdc` |
| Project configuration change | `README.md` |

### 3. Update each affected file
- Write in English (without exception)
- Maintain existing structure — do not reorganize what you do not need to
- Keep consistency with surrounding content
- Be precise: update only what changed, not the whole section

### 4. Report
State which files were updated and what changed:
```
Updated:
- .hive/specs/api-spec.yml — added GET /employees/search endpoint
- .hive/specs/data-model.md — added searchIndex field to Employee
```

If no documentation needed updating, say so explicitly:
```
No documentation updates needed — change was internal refactoring only.
```

---

## Rules
- This step is mandatory — never skip it before a commit
- If unsure whether a doc needs updating, update it — always safer
- ADRs are write-once: never edit an existing ADR, create a new one that supersedes it
- development_guide.md must stay accurate enough that a new dev can set up the project from scratch using only that file
