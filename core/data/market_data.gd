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
	},
	{
		"name": "Advanced Processor",
		"type": "processor",
		"mining_bonus": 1.75,
		"cost": 8000,
	},
	{
		"name": "Refinery",
		"type": "refinery",
		"mining_bonus": 2.5,
		"cost": 25000,
	},
]

static func get_ore_price(ore: ResourceTypes.OreType) -> int:
	return ORE_PRICES.get(ore, 0)
