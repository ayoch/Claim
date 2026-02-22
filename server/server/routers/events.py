from __future__ import annotations
import asyncio
import json
import logging
from fastapi import APIRouter, Depends
from fastapi.responses import StreamingResponse
from server.auth import get_current_player
from server.models.player import Player
from server.simulation.event_bus import event_bus

router = APIRouter(prefix="/events", tags=["events"])
logger = logging.getLogger(__name__)


def _sse_line(event: dict) -> str:
    return "data: " + json.dumps(event) + "

"


@router.get("/stream")
async def stream_events(player: Player = Depends(get_current_player)):
    """Server-Sent Events stream. Auth via Bearer token in query or header."""

    async def event_generator():
        q = event_bus.subscribe()
        try:
            connected = {"type": "connected", "player_id": player.id}
            yield _sse_line(connected)
            while True:
                try:
                    event = await asyncio.wait_for(q.get(), timeout=30.0)
                    player_id = event.get("player_id")
                    if player_id is None or player_id == player.id:
                        yield _sse_line(event)
                except asyncio.TimeoutError:
                    yield ": keepalive

"
                except asyncio.CancelledError:
                    break
        except Exception as exc:
            logger.error("SSE stream error for player 0: ", player.id, exc)
        finally:
            event_bus.unsubscribe(q)
            logger.info("SSE client disconnected (player 0)", player.id)

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "X-Accel-Buffering": "no",
        },
    )
