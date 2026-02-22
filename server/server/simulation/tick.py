from __future__ import annotations
import logging, math, random
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from sqlalchemy.orm import selectinload
from server.models.mission import (
    Mission, STATUS_COMPLETED, STATUS_MINING, STATUS_TRANSIT_BACK, STATUS_TRANSIT_OUT,
)
from server.models.player import Player
from server.models.ship import Ship
from server.models.worker import Worker

logger = logging.getLogger(__name__)

BASE_ORE_PRICES: dict[str, float] = {
    'nickel': 4200, 'iron': 1800, 'cobalt': 18000, 'platinum': 340000,
    'gold': 420000, 'silicon': 2100, 'water_ice': 800, 'carbon': 1500,
    'olivine': 950, 'pyroxene': 1100, 'troilite': 3600, 'palladium': 280000,
}
_market_prices: dict[str, float] = dict(BASE_ORE_PRICES)
_payroll_accum: dict[int, float] = {}
_total_ticks: int = 0

def get_market_prices() -> dict[str, float]:
    return dict(_market_prices)

def get_total_ticks() -> int:
    return _total_ticks

async def process_tick(db: AsyncSession, world_id: int, dt: float) -> list[dict]:
    global _total_ticks
    _total_ticks += 1
    events: list[dict] = []
    try:
        events += await _process_missions(db, dt)
        events += await _process_market(dt)
        events += await _process_payroll(db, dt)
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
    if mission.elapsed_ticks >= mission.transit_time:
        mission.status = STATUS_MINING
        mission.elapsed_ticks = 0.0
        ship.is_stationed = False
        logger.info('Mission %d: arrived, starting mining', mission.id)
        return [{'type': 'mission_arrived', 'mission_id': mission.id, 'player_id': mission.player_id}]
    return []

def _advance_mining(mission: Mission, ship: Ship, dt: float) -> list[dict]:
    mission.elapsed_ticks += dt
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
        return [{'type': 'mission_mining_complete', 'mission_id': mission.id, 'player_id': mission.player_id}]
    return []

def _advance_transit_back(mission: Mission, ship: Ship, dt: float) -> list[dict]:
    mission.elapsed_ticks += dt
    ship.fuel = max(0.0, ship.fuel - mission.fuel_per_tick * dt)
    if mission.elapsed_ticks >= mission.transit_time:
        mission.status = STATUS_COMPLETED
        ship.is_stationed = True
        ship.station_colony_id = None
        total_value = _sell_cargo(ship)
        if total_value > 0:
            logger.info('Mission %d: completed, cargo %.1fM cr', mission.id, total_value / 1e6)
        ev = {'type': 'mission_completed', 'mission_id': mission.id,
              'player_id': mission.player_id, 'ship_id': mission.ship_id}
        if total_value > 0:
            ev['cargo_value'] = total_value
        return [ev]
    return []

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
