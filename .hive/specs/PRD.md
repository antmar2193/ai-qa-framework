# PRD — AI-QA-FRAMEWORK
_Last updated: 2026-04-30_

## Problem
QA teams spend significant time manually writing and maintaining test cases for web applications. As UIs change, tests break and need constant updating. Small teams can't keep up with coverage across functional, visual, and security dimensions.

## Goal
An autonomous QA agent that crawls a target web application, generates a comprehensive test plan via AI, executes it with Playwright, and produces actionable reports — with minimal human input per run.

## Current State
The core pipeline (Crawl → Plan → Execute → Report) is built and working. Sprint 1 stabilized the project foundation. The `kreitech` project (https://kreitech.io) has been manually migrated to `~/.qa-framework/projects/kreitech/` and set as the active project — this is the reference implementation for the multi-project feature.

## Features in Scope

### Multi-project management

Currently, the framework manages a single site via one `qa-config.json` file in the working directory. Teams testing more than one site must juggle multiple config files manually and have no isolation between run histories and reports.

**Feature:** Named project registry — create, list, switch, and run multiple QA projects from a single framework installation, each with isolated config, run history, and reports.

**User stories:**

- [ ] **Create project:** Given I have a site to test, When I run `qa-framework project create --name kreitech --target https://kreitech.io`, Then a named project is created with a default config under `~/.qa-framework/projects/kreitech/` and I see a confirmation message.

- [ ] **List projects:** Given I have one or more projects configured, When I run `qa-framework project list`, Then I see a table with each project's name, target URL, last run date, and pass/fail count.

- [ ] **Run by project name:** Given a project named `kreitech` exists, When I run `qa-framework run --project kreitech`, Then the pipeline runs using that project's config and stores results under its isolated `runs/` and `qa-reports/` directories.

- [ ] **View run history:** Given a project has previous runs, When I run `qa-framework project history kreitech`, Then I see a list of past runs with date, duration, total/passed/failed counts, and a link to the HTML report.

- [ ] **Set active project:** Given I work frequently with one project, When I run `qa-framework project use kreitech`, Then subsequent `run`, `crawl`, `plan`, and `coverage` commands use that project by default without requiring `--project` on every call.

- [ ] **Delete project:** Given I no longer need a project, When I run `qa-framework project delete kreitech --confirm`, Then the project config and all its run history are removed, and the command asks for confirmation before deleting.

- [ ] **Import existing config:** Given I already have a `qa-config.json` in the current directory, When I run `qa-framework project import --name kreitech`, Then the config is copied to `~/.qa-framework/projects/kreitech/config.json`, the project is set as active, and the original `qa-config.json` is left untouched.

**Storage layout:**
```
~/.qa-framework/
  projects/
    kreitech/
      config.json       ← project config (target URL, auth, hints, etc.)
      runs/             ← isolated run output
      qa-reports/       ← isolated HTML/JSON reports
    other-site/
      config.json
      runs/
      qa-reports/
  active-project        ← plain text file: name of the active project
```

**Backward compatibility:** existing `qa-config.json` workflow must continue to work unchanged (`--config path/to/file.json` always overrides project resolution).

## Web Interface (Sprint 3)

The CLI covers power users well, but teams want a browser-based dashboard to manage projects, trigger runs, and review reports without memorizing commands.

**Feature:** A React + Tailwind SPA backed by a FastAPI server that wraps the existing `ProjectRegistry` and `Orchestrator`. The CLI remains fully functional — the web UI is an additive layer on top.

**User stories:**

- [ ] **Projects dashboard:** Given I open the web UI, Then I see all configured projects with their target URL, last run date, and pass/fail count — with buttons to create, delete, and set the active project.

- [ ] **Trigger a run:** Given I am on a project's detail page, When I click "Run Now", Then a pipeline run starts in the background and a live log stream appears in the browser as the pipeline progresses.

- [ ] **Live run progress:** Given a run is in progress, Then I see a real-time log feed via Server-Sent Events — each pipeline stage (Crawl, Plan, Execute, Report) appears as lines scroll in.

- [ ] **Run history:** Given a project has previous runs, Then I see a table of past runs with date, duration, and pass/fail counts, with a "View Report" button for each.

- [ ] **Report viewer:** Given I click "View Report" on a completed run, Then the existing HTML report is displayed in the browser — embedded in an iframe on the report page.

**Technical approach:**
- Backend: FastAPI (`src/web/`) with REST endpoints + SSE streaming; served via new `python -m src.cli serve` command
- Frontend: React + Vite + Tailwind CSS (`web/` directory); production build served as static files by FastAPI
- Dev workflow: `vite` dev server proxies API calls to FastAPI on port 8000

## Out of Scope
- Supporting non-Chromium browsers in the same run (single browser per config)
- Shared run history across projects (each project is fully isolated)
- Authentication/authorization for the web UI (local tool only)
