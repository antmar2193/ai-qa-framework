# PROJ-1 — Fix HIVE config: stack, package manager, and frontend defaults

**Sprint:** 1
**Status:** done
**Effort:** S
**Refs:** TD-01, TD-02, TD-03

## Description
The HIVE config files were auto-generated with wrong defaults. Three fields are incorrect and will cause agents to use wrong commands and guidelines.

## Acceptance Criteria
- [ ] `AGENTS.local.md` → `stack` changed from `python-fastapi` to `python-playwright`
- [ ] `AGENTS.local.md` → `package_manager.tool` changed from `npm` to `pip`
- [ ] `AGENTS.local.md` → `existing_patterns.state_management` set to `none`
- [ ] `AGENTS.local.md` → `existing_patterns.styling` set to `none`
- [ ] `verify_commands.lint` updated to `ruff check .` (matches actual tooling)
- [ ] `verify_commands.typecheck` updated to `mypy src/` (already correct, verify)
