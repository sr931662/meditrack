"""Environment-driven settings. Nothing sensitive has a usable default in production."""

from functools import lru_cache

from pydantic import model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

INSECURE_DEFAULT_SECRET = "change-me"


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="MEDTRACK_", env_file=".env", extra="ignore")

    env: str = "development"  # development | test | production
    database_url: str = "sqlite:///./medtrack-dev.db"
    jwt_secret: str = INSECURE_DEFAULT_SECRET
    access_token_ttl_minutes: int = 15
    refresh_token_ttl_days: int = 30
    login_lockout_threshold: int = 5
    login_lockout_minutes: int = 15
    cors_origins: list[str] = []
    # "mock" -> in-process fake providers (dev/test only). "live" -> real adapters; unconfigured ones fail loudly.
    # "demo" -> accepts everything but labels it SIMULATED (needs demo_mode=true in production).
    provider_mode: str = "live"
    demo_mode: bool = False  # seeds sample accounts/data on startup; for presentations only
    demo_password: str = "Demo@12345"
    embedded_worker: bool = False  # run the reminder/escalation worker inside the API process (Cloud Run)
    auto_migrate: bool = False  # run `alembic upgrade head` at startup
    whatsapp_phone_number_id: str | None = None
    whatsapp_access_token: str | None = None
    ivr_account_sid: str | None = None
    ivr_auth_token: str | None = None
    ivr_from_number: str | None = None
    delivery_webhook_secret: str | None = None
    internal_api_key: str | None = None  # used by the worker's HTTP tick endpoint, if enabled

    @model_validator(mode="after")
    def _guard_production(self) -> "Settings":
        if self.env == "production":
            if self.jwt_secret == INSECURE_DEFAULT_SECRET or len(self.jwt_secret) < 32:
                raise ValueError("MEDTRACK_JWT_SECRET must be set to a random value of at least 32 characters")
            if self.provider_mode == "mock":
                raise ValueError("MEDTRACK_PROVIDER_MODE=mock is not allowed in production")
            if self.provider_mode == "demo" and not self.demo_mode:
                raise ValueError("MEDTRACK_PROVIDER_MODE=demo in production also requires MEDTRACK_DEMO_MODE=true")
            if self.database_url.startswith("sqlite"):
                raise ValueError("SQLite is not allowed in production; use PostgreSQL")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
