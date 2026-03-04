from datetime import datetime, timezone
from sqlalchemy import BigInteger, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from server.database import Base


# Status constants
STATUS_TRANSIT_TO_COLONY = 0
STATUS_REFUELING = 1
STATUS_SELLING = 2
STATUS_IDLE_AT_COLONY = 3
STATUS_TRANSIT_BACK = 4
STATUS_COMPLETED = 5


class TradeMission(Base):
    __tablename__ = "trade_missions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("players.id", ondelete="CASCADE"), nullable=False, index=True
    )
    ship_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("ships.id", ondelete="CASCADE"), nullable=False, index=True
    )
    colony_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("colonies.id", ondelete="SET NULL"), nullable=True
    )

    status: Mapped[int] = mapped_column(Integer, nullable=False, default=STATUS_TRANSIT_TO_COLONY)
    transit_time: Mapped[float] = mapped_column(Float, nullable=False)
    elapsed_ticks: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    fuel_per_tick: Mapped[float] = mapped_column(Float, nullable=False)

    # Cargo being transported (JSON: {ore_type_str: tonnes})
    cargo: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)

    # Revenue from selling (filled when status = SELLING)
    revenue: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    # Origin/destination tracking
    origin_x: Mapped[float] = mapped_column(Float, nullable=False)
    origin_y: Mapped[float] = mapped_column(Float, nullable=False)
    origin_name: Mapped[str] = mapped_column(String(64), nullable=False, default="Earth")
    origin_is_earth: Mapped[bool] = mapped_column(Integer, nullable=False, default=True)

    # Destination position (colony location at dispatch time)
    destination_x: Mapped[float] = mapped_column(Float, nullable=False)
    destination_y: Mapped[float] = mapped_column(Float, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), nullable=False, default=lambda: datetime.now(timezone.utc)
    )

    # Relationships
    player: Mapped["Player"] = relationship("Player", back_populates="trade_missions")  # noqa: F821
    ship: Mapped["Ship"] = relationship("Ship")  # noqa: F821
    colony: Mapped["Colony"] = relationship("Colony")  # noqa: F821

    def __repr__(self) -> str:
        return f"<TradeMission id={self.id} ship_id={self.ship_id} status={self.status}>"
