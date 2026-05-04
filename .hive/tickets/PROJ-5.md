# PROJ-5 — Add CI job for browser and API tests with mocks

**Sprint:** 1
**Status:** done
**Effort:** L
**Refs:** TD-05

## Description
Tests marked `requires_api` and `requires_browser` are excluded from CI. These cover the most critical paths (AI planning, Playwright execution, auth). Regressions go undetected until a manual run. Introduce mocked responses so these tests can run in CI without live credentials or a real browser target.

## Acceptance Criteria
- [ ] `pytest-recording` (or `respx` for httpx mocking) added to dev dependencies
- [ ] Anthropic API calls in `requires_api` tests mocked with recorded responses (cassettes committed to `tests/fixtures/cassettes/`)
- [ ] Playwright browser tests in `requires_browser` tests run against a local static HTML fixture (no external site needed)
- [ ] New CI job `test-full` added to `.github/workflows/ci.yml` — runs all markers including `requires_api` and `requires_browser`
- [ ] `ANTHROPIC_API_KEY` CI secret documented in `CONTRIBUTING.md` (for re-recording cassettes)
- [ ] `TECH_DEBT.md` TD-05 marked resolved
