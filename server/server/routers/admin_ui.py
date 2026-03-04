"""
Admin UI router - Web interface for server administration.

Requires admin key for all operations.
"""
from pathlib import Path
from fastapi import APIRouter, Request, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import select, func
from sqlalchemy.ext.asyncio import AsyncSession
from datetime import datetime, timedelta

from server.database import get_db
from server.models.player import Player
from server.models.ship import Ship
from server.models.mission import Mission
from server.models.asteroid import Asteroid
from server.config import settings


router = APIRouter(prefix="/admin-ui", tags=["admin-ui"])

# Templates directory is at server/templates (one level up from server/server)
templates_dir = Path(__file__).parent.parent.parent / "templates"
print(f"Admin UI templates directory: {templates_dir}")
print(f"Templates directory exists: {templates_dir.exists()}")
if templates_dir.exists():
    print(f"Templates files: {list(templates_dir.glob('*.html'))}")
templates = Jinja2Templates(directory=str(templates_dir))


def check_admin_session(request: Request):
    """Check if admin key is in session."""
    admin_key = request.session.get("admin_key")
    if not admin_key:
        return None
    return admin_key


async def validate_admin_key(admin_key: str, db: AsyncSession) -> bool:
    """Validate admin key against database."""
    from sqlalchemy import select

    # Check if any admin player exists with this key
    result = await db.execute(
        select(Player).where(Player.is_admin == True)
    )
    admin_players = result.scalars().all()

    # For now, just check against settings.ADMIN_KEY
    # In the future, you could store admin keys in a separate table
    return admin_key == settings.ADMIN_KEY


@router.get("/login", response_class=HTMLResponse)
async def admin_login_page(request: Request):
    """Display admin login form."""
    return templates.TemplateResponse("admin_login.html", {"request": request})


@router.post("/login")
async def admin_login(request: Request, admin_key: str = Form(...)):
    """Process admin login."""
    # Store in session
    request.session["admin_key"] = admin_key
    return RedirectResponse(url="/admin-ui/dashboard", status_code=303)


@router.get("/logout")
async def admin_logout(request: Request):
    """Clear admin session."""
    request.session.clear()
    return RedirectResponse(url="/admin-ui/login", status_code=303)


@router.get("/debug")
async def admin_debug(request: Request, db: AsyncSession = Depends(get_db)):
    """Debug endpoint to test functionality."""
    import traceback
    try:
        admin_key = check_admin_session(request)
        is_valid = await validate_admin_key(admin_key or "invalid", db) if admin_key else False

        # Test database query
        result = await db.execute(select(func.count(Player.id)))
        player_count = result.scalar() or 0

        return {
            "templates_dir": str(templates_dir),
            "templates_exist": templates_dir.exists(),
            "templates_files": [str(f.name) for f in templates_dir.glob("*.html")] if templates_dir.exists() else [],
            "admin_key_in_session": admin_key is not None,
            "admin_key_valid": is_valid,
            "player_count": player_count,
            "settings_admin_key_set": bool(settings.ADMIN_KEY),
        }
    except Exception as e:
        return {
            "error": str(e),
            "traceback": traceback.format_exc()
        }


@router.get("/dashboard", response_class=HTMLResponse)
async def admin_dashboard(
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """Main admin dashboard."""
    # Simple test - just return plain HTML
    return HTMLResponse(content="""
    <html>
    <head><title>Test Dashboard</title></head>
    <body>
        <h1>Admin Dashboard Test</h1>
        <p>If you can see this, routing and auth are working!</p>
        <p>Session check and template rendering will be added back once this works.</p>
    </body>
    </html>
    """)


@router.get("/players", response_class=HTMLResponse)
async def admin_players(
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """Player management page."""
    admin_key = check_admin_session(request)
    if not admin_key:
        return RedirectResponse(url="/admin-ui/login", status_code=303)

    if not await validate_admin_key(admin_key, db):
        request.session.clear()
        return RedirectResponse(url="/admin-ui/login", status_code=303)

    # Get all players with their ship counts
    result = await db.execute(
        select(Player).order_by(Player.last_login.desc())
    )
    players = result.scalars().all()

    # Get ship counts for each player
    player_data = []
    for player in players:
        result = await db.execute(
            select(func.count(Ship.id)).where(Ship.player_id == player.id)
        )
        ship_count = result.scalar() or 0

        player_data.append({
            "id": player.id,
            "username": player.username,
            "email": player.email,
            "money": player.money,
            "reputation": player.reputation,
            "total_ticks": player.total_ticks,
            "ship_count": ship_count,
            "last_login": player.last_login,
            "created_at": player.created_at,
        })

    return templates.TemplateResponse("admin_players.html", {
        "request": request,
        "players": player_data,
    })


@router.get("/asteroids", response_class=HTMLResponse)
async def admin_asteroids(
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """Asteroid reserves browser."""
    admin_key = check_admin_session(request)
    if not admin_key:
        return RedirectResponse(url="/admin-ui/login", status_code=303)

    if not await validate_admin_key(admin_key, db):
        request.session.clear()
        return RedirectResponse(url="/admin-ui/login", status_code=303)

    # Get all asteroids with reserves
    result = await db.execute(
        select(Asteroid).order_by(Asteroid.semi_major_axis)
    )
    asteroids = result.scalars().all()

    asteroid_data = []
    for asteroid in asteroids:
        if not asteroid.reserves:
            continue

        total_reserves = sum(asteroid.reserves.values())
        total_original = sum(asteroid.original_reserves.values()) if asteroid.original_reserves else total_reserves

        depletion_pct = 0
        if total_original > 0:
            depletion_pct = ((total_original - total_reserves) / total_original) * 100

        asteroid_data.append({
            "id": asteroid.id,
            "name": asteroid.asteroid_name,
            "body_type": asteroid.body_type,
            "semi_major_axis": asteroid.semi_major_axis,
            "mass_kg": asteroid.estimated_mass_kg,
            "total_reserves": total_reserves,
            "total_original": total_original,
            "depletion_pct": depletion_pct,
            "iron": asteroid.reserves.get("iron", 0),
            "nickel": asteroid.reserves.get("nickel", 0),
            "platinum": asteroid.reserves.get("platinum", 0),
            "water_ice": asteroid.reserves.get("water_ice", 0),
        })

    return templates.TemplateResponse("admin_asteroids.html", {
        "request": request,
        "asteroids": asteroid_data,
    })


@router.post("/grant-money")
async def admin_grant_money(
    request: Request,
    player_id: int = Form(...),
    amount: int = Form(...),
    db: AsyncSession = Depends(get_db)
):
    """Grant money to a player."""
    admin_key = check_admin_session(request)
    if not admin_key:
        return RedirectResponse(url="/admin-ui/login", status_code=303)

    if not await validate_admin_key(admin_key, db):
        request.session.clear()
        return RedirectResponse(url="/admin-ui/login", status_code=303)

    # Find player
    result = await db.execute(select(Player).where(Player.id == player_id))
    player = result.scalar_one_or_none()

    if not player:
        raise HTTPException(status_code=404, detail="Player not found")

    # Grant money
    player.money += amount
    await db.commit()

    return RedirectResponse(url="/admin-ui/players", status_code=303)
