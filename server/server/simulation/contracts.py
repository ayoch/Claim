"""Contract generation and processing."""

import logging
import random
from sqlalchemy import func, select
from sqlalchemy.ext.asyncio import AsyncSession
from server.models.contract import Contract, STATUS_AVAILABLE, STATUS_ACCEPTED, STATUS_EXPIRED, STATUS_FAILED, STATUS_COMPLETED
from server.models.colony import Colony

logger = logging.getLogger(__name__)

# Contract generation settings
CONTRACT_INTERVAL = 14400.0  # Check every 4 game-hours
CONTRACT_GENERATION_CHANCE = 0.4  # 40% chance per interval
MAX_AVAILABLE_CONTRACTS = 10

# Contract parameters
MIN_DEADLINE_DAYS = 5
MAX_DEADLINE_DAYS = 20
PARTIAL_DELIVERY_CHANCE = 0.7  # 70% of contracts allow partial delivery

# Ore types and value tiers
ORE_TIERS = {
    "common": ["iron", "nickel", "silicon", "carbon"],
    "uncommon": ["cobalt", "water_ice", "olivine", "pyroxene"],
    "rare": ["troilite", "palladium", "gold", "platinum"],
}

_accumulated_time = 0.0


async def process_contracts(db: AsyncSession, dt: float) -> list[dict]:
    """
    Process contract generation, expiration, and failure.
    Returns list of events for SSE broadcasting.
    """
    global _accumulated_time
    _accumulated_time += dt

    events: list[dict] = []

    # Tick down active contract deadlines
    result = await db.execute(
        select(Contract).where(Contract.status == STATUS_ACCEPTED)
    )
    active_contracts = list(result.scalars().all())

    for contract in active_contracts:
        contract.deadline_ticks -= dt

        if contract.deadline_ticks <= 0:
            # Check if contract was fulfilled
            if contract.is_complete():
                contract.status = STATUS_COMPLETED
                contract.completed_at = func.now()
                events.append({
                    "type": "contract_completed",
                    "contract_id": contract.id,
                    "player_id": contract.player_id,
                    "reward": contract.reward,
                    "ore_type": contract.ore_type,
                    "quantity_delivered": contract.quantity_delivered,
                })
                logger.info(f"Contract {contract.id} completed by player {contract.player_id}")

            elif contract.allows_partial and contract.quantity_delivered > 0:
                # Partial delivery - pay proportional reward
                partial_reward = int(contract.reward * contract.get_progress())
                contract.status = STATUS_COMPLETED
                contract.completed_at = func.now()
                events.append({
                    "type": "contract_partial_completed",
                    "contract_id": contract.id,
                    "player_id": contract.player_id,
                    "reward": partial_reward,
                    "quantity_delivered": contract.quantity_delivered,
                    "quantity_required": contract.quantity,
                })
                logger.info(f"Contract {contract.id} partially completed ({contract.get_progress():.0%})")

            else:
                # Failed - no delivery or partial not allowed
                contract.status = STATUS_FAILED
                events.append({
                    "type": "contract_failed",
                    "contract_id": contract.id,
                    "player_id": contract.player_id,
                    "ore_type": contract.ore_type,
                })
                logger.info(f"Contract {contract.id} failed (no delivery)")

        db.add(contract)

    # Generate new contracts periodically
    if _accumulated_time >= CONTRACT_INTERVAL:
        _accumulated_time -= CONTRACT_INTERVAL

        if random.random() < CONTRACT_GENERATION_CHANCE:
            # Check how many available contracts exist
            count_result = await db.execute(
                select(Contract).where(Contract.status == STATUS_AVAILABLE)
            )
            available_count = len(list(count_result.scalars().all()))

            if available_count < MAX_AVAILABLE_CONTRACTS:
                new_contract = await _generate_contract(db)
                if new_contract:
                    db.add(new_contract)
                    events.append({
                        "type": "contract_offered",
                        "contract_id": new_contract.id,
                        "ore_type": new_contract.ore_type,
                        "quantity": new_contract.quantity,
                        "reward": new_contract.reward,
                        "deadline_days": new_contract.deadline_ticks / 86400.0,
                        "issuer_name": new_contract.issuer_name,
                        "allows_partial": new_contract.allows_partial,
                    })
                    logger.info(f"Generated new contract: {new_contract.ore_type} x{new_contract.quantity}t for ${new_contract.reward:,}")

    return events


async def _generate_contract(db: AsyncSession) -> Contract | None:
    """Generate a new random contract."""
    # Select ore tier and type
    tier = random.choices(
        ["common", "uncommon", "rare"],
        weights=[0.6, 0.3, 0.1],  # 60% common, 30% uncommon, 10% rare
        k=1
    )[0]
    ore_type = random.choice(ORE_TIERS[tier])

    # Base prices (approximate from MarketData)
    base_prices = {
        "iron": 1800, "nickel": 4200, "silicon": 2100, "carbon": 1500,
        "cobalt": 18000, "water_ice": 800, "olivine": 950, "pyroxene": 1100,
        "troilite": 3600, "palladium": 280000, "gold": 420000, "platinum": 340000,
    }

    base_price = base_prices.get(ore_type, 5000)

    # Quantity based on rarity (more common = larger quantities)
    if tier == "common":
        quantity = random.uniform(200, 800)
    elif tier == "uncommon":
        quantity = random.uniform(50, 300)
    else:  # rare
        quantity = random.uniform(10, 100)

    # Calculate reward (1.2x to 1.8x market value)
    multiplier = random.uniform(1.2, 1.8)
    reward = int(quantity * base_price * multiplier)

    # Deadline (5-20 game-days)
    deadline_days = random.uniform(MIN_DEADLINE_DAYS, MAX_DEADLINE_DAYS)
    deadline_ticks = deadline_days * 86400.0

    # Random issuer name
    issuers = [
        "Helion Industries", "Ceres Mining Co.", "Orbital Dynamics",
        "Asteroid Resources Inc.", "Deep Space Logistics", "Belt Mining Guild",
        "Planetary Materials", "Void Extractors", "Kuiper Consortium",
        "Trans-Neptunian Trading", "Euterpe Refineries", "Oort Cloud Mining",
    ]
    issuer_name = random.choice(issuers)

    # Partial delivery allowed?
    allows_partial = random.random() < PARTIAL_DELIVERY_CHANCE

    # Optional: Delivery to specific colony (80% chance it's Earth/null)
    delivery_colony_id = None
    if random.random() < 0.2:
        # Pick a random colony
        colonies_result = await db.execute(select(Colony))
        colonies = list(colonies_result.scalars().all())
        if colonies:
            delivery_colony_id = random.choice(colonies).id

    contract = Contract(
        ore_type=ore_type,
        quantity=quantity,
        reward=reward,
        deadline_ticks=deadline_ticks,
        issuer_name=issuer_name,
        allows_partial=allows_partial,
        delivery_colony_id=delivery_colony_id,
        status=STATUS_AVAILABLE,
    )

    return contract
