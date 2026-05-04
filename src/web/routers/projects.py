from __future__ import annotations

from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel

from src.projects.exceptions import ProjectAlreadyExistsError, ProjectNotFoundError
from src.projects.registry import ProjectRegistry
from src.web.validation import validate_project_name

router = APIRouter()


class ProjectSummary(BaseModel):
    name: str
    target_url: str
    active: bool
    last_run_date: Optional[str] = None
    last_run_stats: Optional[dict] = None


class CreateProjectRequest(BaseModel):
    name: str
    target_url: str


def _registry(request: Request) -> ProjectRegistry:
    return request.app.state.registry


@router.get("/projects", response_model=list[ProjectSummary])
def list_projects(registry: ProjectRegistry = Depends(_registry)) -> list[ProjectSummary]:
    return [
        ProjectSummary(
            name=p.name,
            target_url=p.target_url,
            active=p.active,
            last_run_date=p.last_run_date,
            last_run_stats=p.last_run_stats,
        )
        for p in registry.list()
    ]


@router.post("/projects", response_model=ProjectSummary, status_code=201)
def create_project(
    body: CreateProjectRequest,
    registry: ProjectRegistry = Depends(_registry),
) -> ProjectSummary:
    validate_project_name(body.name)
    try:
        registry.create(body.name, body.target_url)
    except (ProjectAlreadyExistsError, ValueError) as e:
        status = 409 if isinstance(e, ProjectAlreadyExistsError) else 422
        raise HTTPException(status_code=status, detail=str(e))
    return ProjectSummary(
        name=body.name,
        target_url=body.target_url,
        active=False,
    )


@router.delete("/projects/{name}", status_code=204)
def delete_project(name: str, registry: ProjectRegistry = Depends(_registry)) -> None:
    try:
        registry.delete(name)
    except ProjectNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))


@router.post("/projects/{name}/use")
def use_project(name: str, registry: ProjectRegistry = Depends(_registry)) -> dict:
    try:
        registry.set_active(name)
    except ProjectNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
    return {"active": name}


@router.get("/projects/{name}/runs")
def list_runs(name: str, registry: ProjectRegistry = Depends(_registry)) -> list[dict]:
    try:
        return registry.list_runs(name, limit=20)
    except ProjectNotFoundError as e:
        raise HTTPException(status_code=404, detail=str(e))
