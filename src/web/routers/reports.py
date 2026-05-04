from __future__ import annotations

import datetime
from pathlib import Path

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse

from src.projects.registry import ProjectRegistry
from src.web.validation import validate_safe_filename

router = APIRouter()

_REPORT_EXTENSIONS = frozenset({".html", ".json"})


def _registry(request: Request) -> ProjectRegistry:
    return request.app.state.registry


@router.get("/projects/{name}/reports")
def list_reports(name: str, registry: ProjectRegistry = Depends(_registry)) -> list[dict]:
    if not registry.exists(name):
        raise HTTPException(status_code=404, detail=f"Project '{name}' not found.")
    reports_dir = registry.reports_dir(name)
    if not reports_dir.exists():
        return []
    files = sorted(
        reports_dir.glob("report_*.html"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    return [
        {
            "filename": f.name,
            "run_id": f.stem.replace("report_", ""),
            "modified_at": datetime.datetime.fromtimestamp(
                f.stat().st_mtime, tz=datetime.timezone.utc
            ).isoformat(),
        }
        for f in files
    ]


@router.get("/projects/{name}/reports/{filename}")
def get_report(
    name: str,
    filename: str,
    registry: ProjectRegistry = Depends(_registry),
) -> FileResponse:
    if not registry.exists(name):
        raise HTTPException(status_code=404, detail=f"Project '{name}' not found.")
    validate_safe_filename(filename, allowed_extensions=_REPORT_EXTENSIONS)
    reports_dir = registry.reports_dir(name).resolve()
    report_path = (reports_dir / filename).resolve()
    try:
        report_path.relative_to(reports_dir)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid filename.")
    if not report_path.exists():
        raise HTTPException(status_code=404, detail=f"Report '{filename}' not found.")
    return FileResponse(str(report_path))
