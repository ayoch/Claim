from __future__ import annotations
import asyncio
import logging

from server.config import settings
from server.database import AsyncSessionLocal
from server.simulation.event_bus import event_bus
from server.simulation.tick import process_tick
from server.routers import admin_speed

logger = logging.getLogger(__name__)


async def simulation_loop(world_id: int = 1) -> None:
    '''Runs indefinitely. One real second = one game tick at 1x speed (adjustable via admin endpoint).'''
    logger.info('Simulation loop started (world_id=%d, base_tick_interval=%.2fs)', world_id, settings.TICK_INTERVAL)
    while True:
        loop = asyncio.get_event_loop()
        start = loop.time()

        # Get current speed multiplier (adjustable via /admin/set-speed)
        speed_multiplier = admin_speed.get_speed_multiplier()
        effective_tick_interval = settings.TICK_INTERVAL / speed_multiplier
        dt = settings.TICK_INTERVAL * speed_multiplier  # Process more game time at higher speeds

        try:
            async with AsyncSessionLocal() as db:
                try:
                    events = await process_tick(db, world_id, dt)
                    await db.commit()
                except Exception as tick_exc:
                    logger.exception('Tick processing error, rolling back: %s', tick_exc)
                    await db.rollback()
                    events = []  # Don't publish events from failed tick
            for event in events:
                await event_bus.publish(event)
        except asyncio.CancelledError:
            logger.info('Simulation loop cancelled.')
            raise
        except Exception as exc:
            logger.exception('Simulation loop error (continuing): %s', exc)

        elapsed = asyncio.get_event_loop().time() - start
        sleep_time = max(0.0, effective_tick_interval - elapsed)
        await asyncio.sleep(sleep_time)
