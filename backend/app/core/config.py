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
    SUPABASE_URL: str = Field(..., description="Supabase project URL")
    SUPABASE_SERVICE_KEY: str = Field(
        ..., description="Supabase service_role secret key (server-side only)"
    )

    # --- CORS ---
    CORS_ORIGINS: list[str] = Field(
        default_factory=lambda: ["*"],
        description="Comma-separated in env: CORS_ORIGINS=https://app.example.com,https://staging.example.com",
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