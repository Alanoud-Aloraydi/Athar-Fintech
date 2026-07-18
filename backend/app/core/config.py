"""
Application configuration.

Loads and validates environment variables using pydantic-settings.
A single cached `Settings` instance is exposed via `get_settings()` so the
rest of the application never re-reads the environment at runtime.
"""

from functools import lru_cache
from pathlib import Path

from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from typing import Optional

# Resolve .env relative to this file (backend/app/core/config.py -> backend/.env)
# rather than relative to the process's current working directory. This is
# what makes `.env` loading work regardless of where `uvicorn`/`python` is
# invoked from.
_ENV_PATH = Path(__file__).resolve().parents[2] / ".env"


class Settings(BaseSettings):
    """Strongly-typed application settings, sourced from environment variables / .env file."""

    model_config = SettingsConfigDict(
        env_file=_ENV_PATH,
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )

    # --- Application metadata ---
    APP_NAME: str = "Athar-Fintech API"
    APP_VERSION: str = "0.1.0"
    ENVIRONMENT: str = Field(default="development")

    # --- Supabase ---
    # Optional so the server can start without credentials configured.
    # Endpoints that use the database will raise a clear RuntimeError when
    # called without these values set. Set them as Replit Secrets.
    SUPABASE_URL: Optional[str] = Field(default=None, description="Supabase project URL")
    SUPABASE_SERVICE_KEY: Optional[str] = Field(
        default=None, description="Supabase service_role secret key (server-side only)"
    )
    SUPABASE_ANON_KEY: Optional[str] = Field(
        default=None,
        description=(
            "Supabase project's anon/public key. Used to build per-user Supabase "
            "clients that authenticate as the requesting user (respects RLS). "
            "Safe to expose to clients, but kept server-side here."
        ),
    )
    SUPABASE_JWT_SECRET: Optional[str] = Field(
        default=None,
        description=(
            "Supabase project's JWT Secret (Project Settings -> API -> JWT "
            "Settings -> JWT Secret). Used to verify the access token the "
            "Flutter client sends on every request."
        ),
    )

    # --- CORS ---
    # NOTE: FastAPI raises an error if allow_credentials=True is combined with
    # the wildcard origin ["*"]. Always provide explicit origins here.
    # In the Replit environment, start.sh sets CORS_ORIGINS at launch time.
    CORS_ORIGINS: list[str] = Field(
        default_factory=lambda: ["http://localhost:5000", "http://localhost:3000", "http://0.0.0.0:5000"],
        description=(
            "Comma-separated in env: CORS_ORIGINS=https://app.example.com,https://staging.example.com  "
            "Do NOT use '*' with allow_credentials=True — FastAPI will reject the combination."
        ),
    )

    @field_validator("CORS_ORIGINS", mode="before")
    @classmethod
    def _split_csv(cls, v: object) -> object:
        """Allows `CORS_ORIGINS=https://a.com,https://b.com` in .env as a plain comma-separated string."""
        if isinstance(v, str):
            return [origin.strip() for origin in v.split(",") if origin.strip()]
        return v


@lru_cache
def get_settings() -> Settings:
    """
    Returns a cached, singleton `Settings` instance.

    `lru_cache` ensures the environment/.env file is parsed and validated
    only once per process, and the same instance is reused everywhere
    it's injected (e.g. via FastAPI's Depends).
    """
    return Settings()


# Module-level singleton for direct imports (e.g. `from app.core.config import settings`)
settings = get_settings()