"""
Admin UI router - Web interface for server administration.

Requires admin key for all operations.
"""
import datetime as _dt
import json
from pathlib import Path

from fastapi import APIRouter, Request, Form, Depends, HTTPException
from fastapi.responses import HTMLResponse, JSONResponse, RedirectResponse
from fastapi.templating import Jinja2Templates
from sqlalchemy import select, func, delete
from sqlalchemy.ext.asyncio import AsyncSession

from server.database import get_db
from server.models.asteroid import Asteroid
from server.models.bug_report import BugReport
from server.models.equipment import Equipment
from server.models.mission import Mission
from server.models.player import Player
from server.models.rig import Rig
from server.models.ship import Ship, SHIP_CLASS_STATS, COURIER
from server.models.stockpile import Stockpile
from server.models.trade_mission import TradeMission
from server.models.worker import Worker
from server.models.world_state import WorldState
from server.config import settings

_GAME_EPOCH = _dt.datetime(2112, 1, 1, 0, 0, 0, tzinfo=_dt.timezone.utc)


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


@router.get("/dashboard-data")
async def admin_dashboard_data(request: Request, db: AsyncSession = Depends(get_db)):
    """JSON endpoint for AJAX dashboard updates."""
    admin_key = check_admin_session(request)
    if not admin_key or not await validate_admin_key(admin_key, db):
        raise HTTPException(status_code=403, detail="Unauthorized")

    thirty_days_ago = datetime.utcnow() - timedelta(days=30)

    result = await db.execute(
        select(func.count(Player.id)).where(Player.last_seen >= thirty_days_ago)
    )
    active_players = result.scalar() or 0

    result = await db.execute(select(func.count(Player.id)))
    total_players = result.scalar() or 0

    result = await db.execute(select(func.count(Ship.id)))
    total_ships = result.scalar() or 0

    result = await db.execute(
        select(func.count(Mission.id)).where(Mission.status.in_([0, 1, 2]))
    )
    active_missions = result.scalar() or 0

    result = await db.execute(select(Asteroid))
    asteroids = result.scalars().all()

    total_reserves = 0.0
    total_iron = 0.0
    total_water_ice = 0.0
    total_platinum = 0.0

    for asteroid in asteroids:
        if asteroid.reserves:
            total_reserves += sum(asteroid.reserves.values())
            total_iron += asteroid.reserves.get("iron", 0.0)
            total_water_ice += asteroid.reserves.get("water_ice", 0.0)
            total_platinum += asteroid.reserves.get("platinum", 0.0)

    MINIMUM_RESERVES_PER_PLAYER = 50_000_000
    max_players = int(total_reserves / MINIMUM_RESERVES_PER_PLAYER) if total_reserves > 0 else 0
    slots_available = max(0, max_players - active_players)
    capacity_pct = (active_players / max_players * 100) if max_players > 0 else 0

    return {
        "active_players": active_players,
        "total_players": total_players,
        "total_ships": total_ships,
        "active_missions": active_missions,
        "total_reserves": total_reserves,
        "total_iron": total_iron,
        "total_water_ice": total_water_ice,
        "total_platinum": total_platinum,
        "max_players": max_players,
        "slots_available": slots_available,
        "capacity_pct": capacity_pct,
    }


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
    try:
        admin_key = check_admin_session(request)
        if not admin_key:
            return RedirectResponse(url="/admin-ui/login", status_code=303)

        if not await validate_admin_key(admin_key, db):
            request.session.clear()
            return RedirectResponse(url="/admin-ui/login", status_code=303)

        # Get server stats
        thirty_days_ago = datetime.utcnow() - timedelta(days=30)

        # Count active players (last 30 days)
        result = await db.execute(
            select(func.count(Player.id)).where(Player.last_seen >= thirty_days_ago)
        )
        active_players = result.scalar() or 0

        # Count total players
        result = await db.execute(select(func.count(Player.id)))
        total_players = result.scalar() or 0

        # Count ships
        result = await db.execute(select(func.count(Ship.id)))
        total_ships = result.scalar() or 0

        # Count active missions
        result = await db.execute(
            select(func.count(Mission.id)).where(Mission.status.in_([0, 1, 2]))
        )
        active_missions = result.scalar() or 0

        # Calculate total reserves
        result = await db.execute(select(Asteroid))
        asteroids = result.scalars().all()

        total_reserves = 0.0
        total_iron = 0.0
        total_water_ice = 0.0
        total_platinum = 0.0

        for asteroid in asteroids:
            if asteroid.reserves:
                total_reserves += sum(asteroid.reserves.values())
                total_iron += asteroid.reserves.get("iron", 0.0)
                total_water_ice += asteroid.reserves.get("water_ice", 0.0)
                total_platinum += asteroid.reserves.get("platinum", 0.0)

        # Calculate server capacity
        MINIMUM_RESERVES_PER_PLAYER = 50_000_000  # 50M tonnes
        max_players = int(total_reserves / MINIMUM_RESERVES_PER_PLAYER) if total_reserves > 0 else 0
        slots_available = max(0, max_players - active_players)
        capacity_pct = (active_players / max_players * 100) if max_players > 0 else 0

        # Check if reserves already generated
        has_reserves = any(a.reserves and len(a.reserves) > 0 for a in asteroids)

        return templates.TemplateResponse("admin_dashboard.html", {
            "request": request,
            "admin_key": admin_key,
            "active_players": active_players,
            "total_players": total_players,
            "total_ships": total_ships,
            "active_missions": active_missions,
            "total_reserves": total_reserves,
            "total_iron": total_iron,
            "total_water_ice": total_water_ice,
            "total_platinum": total_platinum,
            "max_players": max_players,
            "slots_available": slots_available,
            "capacity_pct": capacity_pct,
            "has_reserves": has_reserves,
        })
    except Exception as e:
        import traceback
        error_html = f"""
        <html>
        <head><title>Dashboard Error</title></head>
        <body style="font-family: monospace; padding: 20px;">
            <h1>Dashboard Error</h1>
            <h2>Error: {type(e).__name__}</h2>
            <p>{str(e)}</p>
            <h3>Traceback:</h3>
            <pre>{traceback.format_exc()}</pre>
        </body>
        </html>
        """
        return HTMLResponse(content=error_html, status_code=500)


@router.get("/players", response_class=HTMLResponse)
async def admin_players(
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """Player management page."""
    try:
        admin_key = check_admin_session(request)
        if not admin_key:
            return RedirectResponse(url="/admin-ui/login", status_code=303)

        if not await validate_admin_key(admin_key, db):
            request.session.clear()
            return RedirectResponse(url="/admin-ui/login", status_code=303)

        # Get all players with their ship counts
        result = await db.execute(
            select(Player).order_by(Player.last_seen.desc())
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
                "ship_count": ship_count,
                "last_seen": player.last_seen,
                "created_at": player.created_at,
            })

        return templates.TemplateResponse("admin_players.html", {
            "request": request,
            "players": player_data,
        })
    except Exception as e:
        import traceback
        error_html = f"""
        <html>
        <head><title>Players Error</title></head>
        <body style="font-family: monospace; padding: 20px;">
            <h1>Players Page Error</h1>
            <h2>Error: {type(e).__name__}</h2>
            <p>{str(e)}</p>
            <h3>Traceback:</h3>
            <pre>{traceback.format_exc()}</pre>
        </body>
        </html>
        """
        return HTMLResponse(content=error_html, status_code=500)


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


@router.get("/bug-reports", response_class=HTMLResponse)
async def bug_reports_page(
    request: Request,
    status: str = None,
    category: str = None,
    search: str = None,
    db: AsyncSession = Depends(get_db)
):
    """Display bug reports management page."""
    admin_key = check_admin_session(request)
    if not admin_key:
        return RedirectResponse(url="/admin-ui/login", status_code=303)

    if not await validate_admin_key(admin_key, db):
        request.session.clear()
        return RedirectResponse(url="/admin-ui/login", status_code=303)

    # Build query
    query = select(BugReport).order_by(BugReport.created_at.desc())

    # Apply filters
    if status:
        query = query.where(BugReport.status == status)

    if category:
        query = query.where(BugReport.category == category)

    if search:
        search_term = f"%{search}%"
        from sqlalchemy import or_
        query = query.where(
            or_(
                BugReport.title.ilike(search_term),
                BugReport.description.ilike(search_term)
            )
        )

    # Get reports (limit to 100 for UI)
    query = query.limit(100)
    result = await db.execute(query)
    reports = result.scalars().all()

    # Get stats
    total_result = await db.execute(select(func.count()).select_from(BugReport))
    total_count = total_result.scalar() or 0

    open_result = await db.execute(
        select(func.count()).select_from(BugReport).where(BugReport.status == "open")
    )
    open_count = open_result.scalar() or 0

    in_progress_result = await db.execute(
        select(func.count()).select_from(BugReport).where(BugReport.status == "in_progress")
    )
    in_progress_count = in_progress_result.scalar() or 0

    done_result = await db.execute(
        select(func.count()).select_from(BugReport).where(BugReport.status == "done")
    )
    done_count = done_result.scalar() or 0

    # Convert reports to JSON for modal
    reports_json = json.dumps([{
        "id": r.id,
        "title": r.title,
        "description": r.description,
        "category": r.category,
        "reporter_username": r.reporter_username,
        "status": r.status,
        "game_version": r.game_version,
        "backend_mode": r.backend_mode,
        "created_at": r.created_at.strftime('%Y-%m-%d %H:%M:%S'),
        "updated_at": r.updated_at.strftime('%Y-%m-%d %H:%M:%S'),
        "admin_notes": r.admin_notes
    } for r in reports])

    return templates.TemplateResponse(
        "admin_bug_reports.html",
        {
            "request": request,
            "reports": reports,
            "reports_json": reports_json,
            "total_count": total_count,
            "open_count": open_count,
            "in_progress_count": in_progress_count,
            "done_count": done_count,
            "status_filter": status,
            "category_filter": category,
            "search_query": search,
        }
    )


@router.post("/update-bug-report")
async def update_bug_report(
    request: Request,
    report_id: int = Form(...),
    status: str = Form(...),
    admin_notes: str = Form(""),
    db: AsyncSession = Depends(get_db)
):
    """Update a bug report's status and notes."""
    admin_key = check_admin_session(request)
    if not admin_key:
        return RedirectResponse(url="/admin-ui/login", status_code=303)

    if not await validate_admin_key(admin_key, db):
        request.session.clear()
        return RedirectResponse(url="/admin-ui/login", status_code=303)

    # Find report
    result = await db.execute(select(BugReport).where(BugReport.id == report_id))
    report = result.scalar_one_or_none()

    if not report:
        raise HTTPException(status_code=404, detail="Bug report not found")

    # Update fields
    report.status = status
    if admin_notes:
        report.admin_notes = admin_notes

    await db.commit()

    return RedirectResponse(url="/admin-ui/bug-reports", status_code=303)


@router.post("/delete-bug-report")
async def delete_bug_report(
    request: Request,
    report_id: int = Form(...),
    db: AsyncSession = Depends(get_db)
):
    """Delete a bug report."""
    admin_key = check_admin_session(request)
    if not admin_key:
        return RedirectResponse(url="/admin-ui/login", status_code=303)

    if not await validate_admin_key(admin_key, db):
        request.session.clear()
        return RedirectResponse(url="/admin-ui/login", status_code=303)

    # Find report
    result = await db.execute(select(BugReport).where(BugReport.id == report_id))
    report = result.scalar_one_or_none()

    if not report:
        raise HTTPException(status_code=404, detail="Bug report not found")

    # Delete report
    await db.delete(report)
    await db.commit()

    return RedirectResponse(url="/admin-ui/bug-reports", status_code=303)


@router.post("/reset-world")
async def reset_world(
    request: Request,
    db: AsyncSession = Depends(get_db),
):
    """
    Full world reset:
    - Sets game time to current real date mapped to year 2112
    - Wipes all ships, missions, trade missions, rigs, stockpiles, equipment
    - Resets asteroid reserves to empty (preserves ore_yields for regeneration)
    - Resets all player money to starting amount, gives each one fresh Courier
    - Rebuilds NPC corp ships
    - Releases all workers from ship assignments
    """
    admin_key = check_admin_session(request)
    if not admin_key:
        return JSONResponse({"ok": False, "error": "Unauthorized"}, status_code=401)
    if not await validate_admin_key(admin_key, db):
        return JSONResponse({"ok": False, "error": "Unauthorized"}, status_code=401)

    # ── Compute new game time ──────────────────────────────────────────────────
    now_real = _dt.datetime.now(_dt.timezone.utc)
    now_2112 = now_real.replace(year=2112)
    new_ticks = int((now_2112 - _GAME_EPOCH).total_seconds())
    new_game_seconds = float(new_ticks)

    # ── Wipe game objects ──────────────────────────────────────────────────────
    await db.execute(delete(Mission))
    await db.execute(delete(TradeMission))
    await db.execute(delete(Stockpile))
    await db.execute(delete(Rig))
    await db.execute(delete(Equipment))
    await db.execute(delete(Ship))

    # ── Reset asteroid reserves ────────────────────────────────────────────────
    ast_result = await db.execute(select(Asteroid))
    for asteroid in ast_result.scalars().all():
        asteroid.reserves = {}
        db.add(asteroid)

    # ── Release workers from ship assignments ──────────────────────────────────
    w_result = await db.execute(select(Worker))
    for worker in w_result.scalars().all():
        worker.assigned_ship_id = None
        db.add(worker)

    # ── Reset players + give starting ship ────────────────────────────────────
    STARTING_MONEY = 14_000_000
    p_result = await db.execute(select(Player))
    players = p_result.scalars().all()
    human_count = 0
    for player in players:
        player.money = STARTING_MONEY
        db.add(player)
        if player.is_npc:
            continue
        human_count += 1
        stats = SHIP_CLASS_STATS[COURIER]
        ship = Ship(
            player_id=player.id,
            ship_name="Starter",
            ship_class=COURIER,
            max_thrust_g=stats["max_thrust_g"],
            thrust_setting=1.0,
            cargo_capacity=stats["cargo_capacity"],
            cargo_volume=stats["cargo_volume"],
            fuel_capacity=stats["fuel_capacity"],
            fuel=stats["fuel_capacity"],
            base_mass=stats["base_mass"],
            min_crew=stats["min_crew"],
            max_equipment_slots=stats["max_equipment_slots"],
            is_stationed=True,
            station_colony_id=None,
            current_cargo={},
            supplies={},
            position_x=1.0,
            position_y=0.0,
        )
        db.add(ship)

    # ── Rebuild NPC corp ships ─────────────────────────────────────────────────
    from server.simulation.npc_corps import reseed_npc_ships
    await db.flush()  # ensure ship deletes committed before re-inserting
    await reseed_npc_ships(db)

    # ── Update WorldState ──────────────────────────────────────────────────────
    ws_result = await db.execute(select(WorldState).where(WorldState.id == 1))
    ws = ws_result.scalar_one_or_none()
    if ws:
        ws.total_ticks = new_ticks
        ws.game_seconds = new_game_seconds
        db.add(ws)

    await db.commit()

    # ── Sync in-memory tick counters on the running simulation ────────────────
    from server.simulation.tick import reset_world_time
    reset_world_time(new_ticks, new_game_seconds)

    return JSONResponse({
        "ok": True,
        "new_ticks": new_ticks,
        "game_date": now_2112.strftime("%Y-%m-%d"),
        "human_players_reset": human_count,
    })
