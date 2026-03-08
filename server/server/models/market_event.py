"""Market event model — world-wide price shocks."""

from datetime import datetime
from sqlalchemy import Boolean, DateTime, Float, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from server.database import Base


class MarketEvent(Base):
    __tablename__ = "market_events"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    ore_type: Mapped[str] = mapped_column(String(32), nullable=False, index=True)
    multiplier: Mapped[float] = mapped_column(Float, nullable=False)   # 1.4 = +40%, 0.65 = -35%
    start_tick: Mapped[float] = mapped_column(Float, nullable=False)
    duration_ticks: Mapped[float] = mapped_column(Float, nullable=False)
    headline: Mapped[str] = mapped_column(String(256), nullable=False)
    is_active: Mapped[bool] = mapped_column(Boolean, nullable=False, server_default="true")
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )

    def __repr__(self) -> str:
        return f"<MarketEvent(ore={self.ore_type}, x{self.multiplier:.2f}, active={self.is_active})>"
