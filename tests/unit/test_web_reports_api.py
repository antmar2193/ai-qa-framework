"""Tests for FastAPI report serving endpoints (/api/projects/{name}/reports)."""

from __future__ import annotations

from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from src.projects.registry import ProjectRegistry
from src.web.app import create_app


@pytest.fixture
def registry(tmp_path: Path) -> ProjectRegistry:
    return ProjectRegistry(base_dir=tmp_path / ".qa-framework")


@pytest.fixture
def registry_with_reports(tmp_path: Path) -> ProjectRegistry:
    reg = ProjectRegistry(base_dir=tmp_path / ".qa-framework")
    reg.create("mysite", "https://mysite.com")
    reports_dir = reg.reports_dir("mysite")
    (reports_dir / "report_abc123.html").write_text("<html>report</html>")
    (reports_dir / "report_abc123.json").write_text('{"run_id": "abc123"}')
    return reg


class TestListReports:
    def test_empty_when_no_reports(self, registry: ProjectRegistry) -> None:
        registry.create("empty", "https://empty.com")
        client = TestClient(create_app(registry))
        resp = client.get("/api/projects/empty/reports")
        assert resp.status_code == 200
        assert resp.json() == []

    def test_lists_html_reports(self, registry_with_reports: ProjectRegistry) -> None:
        client = TestClient(create_app(registry_with_reports))
        resp = client.get("/api/projects/mysite/reports")
        assert resp.status_code == 200
        data = resp.json()
        assert len(data) == 1
        assert data[0]["filename"] == "report_abc123.html"
        assert data[0]["run_id"] == "abc123"
        assert "modified_at" in data[0]

    def test_project_not_found(self, registry: ProjectRegistry) -> None:
        client = TestClient(create_app(registry))
        resp = client.get("/api/projects/unknown/reports")
        assert resp.status_code == 404


class TestGetReport:
    def test_serves_html_report(self, registry_with_reports: ProjectRegistry) -> None:
        client = TestClient(create_app(registry_with_reports))
        resp = client.get("/api/projects/mysite/reports/report_abc123.html")
        assert resp.status_code == 200
        assert b"<html>report</html>" in resp.content

    def test_serves_json_report(self, registry_with_reports: ProjectRegistry) -> None:
        client = TestClient(create_app(registry_with_reports))
        resp = client.get("/api/projects/mysite/reports/report_abc123.json")
        assert resp.status_code == 200

    def test_report_not_found(self, registry_with_reports: ProjectRegistry) -> None:
        client = TestClient(create_app(registry_with_reports))
        resp = client.get("/api/projects/mysite/reports/report_missing.html")
        assert resp.status_code == 404

    def test_project_not_found(self, registry: ProjectRegistry) -> None:
        client = TestClient(create_app(registry))
        resp = client.get("/api/projects/unknown/reports/report_abc123.html")
        assert resp.status_code == 404

    def test_path_traversal_rejected(self, registry_with_reports: ProjectRegistry) -> None:
        client = TestClient(create_app(registry_with_reports))
        resp = client.get("/api/projects/mysite/reports/..%2F..%2Fetc%2Fpasswd")
        assert resp.status_code in (400, 404)
