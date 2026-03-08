"""Leaderboard API endpoints."""

from fastapi import APIRouter, Depends, Request
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from server.database import get_db
from server.models.player import Player
from server.models.ship import SHIP_CLASS_STATS, Ship
from server.rate_limit import limiter
from server.simulation.tick import BASE_ORE_PRICES, get_market_prices

router = APIRouter(prefix="/api/leaderboard", tags=["leaderboard"])


def _calc_net_worth(player: Player) -> tuple[int, int, int]:
    """Return (net_worth, ship_value, cargo_value) for a player."""
    prices = get_market_prices()
    ship_value = sum(
        SHIP_CLASS_STATS.get(ship.ship_class, {}).get("base_price", 0)
        for ship in player.ships
    )
    cargo_value = sum(
        int(tonnes * prices.get(ore, BASE_ORE_PRICES.get(ore, 1000.0)))
        for ship in player.ships
        for ore, tonnes in (ship.current_cargo or {}).items()
    )
    return player.money + ship_value + cargo_value, ship_value, cargo_value


@router.get("")
@limiter.limit("30/minute")
async def get_leaderboard(
    request: Request,
    limit: int = 100,
    offset: int = 0,
    db: AsyncSession = Depends(get_db),
):
    """
    Get leaderboard sorted by net worth (money + ship values + cargo).
    NPCs are excluded.
    """
    limit = min(limit, 100)

    # Fetch all non-NPC players (pagination applied after sort so ranks are correct)
    stmt = select(Player).where(Player.is_npc == False)  # noqa: E712
    result = await db.execute(stmt)
    all_players = result.scalars().all()

    entries = []
    for player in all_players:
        net_worth, ship_value, cargo_value = _calc_net_worth(player)
        entries.append({
            "player_id": player.id,
            "username": player.username,
            "net_worth": net_worth,
            "money": player.money,
            "ship_value": ship_value,
            "cargo_value": cargo_value,
            "ships_count": len(player.ships),
            "workers_count": len(player.workers),
        })

    entries.sort(key=lambda x: x["net_worth"], reverse=True)

    total_players = len(entries)

    # Apply pagination and assign ranks
    page = entries[offset: offset + limit]
    for i, entry in enumerate(page, start=offset + 1):
        entry["rank"] = i

    return {
        "entries": page,
        "total_players": total_players,
    }


@router.get("/player/{player_id}")
@limiter.limit("60/minute")
async def get_player_rank(
    request: Request,
    player_id: int,
    db: AsyncSession = Depends(get_db),
):
    """Get a specific player's leaderboard rank and net worth."""
    stmt = select(Player).where(Player.id == player_id)
    result = await db.execute(stmt)
    player = result.scalar_one_or_none()

    if not player:
        return {"error": "Player not found"}, 404

    player_net_worth, ship_value, cargo_value = _calc_net_worth(player)

    # Count non-NPC players with higher net worth
    all_stmt = select(Player).where(Player.is_npc == False)  # noqa: E712
    all_result = await db.execute(all_stmt)
    all_players = all_result.scalars().all()

    higher_count = sum(
        1 for p in all_players
        if p.id != player_id and _calc_net_worth(p)[0] > player_net_worth
    )

    return {
        "rank": higher_count + 1,
        "player_id": player.id,
        "username": player.username,
        "net_worth": player_net_worth,
        "money": player.money,
        "ship_value": ship_value,
        "cargo_value": cargo_value,
        "ships_count": len(player.ships),
        "workers_count": len(player.workers),
    }
