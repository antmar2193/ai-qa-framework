"""Tests for run trigger and SSE endpoints (/api/projects/{name}/run)."""

from __future__ import annotations

from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest
from fastapi.testclient import TestClient

from src.projects.registry import ProjectRegistry
from src.web.app import create_app
from src.web.run_manager import RunManager


@pytest.fixture
def registry(tmp_path: Path) -> ProjectRegistry:
    reg = ProjectRegistry(base_dir=tmp_path / ".qa-framework")
    reg.create("kreitech", "https://kreitech.io")
    return reg


@pytest.fixture
def mock_run_manager() -> RunManager:
    mgr = MagicMock(spec=RunManager)
    mgr.active_run_for.return_value = None
    mgr.start.return_value = "abc12345"
    mgr.get_status.return_value = {
        "run_id": "abc12345",
        "project": "kreitech",
        "status": "running",
        "started_at": "2026-04-30T10:00:00+00:00",
        "completed_at": None,
    }
    return mgr


@pytest.fixture
def client(registry: ProjectRegistry, mock_run_manager: RunManager) -> TestClient:
    app = create_app(registry)
    app.state.run_manager = mock_run_manager
    return TestClient(app)


class TestTriggerRun:
    def test_returns_202_with_run_id(self, client: TestClient) -> None:
        resp = client.post("/api/projects/kreitech/run")
        assert resp.status_code == 202
        assert resp.json()["run_id"] == "abc12345"

    def test_project_not_found(self, client: TestClient) -> None:
        resp = client.post("/api/projects/unknown/run")
        assert resp.status_code == 404

    def test_conflict_when_already_running(
        self, registry: ProjectRegistry, mock_run_manager: RunManager
    ) -> None:
        mock_run_manager.active_run_for.return_value = "existing-run"
        app = create_app(registry)
        app.state.run_manager = mock_run_manager
        resp = TestClient(app).post("/api/projects/kreitech/run")
        assert resp.status_code == 409


class TestRunStatus:
    def test_returns_status(self, client: TestClient) -> None:
        resp = client.get("/api/projects/kreitech/run/abc12345/status")
        assert resp.status_code == 200
        data = resp.json()
        assert data["run_id"] == "abc12345"
        assert data["status"] == "running"

    def test_not_found_for_unknown_run(
        self, registry: ProjectRegistry, mock_run_manager: RunManager
    ) -> None:
        mock_run_manager.get_status.return_value = None
        app = create_app(registry)
        app.state.run_manager = mock_run_manager
        resp = TestClient(app).get("/api/projects/kreitech/run/unknown/status")
        assert resp.status_code == 404


class TestRunManager:
    def test_start_returns_run_id(self, registry: ProjectRegistry) -> None:
        mgr = RunManager()
        # Patch the pipeline so it doesn't actually run
        with patch("src.web.run_manager.RunManager._run_pipeline"):
            run_id = mgr.start("kreitech", registry)
        assert run_id is not None
        assert len(run_id) > 0

    def test_no_active_run_initially(self, registry: ProjectRegistry) -> None:
        mgr = RunManager()
        assert mgr.active_run_for("kreitech") is None

    def test_active_run_detected(self, registry: ProjectRegistry) -> None:
        mgr = RunManager()
        with patch("src.web.run_manager.RunManager._run_pipeline"):
            run_id = mgr.start("kreitech", registry)
        assert mgr.active_run_for("kreitech") == run_id

    def test_get_status_unknown_run(self) -> None:
        mgr = RunManager()
        assert mgr.get_status("nonexistent") is None
