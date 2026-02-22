from __future__ import annotations

import asyncio
import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from server.database import init_db
from server.routers import admin, auth, events, game
from server.simulation.runner import simulation_loop

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

app = FastAPI(
    title="Claim Server",
    description="Space mining simulation API for the Claim game.",
    version="0.1.0",
)

# CORS — allow all origins for local dev
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Routers
app.include_router(auth.router)
app.include_router(game.router)
app.include_router(events.router)
app.include_router(admin.router)

_sim_task: asyncio.Task | None = None


@app.on_event("startup")
async def on_startup() -> None:
    global _sim_task
    logger.info("Claim Server starting up...")
    await init_db()
    _sim_task = asyncio.create_task(simulation_loop(world_id=1), name="simulation_loop")
    logger.info("Simulation loop started.")


@app.on_event("shutdown")
async def on_shutdown() -> None:
    global _sim_task
    if _sim_task and not _sim_task.done():
        _sim_task.cancel()
        try:
            await _sim_task
        except asyncio.CancelledError:
            pass
    logger.info("Claim Server shut down.")


@app.get("/")
async def root():
    return {
        "name": "Claim Server",
        "version": "0.1.0",
        "docs": "/docs",
        "events": "/events/stream",
    }


@app.get("/health")
async def health():
    return {"status": "ok"}
