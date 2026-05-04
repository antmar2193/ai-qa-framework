# WEB-2 — Background task runner + SSE log streaming

**Sprint:** 3
**Status:** done ✅
**Effort:** M
**Depends on:** WEB-1

## Description

Add the ability to trigger a pipeline run via the API and stream its log output back to the browser in real time using Server-Sent Events (SSE). Runs execute in a background thread so the HTTP response returns immediately. Each run gets a unique ID; clients open a second SSE request to stream the log.

## Acceptance Criteria

### Trigger a run
- `POST /api/projects/{name}/run` starts a full pipeline run in a background thread and returns `202 Accepted` immediately with `{ "run_id": "<uuid>" }`.
- Returns `404` if the project does not exist.
- Returns `409 Conflict` if a run for that project is already in progress.

### SSE log stream
- `GET /api/projects/{name}/run/{run_id}/stream` returns a `text/event-stream` response.
- Each log line emitted by the pipeline is sent as an SSE event: `data: <line>\n\n`.
- When the run completes, a final event is sent: `data: {"event": "done", "status": "passed"|"failed"}\n\n`, then the stream closes.
- If the run ID is unknown or already finished, returns `404`.

### Run status
- `GET /api/projects/{name}/run/{run_id}` returns the current status of a run:
  ```json
  { "run_id": "...", "status": "running"|"done"|"failed", "started_at": "...", "completed_at": "..." }
  ```

### In-memory state
- Active run state is stored in a module-level dict on the `RunManager` — no file persistence required for in-progress runs (completed runs are already persisted to `run_result.json` by the Orchestrator).

## Technical scope

- `src/web/run_manager.py` — `RunManager` class:
  - `start(name, registry) -> run_id` — spawns background thread, returns UUID
  - `get_status(run_id) -> dict | None`
  - `stream(run_id) -> AsyncGenerator[str, None]` — yields SSE lines from a queue
  - Uses `queue.Queue` to bridge the sync Orchestrator with async SSE generator
- `src/web/routers/runs.py` — three endpoints above, injecting `RunManager` as a FastAPI dependency
- `src/web/app.py` — instantiate `RunManager` once and inject it via `app.state`
- Orchestrator log capture: patch Python's `logging` module with a `QueueHandler` scoped to the run, so all `logging.*` calls from the pipeline are captured and forwarded to the SSE queue
- Tests: `tests/unit/test_web_runs_api.py` — mock `RunManager`, assert 202/404/409 responses and SSE event format
