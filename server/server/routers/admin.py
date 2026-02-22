from __future__ import annotations
import random
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from server.database import get_db, init_db
from server.models.asteroid import Asteroid
from server.models.colony import Colony
from server.models.player import Player
from server.models.ship import Ship, SHIP_CLASS_STATS, PROSPECTOR
from server.models.worker import Worker
from server.simulation.tick import get_total_ticks

router = APIRouter(prefix="/admin", tags=["admin"])


@router.get("/status")
async def server_status(db: AsyncSession = Depends(get_db)):
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
async def seed(db: AsyncSession = Depends(get_db)):
    """Idempotent seed: insert colonies and asteroids if not already present."""
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
async def give_starter_pack(player_id: int, db: AsyncSession = Depends(get_db)):
    """Give a player their starting Prospector + 3 workers. Idempotent."""
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
