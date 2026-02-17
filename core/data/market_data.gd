class_name MarketData
extends RefCounted

const ORE_PRICES: Dictionary = {
	ResourceTypes.OreType.IRON: 50,
	ResourceTypes.OreType.NICKEL: 120,
	ResourceTypes.OreType.PLATINUM: 800,
	ResourceTypes.OreType.WATER_ICE: 200,
	ResourceTypes.OreType.CARBON_ORGANICS: 150,
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
]

## Get current dynamic price (delegates to GameState.market)
static func get_ore_price(ore: ResourceTypes.OreType) -> float:
	if GameState and GameState.market:
		return GameState.market.get_price(ore)
	return float(ORE_PRICES.get(ore, 0))

## Get static base price for reference
static func get_base_price(ore: ResourceTypes.OreType) -> float:
	return float(ORE_PRICES.get(ore, 0))
