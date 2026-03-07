"""
Admin Speed Control - For Testing Only

Allows admins to adjust server simulation speed during development/testing.
WARNING: This affects ALL players simultaneously!
"""

import logging
from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from server.auth import get_current_player
from server.database import get_db
from server.models.player import Player
from server.models.world_state import WorldState
from server.rate_limit import limiter
from server.config import settings

router = APIRouter(prefix="/admin", tags=["admin"])
logger = logging.getLogger(__name__)

# Global simulation speed multiplier
# 1.0 = normal speed (1 tick per second)
# 10.0 = 10x speed (10 ticks per second)
# 100.0 = 100x speed (100 ticks per second)
_simulation_speed_multiplier: float = 1.0


class SpeedUpdate(BaseModel):
    multiplier: float = Field(..., ge=0.1, le=200000.0, description="Speed multiplier (0.1x to 200000x)")


def require_admin(player: Player = Depends(get_current_player)) -> Player:
    """Dependency that checks if player is admin."""
    if not player.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")
    return player


@router.post("/set-speed")
@limiter.limit("30/minute")  # Allow frequent speed changes during testing
async def set_simulation_speed(
    request: Request,
    payload: SpeedUpdate,
    player: Player = Depends(require_admin),
    db: AsyncSession = Depends(get_db),
):
    """
    Set simulation speed multiplier.
    WARNING: Affects ALL players!
    """
    global _simulation_speed_multiplier
    old_speed = _simulation_speed_multiplier
    _simulation_speed_multiplier = payload.multiplier

    # Persist to DB so speed survives server restarts
    result = await db.execute(select(WorldState).where(WorldState.world_id == 1))
    world_state = result.scalar_one_or_none()
    if world_state:
        world_state.speed_multiplier = _simulation_speed_multiplier
        await db.commit()

    logger.info(
        f"Admin {player.username} changed simulation speed: {old_speed}x → {payload.multiplier}x"
    )

    return {
        "old_speed": old_speed,
        "new_speed": _simulation_speed_multiplier,
        "message": f"Simulation speed set to {payload.multiplier}x"
    }


@router.get("/speed")
async def get_simulation_speed(player: Player = Depends(get_current_player)):
    """Get current simulation speed multiplier."""
    return {
        "speed": _simulation_speed_multiplier,
        "tick_interval": settings.TICK_INTERVAL / _simulation_speed_multiplier,
    }


def get_speed_multiplier() -> float:
    """Get current speed multiplier for use by simulation loop."""
    return _simulation_speed_multiplier
