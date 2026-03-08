"""Lightweight helper to record every money change to player_transactions."""
from sqlalchemy.ext.asyncio import AsyncSession
from server.models.transaction import PlayerTransaction

# Module-level reference so tick.py can update it when world ticks advance
_current_ticks: float = 0.0


def set_ticks(ticks: float) -> None:
    global _current_ticks
    _current_ticks = ticks


def log_tx(
    db: AsyncSession,
    player,
    amount: int,
    source: str,
    detail: str = "",
    game_ticks: float | None = None,
) -> None:
    """Record a money transaction.  Call AFTER player.money has been updated."""
    tx = PlayerTransaction(
        player_id=player.id,
        amount=amount,
        balance_after=player.money,
        game_ticks=game_ticks if game_ticks is not None else _current_ticks,
        source=source,
        detail=detail[:128],
    )
    db.add(tx)
