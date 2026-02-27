from pydantic import Field, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
import secrets


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    DATABASE_URL: str = Field(
        ...,
        description="Database connection string (MUST be set via environment variable)"
    )
    SECRET_KEY: str = Field(
        ...,
        min_length=32,
        description="JWT signing key (MUST be set via environment variable, min 32 characters)"
    )
    WORLD_NAME: str = "Euterpe"
    TICK_INTERVAL: float = Field(default=1.0, ge=0.01, le=10.0)

    # JWT settings
    ALGORITHM: str = "HS256"
    ACCESS_TOKEN_EXPIRE_MINUTES: int = 60  # 1 hour (was 7 days - security risk)

    # CORS settings
    CORS_ORIGINS: str = Field(
        default="http://localhost:3000,http://localhost:8080",
        description="Comma-separated list of allowed origins"
    )

    # Environment
    ENVIRONMENT: str = Field(default="development", description="development|production")

    # Logging
    LOG_LEVEL: str = Field(default="INFO", description="DEBUG|INFO|WARNING|ERROR")

    @property
    def cors_origins_list(self) -> list[str]:
        """Parse comma-separated CORS origins into list."""
        return [origin.strip() for origin in self.CORS_ORIGINS.split(",")]

    def validate_production(self) -> None:
        """Validate settings for production deployment."""
        if len(self.SECRET_KEY) < 32:
            raise ValueError("SECRET_KEY must be at least 32 characters")
        if "*" in self.CORS_ORIGINS:
            raise ValueError("CORS_ORIGINS must not contain wildcard in production")
        if "localhost" in self.CORS_ORIGINS:
            raise ValueError("CORS_ORIGINS should not contain localhost in production")
        # Validate CORS origins use HTTPS
        for origin in self.cors_origins_list:
            if not origin.startswith("https://"):
                raise ValueError(f"Production CORS origins must use HTTPS: {origin}")


settings = Settings()
