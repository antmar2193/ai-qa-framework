"""Tests for FastAPI project CRUD endpoints (/api/projects)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from src.projects.registry import ProjectRegistry
from src.web.app import create_app


@pytest.fixture
def registry(tmp_path: Path) -> ProjectRegistry:
    return ProjectRegistry(base_dir=tmp_path / ".qa-framework")


@pytest.fixture
def client(registry: ProjectRegistry) -> TestClient:
    return TestClient(create_app(registry))


@pytest.fixture
def client_with_project(registry: ProjectRegistry) -> TestClient:
    registry.create("kreitech", "https://kreitech.io")
    return TestClient(create_app(registry))


class TestListProjects:
    def test_empty_list(self, client: TestClient) -> None:
        resp = client.get("/api/projects")
        assert resp.status_code == 200
        assert resp.json() == []

    def test_returns_project(self, client_with_project: TestClient) -> None:
        resp = client_with_project.get("/api/projects")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 1
        assert data[0]["name"] == "kreitech"
        assert data[0]["target_url"] == "https://kreitech.io"

    def test_active_marker(self, registry: ProjectRegistry) -> None:
        registry.create("mysite", "https://mysite.com")
        registry.set_active("mysite")
        resp = TestClient(create_app(registry)).get("/api/projects")
        assert resp.json()[0]["active"] is True

    def test_inactive_marker(self, client_with_project: TestClient) -> None:
        data = client_with_project.get("/api/projects").json()
        assert data[0]["active"] is False


class TestCreateProject:
    def test_creates_project(self, client: TestClient, registry: ProjectRegistry) -> None:
        resp = client.post(
            "/api/projects", json={"name": "newsite", "target_url": "https://new.com"}
        )
        assert resp.status_code == 201
        assert resp.json()["name"] == "newsite"
        assert registry.exists("newsite")

    def test_returns_project_summary(self, client: TestClient) -> None:
        resp = client.post(
            "/api/projects", json={"name": "s", "target_url": "https://s.com"}
        )
        body = resp.json()
        assert body["target_url"] == "https://s.com"
        assert body["active"] is False

    def test_conflict_on_duplicate(self, client_with_project: TestClient) -> None:
        resp = client_with_project.post(
            "/api/projects",
            json={"name": "kreitech", "target_url": "https://kreitech.io"},
        )
        assert resp.status_code == 409


class TestDeleteProject:
    def test_deletes_project(
        self, client_with_project: TestClient, registry: ProjectRegistry
    ) -> None:
        resp = client_with_project.delete("/api/projects/kreitech")
        assert resp.status_code == 204
        assert not registry.exists("kreitech")

    def test_not_found(self, client: TestClient) -> None:
        resp = client.delete("/api/projects/unknown")
        assert resp.status_code == 404


class TestUseProject:
    def test_sets_active(
        self, client_with_project: TestClient, registry: ProjectRegistry
    ) -> None:
        resp = client_with_project.post("/api/projects/kreitech/use")
        assert resp.status_code == 200
        assert resp.json()["active"] == "kreitech"
        assert registry.get_active() == "kreitech"

    def test_not_found(self, client: TestClient) -> None:
        resp = client.post("/api/projects/unknown/use")
        assert resp.status_code == 404


class TestListRuns:
    def test_empty_runs(self, client_with_project: TestClient) -> None:
        resp = client_with_project.get("/api/projects/kreitech/runs")
        assert resp.status_code == 200
        assert resp.json() == []

    def test_not_found(self, client: TestClient) -> None:
        resp = client.get("/api/projects/unknown/runs")
        assert resp.status_code == 404

    def test_returns_run_data(self, registry: ProjectRegistry) -> None:
        registry.create("mysite", "https://mysite.com")
        run_dir = registry.runs_dir("mysite") / "run-001"
        run_dir.mkdir(parents=True)
        (run_dir / "run_result.json").write_text(
            json.dumps({"run_id": "run-001", "passed": 5, "failed": 1, "total_tests": 6})
        )
        resp = TestClient(create_app(registry)).get("/api/projects/mysite/runs")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 1
        assert data[0]["run_id"] == "run-001"
        assert data[0]["passed"] == 5
