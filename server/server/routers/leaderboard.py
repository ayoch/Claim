"""Leaderboard API endpoints."""

from fastapi import APIRouter, Depends, Request
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from server.database import get_db
from server.models.player import Player
from server.models.ship import SHIP_CLASS_STATS, Ship
from server.rate_limit import limiter

router = APIRouter(prefix="/api/leaderboard", tags=["leaderboard"])


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

    Args:
        limit: Maximum number of entries to return (max 100)
        offset: Number of entries to skip for pagination

    Returns:
        {
            "entries": [
                {
                    "rank": 1,
                    "player_id": 123,
                    "username": "SpaceMiner42",
                    "net_worth": 15000000,
                    "money": 14000000,
                    "ship_value": 1000000,
                    "ships_count": 1,
                    "workers_count": 4
                },
                ...
            ],
            "total_players": 150
        }
    """
    # Enforce max limit
    limit = min(limit, 100)

    # Get all players with their ships (using selectin loading from relationship)
    stmt = select(Player).offset(offset).limit(limit)
    result = await db.execute(stmt)
    players = result.scalars().all()

    # Calculate net worth for each player
    entries = []
    for player in players:
        # Calculate ship values
        ship_value = sum(
            SHIP_CLASS_STATS.get(ship.ship_class, {}).get("base_price", 0)
            for ship in player.ships
        )

        # TODO: Add cargo value once we have market prices and cargo data in DB
        # For now, net worth = money + ship_value
        net_worth = player.money + ship_value

        entries.append({
            "player_id": player.id,
            "username": player.username,
            "net_worth": net_worth,
            "money": player.money,
            "ship_value": ship_value,
            "ships_count": len(player.ships),
            "workers_count": len(player.workers),
        })

    # Sort by net worth descending
    entries.sort(key=lambda x: x["net_worth"], reverse=True)

    # Add ranks
    for i, entry in enumerate(entries, start=offset + 1):
        entry["rank"] = i

    # Get total player count
    count_stmt = select(func.count()).select_from(Player)
    total_result = await db.execute(count_stmt)
    total_players = total_result.scalar_one()

    return {
        "entries": entries,
        "total_players": total_players,
    }


@router.get("/player/{player_id}")
@limiter.limit("60/minute")
async def get_player_rank(
    request: Request,
    player_id: int,
    db: AsyncSession = Depends(get_db),
):
    """
    Get a specific player's leaderboard rank and net worth.

    Returns:
        {
            "rank": 42,
            "player_id": 123,
            "username": "SpaceMiner42",
            "net_worth": 15000000,
            "money": 14000000,
            "ship_value": 1000000,
            "ships_count": 1,
            "workers_count": 4
        }
    """
    # Get player
    stmt = select(Player).where(Player.id == player_id)
    result = await db.execute(stmt)
    player = result.scalar_one_or_none()

    if not player:
        return {"error": "Player not found"}, 404

    # Calculate player's net worth
    ship_value = sum(
        SHIP_CLASS_STATS.get(ship.ship_class, {}).get("base_price", 0)
        for ship in player.ships
    )
    player_net_worth = player.money + ship_value

    # Calculate rank by counting how many players have higher net worth
    # This is expensive but accurate - could be optimized with caching
    all_players_stmt = select(Player)
    all_result = await db.execute(all_players_stmt)
    all_players = all_result.scalars().all()

    # Calculate all net worths and count how many are higher
    higher_count = 0
    for other_player in all_players:
        if other_player.id == player_id:
            continue
        other_ship_value = sum(
            SHIP_CLASS_STATS.get(ship.ship_class, {}).get("base_price", 0)
            for ship in other_player.ships
        )
        other_net_worth = other_player.money + other_ship_value
        if other_net_worth > player_net_worth:
            higher_count += 1

    rank = higher_count + 1

    return {
        "rank": rank,
        "player_id": player.id,
        "username": player.username,
        "net_worth": player_net_worth,
        "money": player.money,
        "ship_value": ship_value,
        "ships_count": len(player.ships),
        "workers_count": len(player.workers),
    }
