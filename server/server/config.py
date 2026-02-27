from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
import secrets


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    DATABASE_URL: str = "postgresql+asyncpg://claim:claim@localhost/claim_dev"
    SECRET_KEY: str = Field(
        default_factory=lambda: secrets.token_urlsafe(32),
        description="JWT signing key - MUST be set in production"
    )
    WORLD_NAME: str = "Euterpe"
    TICK_INTERVAL: float = Field(default=1.0, ge=0.01, le=10.0)

    # JWT settings
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days

    # CORS settings
    CORS_ORIGINS: str = Field(
        default="http://localhost:3000,http://localhost:8080",
        description="Comma-separated list of allowed origins"
    )

    # Environment
    ENVIRONMENT: str = Field(default="development", description="development|production")

    # Admin API key
    ADMIN_KEY: str = Field(
        default="changeme-admin-key",
        description="Secret key required for all /admin endpoints"
    )

    # Logging
    LOG_LEVEL: str = Field(default="INFO", description="DEBUG|INFO|WARNING|ERROR")

    @property
    def cors_origins_list(self) -> list[str]:
        """Parse comma-separated CORS origins into list."""
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",")]

    def validate_production(self) -> None:
        """Validate settings for production deployment."""
        if self.SECRET_KEY == "changeme-in-production":
            raise ValueError("SECRET_KEY must be set to a secure random value in production")
        if len(self.SECRET_KEY) < 32:
            raise ValueError("SECRET_KEY must be at least 32 characters")
        if self.ADMIN_KEY == "changeme-admin-key":
            raise ValueError("ADMIN_KEY must be set to a secure random value in production")
        if "*" in self.CORS_ORIGINS:
            raise ValueError("CORS_ORIGINS must not contain wildcard in production")
        if "localhost" in self.CORS_ORIGINS:
            raise ValueError("CORS_ORIGINS should not contain localhost in production")


settings = Settings()
