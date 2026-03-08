"""Leaderboard API endpoints."""

from fastapi import APIRouter, Depends, Request
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession

from server.database import get_db
from server.models.player import Player
from server.models.ship import SHIP_CLASS_STATS, Ship
from server.models.sp_score import SPScore
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


# ---------------------------------------------------------------------------
# Single-player global leaderboard (unauthenticated, score submissions)
# ---------------------------------------------------------------------------

class SPScoreSubmit(BaseModel):
    player_name: str
    net_worth: int
    ships_count: int = 0
    workers_count: int = 0
    game_date: str = ""


@router.get("/sp")
@limiter.limit("30/minute")
async def get_sp_leaderboard(
    request: Request,
    limit: int = 100,
    db: AsyncSession = Depends(get_db),
):
    """Top single-player scores. No auth required."""
    limit = min(limit, 100)

    # Best score per player_name
    subq = (
        select(SPScore.player_name, func.max(SPScore.net_worth).label("best"))
        .group_by(SPScore.player_name)
        .subquery()
    )
    stmt = (
        select(SPScore)
        .join(subq, (SPScore.player_name == subq.c.player_name) & (SPScore.net_worth == subq.c.best))
        .order_by(SPScore.net_worth.desc())
        .limit(limit)
    )
    result = await db.execute(stmt)
    scores = result.scalars().all()

    entries = [
        {
            "rank": i + 1,
            "player_name": s.player_name,
            "net_worth": s.net_worth,
            "ships_count": s.ships_count,
            "workers_count": s.workers_count,
            "game_date": s.game_date,
        }
        for i, s in enumerate(scores)
    ]

    count_stmt = select(func.count(func.distinct(SPScore.player_name)))
    total = (await db.execute(count_stmt)).scalar_one()

    return {"entries": entries, "total_players": total}


@router.post("/sp")
@limiter.limit("10/minute")
async def submit_sp_score(
    request: Request,
    payload: SPScoreSubmit,
    db: AsyncSession = Depends(get_db),
):
    """Submit a single-player score. No auth required."""
    if not payload.player_name.strip():
        return {"error": "player_name required"}
    player_name = payload.player_name.strip()[:64]

    score = SPScore(
        player_name=player_name,
        net_worth=max(0, payload.net_worth),
        ships_count=max(0, payload.ships_count),
        workers_count=max(0, payload.workers_count),
        game_date=payload.game_date[:64],
    )
    db.add(score)
    await db.commit()
    return {"ok": True}
