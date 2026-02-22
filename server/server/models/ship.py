from sqlalchemy import Boolean, Float, ForeignKey, Integer, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column, relationship

from server.database import Base


# Ship class constants
COURIER = 0
HAULER = 1
PROSPECTOR = 2
EXPLORER = 3

SHIP_CLASS_NAMES = {COURIER: "Courier", HAULER: "Hauler", PROSPECTOR: "Prospector", EXPLORER: "Explorer"}

# Base stats by class — GDD §8.2 canonical values (must match ship_data.gd CLASS_STATS)
SHIP_CLASS_STATS: dict[int, dict] = {
    COURIER: {
        "max_thrust_g": 0.38,
        "cargo_capacity": 38.0,    # tonnes
        "cargo_volume": 54.0,      # m³
        "fuel_capacity": 46.5,
        "base_mass": 73.4,         # dry mass tonnes
        "min_crew": 2,
        "max_equipment_slots": 3,
        "base_price": 800_000,
    },
    HAULER: {
        "max_thrust_g": 0.19,
        "cargo_capacity": 412.0,
        "cargo_volume": 584.0,
        "fuel_capacity": 237.0,
        "base_mass": 488.2,
        "min_crew": 5,
        "max_equipment_slots": 5,
        "base_price": 1_500_000,
    },
    PROSPECTOR: {
        "max_thrust_g": 0.31,
        "cargo_capacity": 107.0,
        "cargo_volume": 143.0,
        "fuel_capacity": 118.0,
        "base_mass": 214.8,
        "min_crew": 3,
        "max_equipment_slots": 4,
        "base_price": 1_000_000,
    },
    EXPLORER: {
        "max_thrust_g": 0.47,
        "cargo_capacity": 63.0,
        "cargo_volume": 91.0,
        "fuel_capacity": 192.0,
        "base_mass": 141.6,
        "min_crew": 2,
        "max_equipment_slots": 4,
        "base_price": 1_200_000,
    },
}


class Ship(Base):
    __tablename__ = "ships"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("players.id", ondelete="CASCADE"), nullable=False, index=True
    )

    ship_name: Mapped[str] = mapped_column(String(64), nullable=False)
    ship_class: Mapped[int] = mapped_column(Integer, nullable=False)  # 0=COURIER ... 3=EXPLORER

    max_thrust_g: Mapped[float] = mapped_column(Float, nullable=False)
    thrust_setting: Mapped[float] = mapped_column(Float, default=1.0, nullable=False)
    cargo_capacity: Mapped[float] = mapped_column(Float, nullable=False)   # tonnes
    cargo_volume: Mapped[float] = mapped_column(Float, nullable=False)     # m³
    fuel_capacity: Mapped[float] = mapped_column(Float, nullable=False)
    fuel: Mapped[float] = mapped_column(Float, nullable=False)
    base_mass: Mapped[float] = mapped_column(Float, nullable=False)        # dry mass tonnes

    min_crew: Mapped[int] = mapped_column(Integer, nullable=False)
    max_equipment_slots: Mapped[int] = mapped_column(Integer, nullable=False)

    engine_condition: Mapped[float] = mapped_column(Float, default=100.0, nullable=False)
    is_derelict: Mapped[bool] = mapped_column(Boolean, default=False, nullable=False)

    # Position in AU (heliocentric ecliptic)
    position_x: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    position_y: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)

    is_stationed: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)
    station_colony_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("colonies.id", ondelete="SET NULL"), nullable=True
    )

    # JSON payload — {ore_type_str: tonnes}
    current_cargo: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    # {supply_type: units}  e.g. {"food": 30.0, "repair_parts": 5.0}
    supplies: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)

    # Relationships
    player: Mapped["Player"] = relationship("Player", back_populates="ships")  # noqa: F821
    workers: Mapped[list["Worker"]] = relationship("Worker", back_populates="ship", lazy="selectin")  # noqa: F821
    missions: Mapped[list["Mission"]] = relationship(  # noqa: F821
        "Mission", back_populates="ship", lazy="selectin", foreign_keys="[Mission.ship_id]"
    )

    @property
    def class_name(self) -> str:
        return SHIP_CLASS_NAMES.get(self.ship_class, "Unknown")

    @property
    def cargo_used_tonnes(self) -> float:
        return sum(self.current_cargo.values()) if self.current_cargo else 0.0

    def __repr__(self) -> str:
        return f"<Ship id={self.id} name={self.ship_name!r} class={self.class_name}>"
