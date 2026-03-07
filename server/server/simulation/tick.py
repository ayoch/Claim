from __future__ import annotations
import logging, math, random, time
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from server.models.mission import (
    Mission, MISSION_COLLECT_ORE, STATUS_COLLECTING, STATUS_COMPLETED,
    STATUS_MINING, STATUS_TRANSIT_BACK, STATUS_TRANSIT_OUT,
)
from server.models.player import Player
from server.models.rig import Rig
from server.models.ship import Ship
from server.models.stockpile import Stockpile
from server.models.trade_mission import (
    TradeMission, STATUS_TRANSIT_TO_COLONY as TM_TRANSIT_TO,
    STATUS_SELLING as TM_SELLING, STATUS_TRANSIT_BACK as TM_TRANSIT_BACK,
    STATUS_COMPLETED as TM_COMPLETED
)
from server.models.worker import Worker
from server.models.world_state import WorldState
from server.routers import admin_speed as _admin_speed
from server.simulation.contracts import process_contracts as _process_contracts
from server.simulation.worker_spawning import process_worker_spawning

logger = logging.getLogger(__name__)

BASE_ORE_PRICES: dict[str, float] = {
    'nickel': 4200, 'iron': 1800, 'cobalt': 18000, 'platinum': 340000,
    'gold': 420000, 'silicon': 2100, 'water_ice': 800, 'carbon': 1500,
    'olivine': 950, 'pyroxene': 1100, 'troilite': 3600, 'palladium': 280000,
}
_market_prices: dict[str, float] = dict(BASE_ORE_PRICES)
_payroll_accum: dict[int, float] = {}

# Game epoch: Fixed point in time (Jan 1, 2112 00:00:00 UTC)
# All total_ticks are calculated as seconds elapsed since this epoch
# This keeps total_ticks synchronized with real-world time in 2112
import datetime
_GAME_EPOCH = datetime.datetime(2112, 1, 1, 0, 0, 0, tzinfo=datetime.timezone.utc).timestamp()
_total_ticks: int = 0  # Will be calculated from real-time, not incremented

# Worker skill progression constants
BASE_XP: float = 86400.0  # 1 game-day at skill 0.0
SKILL_CAP: float = 2.0
SKILL_INCREMENT: float = 0.05

# Rig mining constants
BASE_MINING_RATE: float = 0.0001  # Scales abstract ore yields to tons/tick

def _get_xp_for_next_level(current_skill: float) -> float:
    """Calculate XP needed for next level. Returns 0 if at cap."""
    if current_skill >= SKILL_CAP:
        return 0.0
    return BASE_XP * pow(current_skill + 1.0, 2.0)

def _add_worker_xp(worker: Worker, skill_type: int, amount: float) -> list[dict]:
    """
    Add XP to a worker's skill and check for level-up.
    skill_type: 0=pilot, 1=engineer, 2=mining
    Returns list of events (worker_skill_leveled if level-up occurred).
    """
    if amount <= 0.0:
        return []

    # Get current skill and XP
    if skill_type == 0:
        current_skill = worker.pilot_skill
        current_xp = worker.pilot_xp
    elif skill_type == 1:
        current_skill = worker.engineer_skill
        current_xp = worker.engineer_xp
    elif skill_type == 2:
        current_skill = worker.mining_skill
        current_xp = worker.mining_xp
    else:
        return []

    # Cap at max skill
    if current_skill >= SKILL_CAP:
        return []

    # Add XP
    current_xp += amount
    events: list[dict] = []

    # Check for level-up (can level multiple times if large XP grant)
    xp_needed = _get_xp_for_next_level(current_skill)
    while current_xp >= xp_needed and xp_needed > 0.0 and current_skill < SKILL_CAP:
        current_xp -= xp_needed
        current_skill += SKILL_INCREMENT
        current_skill = min(current_skill, SKILL_CAP)

        # Update skill value
        if skill_type == 0:
            worker.pilot_skill = current_skill
        elif skill_type == 1:
            worker.engineer_skill = current_skill
        elif skill_type == 2:
            worker.mining_skill = current_skill

        # Recalculate XP needed for next level
        xp_needed = _get_xp_for_next_level(current_skill)

        # Recalculate wage based on new total skill
        total_skill = worker.pilot_skill + worker.engineer_skill + worker.mining_skill
        worker.wage = int(80 + total_skill * 40)

        # Small loyalty boost for career development
        worker.loyalty = min(worker.loyalty + 2.0, 100.0)

        # Emit event
        skill_names = ["pilot", "engineer", "mining"]
        events.append({
            'type': 'worker_skill_leveled',
            'worker_id': worker.id,
            'player_id': worker.player_id,
            'skill_type': skill_names[skill_type],
            'new_value': round(current_skill, 2),
            'worker_name': worker.full_name,
        })
        logger.info('Worker %d (%s): %s skill leveled to %.2f',
                    worker.id, worker.full_name, skill_names[skill_type], current_skill)

    # Store updated XP
    if skill_type == 0:
        worker.pilot_xp = current_xp
    elif skill_type == 1:
        worker.engineer_xp = current_xp
    elif skill_type == 2:
        worker.mining_xp = current_xp

    return events

def get_market_prices() -> dict[str, float]:
    return dict(_market_prices)

def get_total_ticks() -> int:
    """Get current total_ticks value."""
    return _total_ticks


async def load_world_state(db: AsyncSession, world_id: int = 1) -> None:
    """Load world state from database on startup."""
    global _total_ticks
    result = await db.execute(select(WorldState).where(WorldState.world_id == world_id))
    world_state = result.scalar_one_or_none()

    if world_state:
        _total_ticks = world_state.total_ticks
        speed = getattr(world_state, 'speed_multiplier', 1.0) or 1.0
        _admin_speed._simulation_speed_multiplier = speed
        logger.info(f'Loaded world state: total_ticks={_total_ticks}, speed={speed}x')
    else:
        # Create initial world state
        world_state = WorldState(world_id=world_id, total_ticks=0)
        db.add(world_state)
        await db.commit()
        _total_ticks = 0
        logger.info('Created new world state')


async def save_world_state(db: AsyncSession, world_id: int = 1) -> None:
    """Save current world state to database."""
    result = await db.execute(select(WorldState).where(WorldState.world_id == world_id))
    world_state = result.scalar_one_or_none()

    if world_state:
        world_state.total_ticks = _total_ticks
        db.add(world_state)
        await db.commit()


_save_counter: int = 0
_SAVE_INTERVAL: int = 100  # Save world state every 100 ticks

async def process_tick(db: AsyncSession, world_id: int, dt: float) -> list[dict]:
    global _total_ticks, _save_counter
    # Increment total_ticks (allows speed multiplier to affect game time)
    _total_ticks += int(dt)
    _save_counter += 1

    events: list[dict] = []
    try:
        events += await _process_missions(db, dt)
        events += await _process_trade_missions(db, dt)
        events += await _process_rigs(db, dt)
        events += await _process_market(dt)
        events += await _process_payroll(db, dt)
        events += await _process_contracts(db, dt)
        events += await process_worker_spawning(db, dt)

        # Periodically save world state
        if _save_counter >= _SAVE_INTERVAL:
            await save_world_state(db, world_id)
            _save_counter = 0

    except Exception as exc:
        logger.exception('Tick %d failed: %s', _total_ticks, exc)
    return events

async def _process_missions(db: AsyncSession, dt: float) -> list[dict]:
    events: list[dict] = []
    result = await db.execute(
        select(Mission)
        .where(Mission.status.in_([STATUS_TRANSIT_OUT, STATUS_MINING, STATUS_COLLECTING, STATUS_TRANSIT_BACK]))
        .options(selectinload(Mission.ship), selectinload(Mission.asteroid), selectinload(Mission.player))
    )
    missions = list(result.scalars().all())
    for mission in missions:
        ship = mission.ship
        if ship is None or ship.is_derelict:
            continue
        prev_status = mission.status
        if mission.status == STATUS_TRANSIT_OUT:
            events += await _advance_transit_out(mission, ship, dt, db)
        elif mission.status == STATUS_MINING:
            events += _advance_mining(mission, ship, dt)
        elif mission.status == STATUS_COLLECTING:
            events += await _advance_collecting(mission, ship, dt, db)
        elif mission.status == STATUS_TRANSIT_BACK:
            events += _advance_transit_back(mission, ship, dt, mission.player)
        db.add(mission)
        if prev_status != mission.status:
            events.append({'type': 'mission_status_changed', 'mission_id': mission.id,
                'player_id': mission.player_id, 'ship_id': mission.ship_id,
                'old_status': prev_status, 'new_status': mission.status})
    return events

async def _advance_transit_out(mission: Mission, ship: Ship, dt: float, db: AsyncSession) -> list[dict]:
    mission.elapsed_ticks += dt
    ship.fuel = max(0.0, ship.fuel - mission.fuel_per_tick * dt)

    # Update ship position (interpolate between origin and destination)
    if mission.transit_time > 0:
        progress = min(mission.elapsed_ticks / mission.transit_time, 1.0)
        ship.position_x = mission.origin_x + (mission.destination_x - mission.origin_x) * progress
        ship.position_y = mission.origin_y + (mission.destination_y - mission.origin_y) * progress

    # Grant pilot and engineer XP to all crew during transit
    events: list[dict] = []
    for worker in ship.workers:
        events += _add_worker_xp(worker, 0, dt)  # 0 = pilot skill
        events += _add_worker_xp(worker, 1, dt)  # 1 = engineer skill

    if mission.elapsed_ticks >= mission.transit_time:
        mission.elapsed_ticks = 0.0
        ship.is_stationed = False
        # Snap to destination position
        ship.position_x = mission.destination_x
        ship.position_y = mission.destination_y

        # Check mission type to determine next status
        if mission.mission_type == MISSION_COLLECT_ORE:
            mission.status = STATUS_COLLECTING
            logger.info('Mission %d: arrived, starting collection', mission.id)
        else:
            mission.status = STATUS_MINING
            logger.info('Mission %d: arrived, starting mining', mission.id)

        events.append({'type': 'mission_arrived', 'mission_id': mission.id, 'player_id': mission.player_id})

    return events

def _advance_mining(mission: Mission, ship: Ship, dt: float) -> list[dict]:
    mission.elapsed_ticks += dt
    events: list[dict] = []

    # Grant mining XP to all crew during mining
    for worker in ship.workers:
        events += _add_worker_xp(worker, 2, dt)  # 2 = mining skill

    if mission.asteroid and mission.asteroid.ore_yields:
        cargo = dict(ship.current_cargo or {})
        cap = ship.cargo_capacity - sum(cargo.values())

        # Get asteroid reserves (mutable dict we'll update)
        reserves = dict(mission.asteroid.reserves or {})
        reserves_updated = False

        for ore_type, rate_per_day in mission.asteroid.ore_yields.items():
            if cap <= 0:
                break

            # Calculate mining rate
            mined = min((rate_per_day / 86400.0) * dt, cap)

            # Check reserves (if reserves system is initialized)
            if ore_type in reserves:
                available = reserves[ore_type]
                if available <= 0:
                    # This ore type is depleted - skip it
                    continue

                # Cap mining to available reserves
                actual_mined = min(mined, available)

                # Update reserves
                reserves[ore_type] = available - actual_mined
                reserves_updated = True

                # Add to cargo
                cargo[ore_type] = cargo.get(ore_type, 0.0) + actual_mined
                cap -= actual_mined
            else:
                # Reserves not initialized for this ore type - use old behavior
                cargo[ore_type] = cargo.get(ore_type, 0.0) + mined
                cap -= mined

        ship.current_cargo = cargo

        # Save updated reserves back to asteroid (if changed)
        if reserves_updated:
            mission.asteroid.reserves = reserves

    if mission.elapsed_ticks >= mission.mining_duration:
        mission.status = STATUS_TRANSIT_BACK
        mission.elapsed_ticks = 0.0
        logger.info('Mission %d: mining complete, heading back', mission.id)
        events.append({'type': 'mission_mining_complete', 'mission_id': mission.id, 'player_id': mission.player_id})

    return events


async def _advance_collecting(mission: Mission, ship: Ship, dt: float, db: AsyncSession) -> list[dict]:
    """
    Handle collection mission status - load ore from stockpiles into ship cargo.

    Takes 1800 ticks (30 minutes) to complete loading.
    """
    mission.elapsed_ticks += dt
    events: list[dict] = []

    COLLECTION_DURATION = 1800.0  # 30 minutes

    if mission.elapsed_ticks >= COLLECTION_DURATION:
        # Load ore from stockpiles into ship cargo
        if mission.asteroid:
            # Query all stockpiles for this player at this asteroid
            result = await db.execute(
                select(Stockpile).where(
                    Stockpile.player_id == mission.player_id,
                    Stockpile.asteroid_id == mission.asteroid.id,
                    Stockpile.tonnes > 0
                )
            )
            stockpiles = list(result.scalars().all())

            cargo = dict(ship.current_cargo or {})
            current_cargo_total = sum(cargo.values())
            available_capacity = ship.cargo_capacity - current_cargo_total
            total_loaded = 0.0
            stockpiles_to_delete = []

            for stockpile in stockpiles:
                if available_capacity <= 0:
                    break

                # Load as much as possible from this stockpile
                to_load = min(stockpile.tonnes, available_capacity)
                cargo[stockpile.ore_type] = cargo.get(stockpile.ore_type, 0.0) + to_load
                stockpile.tonnes -= to_load
                available_capacity -= to_load
                total_loaded += to_load

                # Mark for deletion if empty
                if stockpile.tonnes <= 0:
                    stockpiles_to_delete.append(stockpile.id)
                else:
                    db.add(stockpile)

                logger.info(
                    'Mission %d: loaded %.1f t of %s from stockpile',
                    mission.id, to_load, stockpile.ore_type
                )

            # Batch delete empty stockpiles
            if stockpiles_to_delete:
                from sqlalchemy import delete
                await db.execute(delete(Stockpile).where(Stockpile.id.in_(stockpiles_to_delete)))

            ship.current_cargo = cargo

            if total_loaded > 0.0:
                events.append({
                    'type': 'stockpile_collected',
                    'mission_id': mission.id,
                    'player_id': mission.player_id,
                    'asteroid_id': mission.asteroid.id,
                    'tonnes_loaded': round(total_loaded, 2)
                })

        # Transition to return trip
        mission.status = STATUS_TRANSIT_BACK
        mission.elapsed_ticks = 0.0
        logger.info('Mission %d: collection complete, heading back', mission.id)
        events.append({'type': 'mission_collection_complete', 'mission_id': mission.id, 'player_id': mission.player_id})

    return events

def _advance_transit_back(mission: Mission, ship: Ship, dt: float, player=None) -> list[dict]:
    mission.elapsed_ticks += dt
    ship.fuel = max(0.0, ship.fuel - mission.fuel_per_tick * dt)

    # Update ship position (interpolate from destination back to origin)
    if mission.transit_time > 0:
        progress = min(mission.elapsed_ticks / mission.transit_time, 1.0)
        ship.position_x = mission.destination_x + (mission.origin_x - mission.destination_x) * progress
        ship.position_y = mission.destination_y + (mission.origin_y - mission.destination_y) * progress

    # Grant pilot and engineer XP to all crew during transit
    events: list[dict] = []
    for worker in ship.workers:
        events += _add_worker_xp(worker, 0, dt)  # 0 = pilot skill
        events += _add_worker_xp(worker, 1, dt)  # 1 = engineer skill

    if mission.elapsed_ticks >= mission.transit_time:
        mission.status = STATUS_COMPLETED
        ship.is_stationed = True
        ship.station_colony_id = None
        # Snap to origin position
        ship.position_x = mission.origin_x
        ship.position_y = mission.origin_y
        auto_sell = player.auto_sell_on_return if player is not None else True
        total_value = 0
        if auto_sell:
            total_value = _sell_cargo(ship)
            if total_value > 0:
                if player:
                    player.money += total_value
                logger.info('Mission %d: completed, auto-sold cargo %.1fM cr', mission.id, total_value / 1e6)
        else:
            logger.info('Mission %d: completed, cargo held (auto_sell_on_return=False)', mission.id)
        ev = {'type': 'mission_completed', 'mission_id': mission.id,
              'player_id': mission.player_id, 'ship_id': mission.ship_id,
              'auto_sold': auto_sell}
        if total_value > 0:
            ev['cargo_value'] = total_value
        events.append(ev)

    return events

def _sell_cargo(ship: Ship) -> float:
    if not ship.current_cargo:
        return 0.0
    total = sum(tonnes * _market_prices.get(ore, BASE_ORE_PRICES.get(ore, 1000.0))
                for ore, tonnes in ship.current_cargo.items())
    ship.current_cargo = {}
    return total


async def _process_trade_missions(db: AsyncSession, dt: float) -> list[dict]:
    """
    Process active trade missions.

    Trade missions go through these phases:
    1. TRANSIT_TO_COLONY: Travel to colony
    2. SELLING: Sell cargo, calculate revenue
    3. TRANSIT_BACK: Return to origin
    4. COMPLETED: Pay player and mark ship as stationed
    """
    events: list[dict] = []
    result = await db.execute(
        select(TradeMission)
        .where(TradeMission.status.in_([TM_TRANSIT_TO, TM_SELLING, TM_TRANSIT_BACK]))
        .options(selectinload(TradeMission.ship), selectinload(TradeMission.player))
    )
    trade_missions = list(result.scalars().all())

    for tm in trade_missions:
        ship = tm.ship
        if ship is None or ship.is_derelict:
            continue

        prev_status = tm.status

        if tm.status == TM_TRANSIT_TO:
            # Travel to colony
            tm.elapsed_ticks += dt
            ship.fuel = max(0.0, ship.fuel - tm.fuel_per_tick * dt)

            # Update ship position
            if tm.transit_time > 0:
                progress = min(tm.elapsed_ticks / tm.transit_time, 1.0)
                ship.position_x = tm.origin_x + (tm.destination_x - tm.origin_x) * progress
                ship.position_y = tm.origin_y + (tm.destination_y - tm.origin_y) * progress

            # Grant pilot/engineer XP
            for worker in ship.workers:
                events += _add_worker_xp(worker, 0, dt)  # pilot
                events += _add_worker_xp(worker, 1, dt)  # engineer

            if tm.elapsed_ticks >= tm.transit_time:
                tm.status = TM_SELLING
                tm.elapsed_ticks = 0.0
                ship.position_x = tm.destination_x
                ship.position_y = tm.destination_y
                logger.info('Trade mission %d: arrived at colony, selling', tm.id)

        elif tm.status == TM_SELLING:
            # Sell cargo (instant for now, could add duration)
            SELLING_DURATION = 300.0  # 5 minutes to offload and sell
            tm.elapsed_ticks += dt

            if tm.elapsed_ticks >= SELLING_DURATION:
                # Calculate revenue from cargo
                revenue = 0
                for ore_type, tonnes in tm.cargo.items():
                    ore_price = _market_prices.get(ore_type, BASE_ORE_PRICES.get(ore_type, 1000.0))
                    revenue += int(tonnes * ore_price)

                tm.revenue = revenue
                tm.cargo = {}  # Clear cargo

                # Pay player
                player = tm.player
                if player:
                    player.money += revenue
                    db.add(player)

                # Transition to return trip
                tm.status = TM_TRANSIT_BACK
                tm.elapsed_ticks = 0.0
                logger.info('Trade mission %d: sold cargo for %d cr, returning', tm.id, revenue)

                events.append({
                    'type': 'trade_cargo_sold',
                    'mission_id': tm.id,
                    'player_id': tm.player_id,
                    'revenue': revenue
                })

        elif tm.status == TM_TRANSIT_BACK:
            # Return to origin
            tm.elapsed_ticks += dt
            ship.fuel = max(0.0, ship.fuel - tm.fuel_per_tick * dt)

            # Update ship position
            if tm.transit_time > 0:
                progress = min(tm.elapsed_ticks / tm.transit_time, 1.0)
                ship.position_x = tm.destination_x + (tm.origin_x - tm.destination_x) * progress
                ship.position_y = tm.destination_y + (tm.origin_y - tm.destination_y) * progress

            # Grant pilot/engineer XP
            for worker in ship.workers:
                events += _add_worker_xp(worker, 0, dt)  # pilot
                events += _add_worker_xp(worker, 1, dt)  # engineer

            if tm.elapsed_ticks >= tm.transit_time:
                tm.status = TM_COMPLETED
                ship.is_stationed = True
                ship.station_colony_id = None
                ship.position_x = tm.origin_x
                ship.position_y = tm.origin_y
                logger.info('Trade mission %d: completed, revenue %d cr', tm.id, tm.revenue)

                events.append({
                    'type': 'trade_mission_completed',
                    'mission_id': tm.id,
                    'player_id': tm.player_id,
                    'ship_id': tm.ship_id,
                    'revenue': tm.revenue
                })

        db.add(tm)
        db.add(ship)

        if prev_status != tm.status:
            events.append({
                'type': 'trade_mission_status_changed',
                'mission_id': tm.id,
                'player_id': tm.player_id,
                'old_status': prev_status,
                'new_status': tm.status
            })

    return events


async def _process_market(dt: float) -> list[dict]:
    changed: dict[str, float] = {}
    for ore, price in _market_prices.items():
        base = BASE_ORE_PRICES[ore]
        drift = random.gauss(0, 0.001 * math.sqrt(dt))
        new_price = max(base * 0.60, min(base * 1.40, price * (1 + drift)))
        _market_prices[ore] = new_price
        if abs(new_price - price) / base > 0.005:
            changed[ore] = round(new_price, 2)
    if changed:
        return [{'type': 'market_update', 'prices': changed}]
    return []

_PAYROLL_INTERVAL = 86400.0

async def _process_payroll(db: AsyncSession, dt: float) -> list[dict]:
    events: list[dict] = []
    result = await db.execute(select(Player))
    players = list(result.scalars().all())
    for player in players:
        acc = _payroll_accum.get(player.id, 0.0) + dt
        days = int(acc // _PAYROLL_INTERVAL)
        if days > 0:
            w_result = await db.execute(select(Worker).where(Worker.player_id == player.id))
            workers = list(w_result.scalars().all())
            daily = sum(w.wage for w in workers)
            deduction = daily * days
            if deduction > 0:
                player.money -= deduction
                db.add(player)
                events.append({'type': 'payroll_deducted', 'player_id': player.id,
                    'amount': deduction, 'days': days, 'new_balance': player.money})
                logger.info('Payroll: player %d --%d cr (%d days)', player.id, deduction, days)
        _payroll_accum[player.id] = acc % _PAYROLL_INTERVAL
    return events


async def _process_rigs(db: AsyncSession, dt: float) -> list[dict]:
    """
    Process deployed rigs (AMUs) to generate ore stockpiles.

    Each functional rig with assigned workers mines ore from its asteroid
    and accumulates it in stockpiles. Workers gain mining XP, and rigs
    degrade over time.
    """
    events: list[dict] = []
    days = dt / 86400.0

    # Load all deployed rigs with relationships
    result = await db.execute(
        select(Rig)
        .where(Rig.deployed_at_asteroid_id.isnot(None))
        .options(
            selectinload(Rig.asteroid),
            selectinload(Rig.assigned_workers)
        )
    )
    rigs = list(result.scalars().all())

    for rig in rigs:
        # Skip non-functional or uncrewed rigs
        if not rig.is_functional:
            continue
        if not rig.assigned_workers:
            continue

        asteroid = rig.asteroid
        if not asteroid or not asteroid.ore_yields:
            continue

        # Calculate total crew mining skill
        skill_total = sum(w.mining_skill for w in rig.assigned_workers)
        if skill_total < 0.1:
            skill_total = 0.1

        # Grant mining XP to all assigned workers
        for worker in rig.assigned_workers:
            xp_events = _add_worker_xp(worker, 2, dt)  # 2 = mining skill
            events += xp_events
            db.add(worker)  # Ensure worker changes are tracked

        # Mine each ore type
        for ore_type, base_yield in asteroid.ore_yields.items():
            # Calculate ore generated this tick
            ore_per_tick = (
                base_yield *
                skill_total *
                rig.mining_multiplier *
                BASE_MINING_RATE *
                dt
            )

            if ore_per_tick <= 0.0:
                continue

            # Find or create stockpile entry
            stockpile_result = await db.execute(
                select(Stockpile).where(
                    Stockpile.player_id == rig.player_id,
                    Stockpile.asteroid_id == asteroid.id,
                    Stockpile.ore_type == ore_type
                )
            )
            stockpile = stockpile_result.scalar_one_or_none()

            if stockpile is None:
                # Create new stockpile
                stockpile = Stockpile(
                    player_id=rig.player_id,
                    asteroid_id=asteroid.id,
                    ore_type=ore_type,
                    tonnes=ore_per_tick
                )
                db.add(stockpile)
                logger.info(
                    'Rig %d: created stockpile at asteroid %d for %s (%.2f t)',
                    rig.id, asteroid.id, ore_type, ore_per_tick
                )
            else:
                # Add to existing stockpile
                stockpile.tonnes += ore_per_tick
                db.add(stockpile)

        # Degrade rig durability
        # Base wear reduced slightly by best engineer skill
        best_eng = max((w.engineer_skill for w in rig.assigned_workers), default=0.0)
        eng_wear_factor = 1.0 - (best_eng * 0.2)  # 0.0 eng = full wear, 1.5 eng = 70% wear

        rig.durability -= rig.wear_per_day * eng_wear_factor * days
        rig.max_durability -= rig.wear_per_day * 0.05 * eng_wear_factor * days  # 5% max durability decay

        if rig.durability < 0.0:
            rig.durability = 0.0
        if rig.max_durability < 0.0:
            rig.max_durability = 0.0

        db.add(rig)

        # Emit event if rig becomes non-functional
        if not rig.is_functional and rig.durability == 0.0:
            events.append({
                'type': 'rig_broken',
                'rig_id': rig.id,
                'player_id': rig.player_id,
                'rig_name': rig.unit_name,
                'asteroid_id': asteroid.id
            })
            logger.warning('Rig %d (%s) broken at asteroid %d', rig.id, rig.unit_name, asteroid.id)

    return events
