"""Tests for Excel export (RUN-3)."""

from __future__ import annotations

import json
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from openpyxl import load_workbook

from src.models.test_result import RunResult, TestResult, Evidence
from src.projects.registry import ProjectRegistry
from src.web.app import create_app
from src.web.excel_export import generate_xlsx


def _make_run_result(**kwargs) -> RunResult:
    defaults = dict(
        run_id="run-001",
        plan_id="plan-1",
        started_at="2026-05-01T10:00:00",
        completed_at="2026-05-01T10:20:00",
        target_url="https://example.com",
        total_tests=2,
        passed=1,
        failed=1,
        skipped=0,
        errors=0,
        duration_seconds=60.0,
        ai_summary="One failure detected.",
        test_results=[
            TestResult(
                test_id="t1", test_name="Login flow", description="", category="functional",
                result="pass", duration_seconds=5.0,
            ),
            TestResult(
                test_id="t2", test_name="Checkout fail", description="", category="functional",
                result="fail", duration_seconds=3.0,
                failure_reason="Button not found",
            ),
        ],
    )
    defaults.update(kwargs)
    return RunResult(**defaults)


class TestGenerateXlsx:
    def test_returns_bytes(self) -> None:
        result = _make_run_result()
        output = generate_xlsx(result)
        assert isinstance(output, bytes)
        assert len(output) > 0

    def test_three_sheets(self) -> None:
        from io import BytesIO
        wb = load_workbook(BytesIO(generate_xlsx(_make_run_result())))
        assert set(wb.sheetnames) == {"Summary", "Test Cases", "Errors"}

    def test_summary_contains_run_id(self) -> None:
        from io import BytesIO
        wb = load_workbook(BytesIO(generate_xlsx(_make_run_result())))
        ws = wb["Summary"]
        values = [str(row[1].value or "") for row in ws.iter_rows(min_row=2)]
        assert "run-001" in values

    def test_test_cases_has_all_tests(self) -> None:
        from io import BytesIO
        wb = load_workbook(BytesIO(generate_xlsx(_make_run_result())))
        ws = wb["Test Cases"]
        # header + 2 data rows
        assert ws.max_row == 3

    def test_errors_sheet_has_only_failed(self) -> None:
        from io import BytesIO
        wb = load_workbook(BytesIO(generate_xlsx(_make_run_result())))
        ws = wb["Errors"]
        # header + 1 failed row
        assert ws.max_row == 2
        assert ws.cell(2, 2).value == "Checkout fail"


class TestExcelExportEndpoint:
    def test_returns_xlsx(self, tmp_path: Path) -> None:
        reg = ProjectRegistry(base_dir=tmp_path / ".qa-framework")
        reg.create("mysite", "https://mysite.com")
        run_dir = reg.runs_dir("mysite") / "run-001"
        run_dir.mkdir(parents=True)
        run_result = _make_run_result()
        (run_dir / "run_result.json").write_text(run_result.model_dump_json())

        client = TestClient(create_app(reg))
        resp = client.get("/api/projects/mysite/runs/run-001/export.xlsx")
        assert resp.status_code == 200
        assert "spreadsheetml" in resp.headers["content-type"]
        assert "report_run-001.xlsx" in resp.headers["content-disposition"]

    def test_run_not_found_returns_404(self, tmp_path: Path) -> None:
        reg = ProjectRegistry(base_dir=tmp_path / ".qa-framework")
        reg.create("mysite", "https://mysite.com")
        client = TestClient(create_app(reg))
        resp = client.get("/api/projects/mysite/runs/missing/export.xlsx")
        assert resp.status_code == 404
