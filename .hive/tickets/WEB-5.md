# WEB-5 — Report viewer

**Sprint:** 3
**Status:** done ✅
**Effort:** S
**Depends on:** WEB-1, WEB-4

## Description

Serve the existing HTML reports and embed them in the web UI. The reports are already self-contained HTML files; the viewer just needs to expose them via a URL and display them in the browser.

## Acceptance Criteria

### Report file serving (already in WEB-1 scope — verify here)
- `GET /api/projects/{name}/reports/{filename}` returns the raw HTML/JSON file with the correct `Content-Type`.
- `GET /api/projects/{name}/reports` returns a JSON array of available report filenames sorted by modification time (newest first):
  ```json
  [{ "filename": "report_abc123.html", "run_id": "abc123", "modified_at": "2026-04-30T..." }]
  ```

### Report viewer page (`/projects/:name/reports/:runId`)
- **Given** I click "View Report" on a run in the history table, **Then** I navigate to `/projects/:name/reports/:runId`.
- The page embeds the report HTML in a full-height `<iframe>` pointed at `/api/projects/{name}/reports/report_{runId}.html`.
- A "Back" link returns to the project detail page.
- If the report file does not exist, show a "Report not found" message.

### "View Report" link in run history
- Each row in `RunHistoryTable` (WEB-4) that has an available HTML report shows a "View Report" link navigating to the viewer page.
- Rows with no report file show "—" in that column.

## Technical scope

```
web/src/
├── pages/
│   └── ReportViewer.tsx         (iframe + back link)
└── components/
    └── RunHistoryTable.tsx       (update to add View Report link — WEB-4 component)
```

- Add route `/projects/:name/reports/:runId` to `App.tsx`.
- `src/web/routers/reports.py` — add `GET /api/projects/{name}/reports` listing endpoint (file serving already in WEB-1).
- Tests: `tests/unit/test_web_reports_api.py` — assert listing returns correct filenames, assert file serving sets correct Content-Type.
