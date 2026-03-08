"""World setup utilities — reserve generation and other one-time world init tasks."""
from __future__ import annotations

import random
import logging

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from server.models.asteroid import Asteroid

logger = logging.getLogger(__name__)

COMPOSITION_BY_TYPE: dict[str, dict[str, float]] = {
    "C-type":   {"iron": 8,  "nickel": 6,  "platinum": 0.01,  "water_ice": 20, "silicates": 65},
    "S-type":   {"iron": 18, "nickel": 8,  "platinum": 0.02,  "water_ice": 3,  "silicates": 70},
    "M-type":   {"iron": 70, "nickel": 20, "platinum": 0.5,   "water_ice": 1,  "silicates": 8},
    "asteroid": {"iron": 15, "nickel": 7,  "platinum": 0.015, "water_ice": 8,  "silicates": 68},
    "NEO":      {"iron": 12, "nickel": 6,  "platinum": 0.01,  "water_ice": 5,  "silicates": 75},
    "trojan":   {"iron": 10, "nickel": 5,  "platinum": 0.008, "water_ice": 15, "silicates": 68},
    "comet":    {"water_ice": 60, "iron": 3, "silicates": 35, "nickel": 1,     "platinum": 0.001},
}


def _estimate_mass(semi_major_axis: float, body_type: str) -> float:
    bt = body_type.lower()
    if bt == "neo":
        return random.uniform(5e10, 5e12)
    elif bt == "comet":
        return random.uniform(1e10, 1e13)
    elif semi_major_axis < 2.0:
        return random.uniform(1e12, 1e15)
    elif semi_major_axis < 3.5:
        return random.uniform(1e13, 1e17)
    elif bt in ("trojan", "centaur"):
        return random.uniform(1e15, 1e18)
    else:
        return random.uniform(1e14, 1e17)


async def generate_reserves(db: AsyncSession, force: bool = False) -> dict:
    """
    Generate (or regenerate) ore reserves for all asteroids.

    By default only fills asteroids that have empty reserves.
    Pass force=True to regenerate all (used after world reset).
    Returns a summary dict.
    """
    result = await db.execute(select(Asteroid))
    asteroids = result.scalars().all()

    if not force:
        has_reserves = any(a.reserves and len(a.reserves) > 0 for a in asteroids)
        if has_reserves:
            return {"status": "already_generated", "count": 0}

    generated = 0
    for asteroid in asteroids:
        if not force and asteroid.reserves and len(asteroid.reserves) > 0:
            continue

        mass_kg = _estimate_mass(asteroid.semi_major_axis, asteroid.body_type)
        composition = COMPOSITION_BY_TYPE.get(
            asteroid.body_type.lower(), COMPOSITION_BY_TYPE["asteroid"]
        )
        accessibility = random.uniform(0.005, 0.03)

        reserves = {
            material: round(mass_kg * (pct / 100.0) * accessibility / 1000.0, 2)
            for material, pct in composition.items()
        }

        asteroid.estimated_mass_kg = mass_kg
        asteroid.composition = composition
        asteroid.reserves = reserves
        asteroid.original_reserves = reserves.copy()
        db.add(asteroid)
        generated += 1

    await db.commit()

    all_result = await db.execute(select(Asteroid))
    all_asteroids = all_result.scalars().all()
    total = sum(sum(a.reserves.values()) for a in all_asteroids if a.reserves)

    logger.info("generate_reserves: %d asteroids, %.0f total tonnes", generated, total)
    return {
        "status": "success",
        "count": generated,
        "total_tonnes": round(total, 2),
    }
