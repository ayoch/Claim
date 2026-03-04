from datetime import datetime
import re

from pydantic import BaseModel, Field, field_validator


# ── Ship ──────────────────────────────────────────────────────────────────────

class ShipOut(BaseModel):
    id: int
    player_id: int  # Owner of this ship
    owner_username: str | None = None  # Owner's username for display (populated for world state)
    ship_name: str
    ship_class: int
    max_thrust_g: float
    thrust_setting: float
    cargo_capacity: float
    cargo_volume: float
    fuel_capacity: float
    fuel: float
    base_mass: float
    min_crew: int
    max_equipment_slots: int
    engine_condition: float
    is_derelict: bool
    position_x: float
    position_y: float
    is_stationed: bool
    station_colony_id: int | None
    current_cargo: dict
    supplies: dict

    model_config = {"from_attributes": True}


# ── Worker ────────────────────────────────────────────────────────────────────

class WorkerOut(BaseModel):
    id: int
    first_name: str
    last_name: str
    pilot_skill: float
    engineer_skill: float
    mining_skill: float
    pilot_xp: float
    engineer_xp: float
    mining_xp: float
    wage: int
    loyalty: float
    fatigue: float
    personality: int
    assigned_ship_id: int | None
    assigned_mission_id: int | None
    is_available: bool
    leave_status: int

    model_config = {"from_attributes": True}


# ── Equipment ─────────────────────────────────────────────────────────────────

class EquipmentOut(BaseModel):
    id: int
    ship_id: int
    equipment_name: str
    equipment_type: str
    mining_bonus: float
    cost: int
    durability: float
    max_durability: float
    weapon_power: int
    weapon_range: float
    weapon_accuracy: float
    weapon_role: str
    ammo_capacity: int
    current_ammo: int
    ammo_cost: int
    mass: float
    mining_speed_bonus: float

    model_config = {"from_attributes": True}


# ── Mission ───────────────────────────────────────────────────────────────────

class MissionOut(BaseModel):
    id: int
    ship_id: int
    asteroid_id: int | None
    mission_type: int
    status: int
    transit_time: float
    elapsed_ticks: float
    fuel_per_tick: float
    origin_name: str
    origin_is_earth: bool
    return_to_station: bool
    mining_duration: float
    created_at: datetime

    model_config = {"from_attributes": True}


# ── Full game state ───────────────────────────────────────────────────────────

class GameState(BaseModel):
    player_id: int
    username: str
    money: int
    reputation: int
    thrust_policy: int
    supply_policy: int
    collection_policy: int
    encounter_policy: int
    total_ticks: int
    ships: list[ShipOut]
    workers: list[WorkerOut]
    active_missions: list[MissionOut]


# ── Action requests ───────────────────────────────────────────────────────────

class DispatchRequest(BaseModel):
    ship_id: int = Field(..., gt=0, description="Ship ID must be positive")
    mission_type: int = Field(..., ge=0, le=5)
    # Target: provide exactly one of asteroid_id or colony_id
    asteroid_id: int | None = Field(None, gt=0)
    colony_id: int | None = Field(None, gt=0)
    mining_duration: float = Field(
        86400.0,
        ge=3600.0,  # Min 1 hour
        le=604800.0,  # Max 7 game-days
        description="Mining duration in game-seconds"
    )
    return_to_station: bool = True

    @field_validator("mining_duration")
    @classmethod
    def reasonable_duration(cls, v: float) -> float:
        if v > 86400.0 * 14:  # 14 game-days
            raise ValueError("Mining duration too long (max 14 days)")
        return v


class HireRequest(BaseModel):
    worker_id: int  # from /admin/available-workers pool


class BuyShipRequest(BaseModel):
    ship_class: int = Field(..., ge=0, le=3, description="Ship class: 0=Courier, 1=Hauler, 2=Prospector, 3=Explorer")
    ship_name: str = Field(..., min_length=1, max_length=64)
    colony_id: int = Field(..., gt=0)

    @field_validator("ship_name")
    @classmethod
    def valid_ship_name(cls, v: str) -> str:
        # Allow alphanumeric, spaces, hyphens, apostrophes
        if not re.match(r'^[a-zA-Z0-9\s\'-]+$', v):
            raise ValueError("Ship name must be alphanumeric (spaces, hyphens, apostrophes allowed)")
        return v.strip()


class AssignWorkerRequest(BaseModel):
    worker_id: int
    ship_id: int


class BuyEquipmentRequest(BaseModel):
    ship_id: int = Field(..., gt=0)
    equipment_name: str = Field(..., min_length=1, max_length=64)


class SellEquipmentRequest(BaseModel):
    equipment_id: int = Field(..., gt=0)


class AsteroidOut(BaseModel):
    id: int
    asteroid_name: str
    body_type: str
    semi_major_axis: float
    eccentricity: float
    ore_yields: dict
    max_mining_slots: int

    model_config = {"from_attributes": True}


class ColonyOut(BaseModel):
    id: int
    colony_name: str
    planet_id: str
    has_rescue_ops: bool
    price_multipliers: dict

    model_config = {"from_attributes": True}
