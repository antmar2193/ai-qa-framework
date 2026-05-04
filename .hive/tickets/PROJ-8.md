# PROJ-8 — CLI: project create, import, use, delete commands

**Sprint:** 2
**Status:** done
**Effort:** M
**Depends on:** PROJ-7

## Description
Add the `project` CLI command group with the four mutating commands: `create`, `import`, `use`, and `delete`. Read-only commands (`list`, `history`) are in PROJ-9.

## Acceptance Criteria

### `project create`
- **Given** `qa-framework project create --name kreitech --target https://kreitech.io` is run, **When** the project does not exist, **Then** the project is created under `~/.qa-framework/projects/kreitech/` and the console prints a confirmation with the config path.
- **Given** the project already exists, **Then** the command prints an error and exits with code 1 (no overwrite).

### `project import`
- **Given** `qa-framework project import --name kreitech` is run from a directory containing `qa-config.json`, **When** the project does not already exist, **Then** the config is copied to `~/.qa-framework/projects/kreitech/config.json`, the project is set as active, and the original file is untouched.
- **Given** `qa-framework project import --name kreitech --config path/to/other.json` is run, **Then** the specified config file is used instead of `qa-config.json`.
- **Given** the target config file does not exist, **Then** an error is printed and the command exits with code 1.

### `project use`
- **Given** `qa-framework project use kreitech` is run, **When** the project exists, **Then** `~/.qa-framework/active-project` is updated to `"kreitech"` and the console confirms.
- **Given** the project does not exist, **Then** an error is printed and the command exits with code 1.

### `project delete`
- **Given** `qa-framework project delete kreitech` is run, **When** the project exists, **Then** the CLI prompts for confirmation before deleting.
- **Given** the user confirms, **Then** the project directory is removed and the console confirms.
- **Given** the deleted project was the active project, **Then** `active-project` is cleared.
- **Given** the user declines, **Then** nothing is deleted.

## Technical scope
- Add `@cli.group() def project()` to `src/cli.py`
- Commands: `project create`, `project import`, `project use`, `project delete`
- Use `click.confirm()` for the delete confirmation
- Tests: `tests/unit/test_cli_project_mutating.py`
