# RUN-3 — Excel export (API endpoint + CLI command)

**Sprint:** 4
**Status:** done ✅
**Effort:** S
**Depends on:** RUN-1

## Description
Export run results to `.xlsx` for sharing. Three sheets: Summary, Test Cases, and Errors (only failed/error tests with details). Available via the web UI (download button on the run detail page) and via CLI.

## Acceptance Criteria

### Backend
- `GET /api/projects/{name}/runs/{run_id}/export.xlsx` returns an `.xlsx` file with `Content-Disposition: attachment; filename=report_{run_id}.xlsx`
- Sheet 1 **Summary**: run_id, target_url, started_at, completed_at, duration_seconds, total, passed, failed, skipped, errors, ai_summary
- Sheet 2 **Test Cases**: test_id, test_name, category, result, duration_seconds, failure_reason (all tests)
- Sheet 3 **Errors**: test_id, test_name, category, failure_reason, step where it failed (failed/error tests only)
- Returns 404 if run_id not found

### CLI
```bash
python -m src.cli export --project <n> --run-id <id> [--output report.xlsx]
```
Writes the xlsx file and prints the path.

### Frontend
- "Export Excel" button on RunDetail page header calls the endpoint and triggers browser download
- Button shows "Exporting…" while in flight

## Technical scope
- `src/web/excel_export.py` — `generate_xlsx(run_result: RunResult) -> bytes`
- `src/web/routers/runs.py` — add `GET /{name}/runs/{run_id}/export.xlsx` endpoint
- `src/cli.py` — add `export` command
- Add `openpyxl>=3.1.0` to `requirements.in`
