"""
Account deletion with asset handling.

When a corporation ceases to exist:
- Workers die (tied to corporate life support/contracts)
- Ships maintain trajectory and become derelict
- Equipment remains with derelict ships
- All records deleted
"""
from __future__ import annotations
import logging
from datetime import datetime, timedelta, timezone

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from server.models.player import Player
from server.models.ship import Ship
from server.models.worker import Worker
from server.models.mission import Mission

logger = logging.getLogger(__name__)


async def delete_player_account(
    db: AsyncSession,
    player_id: int,
    reason: str = "Account deleted"
) -> dict:
    """
    Delete player account. Ships become derelict, workers die.

    Lore: When a corporation dissolves, its workers die (corporate life support
    contracts terminate) and ships continue on their last trajectory as derelicts.

    Args:
        db: Database session
        player_id: ID of player to delete
        reason: Reason for deletion (for logging)

    Returns:
        dict: Summary of deletion
            {
                "success": bool,
                "player_id": int,
                "username": str,
                "ships_set_adrift": int,
                "workers_lost": int,
                "equipment_salvageable": int,
                "reason": str
            }
    """
    player = await db.get(Player, player_id)
    if not player:
        return {
            "success": False,
            "error": "Player not found",
            "player_id": player_id
        }

    summary = {
        "success": True,
        "player_id": player_id,
        "username": player.username,
        "email": player.email,
        "reason": reason,
        "ships_set_adrift": 0,
        "workers_lost": 0,
        "equipment_salvageable": 0,
        "deleted_at": datetime.now(timezone.utc).isoformat()
    }

    # 1. Ships: Set adrift as derelicts (maintain trajectory)
    ships_result = await db.execute(
        select(Ship).where(Ship.player_id == player_id)
    )
    ships = list(ships_result.scalars().all())

    for ship in ships:
        # Remove ownership, mark as derelict
        ship.player_id = None
        ship.is_derelict = True
        ship.derelict_reason = f"Corporation dissolved: {reason}"

        # Clear crew (they died with the corporation)
        ship.crew = []

        # Ship maintains current trajectory and velocity
        # (position/velocity unchanged - pure physics from here)

        # Equipment stays with ship (salvageable)
        summary["equipment_salvageable"] += len(ship.equipment or [])
        summary["ships_set_adrift"] += 1

        db.add(ship)
        logger.info(
            f"Ship {ship.id} ({ship.ship_name}) set adrift at "
            f"({ship.position_x:.3f}, {ship.position_y:.3f} AU)"
        )

    # 2. Workers: Die with corporation (CASCADE will delete them)
    workers_result = await db.execute(
        select(Worker).where(Worker.player_id == player_id)
    )
    workers = list(workers_result.scalars().all())
    summary["workers_lost"] = len(workers)

    # Log worker deaths
    for worker in workers:
        logger.info(
            f"Worker {worker.id} ({worker.full_name}) lost with corporation {player.username}"
        )

    # 3. Missions: Will be deleted via CASCADE, but ships continue their drift
    missions_result = await db.execute(
        select(Mission).where(Mission.player_id == player_id)
    )
    missions = list(missions_result.scalars().all())

    for mission in missions:
        logger.info(
            f"Mission {mission.id} terminated - ship now drifting"
        )

    # 4. Delete player (CASCADE deletes workers, missions, but ships already updated)
    await db.delete(player)
    await db.commit()

    logger.warning(
        f"Player {player_id} ({player.username}) deleted: "
        f"{summary['ships_set_adrift']} ships adrift, "
        f"{summary['workers_lost']} workers lost. "
        f"Reason: {reason}"
    )

    return summary


async def cleanup_inactive_players(
    db: AsyncSession,
    days_inactive: int = 90,
    dry_run: bool = True
) -> list[dict]:
    """
    Delete players who haven't logged in for specified days.

    Args:
        db: Database session
        days_inactive: Delete after this many days of inactivity
        dry_run: If True, only return what would be deleted

    Returns:
        list[dict]: Summary for each deleted player
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=days_inactive)

    # Find inactive players (exclude admins)
    result = await db.execute(
        select(Player).where(
            Player.last_seen < cutoff,
            Player.is_admin == False  # noqa: E712
        )
    )
    inactive_players = list(result.scalars().all())

    logger.info(
        f"Found {len(inactive_players)} inactive players "
        f"(>{days_inactive} days since last seen)"
    )

    if dry_run:
        summaries = []
        for player in inactive_players:
            # Count what would be affected
            ships = await db.execute(select(Ship).where(Ship.player_id == player.id))
            workers = await db.execute(select(Worker).where(Worker.player_id == player.id))

            summaries.append({
                "dry_run": True,
                "player_id": player.id,
                "username": player.username,
                "last_seen": player.last_seen.isoformat(),
                "days_inactive": (datetime.now(timezone.utc) - player.last_seen).days,
                "ships": len(list(ships.scalars())),
                "workers": len(list(workers.scalars()))
            })
        return summaries

    # Actually delete
    results = []
    for player in inactive_players:
        days = (datetime.now(timezone.utc) - player.last_seen).days
        summary = await delete_player_account(
            db,
            player.id,
            f"Inactive for {days} days"
        )
        results.append(summary)

    return results


async def get_deletion_preview(db: AsyncSession, player_id: int) -> dict:
    """
    Preview what would happen if player account was deleted.

    Args:
        db: Database session
        player_id: Player to preview

    Returns:
        dict: Preview of deletion impact
    """
    player = await db.get(Player, player_id)
    if not player:
        return {"error": "Player not found"}

    ships_result = await db.execute(select(Ship).where(Ship.player_id == player_id))
    ships = list(ships_result.scalars().all())

    workers_result = await db.execute(select(Worker).where(Worker.player_id == player_id))
    workers = list(workers_result.scalars().all())

    missions_result = await db.execute(
        select(Mission).where(Mission.player_id == player_id)
    )
    missions = list(missions_result.scalars().all())

    return {
        "player_id": player_id,
        "username": player.username,
        "email": player.email,
        "created_at": player.created_at.isoformat(),
        "last_seen": player.last_seen.isoformat(),
        "days_since_login": (datetime.now(timezone.utc) - player.last_seen).days,
        "assets": {
            "ships": {
                "count": len(ships),
                "ships": [
                    {
                        "id": s.id,
                        "name": s.ship_name,
                        "position": f"({s.position_x:.2f}, {s.position_y:.2f}) AU",
                        "cargo_capacity": s.cargo_capacity,
                        "equipment_count": len(s.equipment or []),
                        "crew_count": len(s.crew or []),
                        "is_derelict": s.is_derelict,
                        "on_mission": any(m.ship_id == s.id for m in missions)
                    }
                    for s in ships
                ]
            },
            "workers": {
                "count": len(workers),
                "workers": [
                    {
                        "id": w.id,
                        "name": w.full_name,
                        "total_skill": w.pilot_skill + w.engineer_skill + w.mining_skill,
                        "wage": w.wage,
                        "assigned_ship": w.ship_id
                    }
                    for w in workers
                ]
            },
            "missions": {
                "count": len(missions),
                "active_count": sum(1 for m in missions if m.status != "COMPLETED")
            },
            "money": player.money,
            "reputation": player.reputation
        },
        "what_happens": {
            "ships": "Set adrift as derelicts (maintain trajectory, can be salvaged)",
            "workers": "Die with corporation (corporate life support terminated)",
            "equipment": "Remains with derelict ships (salvageable)",
            "missions": "Terminated (ships continue drifting on last trajectory)",
            "money": "Forfeited",
            "account": "Permanently deleted"
        }
    }
