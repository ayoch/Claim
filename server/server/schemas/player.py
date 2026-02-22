from datetime import datetime

from pydantic import BaseModel, Field, field_validator


class PlayerCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=64)
    password: str = Field(..., min_length=6, max_length=128)

    @field_validator("username")
    @classmethod
    def username_alphanumeric(cls, v: str) -> str:
        if not v.replace("_", "").replace("-", "").isalnum():
            raise ValueError("Username must be alphanumeric (underscores and hyphens allowed)")
        return v.lower()


class PlayerLogin(BaseModel):
    username: str
    password: str


class PlayerOut(BaseModel):
    id: int
    username: str
    money: int
    reputation: int
    hq_colony_id: int | None
    thrust_policy: int
    supply_policy: int
    collection_policy: int
    encounter_policy: int
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
