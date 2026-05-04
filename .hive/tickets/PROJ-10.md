# PROJ-10 — Wire --project flag and active project resolution into pipeline commands

**Sprint:** 2
**Status:** done
**Effort:** M
**Depends on:** PROJ-7, PROJ-8

## Description
The pipeline commands (`run`, `crawl`, `plan`, `execute`, `coverage`) currently only accept `--config path`. This ticket adds `--project <name>` support and automatic active-project resolution so users no longer need to pass a config path on every command.

## Acceptance Criteria

### `--project` flag
- **Given** `qa-framework run --project kreitech` is run, **When** the project exists, **Then** the pipeline loads config from `~/.qa-framework/projects/kreitech/config.json` and writes runs/reports to `~/.qa-framework/projects/kreitech/runs/` and `.../qa-reports/`.
- **Given** `--project unknown` is passed, **Then** an error is printed and the command exits with code 1.
- **Given** both `--config` and `--project` are passed, **Then** `--config` takes precedence and a warning is printed.

### Active project auto-resolution
- **Given** neither `--config` nor `--project` is passed, **When** an active project is set in `~/.qa-framework/active-project`, **Then** that project's config is used automatically.
- **Given** neither `--config` nor `--project` is passed and no active project is set, **Then** the command falls back to `qa-config.json` in the current directory (existing behaviour).
- **Given** no active project and no `qa-config.json` exist, **Then** the command prints a helpful message: `"No project configured. Run: qa-framework project create --name <n> --target <url>"` and exits with code 1.

### Output path isolation
- **Given** a project is resolved (via `--project` or active project), **When** the pipeline runs, **Then** `runs/` and `qa-reports/` output is written inside the project directory, not the current working directory.
- **Given** `--config` is used (legacy mode), **Then** output paths follow the `report_output_dir` value in the config file (no change from current behaviour).

### Backward compatibility
- **Given** existing scripts use `qa-framework run --config qa-config.json`, **Then** they continue to work without any changes.

## Technical scope
- Add `--project` option to `run`, `crawl`, `plan`, `execute`, `coverage` commands in `src/cli.py`
- Extract config resolution into a shared helper `src/projects/resolver.py`: `resolve_config(project, config) -> (FrameworkConfig, output_dir)`
- `Orchestrator` receives output_dir at init time (or via config override) so it writes to the project dir
- Tests: `tests/integration/test_project_pipeline_resolution.py`
