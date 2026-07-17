"""
Athar-Fintech API — application entrypoint.

Instantiates the FastAPI application and mounts routers. Business and
Persistence-layer wiring is deliberately kept out of this module — routers
imported here should depend only on Facade classes from `app.business`.

On Replit the Flutter web build (athar_frontend/build/web) is served by this
same FastAPI process on port 5000, so there is no cross-origin concern.
A catch-all route at the bottom of the file serves index.html for all unknown
paths, enabling Flutter's client-side router to work correctly.
"""

import logging
import os
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from app.core.config import settings
from app.presentation.routers import analytics, goals, oasis, transactions
from fastapi.middleware.cors import CORSMiddleware

# Ensures the `logger.exception(...)` calls added to the routers (which log
# the real, detailed error server-side while the client only ever sees a
# generic, safe message) actually produce readable, timestamped output in
# Render's log viewer instead of relying on Python's bare default handler.
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)

app = FastAPI(
    title=settings.APP_NAME,
    description=(
        "Backend API for Athar (أَثَر) — a FinTech application blending "
        "offline transaction categorization with 3D gamified financial goals."
    ),
    version=settings.APP_VERSION,
    contact={
        "name": "Athar-Fintech Engineering Team",
    },
)

# FastAPI will raise a ValueError at startup if allow_credentials=True is
# combined with the wildcard origin ["*"] — the browser rejects such responses.
# We guard against accidental wildcard usage here: if someone sets CORS_ORIGINS
# to ["*"] we drop credentials mode to avoid a server crash, and log a warning.
_origins = settings.CORS_ORIGINS
_allow_credentials = True
if "*" in _origins:
    import warnings
    warnings.warn(
        "CORS_ORIGINS contains '*' — allow_credentials has been forced to False "
        "to prevent a FastAPI startup crash. Set explicit origins instead.",
        stacklevel=1,
    )
    _allow_credentials = False

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=_allow_credentials,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(transactions.router, prefix="/transactions", tags=["Transactions"])
app.include_router(goals.router, prefix="/goals", tags=["Goals"])
app.include_router(analytics.router, prefix="/analytics", tags=["Analytics"])
app.include_router(oasis.router, prefix="/oasis", tags=["Oasis"])


@app.get("/health", tags=["System"], summary="Health check")
async def health_check() -> dict[str, str]:
    """Lightweight liveness probe used by orchestrators, uptime monitors, and CI."""
    return {"status": "healthy"}


# ---------------------------------------------------------------------------
# Flutter web SPA — served from the same FastAPI process on port 5000.
#
# The build output lives at  athar_frontend/build/web/  (relative to the
# repo root, one level above backend/).  Uvicorn is started from inside
# backend/, so we resolve the path relative to this file.
#
# Static asset files (JS, CSS, images …) are served directly by the
# /flutter-static mount for efficiency.  Every other path that wasn't
# matched by an API router above falls through to the catch-all which
# returns index.html so Flutter's client-side router can take over.
# ---------------------------------------------------------------------------
_FLUTTER_BUILD = Path(__file__).resolve().parents[2] / "athar_frontend" / "build" / "web"

if _FLUTTER_BUILD.exists():
    # Serve compiled JS, CSS, CanvasKit, assets, etc. under a dedicated prefix
    # so they are never mistaken for API routes.
    app.mount(
        "/flutter-static",
        StaticFiles(directory=_FLUTTER_BUILD),
        name="flutter_static",
    )

    _FLUTTER_BUILD_RESOLVED = _FLUTTER_BUILD.resolve()

    @app.get("/{full_path:path}", include_in_schema=False)
    async def serve_flutter_spa(full_path: str) -> FileResponse:
        """
        Catch-all that serves a specific static file when it exists, or falls
        back to index.html so Flutter's client-side router handles the path.

        Path traversal protection: resolve the candidate path and verify it
        stays inside _FLUTTER_BUILD before serving any file.
        """
        try:
            candidate = (_FLUTTER_BUILD / full_path).resolve()
            # Raises ValueError if candidate is outside the build directory.
            candidate.relative_to(_FLUTTER_BUILD_RESOLVED)
            if candidate.is_file():
                return FileResponse(candidate)
        except ValueError:
            # Attempted traversal outside the build directory — ignore and
            # fall through to index.html so the SPA handles the path.
            pass
        return FileResponse(_FLUTTER_BUILD / "index.html")