class_name MarketData
extends RefCounted

const ORE_PRICES: Dictionary = {
	ResourceTypes.OreType.IRON: 400,
	ResourceTypes.OreType.NICKEL: 1000,
	ResourceTypes.OreType.PLATINUM: 6500,
	ResourceTypes.OreType.WATER_ICE: 1600,
	ResourceTypes.OreType.CARBON_ORGANICS: 1200,
}

const EQUIPMENT_CATALOG: Array[Dictionary] = [
	{
		"name": "Basic Processor",
		"type": "processor",
		"mining_bonus": 1.25,
		"cost": 2000,
		"wear_per_tick": 0.4,
		"fabrication_ticks": 10.0,
	},
	{
		"name": "Advanced Processor",
		"type": "processor",
		"mining_bonus": 1.75,
		"cost": 8000,
		"wear_per_tick": 0.6,
		"fabrication_ticks": 25.0,
	},
	{
		"name": "Refinery",
		"type": "refinery",
		"mining_bonus": 2.5,
		"cost": 25000,
		"wear_per_tick": 0.8,
		"fabrication_ticks": 50.0,
	},
	# Weapons
	{
		"name": "Mining Laser",
		"type": "weapon",
		"cost": 40000,
		"wear_per_tick": 0.3,
		"fabrication_ticks": 15.0,
		"weapon_power": 1,
		"weapon_range": 0.005,
		"weapon_accuracy": 0.6,
		"weapon_role": "dual",
		"fire_rate": "fast",
		"mining_speed_bonus": 0.2,  # +20% mining speed
		"mass": 5.0,
	},
	{
		"name": "Battle Laser",
		"type": "weapon",
		"cost": 120000,
		"wear_per_tick": 0.5,
		"fabrication_ticks": 30.0,
		"weapon_power": 4,
		"weapon_range": 0.02,
		"weapon_accuracy": 0.75,
		"weapon_role": "defensive",
		"fire_rate": "fast",
		"mass": 15.0,
	},
	{
		"name": "Light Rail Gun",
		"type": "weapon",
		"cost": 200000,
		"wear_per_tick": 0.6,
		"fabrication_ticks": 45.0,
		"weapon_power": 6,
		"weapon_range": 0.15,
		"weapon_accuracy": 0.9,
		"weapon_role": "offensive",
		"fire_rate": "slow",
		"mass": 20.0,
	},
	{
		"name": "Heavy Rail Gun",
		"type": "weapon",
		"cost": 500000,
		"wear_per_tick": 0.8,
		"fabrication_ticks": 75.0,
		"weapon_power": 12,
		"weapon_range": 0.30,
		"weapon_accuracy": 0.95,
		"weapon_role": "offensive",
		"fire_rate": "very_slow",
		"mass": 40.0,
	},
	{
		"name": "Explosive Torpedo Launcher",
		"type": "weapon",
		"cost": 80000,
		"wear_per_tick": 0.4,
		"fabrication_ticks": 25.0,
		"weapon_power": 15,
		"weapon_range": 0.25,
		"weapon_accuracy": 0.7,
		"weapon_role": "offensive",
		"fire_rate": "limited",
		"ammo_capacity": 2,
		"ammo_cost": 30000,
		"mass": 12.0,
	},
	{
		"name": "EMP Torpedo Launcher",
		"type": "weapon",
		"cost": 80000,
		"wear_per_tick": 0.4,
		"fabrication_ticks": 25.0,
		"weapon_power": 0,  # No hull damage, disables systems
		"weapon_range": 0.25,
		"weapon_accuracy": 0.7,
		"weapon_role": "offensive",
		"fire_rate": "limited",
		"ammo_capacity": 2,
		"ammo_cost": 30000,
		"mass": 12.0,
	},
	{
		"name": "Fusion Torpedo Launcher",
		"type": "weapon",
		"cost": 300000,
		"wear_per_tick": 0.5,
		"fabrication_ticks": 60.0,
		"weapon_power": 50,  # Massively destructive
		"weapon_range": 0.40,
		"weapon_accuracy": 0.8,
		"weapon_role": "offensive",
		"fire_rate": "limited",
		"ammo_capacity": 2,
		"ammo_cost": 150000,
		"mass": 15.0,
	},
]

## Get current dynamic price (delegates to GameState.market)
static func get_ore_price(ore: ResourceTypes.OreType) -> float:
	if GameState and GameState.market:
		return GameState.market.get_price(ore)
	return float(ORE_PRICES.get(ore, 0))

## Get static base price for reference
static func get_base_price(ore: ResourceTypes.OreType) -> float:
	return float(ORE_PRICES.get(ore, 0))
