"""Account settings endpoints (email, password change, etc.)."""

import logging
from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, EmailStr
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from server.auth import get_current_player, hash_password, verify_password
from server.database import get_db
from server.models.player import Player
from server.rate_limit import limiter

router = APIRouter(prefix="/account", tags=["account"])
logger = logging.getLogger(__name__)


class AddEmailRequest(BaseModel):
    email: EmailStr


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


@router.post("/add-email", status_code=status.HTTP_200_OK)
@limiter.limit("5/hour")
async def add_email(
    payload: AddEmailRequest,
    request: Request,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db)
):
    """
    Add email to account that doesn't have one.
    For accounts created before email requirement.
    """
    if player.email:
        raise HTTPException(
            status_code=400,
            detail="Account already has an email address. Use change-email endpoint instead."
        )

    # Check if email already in use
    result = await db.execute(select(Player).where(Player.email == payload.email))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Email already in use")

    player.email = payload.email
    db.add(player)
    await db.commit()

    logger.info(f"Email added to account {player.username}: {payload.email}")

    return {
        "message": "Email successfully added to account",
        "email": player.email
    }


@router.post("/change-email", status_code=status.HTTP_200_OK)
@limiter.limit("5/hour")
async def change_email(
    payload: AddEmailRequest,
    request: Request,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db)
):
    """Change account email."""
    if not player.email:
        raise HTTPException(
            status_code=400,
            detail="Account doesn't have an email. Use add-email endpoint."
        )

    # Check if new email already in use
    result = await db.execute(select(Player).where(Player.email == payload.email))
    existing = result.scalar_one_or_none()
    if existing and existing.id != player.id:
        raise HTTPException(status_code=400, detail="Email already in use")

    old_email = player.email
    player.email = payload.email
    db.add(player)
    await db.commit()

    logger.info(f"Email changed for {player.username}: {old_email} → {payload.email}")

    return {
        "message": "Email successfully updated",
        "email": player.email
    }


@router.post("/change-password", status_code=status.HTTP_200_OK)
@limiter.limit("10/hour")
async def change_password(
    payload: ChangePasswordRequest,
    request: Request,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db)
):
    """Change account password (requires current password)."""
    # Verify current password
    if not verify_password(payload.current_password, player.password_hash):
        logger.warning(f"Failed password change for {player.username} - incorrect current password")
        raise HTTPException(status_code=400, detail="Current password is incorrect")

    # Validate new password
    if len(payload.new_password) < 12:
        raise HTTPException(status_code=400, detail="Password must be at least 12 characters")
    if not any(c.isupper() for c in payload.new_password):
        raise HTTPException(status_code=400, detail="Password must contain uppercase letter")
    if not any(c.islower() for c in payload.new_password):
        raise HTTPException(status_code=400, detail="Password must contain lowercase letter")
    if not any(c.isdigit() for c in payload.new_password):
        raise HTTPException(status_code=400, detail="Password must contain number")

    # Update password
    player.password_hash = hash_password(payload.new_password)
    db.add(player)
    await db.commit()

    logger.info(f"Password changed for {player.username}")

    return {
        "message": "Password successfully updated"
    }


@router.get("/me", status_code=status.HTTP_200_OK)
async def get_account_info(
    player: Player = Depends(get_current_player)
):
    """Get current account information."""
    return {
        "username": player.username,
        "email": player.email,
        "has_email": player.email is not None,
        "is_admin": player.is_admin,
        "created_at": player.created_at,
    }
