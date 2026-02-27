from __future__ import annotations

import asyncio
import logging

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
from slowapi.errors import RateLimitExceeded
from pathlib import Path

from server.config import settings
from server.database import init_db
from server.blog_database import init_blog_db
from server.rate_limit import limiter, rate_limit_handler
from server.routers import admin, auth, events, game, leaderboard, blog
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

# Rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, rate_limit_handler)

# CORS — configured via environment variables
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Authorization", "Content-Type"],
    max_age=3600,  # Cache preflight for 1 hour
)

# API Routers
app.include_router(auth.router)
app.include_router(game.router)
app.include_router(events.router)
app.include_router(admin.router)
app.include_router(leaderboard.router)
app.include_router(blog.router)
app.include_router(blog.admin_router)

# Static files (website frontend)
static_dir = Path(__file__).parent.parent / "static"
static_dir.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

_sim_task: asyncio.Task | None = None


@app.on_event("startup")
async def on_startup() -> None:
    global _sim_task
    logger.info("Claim Server starting up...")

    # Validate production settings
    if settings.ENVIRONMENT == "production":
        try:
            settings.validate_production()
            logger.info("Production settings validated successfully")
        except ValueError as e:
            logger.error(f"Production validation failed: {e}")
            raise

    await init_db()
    await init_blog_db()
    logger.info("Blog database initialized")

    _sim_task = asyncio.create_task(simulation_loop(world_id=1), name="simulation_loop")
    logger.info("Simulation loop started for world: %s", settings.WORLD_NAME)


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
    """Serve the website homepage."""
    index_path = Path(__file__).parent.parent / "static" / "index.html"
    if index_path.exists():
        return FileResponse(index_path)
    # Fallback if no static site yet
    return {
        "name": "Claim Server",
        "version": "0.1.0",
        "docs": "/docs",
        "events": "/events/stream",
    }


@app.get("/health")
async def health():
    return {"status": "ok"}


# Serve HTML pages
@app.get("/blog.html")
async def blog_page():
    return FileResponse(Path(__file__).parent.parent / "static" / "blog.html")


@app.get("/post.html")
async def post_page():
    return FileResponse(Path(__file__).parent.parent / "static" / "post.html")


@app.get("/admin.html")
async def admin_page():
    return FileResponse(Path(__file__).parent.parent / "static" / "admin.html")


@app.get("/admin-blog-editor.html")
async def admin_editor_page():
    return FileResponse(Path(__file__).parent.parent / "static" / "admin-blog-editor.html")
