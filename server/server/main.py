from __future__ import annotations

import asyncio
import logging
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.httpsredirect import HTTPSRedirectMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles
from slowapi.errors import RateLimitExceeded
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.middleware.sessions import SessionMiddleware

from server.blog_database import init_blog_db
from server.config import settings
from server.database import init_db
from server.rate_limit import limiter, rate_limit_handler
from server.routers import account_settings, admin, admin_speed, admin_ui, auth, blog, bug_reports, events, game, leaderboard, password_reset
from server.simulation.runner import simulation_loop

# Configure logging
log_level = getattr(logging, settings.LOG_LEVEL.upper(), logging.INFO)
logging.basicConfig(
    level=log_level,
    format="%(asctime)s %(levelname)s [%(name)s] %(message)s",
    datefmt="%Y-%m-%d %H:%M:%S",
)


logger = logging.getLogger(__name__)


class LimitUploadSize(BaseHTTPMiddleware):
    """Middleware to limit request body size."""
    def __init__(self, app, max_upload_size: int = 10 * 1024 * 1024):  # 10MB default
        super().__init__(app)
        self.max_upload_size = max_upload_size

    async def dispatch(self, request: Request, call_next):
        if request.method in ["POST", "PUT", "PATCH"]:
            content_length = request.headers.get("content-length")
            if content_length and int(content_length) > self.max_upload_size:
                return JSONResponse(
                    status_code=413,
                    content={"detail": f"Request body too large (max {self.max_upload_size} bytes)"}
                )
        return await call_next(request)


app = FastAPI(
    title="Claim Server",
    description="Space mining simulation API for the Claim game.",
    version="0.1.0",
)

# Rate limiting
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, rate_limit_handler)

# Note: HTTPSRedirectMiddleware omitted — Railway terminates TLS at the edge,
# internal health checks use plain HTTP and would be rejected by the redirect.

# Request size limiting (always enabled)
app.add_middleware(LimitUploadSize, max_upload_size=10 * 1024 * 1024)  # 10MB

# Session middleware for admin UI
app.add_middleware(
    SessionMiddleware,
    secret_key=settings.SECRET_KEY,
    session_cookie="claim_admin_session",
    max_age=86400,  # 24 hours
    https_only=settings.ENVIRONMENT == "production",
)

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
app.include_router(password_reset.router)
app.include_router(account_settings.router)
app.include_router(game.router)
app.include_router(events.router)
app.include_router(admin.router)
app.include_router(admin_speed.router)  # Speed control for testing
app.include_router(admin_ui.router)  # Admin web UI
app.include_router(leaderboard.router)
app.include_router(blog.router)
app.include_router(blog.admin_router)
app.include_router(bug_reports.router)

# Static files (website frontend)
static_dir = Path(__file__).parent.parent / "static"
static_dir.mkdir(exist_ok=True)
app.mount("/static", StaticFiles(directory=str(static_dir)), name="static")

_sim_task: asyncio.Task | None = None


@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception) -> JSONResponse:
    """Hide stack traces in production, show in development."""
    if settings.ENVIRONMENT == "production":
        logger.error(f"Unhandled exception: {exc}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error"}
        )
    else:
        # In development, let FastAPI show the full trace
        raise exc


@app.on_event("startup")
async def on_startup() -> None:
    global _sim_task
    logger.info("Claim Server starting up...")

    # Validate production settings (any non-development environment)
    if settings.ENVIRONMENT != "development":
        try:
            settings.validate_production()
            logger.info(f"Production settings validated for environment: {settings.ENVIRONMENT}")
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
    index_path = static_dir / "index.html"
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
    return FileResponse(static_dir / "blog.html")


@app.get("/post.html")
async def post_page():
    return FileResponse(static_dir / "post.html")


@app.get("/admin.html")
async def admin_page():
    return FileResponse(static_dir / "admin.html")


@app.get("/admin-blog-editor.html")
async def admin_editor_page():
    return FileResponse(static_dir / "admin-blog-editor.html")
