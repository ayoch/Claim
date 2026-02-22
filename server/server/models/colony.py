from sqlalchemy import Boolean, Integer, String
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from server.database import Base


class Colony(Base):
    """
    A player-accessible station / settlement in the solar system.

    planet_id maps to a well-known orbital body name used by the ephemeris
    module to compute position (e.g. "earth", "mars", "ceres", "jupiter_l4").
    """

    __tablename__ = "colonies"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    colony_name: Mapped[str] = mapped_column(String(64), unique=True, nullable=False, index=True)
    planet_id: Mapped[str] = mapped_column(String(32), nullable=False)  # e.g. "mars"

    has_rescue_ops: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    # Ore price multipliers per ore type.
    # Actual price = base_price * multiplier.  Empty dict = multiplier 1.0 for all types.
    # e.g. {"nickel": 1.4, "iron": 0.9}
    price_multipliers: Mapped[dict] = mapped_column(JSONB, default=dict, nullable=False)

    def __repr__(self) -> str:
        return f"<Colony id={self.id} name={self.colony_name!r} planet={self.planet_id}>"
