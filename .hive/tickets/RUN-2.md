# RUN-2 — Run configuration dialog (credentials and overrides before executing)

**Sprint:** 4
**Status:** done ✅
**Effort:** M
**Depends on:** WEB-2, RUN-1

## Description
Before triggering a run the user should be able to supply runtime overrides — credentials (username/password if required), extra hints for this run, and category selection. Credentials are applied in memory only and never stored.

## Acceptance Criteria

### Backend
- `POST /api/projects/{name}/run` body now accepts optional overrides:
  ```json
  { "username": "user@example.com", "password": "s3cr3t", "hints": ["Focus on checkout"], "categories": ["functional","security"] }
  ```
- Overrides are applied to a copy of the project config before the pipeline runs; the original `config.json` is never modified
- Credentials are not logged, not stored in `run_meta.json` (only `auth_username` is stored, not password)
- Returns 400 if a non-http/https URL override is supplied

### Frontend — RunConfigModal
- "Run Now" button opens `RunConfigModal` instead of triggering directly
- Fields (all optional):
  - Username / Password (shown only if project config has `auth` configured OR always, since user may want to add auth for this run)
  - Extra hints (textarea, one per line)
  - Categories (checkboxes: functional, visual, security — defaults to project config)
- "Run" button submits and closes modal; run proceeds as in WEB-4
- Password field uses `type="password"` and is never sent back to the page after submit
