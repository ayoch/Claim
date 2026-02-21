class_name SupplyData
extends RefCounted

# Supply types and their properties
# Supplies share cargo capacity with ore — they're physical items on the ship

enum SupplyType {
	REPAIR_PARTS,
	FOOD_RATIONS,
}

const SUPPLY_INFO: Dictionary = {
	SupplyType.REPAIR_PARTS: {
		"name": "Repair Parts",
		"key": "repair_parts",
		"cost_per_unit": 500,
		"mass_per_unit": 0.45,    # tons
		"volume_per_unit": 0.28,  # m³
		"description": "Fix equipment + engines remotely",
	},
	SupplyType.FOOD_RATIONS: {
		"name": "Food Rations",
		"key": "food",
		"cost_per_unit": 50,
		"mass_per_unit": 0.1,     # tons
		"volume_per_unit": 0.005, # m³ — compact rations
		"description": "Feed deployed crews",
	},
}

static func get_supply_name(supply_type: int) -> String:
	return SUPPLY_INFO.get(supply_type, {}).get("name", "Unknown")

static func get_supply_key(supply_type: int) -> String:
	return SUPPLY_INFO.get(supply_type, {}).get("key", "unknown")

static func get_cost_per_unit(supply_type: int) -> int:
	return SUPPLY_INFO.get(supply_type, {}).get("cost_per_unit", 0)

static func get_mass_per_unit(supply_type: int) -> float:
	return SUPPLY_INFO.get(supply_type, {}).get("mass_per_unit", 0.0)

static func get_volume_per_unit(supply_type: int) -> float:
	return SUPPLY_INFO.get(supply_type, {}).get("volume_per_unit", 0.0)

static func get_supply_type_from_key(key: String) -> int:
	for supply_type in SUPPLY_INFO:
		if SUPPLY_INFO[supply_type]["key"] == key:
			return supply_type
	return -1
