from __future__ import annotations
import asyncio
import logging

from server.config import settings
from server.database import AsyncSessionLocal
from server.simulation.event_bus import event_bus
from server.simulation.tick import process_tick

logger = logging.getLogger(__name__)


async def simulation_loop(world_id: int = 1) -> None:
    '''Runs indefinitely. One real second = one game tick at 1x speed.'''
    logger.info('Simulation loop started (world_id=%d, tick_interval=%.2fs)', world_id, settings.TICK_INTERVAL)
    while True:
        loop = asyncio.get_event_loop()
        start = loop.time()
        try:
            async with AsyncSessionLocal() as db:
                events = await process_tick(db, world_id, settings.TICK_INTERVAL)
                await db.commit()
            for event in events:
                await event_bus.publish(event)
        except asyncio.CancelledError:
            logger.info('Simulation loop cancelled.')
            raise
        except Exception as exc:
            logger.exception('Simulation loop error (continuing): %s', exc)
        elapsed = asyncio.get_event_loop().time() - start
        sleep_time = max(0.0, settings.TICK_INTERVAL - elapsed)
        await asyncio.sleep(sleep_time)
