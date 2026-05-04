"""Unit tests for ProjectRegistry."""

import json
from pathlib import Path

import pytest

from src.projects.exceptions import ProjectAlreadyExistsError, ProjectNotFoundError
from src.projects.registry import ProjectInfo, ProjectRegistry


@pytest.fixture
def registry(tmp_path: Path) -> ProjectRegistry:
    return ProjectRegistry(base_dir=tmp_path / ".qa-framework")


class TestInit:
    def test_creates_base_dirs_on_init(self, tmp_path: Path) -> None:
        base = tmp_path / ".qa-framework"
        assert not base.exists()
        ProjectRegistry(base_dir=base)
        assert (base / "projects").exists()

    def test_idempotent_when_dirs_exist(self, tmp_path: Path) -> None:
        base = tmp_path / ".qa-framework"
        ProjectRegistry(base_dir=base)
        ProjectRegistry(base_dir=base)  # should not raise


class TestCreate:
    def test_creates_project_dirs_and_config(self, registry: ProjectRegistry) -> None:
        config = registry.create("kreitech", "https://kreitech.io")
        project_dir = registry.project_dir("kreitech")
        assert (project_dir / "config.json").exists()
        assert (project_dir / "runs").exists()
        assert (project_dir / "qa-reports").exists()
        assert config.target_url == "https://kreitech.io"

    def test_raises_if_project_already_exists(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        with pytest.raises(ProjectAlreadyExistsError) as exc_info:
            registry.create("kreitech", "https://kreitech.io")
        assert "kreitech" in str(exc_info.value)

    def test_config_report_dir_points_to_project(self, registry: ProjectRegistry) -> None:
        config = registry.create("mysite", "https://mysite.com")
        assert "mysite" in config.report_output_dir
        assert "qa-reports" in config.report_output_dir


class TestGet:
    def test_returns_config_for_existing_project(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        config = registry.get("kreitech")
        assert config.target_url == "https://kreitech.io"

    def test_raises_for_unknown_project(self, registry: ProjectRegistry) -> None:
        with pytest.raises(ProjectNotFoundError) as exc_info:
            registry.get("unknown")
        assert "unknown" in str(exc_info.value)


class TestDelete:
    def test_removes_project_directory(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        assert registry.exists("kreitech")
        registry.delete("kreitech")
        assert not registry.exists("kreitech")

    def test_raises_for_unknown_project(self, registry: ProjectRegistry) -> None:
        with pytest.raises(ProjectNotFoundError):
            registry.delete("unknown")

    def test_clears_active_when_deleting_active_project(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        registry.set_active("kreitech")
        assert registry.get_active() == "kreitech"
        registry.delete("kreitech")
        assert registry.get_active() is None

    def test_does_not_clear_active_when_deleting_other_project(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        registry.create("other", "https://other.com")
        registry.set_active("kreitech")
        registry.delete("other")
        assert registry.get_active() == "kreitech"


class TestList:
    def test_empty_when_no_projects(self, registry: ProjectRegistry) -> None:
        assert registry.list() == []

    def test_returns_all_projects(self, registry: ProjectRegistry) -> None:
        registry.create("alpha", "https://alpha.com")
        registry.create("beta", "https://beta.com")
        projects = registry.list()
        names = {p.name for p in projects}
        assert names == {"alpha", "beta"}

    def test_project_info_fields(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        projects = registry.list()
        assert len(projects) == 1
        info = projects[0]
        assert isinstance(info, ProjectInfo)
        assert info.name == "kreitech"
        assert info.target_url == "https://kreitech.io"
        assert info.last_run_date is None
        assert info.last_run_stats is None

    def test_active_flag_set_correctly(self, registry: ProjectRegistry) -> None:
        registry.create("alpha", "https://alpha.com")
        registry.create("beta", "https://beta.com")
        registry.set_active("alpha")
        projects = {p.name: p for p in registry.list()}
        assert projects["alpha"].active is True
        assert projects["beta"].active is False

    def test_populates_last_run_info(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        run_dir = registry.runs_dir("kreitech") / "run-001"
        run_dir.mkdir(parents=True)
        (run_dir / "run_result.json").write_text(json.dumps({
            "run_id": "run-001",
            "completed_at": "2026-04-30T10:00:00",
            "total_tests": 10,
            "passed": 8,
            "failed": 2,
        }))
        info = registry.list()[0]
        assert info.last_run_date == "2026-04-30T10:00:00"
        assert info.last_run_stats == {"total": 10, "passed": 8, "failed": 2}


class TestActiveProject:
    def test_get_active_returns_none_when_not_set(self, registry: ProjectRegistry) -> None:
        assert registry.get_active() is None

    def test_set_and_get_active(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        registry.set_active("kreitech")
        assert registry.get_active() == "kreitech"

    def test_set_active_raises_for_unknown_project(self, registry: ProjectRegistry) -> None:
        with pytest.raises(ProjectNotFoundError):
            registry.set_active("unknown")

    def test_clear_active(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        registry.set_active("kreitech")
        registry.clear_active()
        assert registry.get_active() is None

    def test_overwrite_active(self, registry: ProjectRegistry) -> None:
        registry.create("alpha", "https://alpha.com")
        registry.create("beta", "https://beta.com")
        registry.set_active("alpha")
        registry.set_active("beta")
        assert registry.get_active() == "beta"


class TestExists:
    def test_returns_true_for_existing_project(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        assert registry.exists("kreitech") is True

    def test_returns_false_for_missing_project(self, registry: ProjectRegistry) -> None:
        assert registry.exists("unknown") is False


class TestPaths:
    def test_project_dir(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        assert registry.project_dir("kreitech").name == "kreitech"

    def test_runs_dir(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        assert registry.runs_dir("kreitech").exists()

    def test_reports_dir(self, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        assert registry.reports_dir("kreitech").exists()
