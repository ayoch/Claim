"""
World state model - stores global simulation state
"""
from datetime import datetime, timezone
from sqlalchemy import Integer, BigInteger, Float, DateTime
from sqlalchemy.orm import Mapped, mapped_column
from server.database import Base


class WorldState(Base):
    __tablename__ = "world_state"

    world_id: Mapped[int] = mapped_column(Integer, primary_key=True, default=1)
    total_ticks: Mapped[int] = mapped_column(BigInteger, default=0, nullable=False)
    game_seconds: Mapped[float] = mapped_column(Float, default=0.0, nullable=False, server_default="0.0")
    speed_multiplier: Mapped[float] = mapped_column(Float, default=1.0, nullable=False, server_default="1.0")
    last_updated: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        default=lambda: datetime.now(timezone.utc),
        onupdate=lambda: datetime.now(timezone.utc),
        nullable=False
    )
