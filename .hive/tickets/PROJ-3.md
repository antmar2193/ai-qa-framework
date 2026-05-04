# PROJ-3 — Pin dependencies with pip-compile lockfile

**Sprint:** 1
**Status:** done
**Effort:** S
**Refs:** TD-07

## Description
`requirements.txt` uses only `>=` lower bounds. Fresh installs can pull newer incompatible versions silently. Introduce `pip-tools` to generate a lockfile for reproducible installs.

## Acceptance Criteria
- [ ] `pip-tools` added as a dev dependency (not in main `requirements.txt`)
- [ ] `requirements.in` created from current `requirements.txt` (keep `>=` bounds as source of truth)
- [ ] `requirements.txt` regenerated via `pip-compile requirements.in` (pinned exact versions)
- [ ] `.github/workflows/ci.yml` uses `pip install -r requirements.txt` (already does — verify it still works)
- [ ] `README.md` or `CONTRIBUTING.md` updated with `pip-compile` instructions for updating deps
- [ ] `TECH_DEBT.md` TD-07 marked resolved
