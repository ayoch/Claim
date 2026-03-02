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
@limiter.limit("5/hour")  # Strict limit for account creation
async def register(payload: PlayerCreate, request: Request, db: AsyncSession = Depends(get_db)):
    # Get client IP for logging
    client_ip = request.client.host if request.client else "unknown"

    # Validate password strength
    validate_password_strength(payload.password)

    result = await db.execute(select(Player).where(Player.username == payload.username))
    if result.scalar_one_or_none():
        logger.warning(f"Registration failed - username already taken: {payload.username} from IP: {client_ip}")
        raise HTTPException(status_code=400, detail="Username already taken")

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
        password_hash=hash_password(payload.password),
        is_admin=is_admin,
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

    return player


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
