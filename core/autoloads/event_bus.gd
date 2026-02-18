extends Node

# Money & resources
signal money_changed(new_amount: int)
signal resource_changed(ore_type: ResourceTypes.OreType, new_amount: float)

# Workers
signal worker_hired(worker: Worker)
signal worker_fired(worker: Worker)

# Ships & equipment
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
signal mission_preview_started(ship: Ship, destination_pos: Vector2, slingshot_route)  # Show planned route (slingshot_route is GravityAssist.SlingshotRoute or null)
signal mission_preview_cancelled()  # Hide planned route

# Trade missions
signal trade_mission_started(trade_mission: TradeMission)
signal trade_mission_completed(trade_mission: TradeMission)
signal trade_mission_phase_changed(trade_mission: TradeMission)

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
signal rescue_mission_started(ship: Ship, cost: int)
signal rescue_mission_completed(ship: Ship)
signal refuel_mission_started(ship: Ship, cost: int, fuel_amount: float)
signal refuel_mission_completed(ship: Ship, fuel_amount: float)
