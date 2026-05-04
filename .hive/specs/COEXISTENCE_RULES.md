# Coexistence Rules — AI-QA-FRAMEWORK
_Assessment date: 2026-04-30_

## Guiding Principle
Existing files maintain current patterns. New files follow HIVE standards.
This project is a working QA tool — don't break what already runs.

## Existing Patterns to Respect
- **Module style:** flat modules under `src/` (not DDD layers) — do not restructure existing files into domain/application/infrastructure
- **Models:** Pydantic v2 `BaseModel` — all data contracts use Pydantic, no dataclasses or TypedDicts
- **Async pattern:** `async/await` throughout — never introduce synchronous blocking calls in existing async code paths
- **Config:** JSON file (`qa-config.json`) + env var injection via `env:VAR_NAME` syntax — do not add a `.env` file loader or pydantic-settings; existing approach is intentional
- **CLI:** Click — do not switch to argparse or Typer in existing commands
- **Testing:** pytest + pytest-asyncio — use existing markers (`unit`, `integration`, `e2e`, `requires_api`, `requires_browser`) for all new tests
- **ORM:** none — no database; persist state as JSON files under `runs/` and `qa-reports/`
- **API style:** no HTTP API — this is a CLI tool; do not add a web server

## Migration Limits
- Max files refactored to new patterns per sprint: 2
- Migration must be a separate ticket — never mix refactoring with feature work
- Do not restructure the `tests/` directory unless it is an explicit ticket

## Protected Paths (DO NOT MODIFY without explicit ticket)
- `src/models/` — shared data contracts used by all pipeline stages; changes here cascade everywhere
- `src/ai/client.py` — Anthropic/Ollama client with retry/fallback logic; fragile
- `src/auth/smart_auth.py` — three-tier auth detection; complex heuristics, high regression risk
- `qa-config.json.example` — the only committed config template; must stay valid and complete

## New Code Rules
- New source modules go under `src/<module>/` with an `__init__.py`
- New tests go in `tests/` following the `test_<module>.py` naming convention
- New Pydantic models use `model_config = ConfigDict(...)` (v2 style) — not `class Config`
- New async functions must be tested with `pytest-asyncio` and the `@pytest.mark.asyncio` marker (or rely on `asyncio_mode = auto` from pytest.ini)
- New CLI subcommands are added to `src/cli.py` as Click `@cli.command()` decorators
- No new runtime dependencies without updating `requirements.txt` and noting it in the PR
