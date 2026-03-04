from sqlalchemy import Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from server.database import Base


# Unit type constants (match client MiningUnit.UnitType enum)
UNIT_TYPE_BASIC = 0
UNIT_TYPE_ADVANCED = 1
UNIT_TYPE_REFINERY = 2


class Rig(Base):
    """
    Rig (AMU - Automated Mining Unit)

    Deployable autonomous miners that generate ore stockpiles at asteroids.
    Workers can be assigned to rigs to increase productivity.
    """
    __tablename__ = "rigs"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("players.id", ondelete="CASCADE"), nullable=False, index=True
    )

    # Unit properties
    unit_type: Mapped[int] = mapped_column(Integer, nullable=False, default=UNIT_TYPE_BASIC)
    unit_name: Mapped[str] = mapped_column(String(64), nullable=False)

    # Stats
    mass: Mapped[float] = mapped_column(Float, nullable=False)
    workers_required: Mapped[int] = mapped_column(Integer, nullable=False, default=1)
    mining_multiplier: Mapped[float] = mapped_column(Float, nullable=False, default=1.0)
    cost: Mapped[int] = mapped_column(Integer, nullable=False)

    # Durability
    durability: Mapped[float] = mapped_column(Float, nullable=False, default=100.0)
    max_durability: Mapped[float] = mapped_column(Float, nullable=False, default=100.0)
    wear_per_day: Mapped[float] = mapped_column(Float, nullable=False, default=0.3)

    # Deployment state
    deployed_at_asteroid_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("asteroids.id", ondelete="SET NULL"), nullable=True, index=True
    )
    deployed_at_tick: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    # Relationships
    player: Mapped["Player"] = relationship("Player", back_populates="rigs")  # noqa: F821
    asteroid: Mapped["Asteroid | None"] = relationship("Asteroid")  # noqa: F821
    assigned_workers: Mapped[list["Worker"]] = relationship(  # noqa: F821
        "Worker",
        primaryjoin="and_(Rig.id==foreign(Worker.assigned_rig_id), Worker.player_id==Rig.player_id)",
        viewonly=True
    )

    @property
    def is_deployed(self) -> bool:
        return self.deployed_at_asteroid_id is not None

    @property
    def is_functional(self) -> bool:
        return self.durability > 0.0

    def __repr__(self) -> str:
        return f"<Rig id={self.id} name={self.unit_name!r} asteroid_id={self.deployed_at_asteroid_id}>"
