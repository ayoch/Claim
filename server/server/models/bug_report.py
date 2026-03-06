from datetime import datetime
from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, Text, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from server.database import Base


class BugReport(Base):
    __tablename__ = "bug_reports"

    # Primary key
    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)

    # Reporter info (nullable for local/anonymous reports)
    player_id: Mapped[int | None] = mapped_column(
        Integer,
        ForeignKey("players.id", ondelete="SET NULL"),
        nullable=True,
        index=True
    )
    reporter_username: Mapped[str] = mapped_column(String(32), nullable=False)

    # Report content
    title: Mapped[str] = mapped_column(String(200), nullable=False, index=True)
    description: Mapped[str] = mapped_column(Text, nullable=False)
    category: Mapped[str] = mapped_column(String(50), nullable=False, default="general", index=True)

    # Status tracking
    status: Mapped[str] = mapped_column(String(20), nullable=False, default="open", index=True)
    # Status values: "open", "in_progress", "done", "wont_fix", "duplicate"

    # Metadata
    game_version: Mapped[str] = mapped_column(String(20), nullable=False, default="unknown")
    backend_mode: Mapped[str] = mapped_column(String(10), nullable=False)  # "local" or "server"

    # Timestamps
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
        index=True
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False
    )

    # Admin notes (optional field for admin to add context)
    admin_notes: Mapped[str | None] = mapped_column(Text, nullable=True)

    # Relationships
    player: Mapped["Player"] = relationship("Player", back_populates="bug_reports")  # noqa: F821

    def __repr__(self) -> str:
        return f"<BugReport id={self.id} title='{self.title[:30]}...' status={self.status}>"
