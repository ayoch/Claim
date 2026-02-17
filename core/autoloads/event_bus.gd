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

# Missions
signal mission_started(mission: Mission)
signal mission_phase_changed(mission: Mission)
signal mission_completed(mission: Mission)

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

# Contracts
signal contract_offered(contract: Contract)
signal contract_accepted(contract: Contract)
signal contract_completed(contract: Contract)
signal contract_expired(contract: Contract)
signal contract_failed(contract: Contract)
