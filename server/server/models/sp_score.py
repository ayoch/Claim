"""Single-player score submission — global leaderboard for offline/SP mode players."""

from datetime import datetime
from sqlalchemy import DateTime, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from server.database import Base


class SPScore(Base):
    __tablename__ = "sp_scores"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_name: Mapped[str] = mapped_column(String(64), nullable=False, index=True)
    net_worth: Mapped[int] = mapped_column(Integer, nullable=False)
    ships_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    workers_count: Mapped[int] = mapped_column(Integer, nullable=False, server_default="0")
    game_date: Mapped[str] = mapped_column(String(64), nullable=False, server_default="")
    submitted_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    def __repr__(self) -> str:
        return f"<SPScore(id={self.id}, player={self.player_name}, net_worth={self.net_worth})>"
