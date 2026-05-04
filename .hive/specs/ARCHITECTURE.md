# Architecture — AI-QA-FRAMEWORK
_Last updated: 2026-05-01_

## Stack
| Layer | Technology | Version |
|---|---|---|
| Runtime | Python | 3.12.12 |
| Browser automation | Playwright | >=1.40.0 |
| AI integration | Anthropic SDK | >=0.39.0 |
| Data validation | Pydantic | v2 (>=2.5.0) |
| CLI framework | Click | >=8.1.0 |
| Web server | FastAPI + uvicorn | >=0.110.0 / >=0.27.0 |
| Report templating | Jinja2 | >=3.1.0 |
| Terminal UI | Rich | >=13.0.0 |
| Excel export | openpyxl | >=3.1.0 |
| Frontend | React + Vite + Tailwind CSS | React 18 / Vite 5 / Tailwind 3 |
| Testing | pytest + pytest-asyncio | >=7.0.0 / >=0.23.0 |
| CI | GitHub Actions | — |

## Architecture Pattern
**Four-stage pipeline CLI tool with optional web UI layer.** The CLI remains the primary interface; the FastAPI server is an additive wrapper around the same `ProjectRegistry` and `Orchestrator` objects.

```
CLI (click)                     Web UI (React SPA)
    └── Orchestrator                └── FastAPI  (/api/*)
            ├── 1. Crawler              ├── ProjectRegistry (same instance)
            ├── 2. Planner              ├── BackgroundTasks → Orchestrator
            ├── 3. Executor             └── SSE streaming → browser
            └── 4. Reporter
```

## Modules
| Module | Responsibility | Notes |
|---|---|---|
| `src/cli.py` | Click CLI entry point, subcommands | existing |
| `src/orchestrator.py` | Ties all four pipeline stages together | existing |
| `src/ai/client.py` | Multi-provider AI client (Anthropic + Ollama), retry/backoff | existing — fragile, do not modify lightly |
| `src/ai/prompts/` | Per-concern prompt builders | existing |
| `src/auth/smart_auth.py` | 3-tier auth detection for target websites | existing — complex heuristics |
| `src/crawler/` | Playwright spider — discovers pages, elements, forms | existing |
| `src/planner/` | AI-driven test plan generation from crawl data | existing |
| `src/executor/` | Test execution, selector resolution, AI fallback, evidence | existing |
| `src/coverage/` | Gap analysis, scoring, visual baseline tracking | existing |
| `src/reporter/` | HTML (Jinja2) and JSON report generation, regression detection | existing |
| `src/models/` | Pydantic v2 data models shared across all modules | existing — shared contracts |
| `src/url_utils.py` | URL normalization and filtering helpers | existing |
| `src/projects/registry.py` | Named project registry — create/get/list/delete projects, active project pointer | new (Sprint 2) |
| `src/projects/resolver.py` | Config resolution — `--project` / active project / legacy `--config` priority | new (Sprint 2) |
| `src/projects/exceptions.py` | `ProjectNotFoundError`, `ProjectAlreadyExistsError` | new (Sprint 2) |
| `src/web/app.py` | FastAPI application factory — mounts API routers + static files, CORS restricted to GET/POST/DELETE | new (Sprint 3) |
| `src/web/routers/projects.py` | REST endpoints for project CRUD and run history list | new (Sprint 3) |
| `src/web/routers/runs.py` | Trigger run (with overrides), SSE log stream, run detail, evidence serving, Excel export | new (Sprint 3), expanded (Sprint 4) |
| `src/web/routers/reports.py` | Serve HTML/JSON reports as static files (path-traversal-safe) | new (Sprint 3) |
| `src/web/run_manager.py` | `RunManager` — starts background pipeline, bridges logging to SSE queue, saves `run_meta.json` | new (Sprint 3), expanded (Sprint 4) |
| `src/web/validation.py` | `validate_safe_filename()`, `validate_project_name()` — shared input guards | new (Sprint 4) |
| `src/web/excel_export.py` | `generate_xlsx(run_result)` — produces three-sheet `.xlsx` via openpyxl | new (Sprint 4) |
| `web/` | React + Vite + Tailwind SPA; pages: Dashboard, ProjectDetail, RunDetail, ReportViewer | new (Sprint 3), expanded (Sprint 4) |

## Data Flow
```
qa-config.json
    → Crawler      → runs/{id}/site_model.json
    → Planner      → runs/{id}/test_plan.json
    → Executor     → runs/{id}/results/, runs/{id}/evidence/
    → Reporter     → qa-reports/{id}/report.html, report.json

POST /api/projects/{name}/run  (RunOverrides)
    → RunManager.start()
        ├── saves runs/{id}/run_meta.json  (NO password — auth_username only)
        └── background thread → Orchestrator → run_result.json
    → GET /api/projects/{name}/runs/{id}          → full RunDetail (+ run_meta)
    → GET /api/projects/{name}/runs/{id}/evidence/{file}  → screenshot / video
    → GET /api/projects/{name}/runs/{id}/export.xlsx      → Excel report
```

## External Dependencies
| Service | Direction | Auth | Purpose |
|---|---|---|---|
| `api.anthropic.com` | outbound | `ANTHROPIC_API_KEY` env var | AI planning, evaluation, selector fallback |
| `http://localhost:11434` | outbound (dev only) | none | Local Ollama LLM alternative |
| Target website (from config) | outbound | smart_auth.py | Subject under test |

## Constraints
- No database — state is persisted as JSON files only
- CLI remains the primary interface; web UI is additive only
- `src/models/` is a shared contract layer — changes cascade to all pipeline stages
- `src/ai/client.py` has complex retry/fallback logic — changes require thorough testing
- Auth credentials for target sites must always come from environment variables, never from committed files; `env:VAR_NAME` references are preserved on save via `field_serializer`
- Project names are restricted to `^[a-zA-Z0-9_-]{1,64}$` (enforced in `registry.create()` and API layer) to prevent path-traversal via directory names
- `target_url` must use `http://` or `https://` scheme (validated in `FrameworkConfig`); `file://`, `ftp://`, etc. are rejected
- Evidence and report file serving validates against path traversal (`..`, null bytes, absolute paths) and restricts to an explicit extension allow-list
- Run overrides (username/password) are applied to an in-memory copy of the config — the original `config.json` is never mutated; `run_meta.json` stores `auth_username` only (never password)
- The web UI has no authentication — it is a local developer tool only (do not expose publicly)
- CORS is restricted to `GET`, `POST`, `DELETE` only
- Frontend build output (`web/dist/`) is gitignored; CI must run `npm run build` before integration tests
