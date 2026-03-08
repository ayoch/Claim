"""Colony tier progression: colonies grow from accumulated trade revenue."""
from __future__ import annotations

# Growth points required to reach each tier (index = tier - 1)
TIER_THRESHOLDS: list[float] = [0, 500, 2500, 10_000, 40_000]

# Price multiplier applied to all ore revenue at a colony based on its tier.
# At tier 3 (default) the multiplier is 1.0 — no change from current behavior.
TIER_PRICE_MULT: dict[int, float] = {
    1: 0.85,
    2: 0.92,
    3: 1.00,
    4: 1.10,
    5: 1.22,
}

TIER_NAMES: dict[int, str] = {
    1: "Outpost",
    2: "Settlement",
    3: "Colony",
    4: "Hub",
    5: "Metropolis",
}

# 1 GP per 50k credits of revenue
_GP_PER_CREDIT: float = 1.0 / 50_000.0


def compute_tier(growth_points: float) -> int:
    tier = 1
    for i, threshold in enumerate(TIER_THRESHOLDS):
        if growth_points >= threshold:
            tier = i + 1
    return min(tier, 5)


def tier_price_multiplier(tier: int) -> float:
    return TIER_PRICE_MULT.get(tier, 1.0)


def award_growth(colony, revenue: int) -> int:
    """Award growth points from a trade sale.

    Mutates colony.growth_points and colony.tier in-place.
    Returns the new tier if it changed, otherwise 0.
    """
    old_tier = colony.tier
    colony.growth_points = (colony.growth_points or 0.0) + revenue * _GP_PER_CREDIT
    new_tier = compute_tier(colony.growth_points)
    colony.tier = new_tier
    return new_tier if new_tier != old_tier else 0
