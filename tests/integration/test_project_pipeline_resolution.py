"""Integration tests for --project flag and active project resolution."""

import json
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from src.projects.registry import ProjectRegistry
from src.projects.resolver import resolve_config


@pytest.fixture
def registry(tmp_path: Path) -> ProjectRegistry:
    return ProjectRegistry(base_dir=tmp_path / ".qa-framework")


@pytest.fixture
def kreitech(registry: ProjectRegistry) -> ProjectRegistry:
    registry.create("kreitech", "https://kreitech.io")
    return registry


class TestResolveConfigProjectFlag:
    def test_loads_config_from_project_dir(self, kreitech: ProjectRegistry) -> None:
        cfg, runs_dir = resolve_config("kreitech", "qa-config.json", kreitech)
        assert cfg.target_url == "https://kreitech.io"

    def test_returns_project_runs_dir(self, kreitech: ProjectRegistry) -> None:
        cfg, runs_dir = resolve_config("kreitech", "qa-config.json", kreitech)
        assert runs_dir is not None
        assert "kreitech" in str(runs_dir)
        assert runs_dir.name == "runs"

    def test_report_output_dir_points_to_project(self, kreitech: ProjectRegistry) -> None:
        cfg, _ = resolve_config("kreitech", "qa-config.json", kreitech)
        assert "kreitech" in cfg.report_output_dir
        assert "qa-reports" in cfg.report_output_dir

    def test_exits_1_for_unknown_project(self, registry: ProjectRegistry) -> None:
        with pytest.raises(SystemExit) as exc_info:
            resolve_config("unknown", "qa-config.json", registry)
        assert exc_info.value.code == 1


class TestResolveConfigLegacyMode:
    def test_loads_from_config_path(self, registry: ProjectRegistry, tmp_path: Path) -> None:
        config_file = tmp_path / "my-config.json"
        config_file.write_text(json.dumps({"target_url": "https://legacy.com"}))
        cfg, runs_dir = resolve_config(None, str(config_file), registry)
        assert cfg.target_url == "https://legacy.com"
        assert runs_dir is None

    def test_config_flag_wins_over_project(self, kreitech: ProjectRegistry, tmp_path: Path) -> None:
        config_file = tmp_path / "override.json"
        config_file.write_text(json.dumps({"target_url": "https://override.com"}))
        kreitech.set_active("kreitech")
        cfg, runs_dir = resolve_config(None, str(config_file), kreitech)
        assert cfg.target_url == "https://override.com"
        assert runs_dir is None


class TestResolveConfigActiveProject:
    def test_uses_active_project_when_no_flags(self, kreitech: ProjectRegistry) -> None:
        kreitech.set_active("kreitech")
        cfg, runs_dir = resolve_config(None, "qa-config.json", kreitech)
        assert cfg.target_url == "https://kreitech.io"
        assert runs_dir is not None
        assert "kreitech" in str(runs_dir)

    def test_falls_back_to_config_file_when_no_active(
        self, registry: ProjectRegistry, tmp_path: Path
    ) -> None:
        config_file = tmp_path / "qa-config.json"
        config_file.write_text(json.dumps({"target_url": "https://fallback.com"}))
        cfg, runs_dir = resolve_config(None, str(config_file), registry)
        assert cfg.target_url == "https://fallback.com"
        assert runs_dir is None

    def test_exits_1_when_nothing_configured(self, registry: ProjectRegistry) -> None:
        with pytest.raises(SystemExit) as exc_info:
            resolve_config(None, "nonexistent-config.json", registry)
        assert exc_info.value.code == 1


class TestOrchestratorRunsDir:
    def test_orchestrator_uses_project_runs_dir(self, kreitech: ProjectRegistry) -> None:
        from src.orchestrator import Orchestrator
        cfg, runs_dir = resolve_config("kreitech", "qa-config.json", kreitech)
        orch = Orchestrator(cfg, runs_dir=runs_dir)
        assert "kreitech" in str(orch.runs_dir)

    def test_orchestrator_defaults_to_local_runs(self, tmp_path: Path) -> None:
        from src.models.config import FrameworkConfig
        from src.orchestrator import Orchestrator
        cfg = FrameworkConfig(target_url="https://example.com")
        orch = Orchestrator(cfg)
        assert orch.runs_dir == Path("runs")

    def test_orchestrator_accepts_custom_runs_dir(self, tmp_path: Path) -> None:
        from src.models.config import FrameworkConfig
        from src.orchestrator import Orchestrator
        cfg = FrameworkConfig(target_url="https://example.com")
        custom = tmp_path / "custom-runs"
        orch = Orchestrator(cfg, runs_dir=custom)
        assert orch.runs_dir == custom
        assert custom.exists()
