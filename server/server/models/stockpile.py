from sqlalchemy import Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column, relationship

from server.database import Base


class Stockpile(Base):
    """
    Ore stockpile at an asteroid from deployed rigs.

    Each player has separate stockpiles at each asteroid.
    Stockpiles are collected by ships via collection missions.
    """
    __tablename__ = "stockpiles"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("players.id", ondelete="CASCADE"), nullable=False, index=True
    )
    asteroid_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("asteroids.id", ondelete="CASCADE"), nullable=False, index=True
    )

    # Ore type (matches OreType enum: "iron", "nickel", "platinum", etc.)
    ore_type: Mapped[str] = mapped_column(String(32), nullable=False)

    # Tonnes of ore in stockpile
    tonnes: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)

    # Relationships
    player: Mapped["Player"] = relationship("Player")  # noqa: F821
    asteroid: Mapped["Asteroid"] = relationship("Asteroid")  # noqa: F821

    def __repr__(self) -> str:
        return f"<Stockpile player={self.player_id} asteroid={self.asteroid_id} ore={self.ore_type} tonnes={self.tonnes}>"
