from sqlalchemy import Float, Integer, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from server.database import Base


class Asteroid(Base):
    """
    Represents a minable body in the solar system.

    Orbital elements follow the standard Keplerian set, which lets us compute
    position at any Julian Date using Kepler's equation.
    """

    __tablename__ = "asteroids"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    asteroid_name: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    body_type: Mapped[str] = mapped_column(String(32), nullable=False)  # "asteroid", "NEO", "trojan", etc.

    # ---------- Keplerian orbital elements ----------
    semi_major_axis: Mapped[float] = mapped_column(Float, nullable=False)        # AU
    eccentricity: Mapped[float] = mapped_column(Float, nullable=False)
    inclination: Mapped[float] = mapped_column(Float, nullable=False)            # degrees
    long_ascending_node: Mapped[float] = mapped_column(Float, nullable=False)    # degrees (Omega)
    arg_perihelion: Mapped[float] = mapped_column(Float, nullable=False)         # degrees (omega)
    mean_anomaly_at_epoch: Mapped[float] = mapped_column(Float, nullable=False)  # degrees (M0)
    epoch_jd: Mapped[float] = mapped_column(Float, nullable=False)               # Julian Date

    # ---------- Game data ----------
    # {ore_type: rate_per_day}  e.g. {"nickel": 120.0, "iron": 80.0}
    ore_yields: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)
    max_mining_slots: Mapped[int] = mapped_column(Integer, default=6, nullable=False)

    def __repr__(self) -> str:
        return f"<Asteroid id={self.id} name={self.asteroid_name!r} type={self.body_type}>"
