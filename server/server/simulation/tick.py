from __future__ import annotations
import logging, math, random, time
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from server.models.mission import (
    Mission, STATUS_COMPLETED, STATUS_MINING, STATUS_TRANSIT_BACK, STATUS_TRANSIT_OUT,
)
from server.models.player import Player
from server.models.ship import Ship
from server.models.worker import Worker
from server.models.world_state import WorldState
from server.simulation.contracts import process_contracts as _process_contracts

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
        logger.info(f'Loaded world state: total_ticks={_total_ticks}')
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
        events += await _process_market(dt)
        events += await _process_payroll(db, dt)
        events += await _process_contracts(db, dt)

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
        .where(Mission.status.in_([STATUS_TRANSIT_OUT, STATUS_MINING, STATUS_TRANSIT_BACK]))
        .options(selectinload(Mission.ship), selectinload(Mission.asteroid))
    )
    missions = list(result.scalars().all())
    for mission in missions:
        ship = mission.ship
        if ship is None or ship.is_derelict:
            continue
        prev_status = mission.status
        if mission.status == STATUS_TRANSIT_OUT:
            events += _advance_transit_out(mission, ship, dt)
        elif mission.status == STATUS_MINING:
            events += _advance_mining(mission, ship, dt)
        elif mission.status == STATUS_TRANSIT_BACK:
            events += _advance_transit_back(mission, ship, dt)
        db.add(mission)
        if prev_status != mission.status:
            events.append({'type': 'mission_status_changed', 'mission_id': mission.id,
                'player_id': mission.player_id, 'ship_id': mission.ship_id,
                'old_status': prev_status, 'new_status': mission.status})
    return events

def _advance_transit_out(mission: Mission, ship: Ship, dt: float) -> list[dict]:
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
        mission.status = STATUS_MINING
        mission.elapsed_ticks = 0.0
        ship.is_stationed = False
        # Snap to destination position
        ship.position_x = mission.destination_x
        ship.position_y = mission.destination_y
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
        for ore_type, rate_per_day in mission.asteroid.ore_yields.items():
            if cap <= 0:
                break
            mined = min((rate_per_day / 86400.0) * dt, cap)
            cargo[ore_type] = cargo.get(ore_type, 0.0) + mined
            cap -= mined
        ship.current_cargo = cargo

    if mission.elapsed_ticks >= mission.mining_duration:
        mission.status = STATUS_TRANSIT_BACK
        mission.elapsed_ticks = 0.0
        logger.info('Mission %d: mining complete, heading back', mission.id)
        events.append({'type': 'mission_mining_complete', 'mission_id': mission.id, 'player_id': mission.player_id})

    return events

def _advance_transit_back(mission: Mission, ship: Ship, dt: float) -> list[dict]:
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
        total_value = _sell_cargo(ship)
        if total_value > 0:
            logger.info('Mission %d: completed, cargo %.1fM cr', mission.id, total_value / 1e6)
        ev = {'type': 'mission_completed', 'mission_id': mission.id,
              'player_id': mission.player_id, 'ship_id': mission.ship_id}
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
