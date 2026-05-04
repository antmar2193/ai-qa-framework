"""Tests for project list and project history CLI commands."""

import json
import time
from pathlib import Path
from unittest.mock import patch

import pytest
from click.testing import CliRunner

from src.cli import cli
from src.projects.registry import ProjectRegistry


@pytest.fixture
def runner() -> CliRunner:
    return CliRunner()


@pytest.fixture
def registry(tmp_path: Path) -> ProjectRegistry:
    return ProjectRegistry(base_dir=tmp_path / ".qa-framework")


def _patch_registry(registry: ProjectRegistry):
    return patch("src.cli._get_registry", return_value=registry)


def _write_run(registry: ProjectRegistry, project: str, run_id: str, data: dict) -> None:
    run_dir = registry.runs_dir(project) / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    (run_dir / "run_result.json").write_text(json.dumps(data))


class TestProjectList:
    def test_shows_empty_message_when_no_projects(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "list"])
        assert result.exit_code == 0
        assert "No projects configured" in result.output

    def test_shows_table_with_projects(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        registry.create("other", "https://other.com")
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "list"])
        assert result.exit_code == 0
        assert "kreitech" in result.output
        assert "https://kreitech.io" in result.output
        assert "other" in result.output

    def test_shows_active_marker(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        registry.set_active("kreitech")
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "list"])
        assert "✓" in result.output

    def test_shows_dashes_when_no_runs(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "list"])
        assert "—" in result.output

    def test_shows_last_run_stats(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        _write_run(registry, "kreitech", "run-001", {
            "run_id": "run-001",
            "completed_at": "2026-04-30T10:00:00",
            "total_tests": 10,
            "passed": 8,
            "failed": 2,
        })
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "list"])
        assert "8" in result.output
        assert "2" in result.output


class TestProjectHistory:
    def test_shows_empty_message_when_no_runs(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "history", "kreitech"])
        assert result.exit_code == 0
        assert "No runs yet" in result.output

    def test_shows_run_table(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        _write_run(registry, "kreitech", "run-001", {
            "run_id": "run-001",
            "completed_at": "2026-04-30T10:00:00",
            "duration_seconds": 120,
            "total_tests": 5,
            "passed": 4,
            "failed": 1,
        })
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "history", "kreitech"])
        assert result.exit_code == 0
        assert "run-001" in result.output
        assert "120s" in result.output

    def test_exits_1_if_project_not_found(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "history", "unknown"])
        assert result.exit_code == 1
        assert "unknown" in result.output

    def test_last_flag_limits_results(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        for i in range(5):
            time.sleep(0.01)
            _write_run(registry, "kreitech", f"run-{i:03d}", {
                "run_id": f"run-{i:03d}",
                "completed_at": f"2026-04-30T10:00:0{i}",
                "total_tests": 1, "passed": 1, "failed": 0,
            })
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "history", "kreitech", "--last", "2"])
        run_count = result.output.count("run-0")
        assert run_count == 2
