import math
from fastapi import APIRouter, Depends, HTTPException, status, Request
import sqlalchemy as sa
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from server.auth import get_current_player
from server.database import get_db
from server.models.asteroid import Asteroid
from server.models.colony import Colony
from server.models.equipment import Equipment
from server.models.mission import Mission, STATUS_TRANSIT_OUT
from server.models.player import Player
from server.models.rig import Rig, UNIT_TYPE_BASIC, UNIT_TYPE_ADVANCED, UNIT_TYPE_REFINERY
from server.models.ship import Ship, SHIP_CLASS_STATS
from server.models.stockpile import Stockpile
from server.models.trade_mission import TradeMission
from server.models.worker import Worker
from server.rate_limit import limiter
from server.routers import admin_speed
from server.schemas.game import (
    AsteroidOut, BuyEquipmentRequest, BuyShipRequest, ColonyOut, DispatchRequest,
    EquipmentOut, GameState, HireRequest, MissionOut, RigOut, SellEquipmentRequest,
    ShipOut, StockpileOut, TradeMissionOut, WorkerOut,
)
from server.schemas.player import PolicyUpdate
from server.simulation.tick import get_market_prices, get_total_ticks, get_game_seconds

router = APIRouter(prefix="/game", tags=["game"])

AU_TO_KM = 149_597_870.7
G_ACCEL = 9.80665

# Semi-major axis (AU) by planet_id — used for transit calculations.
# These are mean orbital radii; good enough for transit time estimates.
PLANET_SEMI_MAJOR_AU: dict[str, float] = {
    "earth":       1.000,
    "moon":        1.003,  # Earth-Moon L1 approximation
    "mars":        1.524,
    "ceres":       2.767,
    "vesta":       2.362,
    "europa":      5.203,
    "ganymede":    5.203,
    "callisto":    5.203,
    "titan":       9.537,
    "triton":     30.070,
}


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
    result = await db.execute(
        select(Mission)
        .options(selectinload(Mission.ship), selectinload(Mission.asteroid))
        .where(
            Mission.player_id == player.id,
            Mission.status.in_([0, 1, 2]),
        )
    )
    active_missions = list(result.scalars().all())

    # Load player's trade missions
    trade_result = await db.execute(select(TradeMission).where(
        TradeMission.player_id == player.id,
        TradeMission.status.in_([0, 1, 2, 3, 4]),  # All statuses except COMPLETED
    ))
    trade_missions = list(trade_result.scalars().all())

    # Load player's rigs
    rigs_result = await db.execute(select(Rig).where(Rig.player_id == player.id))
    rigs = list(rigs_result.scalars().all())

    # Load player's stockpiles
    stockpiles_result = await db.execute(select(Stockpile).where(Stockpile.player_id == player.id))
    stockpiles = list(stockpiles_result.scalars().all())

    return GameState(
        player_id=player.id,
        username=player.username,
        money=player.money,
        reputation=player.reputation,
        thrust_policy=player.thrust_policy,
        supply_policy=player.supply_policy,
        collection_policy=player.collection_policy,
        encounter_policy=player.encounter_policy,
        auto_sell_on_return=player.auto_sell_on_return,
        total_ticks=get_total_ticks(),
        game_seconds=get_game_seconds(),
        speed_multiplier=admin_speed.get_speed_multiplier(),
        ships=[ShipOut.model_validate(s) for s in player.ships],
        workers=[WorkerOut.model_validate(w) for w in player.workers],
        active_missions=[MissionOut.model_validate(m) for m in active_missions],
        trade_missions=[TradeMissionOut.model_validate(tm) for tm in trade_missions],
        rigs=[RigOut.model_validate(r) for r in rigs],
        stockpiles=[StockpileOut.model_validate(s) for s in stockpiles],
    )

@router.post("/dispatch", response_model=MissionOut, status_code=status.HTTP_201_CREATED)
@limiter.limit("20/minute")  # 20 mission dispatches per minute
async def dispatch(
    request: Request,
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
        target_x = PLANET_SEMI_MAJOR_AU.get(colony.planet_id, 1.52)
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
        destination_x=target_x,
        destination_y=target_y,
        return_to_station=req.return_to_station,
        mining_duration=req.mining_duration,
    )
    db.add(mission)
    ship.is_stationed = False
    db.add(ship)
    await db.commit()
    await db.refresh(mission)
    return mission

@router.get("/available-workers", response_model=list[WorkerOut])
async def list_available_workers(
    db: AsyncSession = Depends(get_db),
):
    """Get list of workers available for hire (no player assigned)"""
    result = await db.execute(
        select(Worker).where(Worker.player_id.is_(None))
    )
    return [WorkerOut.model_validate(w) for w in result.scalars().all()]


@router.post("/hire", status_code=status.HTTP_201_CREATED)
@limiter.limit("10/minute")  # 10 worker hires per minute
async def hire(
    request: Request,
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
@limiter.limit("10/minute")  # 10 worker fires per minute
async def fire(
    request: Request,
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
@limiter.limit("5/minute")  # 5 ship purchases per minute
async def buy_ship(
    request: Request,
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


# Equipment catalog (simplified - matches client MarketData)
EQUIPMENT_CATALOG = {
    "Mining Processor": {"type": "processor", "mining_bonus": 1.5, "cost": 50000, "mass": 2.0},
    "Advanced Refinery": {"type": "refinery", "mining_bonus": 2.0, "cost": 150000, "mass": 5.0},
    "Laser Drill": {"type": "mining_laser", "mining_bonus": 1.3, "mining_speed_bonus": 0.2, "weapon_power": 5,
                    "weapon_range": 0.01, "weapon_accuracy": 0.8, "weapon_role": "dual", "cost": 80000, "mass": 3.0},
    "Railgun": {"type": "weapon", "weapon_power": 25, "weapon_range": 0.5, "weapon_accuracy": 0.7,
                "weapon_role": "offensive", "cost": 200000, "mass": 8.0},
    "Point Defense": {"type": "weapon", "weapon_power": 10, "weapon_range": 0.1, "weapon_accuracy": 0.85,
                      "weapon_role": "defensive", "cost": 120000, "mass": 4.0},
    "Torpedo Launcher": {"type": "weapon", "weapon_power": 50, "weapon_range": 2.0, "weapon_accuracy": 0.6,
                         "weapon_role": "offensive", "ammo_capacity": 4, "ammo_cost": 15000, "cost": 300000, "mass": 12.0},
}


@router.post("/buy-equipment", response_model=EquipmentOut, status_code=status.HTTP_201_CREATED)
@limiter.limit("10/minute")
async def buy_equipment(
    request: Request,
    req: BuyEquipmentRequest,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    # Get equipment template from catalog
    if req.equipment_name not in EQUIPMENT_CATALOG:
        raise HTTPException(status_code=404, detail="Equipment not found in catalog")

    template = EQUIPMENT_CATALOG[req.equipment_name]
    cost = template["cost"]

    # Check funds
    if player.money < cost:
        raise HTTPException(status_code=402, detail=f"Insufficient funds (need {cost:,} cr)")

    # Get ship and verify ownership
    ship_result = await db.execute(
        select(Ship).where(Ship.id == req.ship_id, Ship.player_id == player.id)
    )
    ship = ship_result.scalar_one_or_none()
    if not ship:
        raise HTTPException(status_code=404, detail="Ship not found")

    # Check equipment slots
    equipment_count = await db.scalar(
        select(sa.func.count(Equipment.id)).where(Equipment.ship_id == ship.id)
    )
    if equipment_count >= ship.max_equipment_slots:
        raise HTTPException(status_code=409, detail="Ship has no free equipment slots")

    # Create equipment
    equipment = Equipment(
        ship_id=ship.id,
        equipment_name=req.equipment_name,
        equipment_type=template["type"],
        mining_bonus=template.get("mining_bonus", 1.0),
        cost=cost,
        durability=100.0,
        max_durability=100.0,
        weapon_power=template.get("weapon_power", 0),
        weapon_range=template.get("weapon_range", 0.0),
        weapon_accuracy=template.get("weapon_accuracy", 0.0),
        weapon_role=template.get("weapon_role", ""),
        ammo_capacity=template.get("ammo_capacity", 0),
        current_ammo=template.get("ammo_capacity", 0),  # Start with full ammo
        ammo_cost=template.get("ammo_cost", 0),
        mass=template.get("mass", 0.0),
        mining_speed_bonus=template.get("mining_speed_bonus", 0.0),
    )

    player.money -= cost
    db.add(equipment)
    db.add(player)
    await db.commit()
    await db.refresh(equipment)
    return equipment


@router.post("/sell-equipment", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("10/minute")
async def sell_equipment(
    request: Request,
    req: SellEquipmentRequest,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    # Get equipment and verify ownership via ship
    equipment_result = await db.execute(
        select(Equipment)
        .join(Ship, Equipment.ship_id == Ship.id)
        .where(Equipment.id == req.equipment_id, Ship.player_id == player.id)
    )
    equipment = equipment_result.scalar_one_or_none()
    if not equipment:
        raise HTTPException(status_code=404, detail="Equipment not found")

    # Sell for 50% of cost
    refund = equipment.cost // 2
    player.money += refund

    await db.delete(equipment)
    db.add(player)
    await db.commit()


# Rig (AMU) catalog
RIG_CATALOG = {
    "Basic Mining Unit": {
        "type": UNIT_TYPE_BASIC,
        "mass": 5.0,
        "workers_required": 1,
        "mining_multiplier": 1.0,
        "wear_per_day": 0.3,
        "cost": 500000,
    },
    "Advanced Mining Unit": {
        "type": UNIT_TYPE_ADVANCED,
        "mass": 8.0,
        "workers_required": 2,
        "mining_multiplier": 2.5,
        "wear_per_day": 0.5,
        "cost": 1500000,
    },
    "Refinery Unit": {
        "type": UNIT_TYPE_REFINERY,
        "mass": 12.0,
        "workers_required": 3,
        "mining_multiplier": 4.0,
        "wear_per_day": 0.8,
        "cost": 3000000,
    },
}


@router.post("/buy-rig", response_model=RigOut, status_code=status.HTTP_201_CREATED)
@limiter.limit("5/minute")
async def buy_rig(
    request: Request,
    rig_name: str,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    """Purchase a rig (AMU) and add to inventory"""
    if rig_name not in RIG_CATALOG:
        raise HTTPException(status_code=404, detail="Rig type not found")

    template = RIG_CATALOG[rig_name]
    cost = template["cost"]

    if player.money < cost:
        raise HTTPException(status_code=402, detail=f"Insufficient funds (need {cost:,} cr)")

    rig = Rig(
        player_id=player.id,
        unit_type=template["type"],
        unit_name=rig_name,
        mass=template["mass"],
        workers_required=template["workers_required"],
        mining_multiplier=template["mining_multiplier"],
        cost=cost,
        wear_per_day=template["wear_per_day"],
        durability=100.0,
        max_durability=100.0,
        deployed_at_asteroid_id=None,
        deployed_at_tick=0.0,
    )

    player.money -= cost
    db.add(rig)
    db.add(player)
    await db.commit()
    await db.refresh(rig)
    return rig


@router.post("/deploy-rig", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("10/minute")
async def deploy_rig(
    request: Request,
    rig_id: int,
    asteroid_id: int,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    """Deploy a rig to an asteroid"""
    # Get rig and verify ownership
    rig_result = await db.execute(
        select(Rig).where(Rig.id == rig_id, Rig.player_id == player.id)
    )
    rig = rig_result.scalar_one_or_none()
    if not rig:
        raise HTTPException(status_code=404, detail="Rig not found")

    if rig.deployed_at_asteroid_id is not None:
        raise HTTPException(status_code=409, detail="Rig already deployed")

    # Verify asteroid exists
    asteroid_result = await db.execute(select(Asteroid).where(Asteroid.id == asteroid_id))
    asteroid = asteroid_result.scalar_one_or_none()
    if not asteroid:
        raise HTTPException(status_code=404, detail="Asteroid not found")

    # Deploy rig
    rig.deployed_at_asteroid_id = asteroid_id
    rig.deployed_at_tick = get_total_ticks()

    db.add(rig)
    await db.commit()


@router.post("/repair-rig", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("10/minute")
async def repair_rig(
    request: Request,
    rig_id: int,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    """Repair a rig (restores durability up to max_durability)"""
    # Get rig and verify ownership
    rig_result = await db.execute(
        select(Rig).where(Rig.id == rig_id, Rig.player_id == player.id)
    )
    rig = rig_result.scalar_one_or_none()
    if not rig:
        raise HTTPException(status_code=404, detail="Rig not found")

    # Calculate repair cost (30% of original cost, scaled by damage)
    missing = rig.max_durability - rig.durability
    if missing <= 0:
        raise HTTPException(status_code=400, detail="Rig doesn't need repair")

    cost_ratio = missing / rig.max_durability
    repair_cost = int(rig.cost * 0.3 * cost_ratio)

    if player.money < repair_cost:
        raise HTTPException(status_code=402, detail=f"Insufficient funds (need {repair_cost:,} cr)")

    # Repair rig
    rig.durability = rig.max_durability
    player.money -= repair_cost

    db.add(rig)
    db.add(player)
    await db.commit()


@router.post("/rebuild-rig", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("5/minute")
async def rebuild_rig(
    request: Request,
    rig_id: int,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    """Rebuild a rig (restores max_durability to 100)"""
    # Get rig and verify ownership
    rig_result = await db.execute(
        select(Rig).where(Rig.id == rig_id, Rig.player_id == player.id)
    )
    rig = rig_result.scalar_one_or_none()
    if not rig:
        raise HTTPException(status_code=404, detail="Rig not found")

    if rig.max_durability >= 100.0:
        raise HTTPException(status_code=400, detail="Rig doesn't need rebuild")

    # Rebuild costs 50% of original cost
    rebuild_cost = int(rig.cost * 0.5)

    if player.money < rebuild_cost:
        raise HTTPException(status_code=402, detail=f"Insufficient funds (need {rebuild_cost:,} cr)")

    # Rebuild rig
    rig.max_durability = 100.0
    rig.durability = 100.0  # Also repair to full
    player.money -= rebuild_cost

    db.add(rig)
    db.add(player)
    await db.commit()


@router.post("/recall-rig", status_code=status.HTTP_204_NO_CONTENT)
@limiter.limit("10/minute")
async def recall_rig(
    request: Request,
    rig_id: int,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    """Recall a rig from asteroid back to inventory"""
    # Get rig and verify ownership
    rig_result = await db.execute(
        select(Rig).where(Rig.id == rig_id, Rig.player_id == player.id)
    )
    rig = rig_result.scalar_one_or_none()
    if not rig:
        raise HTTPException(status_code=404, detail="Rig not found")

    if rig.deployed_at_asteroid_id is None:
        raise HTTPException(status_code=400, detail="Rig is not deployed")

    # Recall rig (unassign workers handled client-side via game state sync)
    rig.deployed_at_asteroid_id = None
    rig.deployed_at_tick = 0.0

    db.add(rig)
    await db.commit()


@router.get("/stockpiles", response_model=list[StockpileOut])
async def list_stockpiles(
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    """Get all ore stockpiles for player"""
    result = await db.execute(
        select(Stockpile).where(Stockpile.player_id == player.id)
    )
    return [StockpileOut.model_validate(s) for s in result.scalars().all()]


@router.post("/sell-cargo/{ship_id}", response_model=dict)
@limiter.limit("20/minute")
async def sell_cargo(
    request: Request,
    ship_id: int,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    """
    Manually sell all cargo on a docked ship at current market prices.
    Applies price_multipliers of the colony the ship is stationed at (if any).
    Ship must be stationed (docked) and have cargo.
    """
    from server.simulation.tick import get_market_prices, BASE_ORE_PRICES
    ship_result = await db.execute(
        select(Ship).where(Ship.id == ship_id, Ship.player_id == player.id)
    )
    ship = ship_result.scalar_one_or_none()
    if not ship:
        raise HTTPException(status_code=404, detail="Ship not found")
    if not ship.is_stationed:
        raise HTTPException(status_code=409, detail="Ship must be docked to sell cargo")
    if not ship.current_cargo or sum(ship.current_cargo.values()) == 0:
        raise HTTPException(status_code=422, detail="Ship has no cargo to sell")

    # Load colony price multipliers if ship is stationed at one
    price_multipliers: dict = {}
    if ship.station_colony_id:
        col_result = await db.execute(select(Colony).where(Colony.id == ship.station_colony_id))
        colony = col_result.scalar_one_or_none()
        if colony:
            price_multipliers = colony.price_multipliers or {}

    market = get_market_prices()
    total = 0
    for ore_type, tonnes in ship.current_cargo.items():
        base_price = market.get(ore_type, BASE_ORE_PRICES.get(ore_type, 1000.0))
        multiplier = price_multipliers.get(ore_type, 1.0)
        total += int(tonnes * base_price * multiplier)

    ship.current_cargo = {}
    player.money += total
    db.add(ship)
    db.add(player)
    await db.commit()

    return {"sold": True, "revenue": total, "new_balance": player.money}


@router.post("/dispatch-trade", response_model=TradeMissionOut, status_code=status.HTTP_201_CREATED)
@limiter.limit("20/minute")  # 20 trade dispatches per minute
async def dispatch_trade_mission(
    request: Request,
    ship_id: int,
    colony_id: int,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    """
    Dispatch a ship to a colony to sell ore.

    The ship's current cargo is transferred to the trade mission.
    Ship must be stationed and have cargo.
    """
    # Get ship and verify ownership
    ship_result = await db.execute(
        select(Ship).where(Ship.id == ship_id, Ship.player_id == player.id)
    )
    ship = ship_result.scalar_one_or_none()
    if not ship:
        raise HTTPException(status_code=404, detail="Ship not found")

    if not ship.is_stationed:
        raise HTTPException(status_code=409, detail="Ship is already on a mission")

    if ship.is_derelict:
        raise HTTPException(status_code=409, detail="Ship is derelict")

    if not ship.current_cargo or sum(ship.current_cargo.values()) == 0:
        raise HTTPException(status_code=422, detail="Ship has no cargo to trade")

    # Get colony
    colony_result = await db.execute(select(Colony).where(Colony.id == colony_id))
    colony = colony_result.scalar_one_or_none()
    if not colony:
        raise HTTPException(status_code=404, detail="Colony not found")

    # Calculate transit using colony's actual orbital radius
    origin_x = ship.position_x
    origin_y = ship.position_y
    target_x = PLANET_SEMI_MAJOR_AU.get(colony.planet_id, 1.52)
    target_y = 0.0

    dist = math.sqrt((target_x - origin_x) ** 2 + (target_y - origin_y) ** 2)
    transit_sec = _transit_time_seconds(dist, ship.max_thrust_g * ship.thrust_setting)
    fuel_per_tick = (ship.fuel_capacity * 0.001) * ship.thrust_setting

    # Create trade mission
    trade_mission = TradeMission(
        player_id=player.id,
        ship_id=ship.id,
        colony_id=colony_id,
        status=0,  # STATUS_TRANSIT_TO_COLONY
        transit_time=max(transit_sec, 30.0),
        elapsed_ticks=0.0,
        fuel_per_tick=fuel_per_tick,
        cargo=dict(ship.current_cargo),  # Copy cargo
        revenue=0,
        origin_x=origin_x,
        origin_y=origin_y,
        origin_name="Earth" if ship.position_x < 0.1 and ship.position_y < 0.1 else "Unknown",
        origin_is_earth=ship.position_x < 0.1 and ship.position_y < 0.1,
        destination_x=target_x,
        destination_y=target_y,
    )

    db.add(trade_mission)

    # Clear ship cargo and mark as not stationed
    ship.current_cargo = {}
    ship.is_stationed = False
    db.add(ship)

    await db.commit()
    await db.refresh(trade_mission)

    return TradeMissionOut.model_validate(trade_mission)


@router.post("/policies", response_model=dict)
@limiter.limit("20/minute")  # 20 policy updates per minute
async def update_policies(
    request: Request,
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
    if payload.auto_sell_on_return is not None:
        player.auto_sell_on_return = payload.auto_sell_on_return
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


@router.get("/world")
async def get_world_state(
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    """
    Get shared world state - all ships from all players for multiplayer visibility.
    Returns ships with owner information so clients can distinguish their own ships.
    """
    # Get all ships with their player relationship loaded
    result = await db.execute(
        select(Ship).options(selectinload(Ship.player))
    )
    all_ships = list(result.scalars().all())

    # Convert to ShipOut with owner_username populated
    ships_out = []
    for ship in all_ships:
        ship_dict = {
            "id": ship.id,
            "player_id": ship.player_id,
            "owner_username": ship.player.username if ship.player else "Unknown",
            "ship_name": ship.ship_name,
            "ship_class": ship.ship_class,
            "max_thrust_g": ship.max_thrust_g,
            "thrust_setting": ship.thrust_setting,
            "cargo_capacity": ship.cargo_capacity,
            "cargo_volume": ship.cargo_volume,
            "fuel_capacity": ship.fuel_capacity,
            "fuel": ship.fuel,
            "base_mass": ship.base_mass,
            "min_crew": ship.min_crew,
            "max_equipment_slots": ship.max_equipment_slots,
            "engine_condition": ship.engine_condition,
            "is_derelict": ship.is_derelict,
            "position_x": ship.position_x,
            "position_y": ship.position_y,
            "is_stationed": ship.is_stationed,
            "station_colony_id": ship.station_colony_id,
            "current_cargo": ship.current_cargo or {},
            "supplies": ship.supplies or {},
        }
        ships_out.append(ShipOut(**ship_dict))

    return {"ships": ships_out}
