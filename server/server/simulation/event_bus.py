"""
In-memory pub/sub for Server-Sent Events.

Multiple SSE connections subscribe to a single EventBus singleton.
The simulation loop publishes dicts; SSE handlers drain their personal queues.
"""

from __future__ import annotations

import asyncio
import logging

logger = logging.getLogger(__name__)


class EventBus:
    def __init__(self) -> None:
        self._subscribers: list[asyncio.Queue[dict]] = []

    def subscribe(self) -> asyncio.Queue[dict]:
        """Register a new SSE client. Returns a queue to drain events from."""
        q: asyncio.Queue[dict] = asyncio.Queue(maxsize=200)
        self._subscribers.append(q)
        logger.debug("EventBus: new subscriber (total=%d)", len(self._subscribers))
        return q

    def unsubscribe(self, q: asyncio.Queue[dict]) -> None:
        """Remove a client queue when the SSE connection closes."""
        try:
            self._subscribers.remove(q)
            logger.debug("EventBus: subscriber removed (total=%d)", len(self._subscribers))
        except ValueError:
            pass  # already removed

    async def publish(self, event: dict) -> None:
        """Broadcast an event to all connected clients. Drops for slow clients."""
        dead: list[asyncio.Queue[dict]] = []
        for q in self._subscribers:
            try:
                q.put_nowait(event)
            except asyncio.QueueFull:
                # Client is too slow — drop the event rather than blocking the sim
                logger.warning("EventBus: dropped event for slow subscriber")
            except Exception as exc:
                logger.error("EventBus: unexpected error publishing to subscriber: %s", exc)
                dead.append(q)
        for q in dead:
            self.unsubscribe(q)

    @property
    def subscriber_count(self) -> int:
        return len(self._subscribers)


# Module-level singleton — import this everywhere
event_bus = EventBus()
