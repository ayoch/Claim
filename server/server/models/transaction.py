from datetime import datetime
from sqlalchemy import BigInteger, DateTime, Float, ForeignKey, Integer, String, func
from sqlalchemy.orm import Mapped, mapped_column

from server.database import Base


class PlayerTransaction(Base):
    __tablename__ = "player_transactions"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, index=True)
    player_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("players.id", ondelete="CASCADE"),
        nullable=False, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), nullable=False
    )
    amount: Mapped[int] = mapped_column(BigInteger, nullable=False)      # signed: + income, - expense
    balance_after: Mapped[int] = mapped_column(BigInteger, nullable=False)
    game_ticks: Mapped[float] = mapped_column(Float, nullable=False, default=0.0)
    source: Mapped[str] = mapped_column(String(32), nullable=False)       # e.g. "payroll", "trade_sale"
    detail: Mapped[str] = mapped_column(String(128), nullable=False, default="")

    def __repr__(self) -> str:
        sign = "+" if self.amount >= 0 else ""
        return f"<Tx player={self.player_id} {sign}{self.amount:,} [{self.source}]>"
