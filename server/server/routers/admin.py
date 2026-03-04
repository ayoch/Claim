import random
from fastapi import APIRouter, Depends, HTTPException, Path, Request
from pydantic import BaseModel
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from server.auth import hash_password, require_admin_key
from server.database import get_db, init_db
from server.models.asteroid import Asteroid
from server.models.colony import Colony
from server.models.player import Player
from server.models.ship import Ship, SHIP_CLASS_STATS, PROSPECTOR
from server.models.worker import Worker
from server.rate_limit import limiter
from server.simulation.tick import get_total_ticks

router = APIRouter(prefix="/admin", tags=["admin"], dependencies=[Depends(require_admin_key)])


class AdminPasswordResetRequest(BaseModel):
    username: str
    new_password: str


@router.post("/reset-password")
@limiter.limit("10/hour")
async def admin_reset_password(
    payload: AdminPasswordResetRequest,
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """
    Admin-only password reset (no user authentication required).
    Requires X-Admin-Key header.
    """
    # Validate password strength
    if len(payload.new_password) < 12:
        raise HTTPException(status_code=400, detail="Password must be at least 12 characters")
    if not any(c.isupper() for c in payload.new_password):
        raise HTTPException(status_code=400, detail="Password must contain uppercase letter")
    if not any(c.islower() for c in payload.new_password):
        raise HTTPException(status_code=400, detail="Password must contain lowercase letter")
    if not any(c.isdigit() for c in payload.new_password):
        raise HTTPException(status_code=400, detail="Password must contain number")

    # Find player
    result = await db.execute(select(Player).where(Player.username == payload.username.lower()))
    player = result.scalar_one_or_none()

    if not player:
        raise HTTPException(status_code=404, detail=f"User '{payload.username}' not found")

    # Reset password
    player.password_hash = hash_password(payload.new_password)
    db.add(player)
    await db.commit()

    return {
        "message": f"Password reset for user '{player.username}'",
        "is_admin": player.is_admin
    }


@router.post("/grant-admin/{username}")
@limiter.limit("5/hour")
async def grant_admin(
    username: str,
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """
    Grant admin privileges to a user (requires X-Admin-Key header).
    """
    result = await db.execute(select(Player).where(Player.username == username.lower()))
    player = result.scalar_one_or_none()

    if not player:
        raise HTTPException(status_code=404, detail=f"User '{username}' not found")

    player.is_admin = True
    db.add(player)
    await db.commit()

    return {
        "message": f"Admin privileges granted to '{player.username}'",
        "is_admin": player.is_admin
    }


@router.get("/status")
@limiter.limit("10/minute")
async def server_status(
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """Get server status metrics (admin only)."""
    player_count = (await db.execute(select(func.count(Player.id)))).scalar_one()
    ship_count = (await db.execute(select(func.count(Ship.id)))).scalar_one()
    asteroid_count = (await db.execute(select(func.count(Asteroid.id)))).scalar_one()
    return {
        "status": "running",
        "total_ticks": get_total_ticks(),
        "player_count": player_count,
        "ship_count": ship_count,
        "asteroid_count": asteroid_count,
    }


def _colony_seed_data() -> list[dict]:
    return [
        {"colony_name": "Ceres Station", "planet_id": "ceres",
         "price_multipliers": {"nickel": 1.2, "iron": 1.1}},
        {"colony_name": "Mars Gateway", "planet_id": "mars",
         "price_multipliers": {"water_ice": 1.8, "carbon": 1.3}},
        {"colony_name": "Luna Base", "planet_id": "luna",
         "price_multipliers": {"platinum": 1.5, "gold": 1.4}},
        {"colony_name": "Europa Outpost", "planet_id": "europa",
         "price_multipliers": {"water_ice": 2.0}},
        {"colony_name": "Vesta Depot", "planet_id": "vesta",
         "price_multipliers": {"iron": 1.3, "cobalt": 1.2}},
        {"colony_name": "Jupiter L4", "planet_id": "jupiter_l4",
         "price_multipliers": {"troilite": 1.5, "olivine": 1.3}},
        {"colony_name": "Jupiter L5", "planet_id": "jupiter_l5",
         "price_multipliers": {"pyroxene": 1.4, "silicon": 1.2}},
        {"colony_name": "Psyche Station", "planet_id": "psyche",
         "price_multipliers": {"nickel": 1.6, "palladium": 1.3}},
        {"colony_name": "Hygiea Base", "planet_id": "hygiea",
         "price_multipliers": {"cobalt": 1.5, "carbon": 1.2}},
    ]


def _asteroid_seed_data() -> list[dict]:
    ep = 2451545.0  # J2000
    return [
        {"asteroid_name": "1 Ceres", "body_type": "dwarf_planet",
         "semi_major_axis": 2.7675, "eccentricity": 0.0758, "inclination": 10.59,
         "long_ascending_node": 80.33, "arg_perihelion": 73.60,
         "mean_anomaly_at_epoch": 77.37, "epoch_jd": ep, "max_mining_slots": 8,
         "ore_yields": {"nickel": 180, "iron": 120, "carbon": 60}},
        {"asteroid_name": "4 Vesta", "body_type": "asteroid",
         "semi_major_axis": 2.3615, "eccentricity": 0.0887, "inclination": 7.14,
         "long_ascending_node": 103.85, "arg_perihelion": 149.84,
         "mean_anomaly_at_epoch": 20.86, "epoch_jd": ep, "max_mining_slots": 6,
         "ore_yields": {"iron": 200, "cobalt": 40, "pyroxene": 80}},
        {"asteroid_name": "2 Pallas", "body_type": "asteroid",
         "semi_major_axis": 2.7736, "eccentricity": 0.2302, "inclination": 34.84,
         "long_ascending_node": 173.09, "arg_perihelion": 310.03,
         "mean_anomaly_at_epoch": 78.22, "epoch_jd": ep, "max_mining_slots": 5,
         "ore_yields": {"silicon": 150, "carbon": 90, "olivine": 70}},
        {"asteroid_name": "10 Hygiea", "body_type": "asteroid",
         "semi_major_axis": 3.1415, "eccentricity": 0.1177, "inclination": 3.84,
         "long_ascending_node": 283.20, "arg_perihelion": 312.32,
         "mean_anomaly_at_epoch": 114.44, "epoch_jd": ep, "max_mining_slots": 5,
         "ore_yields": {"carbon": 120, "cobalt": 55, "troilite": 40}},
        {"asteroid_name": "16 Psyche", "body_type": "M-type",
         "semi_major_axis": 2.9215, "eccentricity": 0.1340, "inclination": 3.10,
         "long_ascending_node": 150.22, "arg_perihelion": 228.04,
         "mean_anomaly_at_epoch": 190.40, "epoch_jd": ep, "max_mining_slots": 7,
         "ore_yields": {"nickel": 240, "iron": 180, "palladium": 8, "gold": 4}},
        {"asteroid_name": "433 Eros", "body_type": "NEO",
         "semi_major_axis": 1.4580, "eccentricity": 0.2229, "inclination": 10.83,
         "long_ascending_node": 304.35, "arg_perihelion": 178.64,
         "mean_anomaly_at_epoch": 208.12, "epoch_jd": ep, "max_mining_slots": 4,
         "ore_yields": {"nickel": 100, "iron": 80, "silicon": 50}},
        {"asteroid_name": "25143 Itokawa", "body_type": "NEO",
         "semi_major_axis": 1.3241, "eccentricity": 0.2799, "inclination": 1.62,
         "long_ascending_node": 69.08, "arg_perihelion": 162.82,
         "mean_anomaly_at_epoch": 345.02, "epoch_jd": ep, "max_mining_slots": 3,
         "ore_yields": {"olivine": 90, "pyroxene": 60, "iron": 40}},
        {"asteroid_name": "1036 Ganymed", "body_type": "NEO",
         "semi_major_axis": 2.6629, "eccentricity": 0.5337, "inclination": 26.67,
         "long_ascending_node": 215.47, "arg_perihelion": 132.35,
         "mean_anomaly_at_epoch": 0.42, "epoch_jd": ep, "max_mining_slots": 4,
         "ore_yields": {"carbon": 80, "silicon": 70, "troilite": 30}},
        {"asteroid_name": "3200 Phaethon", "body_type": "NEO",
         "semi_major_axis": 1.2713, "eccentricity": 0.8898, "inclination": 22.26,
         "long_ascending_node": 265.22, "arg_perihelion": 322.18,
         "mean_anomaly_at_epoch": 32.51, "epoch_jd": ep, "max_mining_slots": 3,
         "ore_yields": {"carbon": 60, "olivine": 50}},
        {"asteroid_name": "624 Hektor", "body_type": "trojan",
         "semi_major_axis": 5.2340, "eccentricity": 0.0238, "inclination": 18.18,
         "long_ascending_node": 342.55, "arg_perihelion": 178.97,
         "mean_anomaly_at_epoch": 265.01, "epoch_jd": ep, "max_mining_slots": 6,
         "ore_yields": {"pyroxene": 140, "olivine": 110, "carbon": 90, "troilite": 60}},
        {"asteroid_name": "588 Achilles", "body_type": "trojan",
         "semi_major_axis": 5.2040, "eccentricity": 0.1480, "inclination": 10.33,
         "long_ascending_node": 316.75, "arg_perihelion": 324.50,
         "mean_anomaly_at_epoch": 180.36, "epoch_jd": ep, "max_mining_slots": 5,
         "ore_yields": {"olivine": 120, "pyroxene": 80, "carbon": 70}},
        {"asteroid_name": "52 Europa", "body_type": "asteroid",
         "semi_major_axis": 3.0972, "eccentricity": 0.1009, "inclination": 7.46,
         "long_ascending_node": 128.71, "arg_perihelion": 343.50,
         "mean_anomaly_at_epoch": 269.70, "epoch_jd": ep, "max_mining_slots": 5,
         "ore_yields": {"carbon": 100, "water_ice": 80, "silicon": 50}},
        {"asteroid_name": "511 Davida", "body_type": "C-type",
         "semi_major_axis": 3.1776, "eccentricity": 0.1780, "inclination": 15.93,
         "long_ascending_node": 107.36, "arg_perihelion": 339.35,
         "mean_anomaly_at_epoch": 93.20, "epoch_jd": ep, "max_mining_slots": 6,
         "ore_yields": {"carbon": 160, "water_ice": 120, "cobalt": 35}},
        {"asteroid_name": "87 Sylvia", "body_type": "asteroid",
         "semi_major_axis": 3.4905, "eccentricity": 0.0804, "inclination": 10.86,
         "long_ascending_node": 73.38, "arg_perihelion": 266.17,
         "mean_anomaly_at_epoch": 82.31, "epoch_jd": ep, "max_mining_slots": 5,
         "ore_yields": {"silicon": 110, "olivine": 90, "carbon": 60}},
        {"asteroid_name": "65803 Didymos", "body_type": "NEO",
         "semi_major_axis": 1.6444, "eccentricity": 0.3835, "inclination": 3.41,
         "long_ascending_node": 73.22, "arg_perihelion": 319.32,
         "mean_anomaly_at_epoch": 55.64, "epoch_jd": ep, "max_mining_slots": 3,
         "ore_yields": {"nickel": 70, "iron": 55, "troilite": 25}},
        {"asteroid_name": "101955 Bennu", "body_type": "NEO",
         "semi_major_axis": 1.1264, "eccentricity": 0.2037, "inclination": 6.03,
         "long_ascending_node": 2.06, "arg_perihelion": 66.22,
         "mean_anomaly_at_epoch": 101.70, "epoch_jd": ep, "max_mining_slots": 3,
         "ore_yields": {"carbon": 90, "water_ice": 50, "olivine": 40}},
        {"asteroid_name": "21 Lutetia", "body_type": "M-type",
         "semi_major_axis": 2.4353, "eccentricity": 0.1631, "inclination": 3.06,
         "long_ascending_node": 80.88, "arg_perihelion": 250.17,
         "mean_anomaly_at_epoch": 300.52, "epoch_jd": ep, "max_mining_slots": 5,
         "ore_yields": {"nickel": 130, "iron": 100, "cobalt": 30, "palladium": 4}},
        {"asteroid_name": "704 Interamnia", "body_type": "F-type",
         "semi_major_axis": 3.0601, "eccentricity": 0.1531, "inclination": 17.31,
         "long_ascending_node": 280.39, "arg_perihelion": 93.99,
         "mean_anomaly_at_epoch": 346.24, "epoch_jd": ep, "max_mining_slots": 5,
         "ore_yields": {"carbon": 130, "silicon": 80, "water_ice": 55}},
        {"asteroid_name": "45 Eugenia", "body_type": "C-type",
         "semi_major_axis": 2.7214, "eccentricity": 0.0828, "inclination": 6.61,
         "long_ascending_node": 147.88, "arg_perihelion": 86.79,
         "mean_anomaly_at_epoch": 66.40, "epoch_jd": ep, "max_mining_slots": 4,
         "ore_yields": {"water_ice": 90, "carbon": 70, "troilite": 35}},
        {"asteroid_name": "7 Iris", "body_type": "S-type",
         "semi_major_axis": 2.3862, "eccentricity": 0.2296, "inclination": 5.52,
         "long_ascending_node": 259.50, "arg_perihelion": 144.89,
         "mean_anomaly_at_epoch": 238.91, "epoch_jd": ep, "max_mining_slots": 4,
         "ore_yields": {"olivine": 100, "pyroxene": 80, "silicon": 60, "nickel": 45}},
    ]


@router.post("/seed")
@limiter.limit("1/minute")
async def seed(
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """Idempotent seed: insert colonies and asteroids if not already present (admin only)."""
    await init_db()
    seeded = {"colonies": 0, "asteroids": 0}

    for cd in _colony_seed_data():
        exists = (await db.execute(
            select(Colony).where(Colony.colony_name == cd["colony_name"])
        )).scalar_one_or_none()
        if not exists:
            db.add(Colony(**cd))
            seeded["colonies"] += 1
    await db.commit()

    for ad in _asteroid_seed_data():
        exists = (await db.execute(
            select(Asteroid).where(Asteroid.asteroid_name == ad["asteroid_name"])
        )).scalar_one_or_none()
        if not exists:
            db.add(Asteroid(**ad))
            seeded["asteroids"] += 1
    await db.commit()
    return {"seeded": seeded, "message": "Seed complete"}


@router.post("/give-starter-pack/{player_id}")
@limiter.limit("5/hour")
async def give_starter_pack(
    request: Request,
    player_id: int = Path(..., ge=1, le=1_000_000, description="Player ID (1-1000000)"),
    db: AsyncSession = Depends(get_db)
):
    """Give a player their starting Prospector + 3 workers. Idempotent (admin only)."""
    player = (await db.execute(
        select(Player).where(Player.id == player_id)
    )).scalar_one_or_none()
    if not player:
        raise HTTPException(status_code=404, detail="Player not found")

    colony = (await db.execute(
        select(Colony).where(Colony.planet_id == "luna")
    )).scalar_one_or_none()
    if not colony:
        colony = (await db.execute(select(Colony))).scalars().first()
    if not colony:
        raise HTTPException(status_code=400, detail="No colonies seeded. Run /admin/seed first.")

    existing = (await db.execute(
        select(Ship).where(Ship.player_id == player_id)
    )).scalar_one_or_none()
    if existing:
        return {"message": "Player already has ships", "ship_id": existing.id}

    stats = SHIP_CLASS_STATS[PROSPECTOR]
    ship = Ship(
        player_id=player_id,
        ship_name="Perseverance",
        ship_class=PROSPECTOR,
        max_thrust_g=stats["max_thrust_g"],
        thrust_setting=1.0,
        cargo_capacity=stats["cargo_capacity"],
        cargo_volume=stats["cargo_volume"],
        fuel_capacity=stats["fuel_capacity"],
        fuel=stats["fuel_capacity"],
        base_mass=stats["base_mass"],
        min_crew=stats["min_crew"],
        max_equipment_slots=stats["max_equipment_slots"],
        is_stationed=True,
        station_colony_id=colony.id,
        position_x=1.0,
        position_y=0.0,
        current_cargo={},
        supplies={"food": 30.0, "repair_parts": 5.0},
    )
    db.add(ship)
    await db.flush()

    FIRST_NAMES = ["Alex", "Sam", "Jordan", "Casey", "Morgan"]
    LAST_NAMES = ["Chen", "Okafor", "Petrov", "Nakamura", "Singh"]
    for i in range(3):
        w = Worker(
            player_id=player_id,
            first_name=FIRST_NAMES[i],
            last_name=LAST_NAMES[i],
            pilot_skill=round(random.uniform(0.4, 0.7), 2),
            engineer_skill=round(random.uniform(0.4, 0.7), 2),
            mining_skill=round(random.uniform(0.5, 0.8), 2),
            wage=random.randint(800, 1400),
            loyalty=round(random.uniform(45.0, 65.0), 1),
            fatigue=0.0,
            personality=2,
            assigned_ship_id=ship.id,
            is_available=True,
        )
        db.add(w)

    player.hq_colony_id = colony.id
    db.add(player)
    await db.commit()
    return {"message": "Starter pack granted", "ship_id": ship.id, "colony_id": colony.id}


# ══════════════════════════════════════════════════════════════════════════════
# ACCOUNT DELETION
# ══════════════════════════════════════════════════════════════════════════════

from server.admin.account_deletion import (
    delete_player_account,
    cleanup_inactive_players,
    get_deletion_preview
)


@router.get("/players/{player_id}/deletion-preview")
@limiter.limit("30/minute")
async def preview_player_deletion(
    player_id: int,
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """
    Preview what would happen if a player account was deleted.

    Shows ships, workers, equipment, missions that would be affected.
    """
    preview = await get_deletion_preview(db, player_id)

    if "error" in preview:
        raise HTTPException(status_code=404, detail=preview["error"])

    return preview


@router.delete("/players/{player_id}")
@limiter.limit("10/minute")
async def delete_player(
    player_id: int,
    reason: str = "Admin action",
    request: Request = None,
    db: AsyncSession = Depends(get_db)
):
    """
    Delete a player account.

    Ships become derelict (maintain trajectory), workers die.

    Lore: The Whisper (mysterious deep space disease) claims the
    corporation's workers, and ships drift on as ghost vessels.
    """
    summary = await delete_player_account(db, player_id, reason)

    if not summary.get("success"):
        raise HTTPException(status_code=404, detail=summary.get("error", "Unknown error"))

    return summary


@router.post("/cleanup-inactive")
@limiter.limit("5/hour")
async def cleanup_inactive(
    days_inactive: int = 90,
    dry_run: bool = True,
    request: Request = None,
    db: AsyncSession = Depends(get_db)
):
    """
    Delete inactive player accounts.

    Removes players who haven't logged in for specified days.
    Use dry_run=true to preview without deleting.
    """
    results = await cleanup_inactive_players(db, days_inactive, dry_run)

    return {
        "dry_run": dry_run,
        "days_inactive_threshold": days_inactive,
        "players_affected": len(results),
        "results": results
    }


@router.get("/server-stats")
@limiter.limit("60/minute")
async def get_server_stats(request: Request, db: AsyncSession = Depends(get_db)):
    """Get server statistics (players, ships, workers, derelicts)."""
    from server.models.mission import Mission

    total_players = await db.scalar(select(func.count()).select_from(Player))
    total_ships = await db.scalar(select(func.count()).select_from(Ship))
    total_workers = await db.scalar(select(func.count()).select_from(Worker))
    total_missions = await db.scalar(select(func.count()).select_from(Mission))

    # Active players (last 7 days)
    from datetime import datetime, timedelta, timezone
    cutoff = datetime.now(timezone.utc) - timedelta(days=7)
    active_players = await db.scalar(
        select(func.count()).select_from(Player).where(Player.last_seen >= cutoff)
    )

    # Derelict/ownerless ships
    derelict_ships = await db.scalar(
        select(func.count()).select_from(Ship).where(Ship.is_derelict == True)  # noqa: E712
    )
    ownerless_ships = await db.scalar(
        select(func.count()).select_from(Ship).where(Ship.player_id == None)  # noqa: E711
    )

    return {
        "players": {
            "total": total_players,
            "active_7d": active_players,
            "inactive_7d": total_players - active_players
        },
        "ships": {
            "total": total_ships,
            "derelict": derelict_ships,
            "ownerless": ownerless_ships,
            "active": total_ships - derelict_ships
        },
        "workers": {"total": total_workers},
        "missions": {"total": total_missions}
    }


@router.get("/server-capacity")
@limiter.limit("60/minute")
async def get_server_capacity(request: Request, db: AsyncSession = Depends(get_db)):
    """
    Check server capacity based on asteroid reserves and active players.

    Returns whether new players can join based on resource availability.
    """
    from datetime import datetime, timedelta, timezone

    # Count active players (logged in within last 30 days)
    cutoff = datetime.now(timezone.utc) - timedelta(days=30)
    active_players = await db.scalar(
        select(func.count()).select_from(Player).where(Player.last_seen >= cutoff)
    )

    # Calculate total remaining reserves across all asteroids
    result = await db.execute(select(Asteroid))
    asteroids = result.scalars().all()

    total_reserves = 0.0
    total_iron = 0.0
    total_water_ice = 0.0

    for asteroid in asteroids:
        if not asteroid.reserves:
            continue
        total_reserves += sum(asteroid.reserves.values())
        total_iron += asteroid.reserves.get("iron", 0.0)
        total_water_ice += asteroid.reserves.get("water_ice", 0.0)

    # Minimum reserves per player threshold (50 million tonnes)
    MINIMUM_RESERVES_PER_PLAYER = 50_000_000

    # Calculate available slots
    max_players = int(total_reserves / MINIMUM_RESERVES_PER_PLAYER) if total_reserves > 0 else 0
    slots_available = max(0, max_players - active_players)
    reserves_per_player = total_reserves / max(active_players, 1)

    can_join = slots_available > 0

    return {
        "can_join": can_join,
        "active_players": active_players,
        "max_players": max_players,
        "slots_available": slots_available,
        "total_reserves_tonnes": round(total_reserves, 2),
        "reserves_per_player_tonnes": round(reserves_per_player, 2),
        "reserves_by_type": {
            "iron": round(total_iron, 2),
            "water_ice": round(total_water_ice, 2)
        },
        "message": "Server accepting new players" if can_join else "Server at capacity - no slots available"
    }


@router.post("/generate-reserves")
@limiter.limit("1/hour")
async def generate_asteroid_reserves(
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """
    Generate initial reserves for all asteroids.

    Only needs to be run once. Checks if reserves already exist before generating.
    """
    import random

    # Check if reserves already generated
    result = await db.execute(select(Asteroid).limit(10))
    sample_asteroids = result.scalars().all()

    has_reserves = any(a.reserves and len(a.reserves) > 0 for a in sample_asteroids)
    if has_reserves:
        return {
            "status": "already_generated",
            "message": "Asteroid reserves already exist. Not regenerating."
        }

    # Composition by asteroid type
    COMPOSITION_BY_TYPE = {
        "C-type": {"iron": 8, "nickel": 6, "platinum": 0.01, "water_ice": 20, "silicates": 65},
        "S-type": {"iron": 18, "nickel": 8, "platinum": 0.02, "water_ice": 3, "silicates": 70},
        "M-type": {"iron": 70, "nickel": 20, "platinum": 0.5, "water_ice": 1, "silicates": 8},
        "asteroid": {"iron": 15, "nickel": 7, "platinum": 0.015, "water_ice": 8, "silicates": 68},
        "NEO": {"iron": 12, "nickel": 6, "platinum": 0.01, "water_ice": 5, "silicates": 75},
        "trojan": {"iron": 10, "nickel": 5, "platinum": 0.008, "water_ice": 15, "silicates": 68},
        "comet": {"water_ice": 60, "iron": 3, "silicates": 35, "nickel": 1, "platinum": 0.001},
    }

    def estimate_mass(semi_major_axis: float, body_type: str) -> float:
        if body_type.lower() == "neo":
            return random.uniform(5e10, 5e12)
        elif body_type.lower() == "comet":
            return random.uniform(1e10, 1e13)
        elif semi_major_axis < 2.0:
            return random.uniform(1e12, 1e15)
        elif semi_major_axis < 3.5:
            return random.uniform(1e13, 1e17)
        elif body_type.lower() in ("trojan", "centaur"):
            return random.uniform(1e15, 1e18)
        else:
            return random.uniform(1e14, 1e17)

    # Get all asteroids
    result = await db.execute(select(Asteroid))
    asteroids = result.scalars().all()

    generated_count = 0
    for asteroid in asteroids:
        if asteroid.reserves and len(asteroid.reserves) > 0:
            continue  # Skip if already has reserves

        # Estimate mass
        mass_kg = estimate_mass(asteroid.semi_major_axis, asteroid.body_type)

        # Get composition
        composition = COMPOSITION_BY_TYPE.get(asteroid.body_type.lower(), COMPOSITION_BY_TYPE["asteroid"])

        # Calculate extractable reserves (0.5-3% of total mass)
        accessibility_pct = random.uniform(0.005, 0.03)

        reserves = {}
        for material, pct in composition.items():
            total_material_kg = mass_kg * (pct / 100.0)
            extractable_kg = total_material_kg * accessibility_pct
            extractable_tonnes = extractable_kg / 1000.0
            reserves[material] = round(extractable_tonnes, 2)

        # Update asteroid
        asteroid.estimated_mass_kg = mass_kg
        asteroid.composition = composition
        asteroid.reserves = reserves
        asteroid.original_reserves = reserves.copy()
        generated_count += 1

    await db.commit()

    # Calculate totals
    result = await db.execute(select(Asteroid))
    all_asteroids = result.scalars().all()
    total_reserves = sum(sum(a.reserves.values()) for a in all_asteroids if a.reserves)

    return {
        "status": "success",
        "asteroids_updated": generated_count,
        "total_asteroids": len(asteroids),
        "total_reserves_tonnes": round(total_reserves, 2),
        "message": f"Generated reserves for {generated_count} asteroids"
    }


@router.post("/spawn-workers")
@limiter.limit("10/minute")
async def spawn_available_workers(
    request: Request,
    count: int = 10,
    db: AsyncSession = Depends(get_db)
):
    """
    Spawn workers available for hire (player_id = NULL).
    Creates random workers in the labor pool.
    """
    FIRST_NAMES = ["Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Avery", "Quinn", "Reese", "Skyler"]
    LAST_NAMES = ["Chen", "Patel", "Smith", "Garcia", "Kim", "Johnson", "Rodriguez", "Martinez", "Lee", "Davis"]

    HOME_COLONIES = ["Earth", "Lunar Base", "Mars Colony", "Ceres Station", "Europa Lab"]
    PERSONALITIES = [0, 1, 2, 3, 4]  # Cautious, Balanced, Bold, Greedy, Loyal

    spawned = []

    for _ in range(count):
        # Generate random skills
        skills = [0, 1, 2]  # pilot, engineer, mining
        random.shuffle(skills)

        primary_skill = skills[0]
        secondary_skill = skills[1]
        tertiary_skill = skills[2]

        pilot_val = 0.0
        engineer_val = 0.0
        mining_val = 0.0

        primary_val = round(random.uniform(0.8, 1.5), 2)
        secondary_val = round(random.uniform(0.4, 0.9), 2)
        tertiary_val = round(random.uniform(0.0, 0.3), 2)

        if primary_skill == 0:
            pilot_val = primary_val
        elif primary_skill == 1:
            engineer_val = primary_val
        else:
            mining_val = primary_val

        if secondary_skill == 0:
            pilot_val = secondary_val
        elif secondary_skill == 1:
            engineer_val = secondary_val
        else:
            mining_val = secondary_val

        if tertiary_skill == 0:
            pilot_val = tertiary_val
        elif tertiary_skill == 1:
            engineer_val = tertiary_val
        else:
            mining_val = tertiary_val

        # Calculate wage based on total skill
        total_skill = pilot_val + engineer_val + mining_val
        base_wage = 80
        skill_bonus = int(total_skill * 40)
        wage = base_wage + skill_bonus

        worker = Worker(
            player_id=None,  # Available for hire
            first_name=random.choice(FIRST_NAMES),
            last_name=random.choice(LAST_NAMES),
            pilot_skill=pilot_val,
            engineer_skill=engineer_val,
            mining_skill=mining_val,
            wage=wage,
            personality=random.choice(PERSONALITIES)
        )

        db.add(worker)
        spawned.append({
            "name": f"{worker.first_name} {worker.last_name}",
            "pilot": pilot_val,
            "engineer": engineer_val,
            "mining": mining_val,
            "wage": wage
        })

    await db.commit()

    return {
        "status": "success",
        "workers_spawned": len(spawned),
        "workers": spawned
    }
