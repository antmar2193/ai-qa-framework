# Legacy Context — AI-QA-FRAMEWORK
_Assessment date: 2026-04-30_

## Architecture Pattern
**Pipeline-based CLI tool** — four sequential stages orchestrated by `src/orchestrator.py`:
1. **Crawl** — Playwright-driven spider discovers pages and UI elements
2. **Plan** — Claude AI generates a structured test plan from crawl data
3. **Execute** — Playwright runs each test case, with AI fallback for flaky selectors
4. **Report** — HTML and JSON reports with regression detection

No web server, no REST API, no database. Entry point is `src/cli.py` (Click CLI).

## Directory Structure
```
src/
├── ai/                      # Anthropic/Ollama client + prompt templates
│   ├── client.py            # AIClient — multi-provider, retry, exponential backoff
│   └── prompts/             # Per-concern prompt builders (planning, auth, eval, fallback, summary)
├── auth/                    # Smart auth detection for target websites
│   └── smart_auth.py        # 3-tier: explicit selectors → auto-detect → LLM fallback
├── cli.py                   # Click CLI: run, crawl, plan, execute, report subcommands
├── coverage/                # Coverage gap analysis and scoring
│   ├── gap_analyzer.py
│   ├── registry.py
│   ├── scorer.py
│   └── visual_baseline_registry.py
├── crawler/                 # Playwright-based web crawler
│   ├── crawler.py           # Main crawler orchestration
│   ├── element_extractor.py # DOM element extraction
│   ├── form_analyzer.py     # Form field detection
│   └── spa_handler.py       # SPA/dynamic page handling
├── executor/                # Test execution engine
│   ├── executor.py          # Main executor loop
│   ├── action_runner.py     # Playwright action execution
│   ├── assertion_checker.py # Test assertion evaluation
│   ├── evidence_collector.py # Screenshots, video capture
│   ├── fallback.py          # AI-powered selector fallback
│   └── selector_resolver.py # CSS/XPath selector resolution
├── models/                  # Pydantic v2 data models (no DB coupling)
│   ├── config.py            # QAConfig — loads qa-config.json, resolves env vars
│   ├── coverage.py          # Coverage models
│   ├── site_model.py        # Discovered site structure
│   ├── test_plan.py         # AI-generated test plan schema
│   ├── test_result.py       # Execution result models
│   └── visual_baseline.py   # Visual diff baseline
├── orchestrator.py          # Pipeline orchestrator — ties all stages together
├── planner/                 # AI-driven test plan generation
│   ├── planner.py
│   └── schema_validator.py
├── reporter/                # Report generation
│   ├── html_report.py       # Jinja2-rendered HTML reports
│   ├── json_report.py       # Machine-readable JSON output
│   └── regression_detector.py # Cross-run regression comparison
└── url_utils.py             # URL normalization and filtering

tests/                       # 25 pytest test files, flat structure
.hive/                       # HIVE framework layer
.github/workflows/ci.yml     # GitHub Actions CI
qa-config.json               # Active run config (gitignored)
qa-config.json.example       # Config template (committed)
```

## Framework & Library Inventory
| Library | Version | Purpose | Status |
|---|---|---|---|
| playwright | >=1.40.0 | Browser automation | current |
| anthropic | >=0.39.0 | Claude AI API client | current |
| pydantic | >=2.5.0 | Data validation and models | current |
| click | >=8.1.0 | CLI framework | current |
| jinja2 | >=3.1.0 | HTML report templating | current |
| Pillow | >=10.0.0 | Image processing for visual diffs | current |
| aiofiles | >=23.0.0 | Async file I/O | current |
| rich | >=13.0.0 | Terminal output formatting | current |
| pytest | >=7.0.0 | Test runner | current |
| pytest-asyncio | >=0.23.0 | Async test support | current |
| pytest-cov | >=4.1.0 | Coverage reporting | current |

## Database
- **ORM/Access:** none — this project has no database
- **Database:** none
- **Schema summary:** all state is stored as JSON files in `runs/` and `qa-reports/`
- **Migrations:** not applicable

## API Surface
This project is a **CLI tool**, not a web service. It has no HTTP API. External integrations:

| Direction | Service | Auth | Purpose |
|---|---|---|---|
| Outbound | Anthropic API (`api.anthropic.com`) | `ANTHROPIC_API_KEY` env var | AI planning, evaluation, fallback |
| Outbound | Ollama (`http://localhost:11434`) | none | Local LLM alternative (dev only) |
| Outbound | Target website (configured in `qa-config.json`) | smart_auth.py | Subject under test |

## Auth Mechanism
- **Framework auth:** `ANTHROPIC_API_KEY` environment variable — read in `src/ai/client.py:64`
- **Target website auth:** `src/auth/smart_auth.py` — three-tier detection:
  1. Explicit selectors from `qa-config.json`
  2. Auto-detect common login form patterns
  3. LLM fallback for unusual forms
- Credentials for target sites are injected via `env:VAR_NAME` syntax in `qa-config.json` — resolved at runtime in `src/models/config.py`

## CI/CD Pipeline
GitHub Actions — `.github/workflows/ci.yml`:
- Trigger: push/PR to `main`
- Matrix: Python 3.12 only
- Steps: install deps → run pytest (excludes `requires_api`, `requires_browser`, `e2e` markers)
- Artifacts: `.coverage` retained 7 days
- No Docker, no deployment step

## Environment Variables
| Variable | Purpose | Required |
|---|---|---|
| `ANTHROPIC_API_KEY` | Anthropic Claude API authentication | yes (for AI features) |
| `OLLAMA_BASE_URL` | Custom Ollama endpoint | no (default: `http://localhost:11434`) |
| Any `env:VAR_NAME` referenced in `qa-config.json` | Target site credentials | depends on config |

## Test Coverage
- **Framework:** pytest + pytest-asyncio
- **Current coverage:** unknown — not enforced in CI (no `--cov-fail-under`)
- **Test markers:** `unit`, `integration`, `e2e`, `slow`, `requires_api`, `requires_browser`
- **Test patterns:** flat `tests/` directory, 25 test files, one file per source module
- **CI exclusions:** `requires_api` and `requires_browser` tests are skipped in CI (need live credentials/browser)
