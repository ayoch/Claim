extends Node

# Money & resources
signal money_changed(new_amount: int)
signal resource_changed(ore_type: ResourceTypes.OreType, new_amount: float)

# Workers
signal worker_hired(worker: Worker)
signal worker_fired(worker: Worker)
signal worker_skill_leveled(worker: Worker, skill_type: int, new_value: float)

# Ships & equipment
signal ship_purchased(ship: Ship, cost: int)
signal equipment_purchased(equipment: Equipment)
signal equipment_installed(ship: Ship, equipment: Equipment)
signal equipment_broken(ship: Ship, equipment: Equipment)
signal equipment_repaired(ship: Ship, equipment: Equipment)
signal equipment_fabricated(equipment: Equipment)

# Ship upgrades
signal upgrade_purchased(upgrade: ShipUpgrade)
signal upgrade_installed(ship: Ship, upgrade: ShipUpgrade)

# Cargo management
signal cargo_jettisoned(ship: Ship, tons_jettisoned: float)

# Missions
signal mission_started(mission: Mission)
signal mission_phase_changed(mission: Mission)
signal mission_completed(mission: Mission)
signal mission_redirected(ship: Ship, new_destination: AsteroidData, cost: int)
signal mission_redirect_failed(ship: Ship, reason: String)
signal mission_preview_started(ship: Ship, destination_pos: Vector2, slingshot_route)  # Show planned route (slingshot_route is GravityAssist.SlingshotRoute or null)
signal mission_preview_cancelled()  # Hide planned route

# Trade missions
signal trade_mission_started(trade_mission: TradeMission)
signal trade_mission_completed(trade_mission: TradeMission)
signal trade_mission_phase_changed(trade_mission: TradeMission)
signal trade_mission_redirected(ship: Ship, new_colony: Colony, cost: int)
signal trade_mission_redirect_failed(ship: Ship, reason: String)

# Simulation
signal tick(delta_ticks: float)
signal game_speed_changed(new_speed: float)

# Random events
signal survey_update(asteroid: AsteroidData, message: String)

# Market
signal market_event(ore_type: ResourceTypes.OreType, old_price: float, new_price: float, message: String)
signal market_event_started(event: MarketEvent)
signal market_event_ended(event: MarketEvent)

# Contracts
signal contract_offered(contract: Contract)
signal contract_accepted(contract: Contract)
signal contract_completed(contract: Contract)
signal contract_expired(contract: Contract)
signal contract_failed(contract: Contract)
signal contract_progress(contract: Contract, amount: float)

# Waypoint dispatching & breakdowns
signal ship_idle_at_destination(ship: Ship, mission: Mission)
signal ship_idle_at_colony(ship: Ship, trade_mission: TradeMission)
signal ship_breakdown(ship: Ship, reason: String)
signal ship_derelict(ship: Ship)
signal ship_destroyed(ship: Ship, body_name: String)
signal life_support_warning(ship: Ship, percent_remaining: float)
signal rescue_mission_started(ship: Ship, cost: int)
signal rescue_mission_completed(ship: Ship)
signal rescue_impossible(ship: Ship, reason: String)
signal refuel_mission_started(ship: Ship, cost: int, fuel_amount: float)
signal refuel_mission_completed(ship: Ship, fuel_amount: float)

# Stranger rescue
signal stranger_rescue_offered(ship: Ship, stranger_name: String)
signal stranger_rescue_completed(ship: Ship, stranger_name: String)
signal stranger_rescue_declined(ship: Ship, stranger_name: String)

# Reputation
signal reputation_changed(new_score: float, tier: int)

# Station system
signal ship_stationed(ship: Ship, colony: Colony)
signal ship_unstationed(ship: Ship)
signal station_job_started(ship: Ship, job: String, destination: String)
signal station_job_completed(ship: Ship, job: String, summary: String)
signal crew_deployed(asteroid: AsteroidData, workers: Array)
signal crew_recalled(asteroid: AsteroidData, workers: Array)
signal worker_fatigued(worker: Worker)
signal worker_injured(worker: Worker)

# Hitchhiking & tardiness
signal worker_waiting_for_ride(worker: Worker, location: String)
signal worker_hitched_ride(worker: Worker, ship: Ship)
signal worker_tardy(worker: Worker, reason: String)
signal worker_tardiness_resolved(worker: Worker, action: String)

# Mining units
signal mining_unit_purchased(unit: MiningUnit)
signal mining_unit_deployed(unit: MiningUnit, asteroid: AsteroidData)
signal mining_unit_recalled(unit: MiningUnit)
signal mining_unit_broken(unit: MiningUnit)
signal stockpile_collected(asteroid: AsteroidData, tons: float)
