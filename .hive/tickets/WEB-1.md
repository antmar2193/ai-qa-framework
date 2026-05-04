# WEB-1 — FastAPI app + REST API for project CRUD

**Sprint:** 3
**Status:** done ✅
**Effort:** M
**Depends on:** PROJ-7, PROJ-8 (ProjectRegistry already implemented)

## Description

Create the FastAPI application shell (`src/web/`) and wire up REST endpoints for project management. Add a `serve` CLI command so users can start the web server with one command. The frontend (React) will be built separately in WEB-3; this ticket only needs to serve a placeholder at `/` for now and focus on the API.

## Acceptance Criteria

### `serve` CLI command
- **Given** `python -m src.cli serve` is run, **Then** a FastAPI/uvicorn server starts on `http://localhost:8000` and a message is printed: `Web UI: http://localhost:8000`.
- **Given** `--port 9090` is passed, **Then** the server listens on port 9090.
- **Given** `web/dist/index.html` exists, **Then** `GET /` serves that file (React SPA). If it does not exist, return a plain-text "Frontend not built. Run: npm run build in web/" message.

### Project list
- `GET /api/projects` returns `200` with a JSON array of project summaries:
  ```json
  [{ "name": "kreitech", "target_url": "...", "active": true, "last_run_date": "...", "last_run_stats": {...} }]
  ```

### Project create
- `POST /api/projects` body `{ "name": "mysite", "target_url": "https://..." }` creates a project and returns `201` with the created project.
- Returns `409 Conflict` if the project already exists.

### Project delete
- `DELETE /api/projects/{name}` deletes the project and returns `204`.
- Returns `404` if the project does not exist.

### Set active project
- `POST /api/projects/{name}/use` sets the active project and returns `200 { "active": "name" }`.
- Returns `404` if the project does not exist.

### Run history
- `GET /api/projects/{name}/runs` returns the last 20 runs for the project as a JSON array.
- Returns `404` if the project does not exist.

### Static files
- `GET /api/projects/{name}/reports/{filename}` serves the HTML/JSON report file from `~/.qa-framework/projects/{name}/qa-reports/{filename}`.
- Returns `404` if file does not exist.

## Technical scope

- New package `src/web/` with `__init__.py`
- `src/web/app.py` — FastAPI factory: `create_app(registry: ProjectRegistry) -> FastAPI`
  - Mounts `/api` router
  - Mounts `web/dist/` as `StaticFiles` at `/` if directory exists
- `src/web/routers/projects.py` — project CRUD + `use` endpoint
- `src/web/routers/reports.py` — report file serving
- Add `serve` command to `src/cli.py`:
  ```python
  @cli.command()
  @click.option("--port", default=8000)
  def serve(port: int) -> None:
      import uvicorn
      from src.web.app import create_app
      app = create_app(_get_registry())
      uvicorn.run(app, host="0.0.0.0", port=port)
  ```
- Add `fastapi>=0.110.0` and `uvicorn>=0.27.0` to `requirements.in`
- Tests: `tests/unit/test_web_projects_api.py` using FastAPI `TestClient`
