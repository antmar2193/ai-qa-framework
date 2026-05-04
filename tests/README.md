## Test Suite for AI QA Framework

This directory contains unit and integration tests for the AI-powered website QA framework.

## Structure

```
tests/
├── conftest.py                                    # Shared fixtures
├── unit/
│   ├── test_models_config.py                      # FrameworkConfig model
│   ├── test_models_site.py                        # Site model
│   ├── test_models_test_plan.py                   # Test plan model
│   ├── test_models_test_result.py                 # Test result model
│   ├── test_ai_client.py                          # AI client
│   ├── test_ai_prompts.py                         # AI prompt builders
│   ├── test_executor_action_runner.py             # Action runner
│   ├── test_executor_assertion_checker.py         # Assertion checker
│   ├── test_planner_schema_validator.py           # Schema validator
│   ├── test_coverage_scorer.py                    # Coverage scoring
│   ├── test_reporter_json_report.py               # JSON report generation
│   ├── test_project_registry.py                   # ProjectRegistry CRUD
│   ├── test_cli_project_mutating.py               # CLI: project create/import/use/delete
│   ├── test_cli_project_readonly.py               # CLI: project list/history
│   ├── test_web_projects_api.py                   # REST: project CRUD endpoints (Sprint 3)
│   ├── test_web_reports_api.py                    # REST: report file serving (Sprint 3)
│   ├── test_web_runs_api.py                       # REST: trigger run, SSE, status (Sprint 3)
│   ├── test_web_run_detail.py                     # REST: run detail + evidence endpoints (Sprint 4)
│   ├── test_excel_export.py                       # generate_xlsx() + export endpoint (Sprint 4)
│   └── test_security.py                           # All 7 security hardening checks (Sprint 4)
└── integration/
    ├── test_integration.py                        # Full pipeline integration
    └── test_project_pipeline_resolution.py        # --project flag and active-project resolution
```

## Running Tests

### Prerequisites

```bash
pip install -r requirements.txt
```

### Run all tests

```bash
pytest
```

### Run by directory

```bash
pytest tests/unit/
pytest tests/integration/
```

### Run a specific file

```bash
pytest tests/unit/test_models_config.py
pytest tests/unit/test_project_registry.py
pytest tests/integration/test_project_pipeline_resolution.py
```

### Run by marker

```bash
pytest -m unit
pytest -m integration
pytest -m "not slow"
pytest -m requires_browser   # requires Playwright + Chromium
pytest -m requires_api        # requires ANTHROPIC_API_KEY
```

### Run with coverage

```bash
pytest --cov=src --cov-report=html
open htmlcov/index.html
```

### Useful flags

```bash
pytest -v              # verbose
pytest -x              # stop on first failure
pytest -k "registry"   # run tests whose name matches "registry"
pytest --pdb           # drop into debugger on failure
pytest --lf            # re-run last-failed tests only
```

## Test Markers

| Marker | When to use |
|--------|-------------|
| `@pytest.mark.unit` | Tests for a single function/class in isolation |
| `@pytest.mark.integration` | Tests covering multiple components together |
| `@pytest.mark.e2e` | Full end-to-end workflow tests |
| `@pytest.mark.slow` | Tests that take significant time |
| `@pytest.mark.requires_api` | Needs `ANTHROPIC_API_KEY` |
| `@pytest.mark.requires_browser` | Needs Playwright + Chromium installed |

## Key Fixtures (`conftest.py`)

### Configuration
- `framework_config` — complete `FrameworkConfig` with defaults
- `temp_config_file` — writes a config to a temp file and returns its path

### Models
- `site_model`, `page_model`, `form_model` — populated model instances
- `test_plan`, `test_case`, `action`, `assertion` — test plan instances
- `test_result`, `test_run_result` — result instances

### Mocks
- `mock_anthropic_client` — mocked Anthropic SDK client
- `mock_page`, `mock_context`, `mock_browser` — mocked Playwright objects

### Directories
- `temp_evidence_dir`, `temp_report_dir` — temporary output directories

## Project Registry Tests

`tests/unit/test_project_registry.py` tests the `ProjectRegistry` class that stores named projects under `~/.qa-framework/`. All tests use `tmp_path` so they never touch your real project registry.

`tests/integration/test_project_pipeline_resolution.py` tests the full config resolution chain — `--project` flag, active project, legacy `--config` fallback, and `Orchestrator(runs_dir=)` integration.

## Web API Tests (Sprint 3 & 4)

All web tests use `fastapi.testclient.TestClient` and an isolated `ProjectRegistry(base_dir=tmp_path / ".qa-framework")`:

```python
from fastapi.testclient import TestClient
from src.projects.registry import ProjectRegistry
from src.web.app import create_app

def test_something(tmp_path):
    reg = ProjectRegistry(base_dir=tmp_path / ".qa-framework")
    reg.create("mysite", "https://mysite.com")
    client = TestClient(create_app(reg))
    resp = client.get("/api/projects/mysite/runs/run-abc")
    assert resp.status_code == 200
```

## Security Tests

`tests/unit/test_security.py` covers all seven hardening items from Sprint 4:
1. **Password not persisted in plaintext** — `env:` references survive save/load roundtrip
2. **Project name validation** — path traversal, XSS payloads, and empty strings are rejected
3. **`target_url` scheme** — only `http://` and `https://` accepted
4. **Path traversal in file serving** — `../`, null bytes, absolute paths return 400
5. **Credentials not stored** — `run_meta.json` contains `auth_username` but never `password`
6. **Extension allow-list** — `.sh`, `.py`, etc. rejected from evidence and report endpoints
7. **Null bytes in filenames** — explicitly rejected before filesystem access

Key pattern for CLI tests:

```python
from unittest.mock import patch
from click.testing import CliRunner
from src.cli import cli
from src.projects.registry import ProjectRegistry

def test_project_create(tmp_path):
    registry = ProjectRegistry(base_dir=tmp_path / ".qa-framework")
    with patch("src.cli._get_registry", return_value=registry):
        result = CliRunner().invoke(cli, ["project", "create", "--name", "mysite", "--target", "https://example.com"])
    assert result.exit_code == 0
    assert registry.exists("mysite")
```

## Writing Tests

### Unit test example

```python
import pytest
from src.models.config import ViewportConfig

class TestViewportConfig:
    def test_default_values(self):
        config = ViewportConfig()
        assert config.width == 1280
        assert config.height == 720

    def test_custom_values(self):
        config = ViewportConfig(width=375, height=812, name="mobile")
        assert config.width == 375
```

### Async test example

```python
import pytest
from src.executor.action_runner import run_action
from src.models.test_plan import Action

@pytest.mark.asyncio
class TestRunAction:
    async def test_navigate_action(self, mock_page):
        action = Action(action_type="navigate", value="https://example.com")
        await run_action(mock_page, action)
        mock_page.goto.assert_called_once()
```

## Continuous Integration

The CI pipeline (`.github/workflows/ci.yml`) runs two jobs:

- **test**: runs all non-browser tests on every push/PR; requires `--cov-fail-under=50`
- **test-browser**: runs `requires_browser` tests on pushes to `main` after installing Playwright

## Common Issues

**`ANTHROPIC_API_KEY` not set** — set a dummy key for tests that use the AI client but don't make real calls:
```bash
export ANTHROPIC_API_KEY=test-key
pytest
```

**Async tests failing** — ensure `asyncio_mode = "auto"` is set in `pytest.ini` / `pyproject.toml` and `pytest-asyncio` is installed.

**Import errors** — run `pip install -r requirements.txt` to install all dependencies including test packages.
