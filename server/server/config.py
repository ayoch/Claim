from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
import secrets


class Settings(BaseSettings):
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        extra="ignore",
    )

    # Environment must be loaded first to determine if we use dev defaults
    ENVIRONMENT: str = Field(default="development", description="development|production")

    # These are optional to allow dev defaults, but required in production
    DATABASE_URL: str | None = Field(
        default=None,
        description="Database connection string (required in production, has dev default)"
    )
    BLOG_DATABASE_URL: str = Field(
        default="sqlite+aiosqlite:///website.db",
        description="SQLite database for blog/website content"
    )
    SECRET_KEY: str | None = Field(
        default=None,
        description="JWT signing key (required in production, has dev default)"
    )

    @model_validator(mode='after')
    def set_development_defaults(self) -> 'Settings':
        """Set safe defaults for development environment only."""
        if self.ENVIRONMENT == "development":
            # Development database default
            if self.DATABASE_URL is None:
                self.DATABASE_URL = "postgresql+asyncpg://claim_dev:claim_dev_password@localhost/claim_dev"
                print("⚠️  Using development DATABASE_URL (no .env found)")

            # Development secret key default
            if self.SECRET_KEY is None:
                # Generate a random key for this session (won't persist across restarts)
                self.SECRET_KEY = secrets.token_urlsafe(32)
                print("⚠️  Generated random SECRET_KEY for development (tokens won't persist across restarts)")
        else:
            # Production/staging requires both to be set
            if self.DATABASE_URL is None:
                raise ValueError(
                    f"DATABASE_URL is required for environment '{self.ENVIRONMENT}'. "
                    "Set it in .env file or environment variables."
                )
            if self.SECRET_KEY is None:
                raise ValueError(
                    f"SECRET_KEY is required for environment '{self.ENVIRONMENT}'. "
                    "Set it in .env file or environment variables."
                )

        # Ensure DATABASE_URL uses asyncpg driver (Railway provides postgresql://)
        if self.DATABASE_URL and self.DATABASE_URL.startswith("postgresql://"):
            self.DATABASE_URL = self.DATABASE_URL.replace("postgresql://", "postgresql+asyncpg://", 1)

        return self

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
        if self.SECRET_KEY and len(self.SECRET_KEY) < 32:
            raise ValueError("SECRET_KEY must be at least 32 characters")
        if self.ADMIN_KEY == "changeme-admin-key":
            raise ValueError("ADMIN_KEY must be set to a secure random value in production")
        if "*" in self.CORS_ORIGINS:
            raise ValueError("CORS_ORIGINS must not contain wildcard in production")
        if "localhost" in self.CORS_ORIGINS:
            raise ValueError("CORS_ORIGINS should not contain localhost in production")
        # Validate CORS origins use HTTPS
        for origin in self.cors_origins_list:
            if not origin.startswith("https://"):
                raise ValueError(f"Production CORS origins must use HTTPS: {origin}")


settings = Settings()
