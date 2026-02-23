class_name SupplyData
extends RefCounted

# Supply types and their properties
# Supplies share cargo capacity with ore — they're physical items on the ship

enum SupplyType {
	REPAIR_PARTS,
	FOOD_RATIONS,
	WATER,
	OXYGEN,
}

const SUPPLY_INFO: Dictionary = {
	SupplyType.REPAIR_PARTS: {
		"name": "Repair Parts",
		"key": "repair_parts",
		"unit_label": "kit",
		"cost_per_unit": 500,
		"mass_per_unit": 0.45,    # tons
		"volume_per_unit": 0.28,  # m³
		"description": "Fix equipment + engines remotely",
	},
	SupplyType.FOOD_RATIONS: {
		"name": "Food Rations",
		"key": "food",
		"unit_label": "crate",    # 1 crate = 100 kg
		"cost_per_unit": 50,
		"mass_per_unit": 0.1,     # tons (100 kg)
		"volume_per_unit": 0.005, # m³ — compact rations
		"description": "Feed deployed crews",
	},
	SupplyType.WATER: {
		"name": "Water (recycled)",
		"key": "water",
		"unit_label": "tank",     # 1 tank = 20 L makeup water (90% recycling)
		"cost_per_unit": 40,
		"mass_per_unit": 0.02,    # tons (20 kg for 20 L)
		"volume_per_unit": 0.025, # m³
		"description": "Makeup water for recycling systems (~20 L, lasts ~67 crew-days)",
	},
	SupplyType.OXYGEN: {
		"name": "Oxygen (recycled)",
		"key": "oxygen",
		"unit_label": "canister", # 1 canister = 2 kg O2 makeup (CO2 scrubbing)
		"cost_per_unit": 120,
		"mass_per_unit": 0.002,   # tons (2 kg compressed O2)
		"volume_per_unit": 0.01,  # m³ (high-pressure canister)
		"description": "Makeup O2 for life support recycling (~2 kg, lasts ~40 crew-days)",
	},
}

static func get_supply_name(supply_type: int) -> String:
	return SUPPLY_INFO.get(supply_type, {}).get("name", "Unknown")

static func get_supply_key(supply_type: int) -> String:
	return SUPPLY_INFO.get(supply_type, {}).get("key", "unknown")

static func get_unit_label(supply_type: int) -> String:
	return SUPPLY_INFO.get(supply_type, {}).get("unit_label", "unit")

static func get_unit_label_from_key(key: String) -> String:
	for supply_type in SUPPLY_INFO:
		if SUPPLY_INFO[supply_type]["key"] == key:
			return SUPPLY_INFO[supply_type].get("unit_label", "unit")
	return "unit"

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
