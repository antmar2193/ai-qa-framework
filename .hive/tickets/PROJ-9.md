# PROJ-9 — CLI: project list and project history commands

**Sprint:** 2
**Status:** done
**Effort:** S
**Depends on:** PROJ-7

## Description
Read-only display commands for the project registry. `list` shows all configured projects at a glance; `history` shows past runs for a specific project.

## Acceptance Criteria

### `project list`
- **Given** no projects are configured, **When** `qa-framework project list` is run, **Then** the console prints `"No projects configured. Run: qa-framework project create --name <n> --target <url>"`.
- **Given** one or more projects exist, **When** `qa-framework project list` is run, **Then** a Rich table is printed with columns: Name, Target URL, Last Run, Passed, Failed, Active.
- **Given** `kreitech` is the active project, **Then** its row shows `✓` in the Active column.
- **Given** a project has no runs yet, **Then** Last Run shows `"—"` and pass/fail show `"—"`.

### `project history`
- **Given** `qa-framework project history kreitech` is run, **When** the project has previous runs, **Then** a Rich table is printed with columns: Run ID, Date, Duration, Total, Passed, Failed, Report.
- **Given** the project has no runs, **Then** the console prints `"No runs yet for kreitech."`.
- **Given** the project does not exist, **Then** an error is printed and the command exits with code 1.
- **Given** `--last 5` flag is passed, **Then** only the 5 most recent runs are shown (default: 10).

## Technical scope
- Add `project list` and `project history` subcommands to the `project` group in `src/cli.py`
- Read run history from `~/.qa-framework/projects/<name>/runs/` — parse `run_result.json` from each run dir
- Use `rich.table.Table` for output (consistent with existing `run` command output)
- Tests: `tests/unit/test_cli_project_readonly.py`
