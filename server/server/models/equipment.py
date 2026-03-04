from sqlalchemy import Boolean, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from server.database import Base


class Equipment(Base):
    __tablename__ = "equipment"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    ship_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("ships.id", ondelete="CASCADE"), nullable=False, index=True
    )

    equipment_name: Mapped[str] = mapped_column(String(64), nullable=False)
    equipment_type: Mapped[str] = mapped_column(String(32), nullable=False)  # "processor", "refinery", "weapon"

    # Core stats
    mining_bonus: Mapped[float] = mapped_column(Float, default=1.0, nullable=False)
    cost: Mapped[int] = mapped_column(Integer, nullable=False)
    durability: Mapped[float] = mapped_column(Float, default=100.0, nullable=False)
    max_durability: Mapped[float] = mapped_column(Float, default=100.0, nullable=False)

    # Weapon properties
    weapon_power: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    weapon_range: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    weapon_accuracy: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    weapon_role: Mapped[str] = mapped_column(String(16), default="", nullable=False)

    # Ammo (torpedoes)
    ammo_capacity: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    current_ammo: Mapped[int] = mapped_column(Integer, default=0, nullable=False)
    ammo_cost: Mapped[int] = mapped_column(Integer, default=0, nullable=False)

    # Other
    mass: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    mining_speed_bonus: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)

    # Relationships
    ship: Mapped["Ship"] = relationship("Ship", back_populates="equipment")  # noqa: F821

    def is_weapon(self) -> bool:
        return self.weapon_power > 0 and self.weapon_range > 0.0

    def __repr__(self) -> str:
        return f"<Equipment id={self.id} name={self.equipment_name!r} ship_id={self.ship_id}>"
