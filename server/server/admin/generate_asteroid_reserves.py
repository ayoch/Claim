"""
Generate initial reserves for all asteroids based on realistic mass estimates.

Run this ONCE after the add_asteroid_reserves migration.
"""
import asyncio
import math
import random
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from server.database import async_session_maker
from server.models.asteroid import Asteroid


# Composition by asteroid type (percentages)
COMPOSITION_BY_TYPE = {
    "C-type": {"iron": 8, "nickel": 6, "platinum": 0.01, "water_ice": 20, "silicates": 65},
    "S-type": {"iron": 18, "nickel": 8, "platinum": 0.02, "water_ice": 3, "silicates": 70},
    "M-type": {"iron": 70, "nickel": 20, "platinum": 0.5, "water_ice": 1, "silicates": 8},
    "asteroid": {"iron": 15, "nickel": 7, "platinum": 0.015, "water_ice": 8, "silicates": 68},  # Generic
    "NEO": {"iron": 12, "nickel": 6, "platinum": 0.01, "water_ice": 5, "silicates": 75},
    "trojan": {"iron": 10, "nickel": 5, "platinum": 0.008, "water_ice": 15, "silicates": 68},
    "comet": {"water_ice": 60, "iron": 3, "silicates": 35, "nickel": 1, "platinum": 0.001},
}


def estimate_mass_from_orbit(semi_major_axis: float, body_type: str) -> float:
    """
    Estimate asteroid mass based on orbital distance and type.

    Real asteroids vary wildly, but we use rough estimates:
    - NEOs (near Earth): 1e10 to 1e12 kg (100m - 1km diameter)
    - Main belt: 1e12 to 1e18 kg (1km - 100km diameter)
    - Trojans/outer: 1e15 to 1e19 kg (10km - 200km diameter)
    """
    if body_type.lower() == "neo":
        # Small near-Earth asteroids
        return random.uniform(5e10, 5e12)
    elif body_type.lower() == "comet":
        # Comets are typically smaller, irregular
        return random.uniform(1e10, 1e13)
    elif semi_major_axis < 2.0:
        # Inner belt - smaller asteroids
        return random.uniform(1e12, 1e15)
    elif semi_major_axis < 3.5:
        # Main belt - wide range
        return random.uniform(1e13, 1e17)
    elif body_type.lower() in ("trojan", "centaur"):
        # Trojans and centaurs - larger
        return random.uniform(1e15, 1e18)
    else:
        # Outer system - large but sparse
        return random.uniform(1e14, 1e17)


def calculate_reserves(mass_kg: float, body_type: str) -> tuple[dict, dict]:
    """
    Calculate extractable reserves from asteroid mass and composition.

    Returns (composition_pct, reserves_tonnes)
    """
    # Get composition template for this body type
    composition = COMPOSITION_BY_TYPE.get(body_type.lower(), COMPOSITION_BY_TYPE["asteroid"])

    # Accessibility: only 0.5% to 3% of asteroid mass is economically extractable
    # (rest is too deep, diffuse, or structurally bound)
    accessibility_pct = random.uniform(0.005, 0.03)

    reserves = {}
    for material, pct in composition.items():
        # Calculate total tonnes of this material that's extractable
        total_material_kg = mass_kg * (pct / 100.0)
        extractable_kg = total_material_kg * accessibility_pct
        extractable_tonnes = extractable_kg / 1000.0

        reserves[material] = round(extractable_tonnes, 2)

    return composition, reserves


async def generate_reserves_for_all_asteroids():
    """Generate and save reserves for all asteroids in the database."""
    async with async_session_maker() as db:
        # Get all asteroids
        result = await db.execute(select(Asteroid))
        asteroids = result.scalars().all()

        print(f"Generating reserves for {len(asteroids)} asteroids...")

        for asteroid in asteroids:
            # Skip if reserves already exist
            if asteroid.reserves and len(asteroid.reserves) > 0:
                print(f"  Skipping {asteroid.asteroid_name} (already has reserves)")
                continue

            # Estimate mass
            mass_kg = estimate_mass_from_orbit(asteroid.semi_major_axis, asteroid.body_type)

            # Calculate composition and reserves
            composition, reserves = calculate_reserves(mass_kg, asteroid.body_type)

            # Update asteroid
            asteroid.estimated_mass_kg = mass_kg
            asteroid.composition = composition
            asteroid.reserves = reserves
            asteroid.original_reserves = reserves.copy()  # Store original for UI display

            total_reserves = sum(reserves.values())
            print(f"  ✓ {asteroid.asteroid_name}: {mass_kg:.2e} kg, {total_reserves:,.0f} tonnes extractable")

        # Commit all changes
        await db.commit()
        print(f"\n✓ Generated reserves for {len(asteroids)} asteroids")


async def show_reserve_stats():
    """Display statistics about asteroid reserves."""
    async with async_session_maker() as db:
        result = await db.execute(select(Asteroid))
        asteroids = result.scalars().all()

        total_iron = 0.0
        total_water_ice = 0.0
        total_platinum = 0.0
        total_all = 0.0

        for asteroid in asteroids:
            if not asteroid.reserves:
                continue

            total_iron += asteroid.reserves.get("iron", 0.0)
            total_water_ice += asteroid.reserves.get("water_ice", 0.0)
            total_platinum += asteroid.reserves.get("platinum", 0.0)
            total_all += sum(asteroid.reserves.values())

        print("\n=== Asteroid Reserve Statistics ===")
        print(f"Total asteroids: {len(asteroids)}")
        print(f"Total reserves: {total_all:,.0f} tonnes")
        print(f"  Iron: {total_iron:,.0f} tonnes")
        print(f"  Water ice: {total_water_ice:,.0f} tonnes")
        print(f"  Platinum: {total_platinum:,.0f} tonnes")
        print(f"\nAt 50M tonnes/player capacity: ~{int(total_all / 50_000_000)} players supported")


if __name__ == "__main__":
    print("=== Asteroid Reserve Generator ===\n")
    asyncio.run(generate_reserves_for_all_asteroids())
    asyncio.run(show_reserve_stats())
