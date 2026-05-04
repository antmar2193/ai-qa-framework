"""Shared input validation helpers for the web layer."""

from __future__ import annotations

from pathlib import Path

from fastapi import HTTPException

_EVIDENCE_EXTENSIONS = frozenset({".png", ".jpg", ".jpeg", ".webm", ".mp4", ".json"})


def validate_safe_filename(
    filename: str,
    allowed_extensions: frozenset[str] | None = None,
) -> None:
    """Raise HTTP 400 if filename is unsafe (path traversal, null bytes, bad extension).

    This is a second layer of defence; the primary guard is resolve().relative_to().
    """
    if "\x00" in filename:
        raise HTTPException(status_code=400, detail="Invalid filename: null byte.")
    if ".." in filename or filename.startswith(("/", "\\")):
        raise HTTPException(status_code=400, detail="Invalid filename: path traversal.")
    if allowed_extensions is not None:
        ext = Path(filename).suffix.lower()
        if ext not in allowed_extensions:
            raise HTTPException(
                status_code=400,
                detail=f"File type not allowed. Permitted: {sorted(allowed_extensions)}",
            )


def validate_project_name(name: str) -> None:
    """Raise HTTP 422 if project name contains unsafe characters."""
    import re
    if not re.match(r"^[a-zA-Z0-9_-]{1,64}$", name):
        raise HTTPException(
            status_code=422,
            detail=(
                "Invalid project name. "
                "Use only letters, numbers, hyphens, and underscores (1-64 chars)."
            ),
        )
