from __future__ import annotations
import math
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from server.auth import get_current_player
from server.database import get_db
from server.models.asteroid import Asteroid
from server.models.colony import Colony
from server.models.mission import Mission, STATUS_TRANSIT_OUT
from server.models.player import Player
from server.models.ship import Ship, SHIP_CLASS_STATS
from server.models.worker import Worker
from server.schemas.game import (
    AsteroidOut, BuyShipRequest, ColonyOut, DispatchRequest,
    GameState, HireRequest, MissionOut, ShipOut, WorkerOut,
)
from server.schemas.player import PolicyUpdate
from server.simulation.tick import get_market_prices

router = APIRouter(prefix="/game", tags=["game"])

AU_TO_KM = 149_597_870.7
G_ACCEL = 9.80665


def _transit_time_seconds(dist_au: float, thrust_g: float) -> float:
    dist_m = dist_au * AU_TO_KM * 1000.0
    accel = thrust_g * G_ACCEL
    if accel <= 0 or dist_m <= 0:
        return 0.0
    return 2.0 * math.sqrt(dist_m / accel)

@router.get("/state", response_model=GameState)
async def get_state(
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(select(Mission).where(
        Mission.player_id == player.id,
        Mission.status.in_([0, 1, 2]),
    ))
    active_missions = list(result.scalars().all())
    return GameState(
        player_id=player.id,
        username=player.username,
        money=player.money,
        reputation=player.reputation,
        thrust_policy=player.thrust_policy,
        supply_policy=player.supply_policy,
        collection_policy=player.collection_policy,
        encounter_policy=player.encounter_policy,
        ships=[ShipOut.model_validate(s) for s in player.ships],
        workers=[WorkerOut.model_validate(w) for w in player.workers],
        active_missions=[MissionOut.model_validate(m) for m in active_missions],
    )

@router.post("/dispatch", response_model=MissionOut, status_code=status.HTTP_201_CREATED)
async def dispatch(
    req: DispatchRequest,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    ship_result = await db.execute(
        select(Ship).where(Ship.id == req.ship_id, Ship.player_id == player.id)
    )
    ship = ship_result.scalar_one_or_none()
    if not ship:
        raise HTTPException(status_code=404, detail="Ship not found")
    if not ship.is_stationed:
        raise HTTPException(status_code=409, detail="Ship is already on a mission")
    if ship.is_derelict:
        raise HTTPException(status_code=409, detail="Ship is derelict")
    asteroid = None
    origin_name = "Earth"
    origin_is_earth = True
    if req.asteroid_id:
        ast_result = await db.execute(select(Asteroid).where(Asteroid.id == req.asteroid_id))
        asteroid = ast_result.scalar_one_or_none()
        if not asteroid:
            raise HTTPException(status_code=404, detail="Asteroid not found")
        target_x = asteroid.semi_major_axis
        target_y = 0.0
    elif req.colony_id:
        col_result = await db.execute(select(Colony).where(Colony.id == req.colony_id))
        colony = col_result.scalar_one_or_none()
        if not colony:
            raise HTTPException(status_code=404, detail="Colony not found")
        target_x = 1.52
        target_y = 0.0
        origin_name = colony.colony_name
        origin_is_earth = False
    else:
        raise HTTPException(status_code=422, detail="Provide asteroid_id or colony_id")
    origin_x = ship.position_x
    origin_y = ship.position_y
    dist = math.sqrt((target_x - origin_x) ** 2 + (target_y - origin_y) ** 2)
    transit_sec = _transit_time_seconds(dist, ship.max_thrust_g * ship.thrust_setting)
    fuel_per_tick = (ship.fuel_capacity * 0.001) * ship.thrust_setting
    mission = Mission(
        player_id=player.id,
        ship_id=ship.id,
        asteroid_id=asteroid.id if asteroid else None,
        mission_type=req.mission_type,
        status=STATUS_TRANSIT_OUT,
        transit_time=max(transit_sec, 30.0),
        elapsed_ticks=0.0,
        fuel_per_tick=fuel_per_tick,
        origin_x=origin_x,
        origin_y=origin_y,
        origin_name=origin_name,
        origin_is_earth=origin_is_earth,
        return_to_station=req.return_to_station,
        mining_duration=req.mining_duration,
    )
    db.add(mission)
    ship.is_stationed = False
    db.add(ship)
    await db.commit()
    await db.refresh(mission)
    return mission

@router.post("/hire", status_code=status.HTTP_201_CREATED)
async def hire(
    req: HireRequest,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    # Hire from the labour pool (workers with no player_id assigned)
    result = await db.execute(
        select(Worker).where(Worker.id == req.worker_id, Worker.player_id.is_(None))
    )
    worker = result.scalar_one_or_none()
    if not worker:
        raise HTTPException(status_code=404, detail="Worker not available for hire")
    worker.player_id = player.id
    db.add(worker)
    await db.commit()
    await db.refresh(worker)
    return WorkerOut.model_validate(worker)


@router.post("/fire/{worker_id}", status_code=status.HTTP_204_NO_CONTENT)
async def fire(
    worker_id: int,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    result = await db.execute(
        select(Worker).where(Worker.id == worker_id, Worker.player_id == player.id)
    )
    worker = result.scalar_one_or_none()
    if not worker:
        raise HTTPException(status_code=404, detail="Worker not found")
    if worker.assigned_ship_id:
        raise HTTPException(status_code=409, detail="Cannot fire a worker on an active mission")
    worker.player_id = None
    worker.is_available = True
    db.add(worker)
    await db.commit()

@router.post("/buy-ship", response_model=ShipOut, status_code=status.HTTP_201_CREATED)
async def buy_ship(
    req: BuyShipRequest,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    stats = SHIP_CLASS_STATS.get(req.ship_class)
    if not stats:
        raise HTTPException(status_code=422, detail="Invalid ship class")
    price = stats["base_price"]
    if player.money < price:
        raise HTTPException(status_code=402, detail=f"Insufficient funds (need {price:,} cr)")
    col_result = await db.execute(select(Colony).where(Colony.id == req.colony_id))
    colony = col_result.scalar_one_or_none()
    if not colony:
        raise HTTPException(status_code=404, detail="Colony not found")
    ship = Ship(
        player_id=player.id,
        ship_name=req.ship_name,
        ship_class=req.ship_class,
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
        current_cargo={},
        supplies={},
    )
    player.money -= price
    db.add(ship)
    db.add(player)
    await db.commit()
    await db.refresh(ship)
    return ship


@router.post("/policies", response_model=dict)
async def update_policies(
    payload: PolicyUpdate,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    if payload.thrust_policy is not None:
        player.thrust_policy = payload.thrust_policy
    if payload.supply_policy is not None:
        player.supply_policy = payload.supply_policy
    if payload.collection_policy is not None:
        player.collection_policy = payload.collection_policy
    if payload.encounter_policy is not None:
        player.encounter_policy = payload.encounter_policy
    db.add(player)
    await db.commit()
    return {"ok": True}


@router.get("/asteroids", response_model=list[AsteroidOut])
async def list_asteroids(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Asteroid))
    return [AsteroidOut.model_validate(a) for a in result.scalars().all()]


@router.get("/colonies", response_model=list[ColonyOut])
async def list_colonies(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Colony))
    return [ColonyOut.model_validate(c) for c in result.scalars().all()]


@router.get("/market")
async def market_prices():
    return get_market_prices()
