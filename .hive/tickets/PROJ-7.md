# PROJ-7 — Project registry: core storage layer

**Sprint:** 2
**Status:** done
**Effort:** M

## Description
Foundation for multi-project support. A `ProjectRegistry` class that manages reading and writing project configs, run dirs, and the active-project pointer under `~/.qa-framework/`. All other Sprint 2 tickets depend on this.

## Acceptance Criteria

### Given/When/Then

- **Given** the `~/.qa-framework/` directory does not exist, **When** `ProjectRegistry` is instantiated, **Then** it creates the directory structure automatically without error.

- **Given** `ProjectRegistry.create("kreitech", "https://kreitech.io")` is called, **When** the project does not already exist, **Then** `~/.qa-framework/projects/kreitech/config.json`, `runs/`, and `qa-reports/` are created and a `ProjectConfig` is returned.

- **Given** `ProjectRegistry.create("kreitech", ...)` is called, **When** the project already exists, **Then** a `ProjectAlreadyExistsError` is raised.

- **Given** projects exist, **When** `ProjectRegistry.list()` is called, **Then** a list of `ProjectInfo` objects is returned (name, target_url, path, last_run_date, last_run_stats).

- **Given** a project exists, **When** `ProjectRegistry.get("kreitech")` is called, **Then** the `ProjectConfig` loaded from `config.json` is returned.

- **Given** a project does not exist, **When** `ProjectRegistry.get("unknown")` is called, **Then** a `ProjectNotFoundError` is raised.

- **Given** a project exists, **When** `ProjectRegistry.set_active("kreitech")` is called, **Then** `~/.qa-framework/active-project` is written with `"kreitech"`.

- **Given** `~/.qa-framework/active-project` contains `"kreitech"`, **When** `ProjectRegistry.get_active()` is called, **Then** `"kreitech"` is returned.

- **Given** no active project is set, **When** `ProjectRegistry.get_active()` is called, **Then** `None` is returned.

- **Given** a project exists, **When** `ProjectRegistry.delete("kreitech")` is called, **Then** the entire `~/.qa-framework/projects/kreitech/` directory is removed.

## Technical scope
- New module: `src/projects/registry.py` + `src/projects/__init__.py`
- New exceptions: `ProjectNotFoundError`, `ProjectAlreadyExistsError` in `src/projects/exceptions.py`
- `ProjectInfo` dataclass: name, target_url, path, last_run_date, last_run_stats
- Reuse `FrameworkConfig.load()` / `FrameworkConfig.save()` for reading/writing `config.json`
- Tests: `tests/unit/test_project_registry.py` (mock filesystem with `tmp_path`)
