"""Market event simulation — random world-wide price shocks."""

import logging
import random

from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from server.models.market_event import MarketEvent

logger = logging.getLogger(__name__)

# Each template: (ore_type, mult_min, mult_max, dur_days_min, dur_days_max, headline)
_EVENT_TEMPLATES = [
    # Shortages / demand spikes (multiplier > 1)
    ("nickel",    1.30, 1.60,  5, 14, "Trojan belt mining disruption — nickel supply constrained"),
    ("platinum",  1.40, 1.80,  7, 21, "Refinery accident at Callisto station — platinum output halted"),
    ("cobalt",    1.35, 1.65,  6, 14, "Pirate raid on supply convoy — cobalt shortage at inner colonies"),
    ("gold",      1.30, 1.55,  5, 12, "Depletion survey confirms lower-than-expected gold concentrations"),
    ("water_ice", 1.25, 1.50,  4, 10, "Jupiter colony population surge drives water ice demand"),
    ("palladium", 1.50, 2.00,  8, 21, "Deep-space survey team lost — palladium region inaccessible"),
    ("troilite",  1.30, 1.60,  5, 14, "Belt refinery explosion destroys troilite stockpile"),
    ("iron",      1.20, 1.45,  5, 10, "Mars terraforming programme drives iron demand beyond supply"),
    ("cobalt",    1.30, 1.60,  7, 14, "New battery tech breakthrough — cobalt demand surges across colonies"),
    ("platinum",  1.35, 1.65,  6, 14, "Fuel cell manufacturing contracts — platinum demand spikes"),
    ("gold",      1.25, 1.50,  5, 12, "Interplanetary banking consortium increases gold reserves"),
    # Surpluses (multiplier < 1)
    ("silicon",   0.55, 0.75,  5, 12, "Massive silicon-rich asteroid redirected to Earth orbit — prices crash"),
    ("iron",      0.60, 0.80,  4, 10, "Automated mining bots flood inner market with iron"),
    ("carbon",    0.50, 0.72,  5, 12, "Comet intercept yields record carbon haul"),
    ("nickel",    0.60, 0.78,  5, 10, "Record nickel production quarter from main belt operations"),
    ("olivine",   0.55, 0.75,  4, 10, "New olivine deposit opened — oversupply expected for weeks"),
    ("pyroxene",  0.58, 0.78,  5, 12, "Rival corp dumps pyroxene reserves — market flooded"),
    ("water_ice", 0.60, 0.80,  4,  9, "Automated ice harvester network exceeds quota — prices drop"),
    ("troilite",  0.62, 0.80,  4, 10, "Troilite processing efficiency breakthrough floods the market"),
]

_CHECK_INTERVAL = 3600.0   # game-seconds between event roll checks (1 game-hour)
_EVENT_CHANCE   = 0.18     # 18% chance of new event each check
_MAX_ACTIVE     = 3        # max concurrent events

# In-memory multiplier cache: ore_type -> multiplier
_active_multipliers: dict[str, float] = {}
_ticks_since_check: float = 0.0


def get_event_multipliers() -> dict[str, float]:
    """Return current event price multipliers (ore_type -> float)."""
    return dict(_active_multipliers)


async def load_active_events(db: AsyncSession) -> None:
    """Called on server startup to restore in-memory multiplier cache from DB."""
    global _active_multipliers
    stmt = select(MarketEvent).where(MarketEvent.is_active == True)  # noqa: E712
    result = await db.execute(stmt)
    active = result.scalars().all()
    _active_multipliers = {ev.ore_type: ev.multiplier for ev in active}
    if _active_multipliers:
        logger.info("Loaded %d active market events from DB", len(_active_multipliers))


async def process_market_events(
    db: AsyncSession,
    total_ticks: float,
    dt: float,
) -> list[dict]:
    """
    Called each tick. Returns list of new event dicts for the event log.
    Expires old events, maybe spawns new ones, rebuilds the multiplier cache.
    """
    global _ticks_since_check, _active_multipliers

    _ticks_since_check += dt
    if _ticks_since_check < _CHECK_INTERVAL:
        return []
    _ticks_since_check = 0.0

    new_event_log: list[dict] = []

    # Expire finished events
    stmt = select(MarketEvent).where(MarketEvent.is_active == True)  # noqa: E712
    result = await db.execute(stmt)
    active = list(result.scalars().all())

    for ev in active:
        if total_ticks >= ev.start_tick + ev.duration_ticks:
            ev.is_active = False
            logger.info("Market event expired: %s", ev.headline)

    await db.flush()

    # Reload active list after expiry
    stmt = select(MarketEvent).where(MarketEvent.is_active == True)  # noqa: E712
    result = await db.execute(stmt)
    active = list(result.scalars().all())
    active_ores = {ev.ore_type for ev in active}

    # Maybe spawn a new event
    if len(active) < _MAX_ACTIVE and random.random() < _EVENT_CHANCE:
        candidates = [t for t in _EVENT_TEMPLATES if t[0] not in active_ores]
        if candidates:
            ore, mult_min, mult_max, dur_min, dur_max, headline = random.choice(candidates)
            multiplier = round(random.uniform(mult_min, mult_max), 3)
            duration = random.uniform(dur_min * 86400.0, dur_max * 86400.0)

            ev = MarketEvent(
                ore_type=ore,
                multiplier=multiplier,
                start_tick=total_ticks,
                duration_ticks=duration,
                headline=headline,
                is_active=True,
            )
            db.add(ev)
            await db.flush()
            active.append(ev)

            new_event_log.append({
                "type": "market_event",
                "ore_type": ore,
                "multiplier": multiplier,
                "headline": headline,
                "duration_days": round(duration / 86400.0, 1),
            })
            logger.info(
                "New market event: %s (x%.2f, %.1f days)",
                headline, multiplier, duration / 86400.0
            )

    # Rebuild multiplier cache
    _active_multipliers = {ev.ore_type: ev.multiplier for ev in active}
    return new_event_log
