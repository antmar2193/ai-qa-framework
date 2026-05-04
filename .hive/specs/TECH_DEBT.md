# Technical Debt Register — AI-QA-FRAMEWORK
_Assessment date: 2026-04-30_

| ID | Category | Severity | Description | Effort | Recommendation |
|----|----------|----------|-------------|--------|----------------|
| TD-01 | Architecture | High | ~~`STACK.md` and `AGENTS.local.md` say `python-fastapi` but this is a CLI pipeline tool with no FastAPI.~~ | S | ✅ Fixed 2026-04-30 — stack updated to `python-playwright` |
| TD-02 | Architecture | High | ~~`AGENTS.local.md` sets `package_manager: npm` but project uses pip/Python.~~ | S | ✅ Fixed 2026-04-30 — changed to `pip` |
| TD-03 | Architecture | Medium | ~~`existing_patterns.state_management: zustand` and `existing_patterns.styling: tailwind` are frontend defaults.~~ | S | ✅ Fixed 2026-04-30 — both set to `none` |
| TD-04 | Testing | Medium | ~~No coverage threshold enforced.~~ | M | ✅ Fixed 2026-04-30 — `--cov-fail-under=50` added to CI. Raise threshold after first CI run shows real baseline. |
| TD-05 | Testing | Medium | ~~`requires_api` and `requires_browser` tests excluded from CI.~~ | L | ✅ Fixed 2026-04-30 — `requires_api` now runs in main job with `ANTHROPIC_API_KEY=test-key` (all AI tests already mock via `@patch`). New `test-browser` CI job installs Playwright and runs `requires_browser` tests on push to main. |
| TD-06 | Architecture | Medium | ~~No Docker setup.~~ | M | ✅ Fixed 2026-04-30 — `Dockerfile`, `docker-compose.yml`, `.dockerignore` added. README updated with Docker quick-start. |
| TD-07 | Dependencies | Low | ~~`requirements.txt` uses `>=` lower bounds only — no lockfile.~~ | S | ✅ Fixed 2026-04-30 — `requirements.in` and `requirements-dev.in` created. Run `pip-compile requirements.in -o requirements.txt` to generate pinned lockfile. |
| TD-08 | Architecture | Low | `ARCHITECTURE.md` in `.hive/specs/` was a stub with no real content. | S | Done — updated in this assessment. |
| TD-09 | Testing | Low | ~~Test files in a flat `tests/` directory.~~ | M | ✅ Fixed 2026-04-30 — 14 files → `tests/unit/`, 9 files → `tests/integration/`. `conftest.py` stays at root. pytest.ini unchanged (recurses automatically). |
