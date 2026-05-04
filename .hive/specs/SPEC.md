# SPEC.md — AI-QA-FRAMEWORK
_Sprint 4 | Generated: 2026-05-01_

## Sprint Goal
Complete the web UI with rich run evidence (screenshots/videos), a pre-run configuration dialog for credentials and overrides, Excel export for sharing results, and a thorough security review that fixes all identified vulnerabilities.

## Tickets

| ID | Title | Effort | Priority | Status | Depends on |
|----|-------|--------|----------|--------|------------|
| RUN-1 | Rich run detail page — evidence viewer, metadata, config snapshot | M | High | done ✅ | WEB-1, WEB-4 |
| RUN-2 | Run configuration dialog — credentials and overrides before executing | M | High | done ✅ | WEB-2, RUN-1 |
| RUN-3 | Excel export — API endpoint + CLI command | S | Medium | done ✅ | RUN-1 |
| RUN-4 | Security review and hardening | M | High | done ✅ | — |

## Suggested order
1. **RUN-4** — security fixes first; touches shared models used by everything else
2. **RUN-1** — backend API + evidence serving + frontend detail page
3. **RUN-2** — run config dialog (needs detail page to link to)
4. **RUN-3** — Excel export (needs run detail page for download button)

## Security issues addressed (RUN-4)
| # | Issue | Severity | Fix |
|---|-------|----------|-----|
| 1 | Password saved in plaintext via model_dump() | HIGH | field_serializer restores env: ref |
| 2 | No project name validation (path traversal) | HIGH | regex `^[a-zA-Z0-9_-]{1,64}$` |
| 3 | target_url accepts any scheme | MEDIUM | validator enforces http/https |
| 4 | Path traversal in evidence file serving | MEDIUM | resolve+relative_to + extension allow-list |
| 5 | Credentials in run body not sanitized | MEDIUM | max-length validation, not logged/stored |
| 6 | Null bytes in report filename | LOW | explicit `\x00` rejection |
| 7 | CORS allow_methods too broad | LOW | restrict to GET/POST/DELETE |

## New dependencies
- Python: `openpyxl>=3.1.0`
- CI: `pip-audit` added to ci.yml

## Ticket files
All tickets are in `.hive/tickets/RUN-{N}.md`
