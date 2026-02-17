class_name ResourceTypes
extends RefCounted

enum OreType {
	IRON,
	NICKEL,
	PLATINUM,
	WATER_ICE,
	CARBON_ORGANICS,
}

const ORE_NAMES: Dictionary = {
	OreType.IRON: "Iron",
	OreType.NICKEL: "Nickel",
	OreType.PLATINUM: "Platinum",
	OreType.WATER_ICE: "Water/Ice",
	OreType.CARBON_ORGANICS: "Carbon/Organics",
}

static func get_ore_name(ore: OreType) -> String:
	return ORE_NAMES.get(ore, "Unknown")
