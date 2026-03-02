"""
Randomized Starter Package Generator

Creates a fair but varied starting package for new players.
All players start with the same NET VALUE but different ships, crew, and equipment.
"""

import random
from sqlalchemy.ext.asyncio import AsyncSession
from server.models.player import Player
from server.models.ship import Ship, SHIP_CLASS_STATS, COURIER, HAULER, PROSPECTOR, EXPLORER
from server.models.worker import Worker

# Target net value for all players
TARGET_NET_VALUE = 14_000_000

# Ship selection weights (more Couriers and Prospectors, fewer Haulers/Explorers)
SHIP_WEIGHTS = {
    COURIER: 40,      # Common, cheap, fast
    PROSPECTOR: 35,   # Common, mining-focused
    HAULER: 15,       # Rare, expensive, slow
    EXPLORER: 10,     # Rare, expensive, long-range
}

# First names pool
FIRST_NAMES = [
    "Alex", "Jordan", "Taylor", "Morgan", "Casey", "Riley", "Avery", "Quinn",
    "Blake", "Cameron", "Dakota", "Reese", "Skyler", "Rowan", "Sage", "River",
    "Phoenix", "Harper", "Finley", "Kai", "Elliot", "Remy", "Sawyer", "Charlie",
]

# Last names pool
LAST_NAMES = [
    "Chen", "Patel", "Kim", "Silva", "Kowalski", "Nguyen", "O'Brien", "Santos",
    "Rodriguez", "Ivanov", "Hansen", "Yamamoto", "Cohen", "Müller", "Ali",
    "Dubois", "Andersson", "Rossi", "Novak", "Eriksen", "Petrov", "Garcia",
]


def _generate_ship_name(ship_class: int, used_names: set) -> str:
    """Generate a unique ship name based on class."""
    prefixes = {
        COURIER: ["Swift", "Quick", "Rapid", "Fleet", "Arrow", "Dart"],
        HAULER: ["Titan", "Colossus", "Behemoth", "Leviathan", "Atlas", "Mammoth"],
        PROSPECTOR: ["Finder", "Seeker", "Hunter", "Scout", "Explorer", "Ranger"],
        EXPLORER: ["Voyager", "Pioneer", "Odyssey", "Venture", "Quest", "Frontier"],
    }
    suffixes = ["I", "II", "III", "IV", "V", "Alpha", "Beta", "Gamma", "Delta", "Prime"]

    for _ in range(100):  # Try up to 100 times to find unique name
        prefix = random.choice(prefixes[ship_class])
        suffix = random.choice(suffixes)
        name = f"{prefix} {suffix}"
        if name not in used_names:
            used_names.add(name)
            return name

    # Fallback: add random number
    return f"{random.choice(prefixes[ship_class])} {random.randint(1000, 9999)}"


def _generate_worker() -> dict:
    """Generate a random worker with skills and wage."""
    # Random skills between 0.0 and 0.5 (beginners to intermediate)
    pilot_skill = random.uniform(0.0, 0.5)
    engineer_skill = random.uniform(0.0, 0.5)
    mining_skill = random.uniform(0.0, 0.5)

    # Total skill affects wage (80 base + 40 per skill point)
    total_skill = pilot_skill + engineer_skill + mining_skill
    wage = int(80 + total_skill * 40)

    # Random personality (0-5: nervous, reckless, loyal, mercenary, lazy, diligent)
    personality = random.randint(0, 5)

    return {
        "first_name": random.choice(FIRST_NAMES),
        "last_name": random.choice(LAST_NAMES),
        "pilot_skill": pilot_skill,
        "engineer_skill": engineer_skill,
        "mining_skill": mining_skill,
        "pilot_xp": 0.0,
        "engineer_xp": 0.0,
        "mining_xp": 0.0,
        "wage": wage,
        "loyalty": random.uniform(50.0, 80.0),
        "fatigue": 0.0,
        "personality": personality,
        "is_available": True,
        "leave_status": 0,  # 0 = AVAILABLE
    }


async def create_starter_package(db: AsyncSession, player: Player) -> dict:
    """
    Create a randomized starter package for a new player.

    Returns a dict with:
        - ships_created: int
        - workers_created: int
        - money_spent: int
        - money_remaining: int
    """
    budget = TARGET_NET_VALUE
    money_spent = 0
    ships_created = 0
    workers_created = 0
    used_ship_names = set()

    # Strategy: Build 1-3 ships until we've spent ~85% of budget
    target_ship_spending = int(budget * 0.85)

    while money_spent < target_ship_spending and ships_created < 3:
        # Randomly select ship class (weighted)
        ship_class = random.choices(
            list(SHIP_WEIGHTS.keys()),
            weights=list(SHIP_WEIGHTS.values()),
            k=1
        )[0]

        ship_price = SHIP_CLASS_STATS[ship_class]["base_price"]

        # Can we afford it?
        if money_spent + ship_price > target_ship_spending:
            # Try a cheaper ship class
            if ship_class in [HAULER, EXPLORER]:
                ship_class = random.choice([COURIER, PROSPECTOR])
                ship_price = SHIP_CLASS_STATS[ship_class]["base_price"]

            # Still can't afford? Break
            if money_spent + ship_price > target_ship_spending:
                break

        # Create the ship
        stats = SHIP_CLASS_STATS[ship_class]
        ship = Ship(
            player_id=player.id,
            ship_name=_generate_ship_name(ship_class, used_ship_names),
            ship_class=ship_class,
            max_thrust_g=stats["max_thrust_g"],
            thrust_setting=1.0,
            cargo_capacity=stats["cargo_capacity"],
            cargo_volume=stats["cargo_volume"],
            fuel_capacity=stats["fuel_capacity"],
            fuel=stats["fuel_capacity"],  # Start with full tank
            base_mass=stats["base_mass"],
            min_crew=stats["min_crew"],
            max_equipment_slots=stats["max_equipment_slots"],
            engine_condition=100.0,
            is_derelict=False,
            position_x=1.0,  # Earth position
            position_y=0.0,
            is_stationed=True,
            station_colony_id=1,  # Earth (colony ID 1)
            current_cargo={},
            supplies={},
        )

        db.add(ship)
        money_spent += ship_price
        ships_created += 1

    # Commit ships so we can assign workers to them
    await db.commit()
    await db.refresh(player)

    # Now hire workers to crew the ships
    # Each ship needs min_crew, plus we'll add a few extras
    total_crew_needed = sum(ship.min_crew for ship in player.ships)
    extra_workers = random.randint(1, 3)  # 1-3 backup workers
    total_workers = total_crew_needed + extra_workers

    for _ in range(total_workers):
        worker_data = _generate_worker()
        worker = Worker(
            player_id=player.id,
            **worker_data
        )
        db.add(worker)
        workers_created += 1

        # Rough wage cost estimate (assume 30 days = 1 month salary reserve)
        money_spent += worker_data["wage"] * 30

    # Adjust player money to match actual spending
    # Player starts with TARGET_NET_VALUE, we spent some on ships/crew
    player.money = TARGET_NET_VALUE - money_spent
    db.add(player)

    await db.commit()

    return {
        "ships_created": ships_created,
        "workers_created": workers_created,
        "money_spent": money_spent,
        "money_remaining": player.money,
    }
