# PROJ-6 — Reorganize tests into unit/ and integration/ subdirectories

**Sprint:** 1
**Status:** done
**Effort:** M
**Refs:** TD-09

## Description
All 25 test files are in a flat `tests/` directory. As the suite grows this becomes hard to navigate. pytest.ini already defines `unit` and `integration` markers — the directory structure should match.

## Acceptance Criteria
- [ ] `tests/unit/` created — contains tests that mock all I/O (no browser, no API, no filesystem writes)
- [ ] `tests/integration/` created — contains tests that touch real filesystem, multiple modules, or use fixtures
- [ ] All 25 existing test files moved to the appropriate subdirectory
- [ ] `tests/conftest.py` remains at root `tests/` (shared fixtures)
- [ ] `pytest.ini` `testpaths` updated if needed — confirm pytest still discovers all tests
- [ ] CI green after reorganization
- [ ] `TECH_DEBT.md` TD-09 marked resolved
