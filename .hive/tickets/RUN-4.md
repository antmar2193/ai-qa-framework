# RUN-4 — Security review and hardening

**Sprint:** 4
**Status:** done ✅
**Effort:** M
**Depends on:** — (cross-cutting, should be done alongside other tickets)

## Vulnerabilities found and fixes

### 1. Password saved in plaintext (HIGH)
**File:** `src/models/config.py` — `AuthConfig`
**Issue:** `resolve_env_password` field_validator resolves `"env:VAR_NAME"` → actual password at model creation. `FrameworkConfig.save()` calls `model_dump()` which writes the resolved password to `config.json`.
**Fix:** Add `password_env_ref: Optional[str] = Field(default=None, exclude=True)` to store the original reference; add `@field_serializer("password")` that returns the env: ref when available instead of the resolved value.

### 2. No project name validation (HIGH)
**Files:** `src/projects/registry.py`, `src/web/routers/projects.py`
**Issue:** Project names are used as directory names and URL path segments with no validation. A name like `../../../etc` or `<script>` could cause path traversal or XSS.
**Fix:** Add `_validate_name(name)` in registry that enforces `^[a-zA-Z0-9_-]{1,64}$`. Raise `ValueError` on violation. Validate in both `registry.create()` and the API endpoint.

### 3. No target_url validation (MEDIUM)
**File:** `src/models/config.py` — `FrameworkConfig`
**Issue:** `target_url` accepts any string including `file://`, `ftp://`, or `javascript:`. Could allow unexpected behaviour in the crawler.
**Fix:** Add `@field_validator("target_url")` that enforces `http://` or `https://` scheme and non-empty host.

### 4. Path traversal in evidence serving (MEDIUM)
**File:** `src/web/routers/runs.py` (new in RUN-1)
**Issue:** The evidence endpoint will serve files from `runs/{run_id}/evidence/{filename}`. The filename could contain `../` sequences, null bytes, or absolute paths.
**Fix:** Reject filenames containing `\x00`, `..`, or starting with `/` or `\`. Use `path.resolve().relative_to(evidence_dir.resolve())` guard. Allow only extensions: `.png`, `.jpg`, `.jpeg`, `.webm`, `.mp4`, `.json`.

### 5. Credentials sent in API body not sanitized (MEDIUM)
**File:** `src/web/routers/runs.py`
**Issue:** In RUN-2 the run trigger accepts `username` and `password` in the request body. These must not appear in logs or in stored run metadata.
**Fix:** Never log the password field. Store only `auth_username` (not password) in `run_meta.json`. Validate that `username` and `password` are strings with max length 512.

### 6. Report filename allow-list too permissive (LOW)
**File:** `src/web/routers/reports.py`
**Issue:** Current path traversal guard uses `relative_to()` which is good, but null bytes in the filename would still pass through on some OS.
**Fix:** Add explicit null byte rejection: `if '\x00' in filename: raise HTTPException(400)`. Restrict to `.html` and `.json` extensions.

### 7. CORS too permissive for production (LOW)
**File:** `src/web/app.py`
**Issue:** `allow_origins=["http://localhost:5173"]` is correct for dev but `allow_methods=["*"]` is wider than needed.
**Fix:** Restrict to `["GET", "POST", "DELETE"]` only.

## Acceptance Criteria
- All 7 vulnerabilities fixed with tests
- `tests/unit/test_security.py` covers: name injection, password save/load roundtrip, target_url validation, path traversal in evidence and reports, null byte rejection
- `pip-audit` runs in CI (add to `.github/workflows/ci.yml`)
