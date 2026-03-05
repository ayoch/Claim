"""
Worker spawning system - automatically spawns workers at colonies over time
"""
import random, logging
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from server.models.worker import Worker

MAX_AVAILABLE_PER_COLONY = 5  # Cap on unowned workers waiting at each colony

logger = logging.getLogger(__name__)

# Worker spawning accumulator - tracks time since last spawn per colony
_worker_spawn_accum: dict[int, float] = {}

async def process_worker_spawning(db: AsyncSession, dt: float) -> list[dict]:
    """
    Automatically spawn workers at colonies based on population/tier.
    Major colonies spawn more frequently than small ones.
    """
    events: list[dict] = []

    # Colony spawn intervals (in game-seconds)
    COLONY_SPAWN_INTERVALS = {
        1: 86400.0,      # Earth - 1 worker per day
        2: 86400.0 * 2,  # Lunar Base - 1 worker per 2 days
        3: 86400.0 * 2,  # Mars Colony - 1 worker per 2 days
        4: 86400.0 * 3,  # Ceres Station - 1 worker per 3 days
        5: 86400.0 * 7,  # Europa Lab - 1 worker per week
        6: 86400.0 * 7,  # Ganymede Port - 1 worker per week
        7: 86400.0 * 7,  # Vesta Refinery - 1 worker per week
        8: 86400.0 * 14, # Titan Outpost - 1 worker per 2 weeks
        9: 86400.0 * 14, # Callisto Base - 1 worker per 2 weeks
        10: 86400.0 * 14,# Triton Station - 1 worker per 2 weeks
    }

    FIRST_NAMES = ["Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Avery", "Quinn", "Reese", "Skyler",
                   "Cameron", "Dakota", "Emerson", "Finley", "Harper", "Kai", "Logan", "Parker", "River", "Sage"]
    LAST_NAMES = ["Chen", "Patel", "Smith", "Garcia", "Kim", "Johnson", "Rodriguez", "Martinez", "Lee", "Davis",
                  "Nakamura", "Singh", "Hassan", "O'Brien", "Kowalski", "Volkov", "Santos", "Anderson", "Zhang", "Ali"]

    for colony_id, spawn_interval in COLONY_SPAWN_INTERVALS.items():
        # Initialize accumulator for this colony
        if colony_id not in _worker_spawn_accum:
            _worker_spawn_accum[colony_id] = 0.0

        _worker_spawn_accum[colony_id] += dt

        # Check if enough time has passed to spawn a worker
        if _worker_spawn_accum[colony_id] >= spawn_interval:
            _worker_spawn_accum[colony_id] -= spawn_interval

            # Don't spawn if colony is already at the cap
            existing = await db.scalar(
                select(func.count(Worker.id)).where(
                    Worker.player_id == None,  # noqa: E711
                    Worker.location_colony_id == colony_id
                )
            )
            if existing >= MAX_AVAILABLE_PER_COLONY:
                continue

            # Generate random skills
            skills = [0, 1, 2]  # pilot, engineer, mining
            random.shuffle(skills)

            primary_skill = skills[0]
            secondary_skill = skills[1]
            tertiary_skill = skills[2]

            pilot_val = 0.0
            engineer_val = 0.0
            mining_val = 0.0

            primary_val = round(random.uniform(0.8, 1.5), 2)
            secondary_val = round(random.uniform(0.4, 0.9), 2)
            tertiary_val = round(random.uniform(0.0, 0.3), 2)

            if primary_skill == 0:
                pilot_val = primary_val
            elif primary_skill == 1:
                engineer_val = primary_val
            else:
                mining_val = primary_val

            if secondary_skill == 0:
                pilot_val = secondary_val
            elif secondary_skill == 1:
                engineer_val = secondary_val
            else:
                mining_val = secondary_val

            if tertiary_skill == 0:
                pilot_val = tertiary_val
            elif tertiary_skill == 1:
                engineer_val = tertiary_val
            else:
                mining_val = tertiary_val

            # Calculate wage based on total skill
            total_skill = pilot_val + engineer_val + mining_val
            base_wage = 80
            skill_bonus = int(total_skill * 40)
            wage = base_wage + skill_bonus

            # Create worker at this colony
            worker = Worker(
                player_id=None,  # Available for hire
                location_colony_id=colony_id,
                first_name=random.choice(FIRST_NAMES),
                last_name=random.choice(LAST_NAMES),
                pilot_skill=pilot_val,
                engineer_skill=engineer_val,
                mining_skill=mining_val,
                wage=wage,
                personality=random.choice([0, 1, 2, 3, 4, 5])
            )

            db.add(worker)

            events.append({
                'type': 'worker_spawned',
                'colony_id': colony_id,
                'worker_name': f"{worker.first_name} {worker.last_name}",
                'wage': wage
            })

            logger.info(f"Spawned worker {worker.first_name} {worker.last_name} at colony {colony_id}")

    return events
