"""Password reset endpoints."""

import logging
import secrets
from datetime import datetime, timedelta, timezone
from fastapi import APIRouter, Depends, HTTPException, Request, status
from pydantic import BaseModel, EmailStr, Field
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession

from server.auth import hash_password
from server.database import get_db
from server.email_service import send_password_reset_email
from server.models.password_reset import PasswordResetToken
from server.models.player import Player
from server.rate_limit import limiter

router = APIRouter(prefix="/auth", tags=["auth"])
logger = logging.getLogger(__name__)


class PasswordResetRequest(BaseModel):
    email: EmailStr = Field(..., description="Email address of account to reset")


class PasswordResetConfirm(BaseModel):
    token: str = Field(..., min_length=32, max_length=64, description="Reset token from email")
    new_password: str = Field(..., min_length=12, description="New password")


@router.post("/request-password-reset", status_code=status.HTTP_200_OK)
@limiter.limit("3/hour")  # Strict limit to prevent abuse
async def request_password_reset(
    payload: PasswordResetRequest,
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """
    Request a password reset email.
    Always returns 200 OK to prevent email enumeration attacks.
    """
    client_ip = request.client.host if request.client else "unknown"

    # Find player by email
    result = await db.execute(select(Player).where(Player.email == payload.email))
    player = result.scalar_one_or_none()

    if not player:
        # Don't reveal that email doesn't exist (prevent enumeration)
        logger.warning(f"Password reset requested for non-existent email: {payload.email} from {client_ip}")
        return {
            "message": "If an account with that email exists, a reset link has been sent."
        }

    # Generate secure token
    reset_token = secrets.token_urlsafe(32)
    expires_at = datetime.now(timezone.utc) + timedelta(hours=1)

    # Delete any existing tokens for this player
    await db.execute(
        select(PasswordResetToken).where(PasswordResetToken.player_id == player.id)
    )
    # Note: Actually delete them
    existing_tokens = await db.execute(
        select(PasswordResetToken).where(PasswordResetToken.player_id == player.id)
    )
    for token in existing_tokens.scalars().all():
        await db.delete(token)

    # Create new token
    token_record = PasswordResetToken(
        player_id=player.id,
        token=reset_token,
        expires_at=expires_at,
    )
    db.add(token_record)
    await db.commit()

    # Send email
    email_sent = send_password_reset_email(player.email, player.username, reset_token)

    if email_sent:
        logger.info(f"Password reset requested for {player.username} ({player.email}) from {client_ip}")
    else:
        logger.error(f"Failed to send reset email for {player.username}")

    # Always return success (prevent enumeration)
    return {
        "message": "If an account with that email exists, a reset link has been sent."
    }


@router.post("/confirm-password-reset", status_code=status.HTTP_200_OK)
@limiter.limit("10/hour")
async def confirm_password_reset(
    payload: PasswordResetConfirm,
    request: Request,
    db: AsyncSession = Depends(get_db)
):
    """
    Confirm password reset with token and set new password.
    """
    client_ip = request.client.host if request.client else "unknown"

    # Find token
    result = await db.execute(
        select(PasswordResetToken).where(PasswordResetToken.token == payload.token)
    )
    token_record = result.scalar_one_or_none()

    if not token_record or not token_record.is_valid():
        logger.warning(f"Invalid or expired reset token used from {client_ip}")
        raise HTTPException(
            status_code=400,
            detail="Invalid or expired reset token"
        )

    # Get player
    player_result = await db.execute(
        select(Player).where(Player.id == token_record.player_id)
    )
    player = player_result.scalar_one_or_none()

    if not player:
        logger.error(f"Reset token {token_record.id} references non-existent player {token_record.player_id}")
        raise HTTPException(status_code=400, detail="Invalid reset token")

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

    # Mark token as used
    token_record.used_at = datetime.now(timezone.utc)
    db.add(token_record)

    await db.commit()

    logger.info(f"Password reset completed for {player.username} from {client_ip}")

    return {
        "message": "Password reset successful. You can now log in with your new password."
    }
