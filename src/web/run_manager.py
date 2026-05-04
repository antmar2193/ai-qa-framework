from __future__ import annotations

import copy
import json
import logging
import queue
import threading
import uuid
from asyncio import sleep as async_sleep
from datetime import datetime, timezone
from typing import TYPE_CHECKING, AsyncGenerator, Optional

from src.projects.registry import ProjectRegistry

if TYPE_CHECKING:
    from src.web.routers.runs import RunOverrides

_SENTINEL = object()


class RunState:
    def __init__(self, run_id: str, project: str) -> None:
        self.run_id = run_id
        self.project = project
        self.status = "running"
        self.started_at = datetime.now(tz=timezone.utc).isoformat()
        self.completed_at: Optional[str] = None
        self._log_queue: queue.Queue = queue.Queue()

    def put_line(self, line: str) -> None:
        self._log_queue.put(line)

    def finish(self, status: str) -> None:
        self.status = status
        self.completed_at = datetime.now(tz=timezone.utc).isoformat()
        self._log_queue.put(_SENTINEL)

    def to_dict(self) -> dict:
        return {
            "run_id": self.run_id,
            "project": self.project,
            "status": self.status,
            "started_at": self.started_at,
            "completed_at": self.completed_at,
        }


class _QueueLogHandler(logging.Handler):
    def __init__(self, state: RunState) -> None:
        super().__init__()
        self._state = state

    def emit(self, record: logging.LogRecord) -> None:
        self._state.put_line(self.format(record))


class RunManager:
    def __init__(self) -> None:
        self._runs: dict[str, RunState] = {}
        self._lock = threading.Lock()

    def active_run_for(self, project: str) -> Optional[str]:
        with self._lock:
            for run_id, state in self._runs.items():
                if state.project == project and state.status == "running":
                    return run_id
        return None

    def start(
        self,
        project: str,
        registry: ProjectRegistry,
        overrides: Optional[RunOverrides] = None,
    ) -> str:
        run_id = str(uuid.uuid4())[:8]
        state = RunState(run_id, project)
        with self._lock:
            self._runs[run_id] = state
        thread = threading.Thread(
            target=self._run_pipeline,
            args=(run_id, project, registry, state, overrides),
            daemon=True,
        )
        thread.start()
        return run_id

    def get_status(self, run_id: str) -> Optional[dict]:
        with self._lock:
            state = self._runs.get(run_id)
        return state.to_dict() if state else None

    async def stream(self, run_id: str) -> AsyncGenerator[str, None]:
        with self._lock:
            state = self._runs.get(run_id)
        if state is None:
            return
        while True:
            try:
                item = state._log_queue.get(timeout=0.1)
                if item is _SENTINEL:
                    yield f"data: {{\"event\": \"done\", \"status\": \"{state.status}\"}}\n\n"
                    break
                yield f"data: {item}\n\n"
            except queue.Empty:
                await async_sleep(0.05)

    def _run_pipeline(
        self,
        run_id: str,
        project: str,
        registry: ProjectRegistry,
        state: RunState,
        overrides: Optional[RunOverrides],
    ) -> None:
        handler = _QueueLogHandler(state)
        handler.setFormatter(logging.Formatter("%(levelname)s %(name)s: %(message)s"))
        root_logger = logging.getLogger()
        root_logger.addHandler(handler)

        try:
            from src.orchestrator import Orchestrator
            from src.projects.resolver import resolve_config

            cfg, runs_dir = resolve_config(project, "qa-config.json", registry)

            # Apply overrides (credentials and hints) to a copy — never mutate the original config
            if overrides is not None:
                cfg = copy.deepcopy(cfg)
                if overrides.categories:
                    cfg.categories = overrides.categories
                if overrides.hints:
                    cfg.hints = cfg.hints + overrides.hints
                if overrides.username or overrides.password:
                    from src.models.config import AuthConfig
                    if cfg.auth is not None:
                        # Update credentials without modifying stored config
                        auth_data = cfg.auth.model_dump()
                        if overrides.username:
                            auth_data["username"] = overrides.username
                        if overrides.password:
                            auth_data["password"] = overrides.password
                            auth_data["password_env_ref"] = None
                        cfg.auth = AuthConfig(**auth_data)
                    else:
                        if overrides.username and overrides.password:
                            cfg.auth = AuthConfig(
                                login_url=cfg.target_url + "/login",
                                username=overrides.username,
                                password=overrides.password,
                            )

            # Save run metadata (no password) for the detail page
            self._save_run_meta(run_id, project, registry, cfg, overrides)

            orchestrator = Orchestrator(cfg, runs_dir=runs_dir)
            orchestrator.run_full_pipeline()
            state.finish("passed")
        except Exception as exc:
            state.put_line(f"ERROR: {exc}")
            state.finish("failed")
        finally:
            root_logger.removeHandler(handler)

    def _save_run_meta(
        self,
        run_id: str,
        project: str,
        registry: ProjectRegistry,
        cfg: object,
        overrides: Optional[RunOverrides],
    ) -> None:
        try:
            meta: dict = {
                "run_id": run_id,
                "project": project,
                "triggered_at": datetime.now(tz=timezone.utc).isoformat(),
                "target_url": getattr(cfg, "target_url", ""),
                "categories": getattr(cfg, "categories", []),
                "hints_count": len(getattr(cfg, "hints", [])),
                "ai_model": getattr(cfg, "ai_model", ""),
            }
            if overrides and overrides.username:
                meta["auth_username"] = overrides.username
            # Never include password in metadata
            run_dir = registry.runs_dir(project) / run_id
            run_dir.mkdir(parents=True, exist_ok=True)
            (run_dir / "run_meta.json").write_text(json.dumps(meta, indent=2))
        except Exception:
            pass  # metadata saving failure must never abort the run
