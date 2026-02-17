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

# Missions
signal mission_started(mission: Mission)
signal mission_phase_changed(mission: Mission)
signal mission_completed(mission: Mission)

# Simulation
signal tick(delta_ticks: float)
signal game_speed_changed(new_speed: float)

# Random events
signal survey_update(asteroid: AsteroidData, message: String)
