"""
Standalone seed script.

Run from the server/ directory:
    python seed.py

Or from the project root:
    python server/seed.py

Requires DATABASE_URL to be set (via .env or environment).
"""
from __future__ import annotations

import asyncio
import sys
from pathlib import Path

# Ensure the server package is importable when run as a script
sys.path.insert(0, str(Path(__file__).parent))

from server.database import AsyncSessionLocal, init_db
from server.routers.admin import _asteroid_seed_data, _colony_seed_data
from server.models.asteroid import Asteroid
from server.models.colony import Colony
from server.models.player import Player
from server.models.ship import Ship, SHIP_CLASS_STATS, PROSPECTOR
from server.models.worker import Worker
from sqlalchemy import select
import random


async def seed_all() -> None:
    print("Initialising database tables...")
    await init_db()

    async with AsyncSessionLocal() as db:
        # Colonies
        colonies_added = 0
        for cd in _colony_seed_data():
            exists = (await db.execute(
                select(Colony).where(Colony.colony_name == cd["colony_name"])
            )).scalar_one_or_none()
            if not exists:
                db.add(Colony(**cd))
                colonies_added += 1
        await db.commit()
        print(f"Colonies: {colonies_added} added")

        # Asteroids
        asteroids_added = 0
        for ad in _asteroid_seed_data():
            exists = (await db.execute(
                select(Asteroid).where(Asteroid.asteroid_name == ad["asteroid_name"])
            )).scalar_one_or_none()
            if not exists:
                db.add(Asteroid(**ad))
                asteroids_added += 1
        await db.commit()
        print(f"Asteroids: {asteroids_added} added")

        # Default player if none exists
        player_count = (await db.execute(
            select(Player)
        )).scalars().all()

        if not player_count:
            from server.auth import hash_password
            print("Creating default player 'player1' (password: 'test')...")
            player = Player(
                username="player1",
                password_hash=hash_password("test"),
                money=14_000_000,
            )
            db.add(player)
            await db.flush()

            # Starter ship
            colony = (await db.execute(
                select(Colony).where(Colony.planet_id == "luna")
            )).scalar_one_or_none()
            if not colony:
                colony = (await db.execute(select(Colony))).scalars().first()

            stats = SHIP_CLASS_STATS[PROSPECTOR]
            ship = Ship(
                player_id=player.id,
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
                station_colony_id=colony.id if colony else None,
                position_x=1.0,
                position_y=0.0,
                current_cargo={},
                supplies={"food": 30.0, "repair_parts": 5.0},
            )
            db.add(ship)
            await db.flush()

            FIRST_NAMES = ["Alex", "Sam", "Jordan"]
            LAST_NAMES = ["Chen", "Okafor", "Petrov"]
            for i in range(3):
                w = Worker(
                    player_id=player.id,
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

            if colony:
                player.hq_colony_id = colony.id

            await db.commit()
            print("Default player created with starter ship and 3 workers.")
        else:
            print(f"Players already exist ({len(player_count)}), skipping default player creation.")

    print("Seed complete.")


if __name__ == "__main__":
    asyncio.run(seed_all())
