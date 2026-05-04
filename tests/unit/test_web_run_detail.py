"""Tests for run detail and evidence endpoints (RUN-1)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from src.projects.registry import ProjectRegistry
from src.web.app import create_app


@pytest.fixture
def registry_with_run(tmp_path: Path) -> ProjectRegistry:
    reg = ProjectRegistry(base_dir=tmp_path / ".qa-framework")
    reg.create("mysite", "https://mysite.com")
    run_dir = reg.runs_dir("mysite") / "run-abc"
    run_dir.mkdir(parents=True)
    (run_dir / "run_result.json").write_text(json.dumps({
        "run_id": "run-abc",
        "plan_id": "plan-1",
        "started_at": "2026-05-01T10:00:00",
        "completed_at": "2026-05-01T10:20:00",
        "target_url": "https://mysite.com",
        "total_tests": 3,
        "passed": 2,
        "failed": 1,
        "skipped": 0,
        "errors": 0,
        "duration_seconds": 1200.0,
        "test_results": [],
        "ai_summary": "Two tests passed, one failed.",
    }))
    (run_dir / "run_meta.json").write_text(json.dumps({
        "run_id": "run-abc",
        "project": "mysite",
        "triggered_at": "2026-05-01T10:00:00Z",
        "target_url": "https://mysite.com",
        "categories": ["functional"],
        "hints_count": 1,
        "ai_model": "claude-opus-4-6",
    }))
    # Evidence files
    evidence_dir = run_dir / "evidence"
    evidence_dir.mkdir()
    (evidence_dir / "step_1.png").write_bytes(b"\x89PNG\r\n")
    return reg


class TestRunDetailEndpoint:
    def test_returns_run_result(self, registry_with_run: ProjectRegistry) -> None:
        client = TestClient(create_app(registry_with_run))
        resp = client.get("/api/projects/mysite/runs/run-abc")
        assert resp.status_code == 200
        data = resp.json()
        assert data["run_id"] == "run-abc"
        assert data["passed"] == 2

    def test_includes_run_meta(self, registry_with_run: ProjectRegistry) -> None:
        client = TestClient(create_app(registry_with_run))
        resp = client.get("/api/projects/mysite/runs/run-abc")
        assert "run_meta" in resp.json()
        assert resp.json()["run_meta"]["ai_model"] == "claude-opus-4-6"

    def test_project_not_found(self, tmp_path: Path) -> None:
        reg = ProjectRegistry(base_dir=tmp_path / ".qa-framework")
        client = TestClient(create_app(reg))
        resp = client.get("/api/projects/unknown/runs/run-abc")
        assert resp.status_code == 404

    def test_run_not_found(self, registry_with_run: ProjectRegistry) -> None:
        client = TestClient(create_app(registry_with_run))
        resp = client.get("/api/projects/mysite/runs/nonexistent")
        assert resp.status_code == 404


class TestEvidenceEndpoint:
    def test_serves_screenshot(self, registry_with_run: ProjectRegistry) -> None:
        client = TestClient(create_app(registry_with_run))
        resp = client.get("/api/projects/mysite/runs/run-abc/evidence/step_1.png")
        assert resp.status_code == 200
        assert resp.content[:4] == b"\x89PNG"

    def test_rejects_path_traversal(self, registry_with_run: ProjectRegistry) -> None:
        client = TestClient(create_app(registry_with_run))
        resp = client.get("/api/projects/mysite/runs/run-abc/evidence/../../config.json")
        assert resp.status_code in (400, 404, 422)

    def test_rejects_disallowed_extension(self, registry_with_run: ProjectRegistry) -> None:
        client = TestClient(create_app(registry_with_run))
        resp = client.get("/api/projects/mysite/runs/run-abc/evidence/exploit.sh")
        assert resp.status_code == 400

    def test_missing_evidence_returns_404(self, registry_with_run: ProjectRegistry) -> None:
        client = TestClient(create_app(registry_with_run))
        resp = client.get("/api/projects/mysite/runs/run-abc/evidence/missing.png")
        assert resp.status_code == 404
