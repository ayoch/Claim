from datetime import datetime
import re

from pydantic import BaseModel, EmailStr, Field, field_validator


class PlayerCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=32)
    email: EmailStr | None = None  # Optional for backward compatibility
    password: str = Field(..., min_length=8, max_length=128)

    @field_validator("username")
    @classmethod
    def username_alphanumeric(cls, v: str) -> str:
        if not re.match(r'^[a-zA-Z0-9_-]+$', v):
            raise ValueError("Username must contain only letters, numbers, hyphens, and underscores")
        return v.lower()

    @field_validator("password")
    @classmethod
    def strong_password(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError("Password must be at least 8 characters")
        if not re.search(r'[A-Z]', v):
            raise ValueError("Password must contain at least one uppercase letter")
        if not re.search(r'[a-z]', v):
            raise ValueError("Password must contain at least one lowercase letter")
        if not re.search(r'\d', v):
            raise ValueError("Password must contain at least one number")
        return v


class PlayerLogin(BaseModel):
    username: str
    password: str


class PlayerOut(BaseModel):
    id: int
    username: str
    email: str | None
    money: int
    reputation: int
    hq_colony_id: int | None
    thrust_policy: int
    supply_policy: int
    collection_policy: int
    encounter_policy: int
    is_admin: bool
    created_at: datetime
    last_seen: datetime

    model_config = {"from_attributes": True}


class PolicyUpdate(BaseModel):
    thrust_policy: int | None = Field(None, ge=0, le=2)
    supply_policy: int | None = Field(None, ge=0, le=2)
    collection_policy: int | None = Field(None, ge=0, le=2)
    encounter_policy: int | None = Field(None, ge=0, le=2)


class Token(BaseModel):
    access_token: str
    token_type: str = "bearer"


class TokenData(BaseModel):
    player_id: int | None = None
