from __future__ import annotations

import json
from pathlib import Path
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from fastapi.responses import FileResponse, Response, StreamingResponse
from pydantic import BaseModel, Field

from src.projects.registry import ProjectRegistry
from src.web.run_manager import RunManager
from src.web.validation import validate_safe_filename

router = APIRouter()

_EVIDENCE_EXTENSIONS = frozenset({".png", ".jpg", ".jpeg", ".webm", ".mp4", ".json"})


def _registry(request: Request) -> ProjectRegistry:
    return request.app.state.registry


def _run_manager(request: Request) -> RunManager:
    return request.app.state.run_manager


class RunOverrides(BaseModel):
    username: Optional[str] = Field(default=None, max_length=512)
    password: Optional[str] = Field(default=None, max_length=512)
    hints: list[str] = Field(default_factory=list, max_length=20)
    categories: Optional[list[str]] = None


# ── Trigger + stream ──────────────────────────────────────────────────────────

@router.post("/projects/{name}/run", status_code=202)
def trigger_run(
    name: str,
    body: RunOverrides = RunOverrides(),
    registry: ProjectRegistry = Depends(_registry),
    run_manager: RunManager = Depends(_run_manager),
) -> dict:
    if not registry.exists(name):
        raise HTTPException(status_code=404, detail=f"Project '{name}' not found.")
    active = run_manager.active_run_for(name)
    if active:
        raise HTTPException(
            status_code=409,
            detail=f"A run ({active}) is already in progress for '{name}'.",
        )
    run_id = run_manager.start(name, registry, overrides=body)
    return {"run_id": run_id}


@router.get("/projects/{name}/run/{run_id}/status")
def run_status(
    name: str,
    run_id: str,
    run_manager: RunManager = Depends(_run_manager),
) -> dict:
    status = run_manager.get_status(run_id)
    if status is None:
        raise HTTPException(status_code=404, detail=f"Run '{run_id}' not found.")
    return status


@router.get("/projects/{name}/run/{run_id}/stream")
async def stream_run(
    name: str,
    run_id: str,
    run_manager: RunManager = Depends(_run_manager),
) -> StreamingResponse:
    if run_manager.get_status(run_id) is None:
        raise HTTPException(status_code=404, detail=f"Run '{run_id}' not found.")
    return StreamingResponse(
        run_manager.stream(run_id),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )


# ── Run detail ────────────────────────────────────────────────────────────────

@router.get("/projects/{name}/runs/{run_id}")
def get_run_detail(name: str, run_id: str, registry: ProjectRegistry = Depends(_registry)) -> dict:
    if not registry.exists(name):
        raise HTTPException(status_code=404, detail=f"Project '{name}' not found.")
    result_path = registry.runs_dir(name) / run_id / "run_result.json"
    if not result_path.exists():
        raise HTTPException(status_code=404, detail=f"Run '{run_id}' not found.")
    data = json.loads(result_path.read_text())
    # Attach run metadata if present (saved by run_manager)
    meta_path = registry.runs_dir(name) / run_id / "run_meta.json"
    if meta_path.exists():
        try:
            data["run_meta"] = json.loads(meta_path.read_text())
        except Exception:
            pass
    return data


# ── Evidence files ────────────────────────────────────────────────────────────

@router.get("/projects/{name}/runs/{run_id}/evidence/{filename}")
def get_evidence_file(
    name: str,
    run_id: str,
    filename: str,
    registry: ProjectRegistry = Depends(_registry),
) -> FileResponse:
    if not registry.exists(name):
        raise HTTPException(status_code=404, detail=f"Project '{name}' not found.")
    validate_safe_filename(filename, allowed_extensions=_EVIDENCE_EXTENSIONS)
    evidence_dir = (registry.runs_dir(name) / run_id / "evidence").resolve()
    file_path = (evidence_dir / filename).resolve()
    try:
        file_path.relative_to(evidence_dir)
    except ValueError:
        raise HTTPException(status_code=400, detail="Invalid filename.")
    if not file_path.exists():
        raise HTTPException(status_code=404, detail=f"Evidence file '{filename}' not found.")
    return FileResponse(str(file_path))


# ── Excel export ──────────────────────────────────────────────────────────────

@router.get("/projects/{name}/runs/{run_id}/export.xlsx")
def export_run_xlsx(
    name: str,
    run_id: str,
    registry: ProjectRegistry = Depends(_registry),
) -> Response:
    if not registry.exists(name):
        raise HTTPException(status_code=404, detail=f"Project '{name}' not found.")
    result_path = registry.runs_dir(name) / run_id / "run_result.json"
    if not result_path.exists():
        raise HTTPException(status_code=404, detail=f"Run '{run_id}' not found.")

    from src.models.test_result import RunResult
    from src.web.excel_export import generate_xlsx

    run_result = RunResult.model_validate_json(result_path.read_text())
    xlsx_bytes = generate_xlsx(run_result)

    return Response(
        content=xlsx_bytes,
        media_type="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
        headers={"Content-Disposition": f'attachment; filename="report_{run_id}.xlsx"'},
    )
