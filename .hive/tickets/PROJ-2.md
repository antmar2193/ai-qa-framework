# PROJ-2 — Add test coverage baseline and enforce threshold in CI

**Sprint:** 1
**Status:** done
**Effort:** M
**Refs:** TD-04

## Description
CI currently runs pytest with no coverage enforcement. Coverage percentage is unknown. We need to establish a baseline and enforce a minimum threshold so regressions are caught automatically.

## Acceptance Criteria
- [ ] Run `pytest --cov=src --cov-report=term-missing` locally and document current coverage %
- [ ] Set `--cov-fail-under` to current baseline (round down to nearest 5%)
- [ ] Update `.github/workflows/ci.yml` to use coverage threshold
- [ ] Coverage report uploaded as CI artifact
- [ ] `TECH_DEBT.md` TD-04 marked resolved
