from __future__ import annotations
from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from server.auth import create_access_token, get_current_player, hash_password, verify_password
from server.database import get_db
from server.models.player import Player
from server.schemas.player import PlayerCreate, PlayerOut, Token

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/register", response_model=PlayerOut, status_code=status.HTTP_201_CREATED)
async def register(payload: PlayerCreate, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Player).where(Player.username == payload.username))
    if result.scalar_one_or_none():
        raise HTTPException(status_code=400, detail="Username already taken")
    player = Player(
        username=payload.username,
        password_hash=hash_password(payload.password),
    )
    db.add(player)
    await db.commit()
    await db.refresh(player)
    return player


@router.post("/login", response_model=Token)
async def login(form: OAuth2PasswordRequestForm = Depends(), db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(Player).where(Player.username == form.username.lower()))
    player = result.scalar_one_or_none()
    if not player or not verify_password(form.password, player.password_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    token = create_access_token({"sub": str(player.id)})
    return Token(access_token=token)


@router.get("/me", response_model=PlayerOut)
async def me(player: Player = Depends(get_current_player)):
    return player
