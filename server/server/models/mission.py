from datetime import datetime

from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from server.database import Base


# Mission type constants
MISSION_MINING = 0
MISSION_DEPLOY_UNIT = 1
MISSION_COLLECT_ORE = 2
MISSION_TRADE = 3
MISSION_SURVEY = 4
MISSION_RESCUE = 5

MISSION_TYPE_NAMES = {
    MISSION_MINING: "Mining",
    MISSION_DEPLOY_UNIT: "Deploy Unit",
    MISSION_COLLECT_ORE: "Collect Ore",
    MISSION_TRADE: "Trade",
    MISSION_SURVEY: "Survey",
    MISSION_RESCUE: "Rescue",
}

# Mission status constants
STATUS_TRANSIT_OUT = 0
STATUS_MINING = 1
STATUS_TRANSIT_BACK = 2
STATUS_COMPLETED = 3
STATUS_FAILED = 4
STATUS_ABORTED = 5

STATUS_NAMES = {
    STATUS_TRANSIT_OUT: "Transit Out",
    STATUS_MINING: "Mining",
    STATUS_TRANSIT_BACK: "Transit Back",
    STATUS_COMPLETED: "Completed",
    STATUS_FAILED: "Failed",
    STATUS_ABORTED: "Aborted",
}


class Mission(Base):
    __tablename__ = "missions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("players.id", ondelete="CASCADE"), nullable=False, index=True
    )
    ship_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("ships.id", ondelete="CASCADE"), nullable=False, index=True
    )
    asteroid_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("asteroids.id", ondelete="SET NULL"), nullable=True
    )

    # 0=MINING 1=DEPLOY_UNIT 2=COLLECT_ORE 3=TRADE 4=SURVEY 5=RESCUE
    mission_type: Mapped[int] = mapped_column(Integer, nullable=False)
    # 0=TRANSIT_OUT 1=MINING 2=TRANSIT_BACK 3=COMPLETED 4=FAILED 5=ABORTED
    status: Mapped[int] = mapped_column(Integer, default=STATUS_TRANSIT_OUT, nullable=False)

    transit_time: Mapped[float] = mapped_column(Float, nullable=False)      # seconds total
    elapsed_ticks: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    fuel_per_tick: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)

    # Origin snapshot (for return leg)
    origin_x: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    origin_y: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    origin_name: Mapped[str] = mapped_column(String(64), default="", nullable=False)
    origin_is_earth: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    return_to_station: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # How long to spend mining (in game seconds = real seconds at 1x)
    mining_duration: Mapped[float] = mapped_column(Float, default=86400.0, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )

    # Relationships
    player: Mapped["Player"] = relationship("Player", back_populates="missions")  # noqa: F821
    ship: Mapped["Ship"] = relationship(  # noqa: F821
        "Ship", back_populates="missions", foreign_keys=[ship_id]
    )
    asteroid: Mapped["Asteroid | None"] = relationship("Asteroid", lazy="selectin")  # noqa: F821

    @property
    def mission_type_name(self) -> str:
        return MISSION_TYPE_NAMES.get(self.mission_type, "Unknown")

    @property
    def status_name(self) -> str:
        return STATUS_NAMES.get(self.status, "Unknown")

    def __repr__(self) -> str:
        return f"<Mission id={self.id} type={self.mission_type_name} status={self.status_name}>"
