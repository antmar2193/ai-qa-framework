# Stack: python-fastapi

> **Technology choices for this stack.**
> Extends `core/` — all core rules apply. This file only adds stack-specific rules.
> Full-stack backend: Python · FastAPI · SQLAlchemy 2 async · PostgreSQL

<!-- sync-standards: stacks/python-fastapi -->

---

## Stack Identity

| Layer | Technology | Version |
|---|---|---|
| Runtime | Python | 3.12+ |
| Backend framework | FastAPI | 0.115+ |
| Validation | Pydantic | v2 |
| ORM | SQLAlchemy | 2.x (async) |
| Migrations | Alembic | 1.x |
| Database | PostgreSQL (primary) | 16.x |
| ASGI server | uvicorn | latest |
| Testing | pytest | 8.x |
| Async testing | pytest-asyncio | latest |
| HTTP test client | httpx (AsyncClient) | latest |
| Test factories | factory-boy | 3.x |
| Linting + formatting | Ruff | latest |
| Type checking | mypy (strict) | latest |
| Structured logging | structlog | latest |
| Settings | pydantic-settings | 2.x |

## Architecture Pattern

Backend: Domain-Driven Design (DDD) with 4 layers
- Domain → Entities (Pydantic models), Value Objects, Domain Services
- Application → Use Cases, DTOs (schemas), Interfaces (Protocols)
- Infrastructure → SQLAlchemy models + repositories, External API clients, Config
- Presentation → FastAPI routers, Middleware, Depends() wiring

## Key Standards Files
- `.hive/standards/backend.mdc` — DDD layers, FastAPI patterns, SQLAlchemy async, testing rules

## Verify Commands

| Command | Purpose |
|---|---|
| `pytest` | Run all tests |
| `mypy src/` | Type check (strict) |
| `ruff check . && ruff format --check .` | Lint + format check |
| `pytest --cov=src --cov-fail-under=80` | Tests with coverage |
| *(no build step)* | Python is interpreted |

## Project Structure

```
{project-slug}/
├── src/
│   ├── domain/                    # Business entities and domain logic
│   │   ├── entities/              # Pydantic domain models (no DB coupling)
│   │   ├── value_objects/         # Immutable value types
│   │   ├── services/              # Pure domain services
│   │   ├── repositories/          # Repository interfaces (Protocol-based)
│   │   └── exceptions.py          # Domain-specific exceptions
│   ├── application/               # Use cases and orchestration
│   │   ├── use_cases/             # One file per use case
│   │   ├── schemas/               # Pydantic DTOs (request/response)
│   │   └── interfaces.py          # Application-level Protocols
│   ├── infrastructure/            # Technical implementations
│   │   ├── database/
│   │   │   ├── models.py          # SQLAlchemy ORM models
│   │   │   ├── session.py         # Async engine + sessionmaker
│   │   │   └── repositories/      # SQLAlchemy repository implementations
│   │   ├── clients/               # External API clients
│   │   └── config.py              # pydantic-settings Settings class
│   ├── presentation/              # HTTP layer
│   │   ├── routers/               # FastAPI APIRouter per resource
│   │   ├── deps.py                # Shared Depends() functions
│   │   ├── middleware.py          # Custom ASGI middleware
│   │   └── exception_handlers.py  # HTTPException and custom handlers
│   └── main.py                    # FastAPI app creation + router registration
├── migrations/                    # Alembic migration scripts
│   ├── env.py
│   └── versions/
├── tests/
│   ├── conftest.py                # Fixtures: async client, test DB, factories
│   ├── unit/                      # pytest unit tests (no DB)
│   └── integration/               # Tests with real DB (pytest-asyncio)
├── pyproject.toml                 # Project metadata + tool configs
├── .env.example                   # All env vars with placeholder values
└── .hive/                         # HIVE framework layer
```

## Cursor / IDE — globs for this stack

| File | Globs | When it activates |
|---|---|---|
| `backend-area.mdc` | `src/**/*.py` | Editing any Python source file |
| `tests-area.mdc` | `tests/**/*.py`, `**/test_*.py` | Editing any test file |

## Context Loading for This Stack

| Task | Files to load |
|---|---|
| Planning backend | `.hive/.agents/architect.md` + `.hive/standards/core.mdc` + `.hive/standards/backend.mdc` |
| Implementing backend | `.hive/.agents/coder.md` + failing tests + `.hive/standards/backend.mdc` |
| Reviewing PR | `.hive/.agents/reviewer.md` + `.hive/standards/backend.mdc` |

## Database Migrations (Alembic)

```bash
alembic revision --autogenerate -m "descriptive_name"   # create migration
alembic upgrade head                                     # apply all pending
alembic downgrade -1                                     # rollback one step
alembic current                                          # show current revision
alembic history                                          # show migration history
```

## Development Scripts

```bash
uvicorn src.main:app --reload          # Dev server with hot reload
pytest                                 # All tests
pytest --cov=src --cov-fail-under=80  # Tests + coverage
mypy src/                              # Type check
ruff check .                           # Lint
ruff format .                          # Format code
ruff check . --fix                     # Auto-fix lint issues
```

## Design Integration

This stack supports:
- **FastAPI built-in OpenAPI** — Swagger UI at `/docs`, ReDoc at `/redoc`
- **Orval** — if paired with a Next.js/React frontend, generate typed API client from OpenAPI spec
See `.hive/AGENTS.local.md` → `design_tool` section to configure.
