from datetime import datetime

from pydantic import BaseModel, Field


# ── Ship ──────────────────────────────────────────────────────────────────────

class ShipOut(BaseModel):
    id: int
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
    ships: list[ShipOut]
    workers: list[WorkerOut]
    active_missions: list[MissionOut]


# ── Action requests ───────────────────────────────────────────────────────────

class DispatchRequest(BaseModel):
    ship_id: int
    mission_type: int = Field(..., ge=0, le=5)
    # Target: provide exactly one of asteroid_id or colony_id
    asteroid_id: int | None = None
    colony_id: int | None = None
    mining_duration: float = Field(86400.0, gt=0)
    return_to_station: bool = True


class HireRequest(BaseModel):
    worker_id: int  # from /admin/available-workers pool


class BuyShipRequest(BaseModel):
    ship_class: int = Field(..., ge=0, le=3)
    ship_name: str = Field(..., min_length=1, max_length=64)
    colony_id: int  # where to deliver / station the ship


class AssignWorkerRequest(BaseModel):
    worker_id: int
    ship_id: int


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
