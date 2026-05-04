"""Config resolution for pipeline commands.

Priority order:
  1. --config path  (legacy, always wins)
  2. --project name
  3. active project  (~/.qa-framework/active-project)
  4. qa-config.json  in current working directory
  5. error
"""

from __future__ import annotations

import logging
import sys
from pathlib import Path
from typing import Optional

from src.models.config import FrameworkConfig
from src.projects.exceptions import ProjectNotFoundError
from src.projects.registry import ProjectRegistry

logger = logging.getLogger(__name__)


def resolve_config(
    project: Optional[str],
    config_path: str,
    registry: ProjectRegistry,
) -> tuple[FrameworkConfig, Optional[Path]]:
    """Return (FrameworkConfig, runs_dir).

    runs_dir is None in legacy --config mode; the Orchestrator then
    defaults to ./runs (unchanged behaviour).
    """
    # 1. Explicit --config always wins
    if config_path != "qa-config.json" or (project is None and Path(config_path).exists() and _no_active(registry)):
        if project is not None:
            logger.warning("--project ignored because --config was also provided.")
        try:
            return FrameworkConfig.load(config_path), None
        except FileNotFoundError:
            pass  # fall through to project resolution if default was not found

    # 2. --project flag
    if project is not None:
        try:
            cfg = registry.get(project)
            cfg.report_output_dir = str(registry.reports_dir(project))
            return cfg, registry.runs_dir(project)
        except ProjectNotFoundError as e:
            print(str(e))
            sys.exit(1)

    # 3. Active project
    active = registry.get_active()
    if active:
        try:
            cfg = registry.get(active)
            cfg.report_output_dir = str(registry.reports_dir(active))
            return cfg, registry.runs_dir(active)
        except ProjectNotFoundError:
            logger.warning("Active project '%s' not found — falling back to qa-config.json.", active)

    # 4. qa-config.json in cwd
    default = Path(config_path)
    if default.exists():
        return FrameworkConfig.load(config_path), None

    # 5. Nothing found
    print(
        "No project configured. "
        "Run: qa-framework project create --name <n> --target <url>"
    )
    sys.exit(1)


def _no_active(registry: ProjectRegistry) -> bool:
    return registry.get_active() is None
