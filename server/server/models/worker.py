from sqlalchemy import Boolean, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from server.database import Base


# Personality enum constants
NERVOUS = 0
RECKLESS = 1
LOYAL = 2
MERCENARY = 3
LAZY = 4
DILIGENT = 5

PERSONALITY_NAMES = {
    NERVOUS: "Nervous",
    RECKLESS: "Reckless",
    LOYAL: "Loyal",
    MERCENARY: "Mercenary",
    LAZY: "Lazy",
    DILIGENT: "Diligent",
}

# Leave status constants
LEAVE_NONE = 0
LEAVE_REQUESTED = 1
LEAVE_GRANTED = 2
LEAVE_ABSENT = 3


class Worker(Base):
    __tablename__ = "workers"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("players.id", ondelete="CASCADE"), nullable=False, index=True
    )

    first_name: Mapped[str] = mapped_column(String(32), nullable=False)
    last_name: Mapped[str] = mapped_column(String(32), nullable=False)

    pilot_skill: Mapped[float] = mapped_column(Float, nullable=False)
    engineer_skill: Mapped[float] = mapped_column(Float, nullable=False)
    mining_skill: Mapped[float] = mapped_column(Float, nullable=False)

    pilot_xp: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    engineer_xp: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    mining_xp: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)

    wage: Mapped[int] = mapped_column(Integer, nullable=False)  # credits per in-game day
    loyalty: Mapped[float] = mapped_column(Float, default=50.0, nullable=False)
    fatigue: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)

    # 0=NERVOUS 1=RECKLESS 2=LOYAL 3=MERCENARY 4=LAZY 5=DILIGENT
    personality: Mapped[int] = mapped_column(Integer, default=LOYAL, nullable=False)

    assigned_ship_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("ships.id", ondelete="SET NULL"), nullable=True
    )
    assigned_mission_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("missions.id", ondelete="SET NULL"), nullable=True
    )

    is_available: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    leave_status: Mapped[int] = mapped_column(Integer, default=LEAVE_NONE, nullable=False)

    # Relationships
    player: Mapped["Player"] = relationship("Player", back_populates="workers")  # noqa: F821
    ship: Mapped["Ship | None"] = relationship("Ship", back_populates="workers")  # noqa: F821

    @property
    def full_name(self) -> str:
        return f"{self.first_name} {self.last_name}"

    @property
    def personality_name(self) -> str:
        return PERSONALITY_NAMES.get(self.personality, "Unknown")

    def __repr__(self) -> str:
        return f"<Worker id={self.id} name={self.full_name!r} ship_id={self.assigned_ship_id}>"
