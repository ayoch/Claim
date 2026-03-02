"""Password reset token model."""

from datetime import datetime, timezone
from sqlalchemy import DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column
from server.database import Base


class PasswordResetToken(Base):
    """
    Time-limited, single-use tokens for password reset.
    Tokens expire after 1 hour and are deleted after use.
    """
    __tablename__ = "password_reset_tokens"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("players.id", ondelete="CASCADE"), nullable=False, index=True
    )
    token: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    expires_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
    )
    used_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    def __repr__(self) -> str:
        return f"<PasswordResetToken(id={self.id}, player_id={self.player_id}, used={'Yes' if self.used_at else 'No'})>"

    def is_valid(self) -> bool:
        """Check if token is still valid (not used and not expired)."""
        now = datetime.now(timezone.utc)
        return self.used_at is None and self.expires_at > now
