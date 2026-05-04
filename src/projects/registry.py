from __future__ import annotations

import json
import re
import shutil
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

from src.models.config import FrameworkConfig
from src.projects.exceptions import ProjectAlreadyExistsError, ProjectNotFoundError

_NAME_RE = re.compile(r"^[a-zA-Z0-9_-]{1,64}$")


def _validate_name(name: str) -> None:
    """Raise ValueError if name is not a safe project identifier."""
    if not _NAME_RE.match(name):
        raise ValueError(
            f"Invalid project name '{name}'. "
            "Use only letters, numbers, hyphens, and underscores (1-64 chars)."
        )


@dataclass
class ProjectInfo:
    name: str
    target_url: str
    path: Path
    last_run_date: Optional[str] = None
    last_run_stats: Optional[dict] = field(default=None)
    active: bool = False


class ProjectRegistry:
    def __init__(self, base_dir: Optional[Path] = None) -> None:
        self._base = base_dir or (Path.home() / ".qa-framework")
        self._projects_dir = self._base / "projects"
        self._active_file = self._base / "active-project"
        self._base.mkdir(parents=True, exist_ok=True)
        self._projects_dir.mkdir(parents=True, exist_ok=True)

    # ------------------------------------------------------------------
    # Project CRUD
    # ------------------------------------------------------------------

    def create(self, name: str, target_url: str) -> FrameworkConfig:
        _validate_name(name)
        project_dir = self._projects_dir / name
        if project_dir.exists():
            raise ProjectAlreadyExistsError(name)

        (project_dir / "runs").mkdir(parents=True)
        (project_dir / "qa-reports").mkdir(parents=True)

        config = FrameworkConfig(
            target_url=target_url,
            report_output_dir=str(project_dir / "qa-reports"),
        )
        config.save(project_dir / "config.json")
        return config

    def get(self, name: str) -> FrameworkConfig:
        config_path = self._projects_dir / name / "config.json"
        if not config_path.exists():
            raise ProjectNotFoundError(name)
        return FrameworkConfig.load(config_path)

    def delete(self, name: str) -> None:
        project_dir = self._projects_dir / name
        if not project_dir.exists():
            raise ProjectNotFoundError(name)
        shutil.rmtree(project_dir)
        if self.get_active() == name:
            self._active_file.unlink(missing_ok=True)

    def list(self) -> list[ProjectInfo]:
        active = self.get_active()
        projects = []
        for project_dir in sorted(self._projects_dir.iterdir()):
            if not project_dir.is_dir():
                continue
            config_path = project_dir / "config.json"
            if not config_path.exists():
                continue
            try:
                config = FrameworkConfig.load(config_path)
            except Exception:
                continue
            last_run_date, last_run_stats = self._latest_run_info(project_dir / "runs")
            projects.append(ProjectInfo(
                name=project_dir.name,
                target_url=config.target_url,
                path=project_dir,
                last_run_date=last_run_date,
                last_run_stats=last_run_stats,
                active=(project_dir.name == active),
            ))
        return projects

    def exists(self, name: str) -> bool:
        return (self._projects_dir / name / "config.json").exists()

    # ------------------------------------------------------------------
    # Active project
    # ------------------------------------------------------------------

    def set_active(self, name: str) -> None:
        if not self.exists(name):
            raise ProjectNotFoundError(name)
        self._active_file.write_text(name.strip())

    def get_active(self) -> Optional[str]:
        if not self._active_file.exists():
            return None
        name = self._active_file.read_text().strip()
        return name if name else None

    def clear_active(self) -> None:
        self._active_file.unlink(missing_ok=True)

    # ------------------------------------------------------------------
    # Paths
    # ------------------------------------------------------------------

    def project_dir(self, name: str) -> Path:
        return self._projects_dir / name

    def runs_dir(self, name: str) -> Path:
        return self._projects_dir / name / "runs"

    def reports_dir(self, name: str) -> Path:
        return self._projects_dir / name / "qa-reports"

    # ------------------------------------------------------------------
    # Internals
    # ------------------------------------------------------------------

    def list_runs(self, name: str, limit: int = 10) -> list[dict]:
        """Return the most recent run results for a project, newest first."""
        if not self.exists(name):
            raise ProjectNotFoundError(name)
        result_files = sorted(
            self.runs_dir(name).glob("*/run_result.json"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        runs = []
        for f in result_files[:limit]:
            try:
                runs.append(json.loads(f.read_text()))
            except Exception:
                continue
        return runs

    def _latest_run_info(self, runs_dir: Path) -> tuple[Optional[str], Optional[dict]]:
        if not runs_dir.exists():
            return None, None
        result_files = sorted(
            runs_dir.glob("*/run_result.json"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
        if not result_files:
            return None, None
        try:
            data = json.loads(result_files[0].read_text())
            return data.get("completed_at"), {
                "total": data.get("total_tests", 0),
                "passed": data.get("passed", 0),
                "failed": data.get("failed", 0),
            }
        except Exception:
            return None, None
