"""
Athar-Fintech API — application entrypoint.

Instantiates the FastAPI application, wires security middleware, and mounts
routers. Business and Persistence-layer wiring is deliberately kept out of
this module — routers imported here depend only on Facade classes from
`app.business`.

On Replit the Flutter web build (athar_frontend/build/web) is served by this
same FastAPI process on port 5000, so there is no cross-origin concern.
A catch-all route at the bottom serves index.html for all unmatched paths,
enabling Flutter's client-side router to work correctly.
"""

import json
import logging
import mimetypes
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import FileResponse, HTMLResponse, JSONResponse, Response
from fastapi.staticfiles import StaticFiles
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.errors import RateLimitExceeded
from slowapi.util import get_remote_address

from app.core.config import settings
from app.presentation.routers import analytics, goals, oasis, transactions

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)

# ── Rate limiter ────────────────────────────────────────────────────────────
# Keyed on the caller's IP address. Individual routes can override the default
# limit by adding @limiter.limit("N/period") to their handler.
limiter = Limiter(key_func=get_remote_address, default_limits=["200/minute"])

app = FastAPI(
    title=settings.APP_NAME,
    description=(
        "Backend API for Athar (أَثَر) — a FinTech application blending "
        "offline transaction categorization with 3D gamified financial goals."
    ),
    version=settings.APP_VERSION,
    # Hide schema endpoints in production to reduce attack surface.
    docs_url="/docs" if settings.ENVIRONMENT != "production" else None,
    redoc_url="/redoc" if settings.ENVIRONMENT != "production" else None,
    openapi_url="/openapi.json" if settings.ENVIRONMENT != "production" else None,
)

# Register SlowAPI state and its 429 handler.
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)

# ── Security headers middleware ─────────────────────────────────────────────
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    response = await call_next(request)
    # Prevent MIME-type sniffing.
    response.headers["X-Content-Type-Options"] = "nosniff"
    # Block framing by external sites (clickjacking protection).
    response.headers["X-Frame-Options"] = "SAMEORIGIN"
    # Only send the origin as referrer, never the full URL path.
    response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"
    # Instruct browsers to use HTTPS for the next year once the app is deployed.
    response.headers["Strict-Transport-Security"] = (
        "max-age=31536000; includeSubDomains"
    )
    # Content Security Policy.
    # Flutter web needs:
    #   - gstatic.com  — CanvasKit JS + WASM (always), fallback fonts
    #   - fonts.gstatic.com / fonts.googleapis.com — Roboto, Noto Sans Arabic
    #   - blob:        — service worker, WASM execution
    #   - 'unsafe-inline'/'unsafe-eval' — Flutter's compiled JS bootstrap
    # Spline runtime and scene are now local (same origin); no CDN needed.
    response.headers["Content-Security-Policy"] = (
        "default-src 'self'; "
        "script-src 'self' 'unsafe-inline' 'unsafe-eval' 'wasm-unsafe-eval' blob: "
        "https://www.gstatic.com; "
        "script-src-elem 'self' 'unsafe-inline' blob: "
        "https://www.gstatic.com; "
        "style-src 'self' 'unsafe-inline' https://fonts.googleapis.com; "
        "font-src 'self' data: https://fonts.gstatic.com; "
        "img-src 'self' data: blob:; "
        "connect-src 'self' blob: "
        "https://*.supabase.co wss://*.supabase.co "
        "https://www.gstatic.com https://fonts.gstatic.com "
        "https://fonts.googleapis.com; "
        "worker-src 'self' blob:; "
        "frame-src 'self'; "
        "frame-ancestors 'self';"
    )
    return response

# ── CORS ────────────────────────────────────────────────────────────────────
# FastAPI raises ValueError if allow_credentials=True is combined with ["*"].
_origins = settings.CORS_ORIGINS
_allow_credentials = True
if "*" in _origins:
    import warnings
    warnings.warn(
        "CORS_ORIGINS contains '*' — allow_credentials forced to False. "
        "Set explicit origins instead.",
        stacklevel=1,
    )
    _allow_credentials = False

app.add_middleware(
    CORSMiddleware,
    allow_origins=_origins,
    allow_credentials=_allow_credentials,
    allow_methods=["GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type", "X-Request-ID"],
    expose_headers=["X-Request-ID"],
)

# ── API routers ─────────────────────────────────────────────────────────────
app.include_router(transactions.router, prefix="/transactions", tags=["Transactions"])
app.include_router(goals.router, prefix="/goals", tags=["Goals"])
app.include_router(analytics.router, prefix="/analytics", tags=["Analytics"])
app.include_router(oasis.router, prefix="/oasis", tags=["Oasis"])


@app.get("/health", tags=["System"], summary="Liveness probe")
async def health_check() -> dict[str, str]:
    """Lightweight liveness probe for orchestrators and uptime monitors."""
    return {"status": "healthy"}


# ── Flutter web SPA ─────────────────────────────────────────────────────────
# The build output lives at athar_frontend/build/web/ (two levels above this
# file: backend/app/main.py → backend/ → repo root → athar_frontend/).
# Static assets are served under /flutter-static; every other unmatched path
# falls through to index.html so Flutter's client-side router works correctly.
_FLUTTER_BUILD = (
    Path(__file__).resolve().parents[2] / "athar_frontend" / "build" / "web"
)

def _build_index_html() -> str:
    """
    Reads the compiled index.html and injects a small runtime-config script
    (`window.atharEnv`) carrying the PUBLIC Supabase URL + anon key from the
    server's own environment. This lets the same web bundle authenticate on
    any host without those values being baked in at `flutter build` time —
    important on hosts (e.g. Render) that don't pass env vars as Docker build
    args. Only the anon key (designed to be shipped to browsers) is exposed
    here — never the service key or JWT secret.
    """
    raw = (_FLUTTER_BUILD / "index.html").read_text(encoding="utf-8")
    config = {
        "SUPABASE_URL": settings.SUPABASE_URL or "",
        "SUPABASE_ANON_KEY": settings.SUPABASE_ANON_KEY or "",
    }
    script = f"<script>window.atharEnv={json.dumps(config)};</script>"
    # Insert right after <head> so it runs before Flutter's bootstrap.
    if "<head>" in raw:
        return raw.replace("<head>", "<head>\n    " + script, 1)
    return script + raw


if _FLUTTER_BUILD.exists():
    app.mount(
        "/flutter-static",
        StaticFiles(directory=_FLUTTER_BUILD),
        name="flutter_static",
    )

    _FLUTTER_BUILD_RESOLVED = _FLUTTER_BUILD.resolve()
    # Cache the injected HTML once at startup (config comes from env, fixed
    # for the process lifetime).
    _INDEX_HTML = _build_index_html()

    @app.get("/{full_path:path}", include_in_schema=False)
    async def serve_flutter_spa(full_path: str) -> Response:
        """
        Serves a specific static file when it exists, or falls back to
        index.html so Flutter's client-side router handles the path.

        Path traversal protection: resolves the candidate and verifies it
        stays inside _FLUTTER_BUILD before serving any file.
        """
        try:
            candidate = (_FLUTTER_BUILD / full_path).resolve()
            candidate.relative_to(_FLUTTER_BUILD_RESOLVED)  # raises ValueError on traversal
            if candidate.is_file():
                # Explicit media type: FastAPI's response_class default would
                # otherwise stamp application/json on these files, which breaks
                # strict MIME checks (e.g. <script type="module"> imports).
                media_type, _ = mimetypes.guess_type(str(candidate))
                return FileResponse(
                    candidate,
                    media_type=media_type or "application/octet-stream",
                )
        except ValueError:
            pass
        # Fall through to the SPA entrypoint, with runtime config injected.
        return HTMLResponse(_INDEX_HTML)
