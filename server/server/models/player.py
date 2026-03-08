from datetime import datetime, timezone

from sqlalchemy import Boolean, DateTime, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship

from server.database import Base


class Player(Base):
    __tablename__ = "players"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    username: Mapped[str] = mapped_column(String(64), unique=False, nullable=False, index=True)  # Not unique - multiple players can have same name
    email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)  # Required unique email - primary anti-cheat measure
    password_hash: Mapped[str] = mapped_column(String(128), nullable=False)
    money: Mapped[int] = mapped_column(Integer, default=14_000_000, nullable=False)
    reputation: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    is_admin: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)
    is_npc: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    hq_colony_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("colonies.id", ondelete="SET NULL"), nullable=True
    )

    # Company policy enums — must match GDScript CompanyPolicy enums exactly
    # ThrustPolicy:    0=CONSERVATIVE  1=BALANCED  2=AGGRESSIVE  3=ECONOMICAL
    thrust_policy: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    # SupplyPolicy:    0=PROACTIVE     1=ROUTINE   2=MINIMAL     3=MANUAL
    supply_policy: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    # CollectionPolicy:0=AGGRESSIVE    1=ROUTINE   2=PATIENT     3=MANUAL
    collection_policy: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    # EncounterPolicy: 0=AVOID         1=COEXIST   2=CONFRONT    3=DEFEND
    encounter_policy: Mapped[int] = mapped_column(Integer, default=1, nullable=False)
    # Whether the server automatically sells cargo when a ship returns from a mission.
    # If False, cargo stays on the ship and the player must sell manually.
    auto_sell_on_return: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    last_seen: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        onupdate=func.now(),
        nullable=False,
    )

    # Relationships
    ships: Mapped[list["Ship"]] = relationship("Ship", back_populates="player", lazy="selectin")  # noqa: F821
    workers: Mapped[list["Worker"]] = relationship("Worker", back_populates="player", lazy="selectin")  # noqa: F821
    missions: Mapped[list["Mission"]] = relationship("Mission", back_populates="player", lazy="selectin")  # noqa: F821
    trade_missions: Mapped[list["TradeMission"]] = relationship("TradeMission", back_populates="player", lazy="selectin")  # noqa: F821
    rigs: Mapped[list["Rig"]] = relationship("Rig", back_populates="player", lazy="selectin")  # noqa: F821
    bug_reports: Mapped[list["BugReport"]] = relationship("BugReport", back_populates="player", lazy="selectin")  # noqa: F821

    def __repr__(self) -> str:
        return f"<Player id={self.id} username={self.username!r} money={self.money}>"
