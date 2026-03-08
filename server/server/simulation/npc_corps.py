"""NPC rival corporations — server-side AI competitors in multiplayer.

NPC corps are Player rows with is_npc=True. Their ships are regular Ship rows.
The server tick dispatches them autonomously via process_npc_tick(), so players
encounter and can attack them exactly the same way they attack each other.
No special combat infrastructure needed — /game/attack handles NPC targets
identically to player targets.
"""
from __future__ import annotations

import logging
import math
import random

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload

from server.models.asteroid import Asteroid
from server.models.mission import Mission, MISSION_MINING, STATUS_TRANSIT_OUT
from server.models.player import Player
from server.models.ship import Ship, SHIP_CLASS_STATS, COURIER, PROSPECTOR, HAULER

logger = logging.getLogger(__name__)

AU_TO_KM = 149_597_870.7
G_ACCEL = 9.80665


def _transit_time(dist_au: float, thrust_g: float) -> float:
    dist_m = dist_au * AU_TO_KM * 1000.0
    accel = thrust_g * G_ACCEL
    if accel <= 0 or dist_m <= 0:
        return 0.0
    return 2.0 * math.sqrt(dist_m / accel)


# ── Corp definitions ───────────────────────────────────────────────────────────

NPC_CORPS = [
    {
        "username": "Helios Mining Corp",
        "email": "helios@npc.claim-internal.invalid",
        "ship_count": 3,
        "ship_class": PROSPECTOR,
        "starting_money": 50_000_000,
        "ship_names": ["Solar Flare", "Sunseeker", "Heliosphere"],
    },
    {
        "username": "Apex Industries",
        "email": "apex@npc.claim-internal.invalid",
        "ship_count": 2,
        "ship_class": HAULER,
        "starting_money": 80_000_000,
        "ship_names": ["Iron Colossus", "Apex Prime"],
    },
    {
        "username": "Ironclad Freight",
        "email": "ironclad@npc.claim-internal.invalid",
        "ship_count": 4,
        "ship_class": COURIER,
        "starting_money": 30_000_000,
        "ship_names": ["Rivet", "Keel", "Bolted", "Plating"],
    },
]


# ── Seeding ────────────────────────────────────────────────────────────────────

async def seed_npc_corps(db: AsyncSession) -> None:
    """Create NPC corp accounts and starting ships if they don't already exist. Idempotent."""
    for corp_def in NPC_CORPS:
        result = await db.execute(
            select(Player).where(Player.email == corp_def["email"])
        )
        if result.scalar_one_or_none():
            continue

        npc = Player(
            username=corp_def["username"],
            email=corp_def["email"],
            password_hash="NPC_NO_LOGIN",
            money=corp_def["starting_money"],
            is_npc=True,
        )
        db.add(npc)
        await db.flush()  # get npc.id before creating ships

        stats = SHIP_CLASS_STATS[corp_def["ship_class"]]
        for name in corp_def["ship_names"]:
            ship = Ship(
                player_id=npc.id,
                ship_name=name,
                ship_class=corp_def["ship_class"],
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
                station_colony_id=None,
                current_cargo={},
                supplies={},
                position_x=1.0,
                position_y=0.0,
            )
            db.add(ship)

        await db.commit()
        logger.info(
            "Seeded NPC corp '%s' with %d ships",
            corp_def["username"], len(corp_def["ship_names"])
        )


# ── Post-reset reseeding ───────────────────────────────────────────────────────

async def reseed_npc_ships(db: AsyncSession) -> None:
    """Recreate starting ships for existing NPC corp accounts. Called after world reset."""
    for corp_def in NPC_CORPS:
        result = await db.execute(
            select(Player).where(Player.email == corp_def["email"])
        )
        npc = result.scalar_one_or_none()
        if not npc:
            continue  # Shouldn't happen, but skip if missing

        stats = SHIP_CLASS_STATS[corp_def["ship_class"]]
        for name in corp_def["ship_names"]:
            ship = Ship(
                player_id=npc.id,
                ship_name=name,
                ship_class=corp_def["ship_class"],
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
                station_colony_id=None,
                current_cargo={},
                supplies={},
                position_x=1.0,
                position_y=0.0,
            )
            db.add(ship)

        logger.info("Reseeded ships for NPC corp '%s'", corp_def["username"])


# ── AI tick ────────────────────────────────────────────────────────────────────

_NPC_DECISION_INTERVAL = 3600.0  # Game-seconds between NPC decisions
_npc_accum: float = 0.0


async def process_npc_tick(db: AsyncSession, dt: float) -> list[dict]:
    """
    Drive NPC corp AI each server tick.
    Idle (stationed) NPC ships get dispatched to a random asteroid.
    The existing _process_missions() in tick.py advances their missions for free.
    """
    global _npc_accum
    _npc_accum += dt
    if _npc_accum < _NPC_DECISION_INTERVAL:
        return []
    _npc_accum = 0.0

    result = await db.execute(
        select(Player)
        .where(Player.is_npc == True)  # noqa: E712
        .options(selectinload(Player.ships))
    )
    npc_players = list(result.scalars().all())
    if not npc_players:
        return []

    ast_result = await db.execute(select(Asteroid))
    asteroids = list(ast_result.scalars().all())
    if not asteroids:
        return []

    events: list[dict] = []

    for npc in npc_players:
        for ship in npc.ships:
            if not ship.is_stationed or ship.is_derelict:
                continue

            target = random.choice(asteroids)
            target_x = target.semi_major_axis
            target_y = 0.0
            dist = math.sqrt(
                (target_x - ship.position_x) ** 2 +
                (target_y - ship.position_y) ** 2
            )
            transit_sec = _transit_time(dist, ship.max_thrust_g * ship.thrust_setting)
            fuel_per_tick = (ship.fuel_capacity * 0.001) * ship.thrust_setting

            mission = Mission(
                player_id=npc.id,
                ship_id=ship.id,
                asteroid_id=target.id,
                mission_type=MISSION_MINING,
                status=STATUS_TRANSIT_OUT,
                transit_time=max(transit_sec, 30.0),
                elapsed_ticks=0.0,
                fuel_per_tick=fuel_per_tick,
                origin_x=ship.position_x,
                origin_y=ship.position_y,
                origin_name="Earth",
                origin_is_earth=True,
                destination_x=target_x,
                destination_y=target_y,
                return_to_station=True,
                mining_duration=86400.0,
            )
            db.add(mission)

            ship.is_stationed = False
            ship.fuel = ship.fuel_capacity  # Top up before departure
            db.add(ship)

            logger.info(
                "NPC '%s': dispatched '%s' to asteroid %d (dist=%.2f AU)",
                npc.username, ship.ship_name, target.id, dist
            )

    return events
