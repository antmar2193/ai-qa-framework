# WEB-4 — Project detail page + trigger run + live log viewer

**Sprint:** 3
**Status:** done ✅
**Effort:** L
**Depends on:** WEB-2, WEB-3

## Description

Implement the project detail page (`/projects/:name`). It shows run history, lets the user trigger a new pipeline run, and displays a live log stream as the run progresses via SSE.

## Acceptance Criteria

### Project detail page (`/projects/:name`)
- **Given** I navigate to `/projects/kreitech`, **Then** I see:
  - Project name and target URL in a header
  - "Run Now" button (disabled while a run is in progress)
  - A run history table (from `GET /api/projects/{name}/runs`) with columns: Run ID, Date, Duration, Total, Passed, Failed, and a "View Report" link
  - "Set Active" button if the project is not the active one

### Trigger a run
- **Given** I click "Run Now", **Then**:
  1. `POST /api/projects/{name}/run` is called → returns `{ "run_id": "..." }`
  2. The "Run Now" button becomes disabled and shows "Running…"
  3. A log panel opens below the button showing real-time SSE output

### Live log panel
- **Given** a run is in progress, **Then** the log panel:
  - Connects to `GET /api/projects/{name}/run/{run_id}/stream`
  - Appends each incoming SSE line to a scrollable, monospace text area (auto-scrolls to bottom)
  - Shows a pulsing "Live" indicator while streaming
  - On the `done` event: closes the stream, re-enables "Run Now", shows a green "Passed" or red "Failed" banner
  - On network error: shows an "Connection lost — refresh to retry" message

### Run history refresh
- After a run completes, the run history table automatically refreshes to include the new run (without a full page reload).

### Error states
- If `POST /api/projects/{name}/run` returns 409, show "A run is already in progress."
- If the project is not found (404), show a "Project not found" message with a link back to the dashboard.

## Technical scope

```
web/src/
├── pages/
│   └── ProjectDetail.tsx       (replaces stub from WEB-3)
└── components/
    ├── RunHistoryTable.tsx
    ├── RunNowButton.tsx
    └── LiveLogPanel.tsx         (SSE consumer using EventSource API)
```

- `LiveLogPanel` uses the browser `EventSource` API; close the connection in a `useEffect` cleanup function.
- `useRunPoller` hook: starts SSE on run trigger, updates state on `done` event, re-fetches run history.
- `RunHistoryTable` accepts a `projectName` prop and fetches from `GET /api/projects/{name}/runs`.
