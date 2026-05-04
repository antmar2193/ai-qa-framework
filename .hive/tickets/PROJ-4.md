# PROJ-4 — Add Docker setup for local dev

**Sprint:** 1
**Status:** done
**Effort:** M
**Refs:** TD-06

## Description
Onboarding currently requires manual steps: Python version, pip install, Playwright browser install, and env vars. A Dockerfile makes the environment reproducible and removes machine-specific issues.

## Acceptance Criteria
- [ ] `Dockerfile` added — Python 3.12, installs requirements, installs Playwright browsers
- [ ] `docker-compose.yml` added — mounts project dir, passes env vars via `.env` file
- [ ] `docker-compose.yml` supports running a single QA run: `docker compose run qa-framework run --config qa-config.json`
- [ ] `.dockerignore` excludes `runs/`, `qa-reports/`, `.venv/`, `.git/`
- [ ] `README.md` updated with Docker quick-start section
- [ ] `TECH_DEBT.md` TD-06 marked resolved
