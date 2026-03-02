import logging
import re
from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, Request, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from server.auth import create_access_token, get_current_player, hash_password, verify_password
from server.database import get_db
from server.models.player import Player
from server.rate_limit import limiter
from server.schemas.player import PlayerCreate, PlayerOut, Token
from server.starter_package import create_starter_package

router = APIRouter(prefix="/auth", tags=["auth"])
logger = logging.getLogger(__name__)


def validate_password_strength(password: str) -> None:
    """Validate password meets security requirements."""
    if len(password) < 12:
        raise HTTPException(
            status_code=400,
            detail="Password must be at least 12 characters long"
        )
    if not re.search(r"[A-Z]", password):
        raise HTTPException(
            status_code=400,
            detail="Password must contain at least one uppercase letter"
        )
    if not re.search(r"[a-z]", password):
        raise HTTPException(
            status_code=400,
            detail="Password must contain at least one lowercase letter"
        )
    if not re.search(r"[0-9]", password):
        raise HTTPException(
            status_code=400,
            detail="Password must contain at least one number"
        )
    # Check for common weak passwords
    common_passwords = ["password123", "123456789012", "qwertyuiop12", "admin1234567"]
    if password.lower() in common_passwords:
        raise HTTPException(
            status_code=400,
            detail="Password is too common. Please choose a stronger password."
        )


@router.post("/register", response_model=PlayerOut, status_code=status.HTTP_201_CREATED)
@limiter.limit("10/hour")  # Reasonable limit for account creation
async def register(payload: PlayerCreate, request: Request, db: AsyncSession = Depends(get_db)):
    # Get client IP for logging
    client_ip = request.client.host if request.client else "unknown"

    # Validate password strength
    validate_password_strength(payload.password)

    # Check if username already exists
    result = await db.execute(select(Player).where(Player.username == payload.username))
    if result.scalar_one_or_none():
        logger.warning(f"Registration failed - username already taken: {payload.username} from IP: {client_ip}")
        raise HTTPException(status_code=400, detail="Username already taken")

    # Check if email already exists (only if email provided)
    if payload.email:
        email_result = await db.execute(select(Player).where(Player.email == payload.email))
        if email_result.scalar_one_or_none():
            logger.warning(f"Registration failed - email already taken: {payload.email} from IP: {client_ip}")
            raise HTTPException(status_code=400, detail="Email already taken")

    # Check if username should be admin (only if NO admin exists yet)
    from server.config import settings
    admin_usernames = settings.ADMIN_USERNAMES.split(",") if hasattr(settings, "ADMIN_USERNAMES") and settings.ADMIN_USERNAMES else []

    # Check if any admin already exists
    admin_check = await db.execute(select(Player).where(Player.is_admin == True))
    admin_exists = admin_check.scalar_one_or_none() is not None

    # Only grant admin if username matches AND no admin exists yet
    is_admin = (payload.username in admin_usernames) and (not admin_exists)

    player = Player(
        username=payload.username,
        email=payload.email,
        password_hash=hash_password(payload.password),
        is_admin=is_admin,
        money=14_000_000,  # Default starting money
        reputation=0,  # Default reputation
        thrust_policy=1,  # BALANCED
        supply_policy=1,  # ROUTINE
        collection_policy=1,  # ROUTINE
        encounter_policy=1,  # COEXIST
    )
    db.add(player)
    await db.commit()
    await db.refresh(player)

    if is_admin:
        logger.info(f"Admin user registered: {player.username} from IP: {client_ip}")
    elif payload.username in admin_usernames and admin_exists:
        logger.warning(f"Admin username '{payload.username}' registered but admin already exists - not granting admin privileges")

    # Create randomized starter package (ships + crew with equal net value)
    try:
        starter_info = await create_starter_package(db, player)
        logger.info(
            f"New user registered: {player.username} (ID: {player.id}) from IP: {client_ip} | "
            f"Starter package: {starter_info['ships_created']} ships, "
            f"{starter_info['workers_created']} workers, "
            f"${starter_info['money_remaining']:,} cash"
        )
    except Exception as e:
        logger.error(f"Failed to create starter package for {player.username}: {e}")
        # Rollback and re-raise
        await db.rollback()
        raise HTTPException(status_code=500, detail="Failed to create starter package")

    # Refresh player to get updated values and ensure all attributes are loaded
    await db.refresh(player)

    # Explicitly construct response to avoid relationship serialization issues
    return PlayerOut(
        id=player.id,
        username=player.username,
        email=player.email,
        money=player.money,
        reputation=player.reputation,
        hq_colony_id=player.hq_colony_id,
        thrust_policy=player.thrust_policy,
        supply_policy=player.supply_policy,
        collection_policy=player.collection_policy,
        encounter_policy=player.encounter_policy,
        is_admin=player.is_admin,
        created_at=player.created_at,
        last_seen=player.last_seen,
    )


@router.post("/login", response_model=Token)
@limiter.limit("10/minute")  # Prevent brute force attacks
async def login(
    form: OAuth2PasswordRequestForm = Depends(),
    request: Request = None,
    db: AsyncSession = Depends(get_db)
):
    # Get client IP and user agent for logging
    client_ip = request.client.host if request and request.client else "unknown"
    user_agent = request.headers.get("user-agent", "unknown") if request else "unknown"

    result = await db.execute(select(Player).where(Player.username == form.username.lower()))
    player = result.scalar_one_or_none()

    if not player or not verify_password(form.password, player.password_hash):
        # Log failed login attempt with details
        logger.warning(
            f"Failed login attempt for username: {form.username} "
            f"from IP: {client_ip} "
            f"User-Agent: {user_agent}"
        )
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )

    # Log successful login
    logger.info(
        f"Successful login: {player.username} (ID: {player.id}) "
        f"from IP: {client_ip} "
        f"User-Agent: {user_agent}"
    )

    token = create_access_token({"sub": str(player.id)})
    return Token(access_token=token)


@router.get("/me", response_model=PlayerOut)
async def me(player: Player = Depends(get_current_player)):
    return player
