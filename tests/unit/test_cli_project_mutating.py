"""Tests for project create, import, use, delete CLI commands."""

import json
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


class TestProjectCreate:
    def test_creates_project_and_sets_active(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "create", "--name", "kreitech", "--target", "https://kreitech.io"])
        assert result.exit_code == 0
        assert "Created project 'kreitech'" in result.output
        assert registry.exists("kreitech")
        assert registry.get_active() == "kreitech"

    def test_prints_config_path(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "create", "--name", "kreitech", "--target", "https://kreitech.io"])
        assert "config.json" in result.output

    def test_exits_1_if_project_already_exists(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "create", "--name", "kreitech", "--target", "https://kreitech.io"])
        assert result.exit_code == 1
        assert "already exists" in result.output


class TestProjectImport:
    def test_imports_existing_config(self, runner: CliRunner, registry: ProjectRegistry, tmp_path: Path) -> None:
        config_file = tmp_path / "qa-config.json"
        config_file.write_text(json.dumps({"target_url": "https://kreitech.io"}))
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "import", "--name", "kreitech", "--config", str(config_file)])
        assert result.exit_code == 0
        assert "Imported" in result.output
        assert registry.exists("kreitech")
        assert registry.get_active() == "kreitech"

    def test_original_file_untouched(self, runner: CliRunner, registry: ProjectRegistry, tmp_path: Path) -> None:
        config_file = tmp_path / "qa-config.json"
        original = {"target_url": "https://kreitech.io"}
        config_file.write_text(json.dumps(original))
        with _patch_registry(registry):
            runner.invoke(cli, ["project", "import", "--name", "kreitech", "--config", str(config_file)])
        assert json.loads(config_file.read_text()) == original

    def test_updates_report_output_dir(self, runner: CliRunner, registry: ProjectRegistry, tmp_path: Path) -> None:
        config_file = tmp_path / "qa-config.json"
        config_file.write_text(json.dumps({"target_url": "https://kreitech.io", "report_output_dir": "./qa-reports"}))
        with _patch_registry(registry):
            runner.invoke(cli, ["project", "import", "--name", "kreitech", "--config", str(config_file)])
        imported = registry.get("kreitech")
        assert "kreitech" in imported.report_output_dir

    def test_exits_1_if_config_file_missing(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "import", "--name", "kreitech", "--config", "nonexistent.json"])
        assert result.exit_code == 1
        assert "not found" in result.output

    def test_exits_1_if_project_already_exists(self, runner: CliRunner, registry: ProjectRegistry, tmp_path: Path) -> None:
        registry.create("kreitech", "https://kreitech.io")
        config_file = tmp_path / "qa-config.json"
        config_file.write_text(json.dumps({"target_url": "https://kreitech.io"}))
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "import", "--name", "kreitech", "--config", str(config_file)])
        assert result.exit_code == 1


class TestProjectUse:
    def test_sets_active_project(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "use", "kreitech"])
        assert result.exit_code == 0
        assert registry.get_active() == "kreitech"

    def test_exits_1_if_project_not_found(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "use", "unknown"])
        assert result.exit_code == 1
        assert "not found" in result.output.lower() or "unknown" in result.output


class TestProjectDelete:
    def test_deletes_project_after_confirmation(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "delete", "kreitech"], input="y\n")
        assert result.exit_code == 0
        assert not registry.exists("kreitech")
        assert "deleted" in result.output

    def test_does_not_delete_on_decline(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "delete", "kreitech"], input="n\n")
        assert result.exit_code == 0
        assert registry.exists("kreitech")

    def test_clears_active_when_deleting_active_project(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        registry.create("kreitech", "https://kreitech.io")
        registry.set_active("kreitech")
        with _patch_registry(registry):
            runner.invoke(cli, ["project", "delete", "kreitech"], input="y\n")
        assert registry.get_active() is None

    def test_exits_1_if_project_not_found(self, runner: CliRunner, registry: ProjectRegistry) -> None:
        with _patch_registry(registry):
            result = runner.invoke(cli, ["project", "delete", "unknown"])
        assert result.exit_code == 1
