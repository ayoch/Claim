"""Contract model for delivery contracts."""

from datetime import datetime, timezone
from sqlalchemy import Boolean, DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column, relationship
from server.database import Base


# Contract status constants (match GDScript Contract.Status enum)
STATUS_AVAILABLE = 0
STATUS_ACCEPTED = 1
STATUS_COMPLETED = 2
STATUS_EXPIRED = 3
STATUS_FAILED = 4


class Contract(Base):
    """
    Delivery contracts for ore transport.
    Players accept contracts, deliver ore, and receive payment.
    """
    __tablename__ = "contracts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("players.id", ondelete="CASCADE"), nullable=True, index=True
    )

    # Contract details
    ore_type: Mapped[str] = mapped_column(String(32), nullable=False)  # "iron", "platinum", etc.
    quantity: Mapped[float] = mapped_column(Float, nullable=False)  # Total tonnes required
    quantity_delivered: Mapped[float] = mapped_column(Float, default=0.0, nullable=False)
    reward: Mapped[int] = mapped_column(Integer, nullable=False)  # Payment in credits
    deadline_ticks: Mapped[float] = mapped_column(Float, nullable=False)  # Remaining ticks
    original_deadline_ticks: Mapped[float] = mapped_column(Float, nullable=False, server_default="0")  # At acceptance, for early-bonus calc

    # Contract metadata
    status: Mapped[int] = mapped_column(Integer, default=STATUS_AVAILABLE, nullable=False, index=True)
    issuer_name: Mapped[str] = mapped_column(String(128), nullable=False)
    delivery_colony_id: Mapped[int | None] = mapped_column(
        Integer, ForeignKey("colonies.id", ondelete="SET NULL"), nullable=True
    )
    allows_partial: Mapped[bool] = mapped_column(Boolean, default=True, nullable=False)

    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        server_default=func.now(),
        nullable=False,
    )
    accepted_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )
    completed_at: Mapped[datetime | None] = mapped_column(
        DateTime(timezone=True),
        nullable=True,
    )

    def __repr__(self) -> str:
        return f"<Contract(id={self.id}, ore={self.ore_type}, qty={self.quantity}, reward={self.reward}, status={self.status})>"

    def get_progress(self) -> float:
        """Get completion progress (0.0 to 1.0)."""
        if self.quantity <= 0:
            return 1.0
        return min(1.0, self.quantity_delivered / self.quantity)

    def is_complete(self) -> bool:
        """Check if contract requirements are met."""
        return self.quantity_delivered >= self.quantity

    def can_accept(self, player_id: int) -> bool:
        """Check if contract can be accepted by player."""
        return (
            self.status == STATUS_AVAILABLE
            and (self.player_id is None or self.player_id == player_id)
            and self.deadline_ticks > 0
        )
