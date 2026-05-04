from __future__ import annotations

from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import HTMLResponse
from fastapi.staticfiles import StaticFiles

from src.projects.registry import ProjectRegistry
from src.web.run_manager import RunManager
from src.web.routers import projects, reports, runs

_DIST = Path(__file__).parent.parent.parent / "web" / "dist"


def create_app(registry: ProjectRegistry) -> FastAPI:
    app = FastAPI(title="QA Framework Web UI", version="1.0.0")

    # Allow Vite dev server to call the API during development.
    # This tool is local-only; CORS is intentionally restricted to dev origin.
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["http://localhost:5173"],
        allow_methods=["GET", "POST", "DELETE"],
        allow_headers=["Content-Type"],
    )

    app.state.registry = registry
    app.state.run_manager = RunManager()

    app.include_router(projects.router, prefix="/api")
    app.include_router(runs.router, prefix="/api")
    app.include_router(reports.router, prefix="/api")

    if _DIST.is_dir():
        # Serve the built React SPA; html=True makes it serve index.html for unknown routes
        app.mount("/", StaticFiles(directory=_DIST, html=True), name="spa")
    else:
        @app.get("/")
        async def no_frontend() -> HTMLResponse:
            return HTMLResponse(
                "<pre>Frontend not built.\nRun: npm run build in web/</pre>"
            )

    return app
