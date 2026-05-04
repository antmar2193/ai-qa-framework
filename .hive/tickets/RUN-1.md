# RUN-1 — Rich run detail page (evidence viewer, metadata, config snapshot)

**Sprint:** 4
**Status:** done ✅
**Effort:** M
**Depends on:** WEB-1, WEB-4

## Description
Add a dedicated run detail page that shows the full picture of an execution: which config was used, every test case result, screenshots per step, and video evidence if captured. The run history table links to this page instead of (or alongside) the HTML report.

## Acceptance Criteria

### Backend
- `GET /api/projects/{name}/runs/{run_id}` returns the full `RunResult` JSON from `runs/{run_id}/run_result.json` (404 if missing)
- `GET /api/projects/{name}/runs/{run_id}/evidence/{filename}` serves evidence files (screenshots, videos) from `runs/{run_id}/evidence/`; rejects path traversal with 400; returns 404 if missing

### Frontend — RunDetail page (`/projects/:name/runs/:runId`)
- Header: run ID, date, duration, target URL, pass/fail/skip/error counts
- Config snapshot section: shows the categories tested, hint count, AI model used
- Test case table: test name, category, result badge (pass/green, fail/red, skip/yellow), duration, failure_reason
- Evidence panel: clicking a test row expands it to show step screenshots inline (thumbnail grid); clicking a thumbnail opens full-size
- Video: if `evidence.video_path` is set, shows a `<video>` element
- RunHistoryTable: "Details" link navigates to this page; "Report" link navigates to the HTML report viewer

### Run input metadata
- When a run is triggered with overrides (username, hints), a `run_meta.json` is saved alongside `run_result.json` containing: triggered_at, categories, hints_used, auth_username (NOT password), target_url
- The detail page shows this metadata in the header section
