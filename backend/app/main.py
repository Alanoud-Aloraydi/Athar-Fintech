"""
Athar-Fintech API — application entrypoint.

Instantiates the FastAPI application and mounts routers. Business and
Persistence-layer wiring is deliberately kept out of this module — routers
imported here should depend only on Facade classes from `app.business`.
"""

import logging

from fastapi import FastAPI

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

app.add_middleware(CORSMiddleware, allow_origins=settings.CORS_ORIGINS, allow_credentials=True, allow_methods=["*"],
                   allow_headers=["*"], )

app.include_router(transactions.router, prefix="/transactions", tags=["Transactions"])
app.include_router(goals.router, prefix="/goals", tags=["Goals"])
app.include_router(analytics.router, prefix="/analytics", tags=["Analytics"])
app.include_router(oasis.router, prefix="/oasis", tags=["Oasis"])


@app.get("/health", tags=["System"], summary="Health check")
async def health_check() -> dict[str, str]:
    """Lightweight liveness probe used by orchestrators, uptime monitors, and CI."""
    return {"status": "healthy"}