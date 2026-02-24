class_name MunitionsData
extends RefCounted

## Munitions quality and availability system
## Different colonies offer different quality munitions at varying prices

enum Quality {
	MILITARY_GRADE,  # Earth, Mars — premium, reliable
	STANDARD,        # Lunar, Ceres, Vesta — industrial baseline
	SURPLUS,         # Ganymede, Europa, Callisto — secondary market
	FRONTIER,        # Titan, Triton — remote, improvised
}

const QUALITY_NAMES: Dictionary = {
	Quality.MILITARY_GRADE: "Military Grade",
	Quality.STANDARD: "Standard",
	Quality.SURPLUS: "Surplus",
	Quality.FRONTIER: "Frontier",
}

const QUALITY_STATS: Dictionary = {
	Quality.MILITARY_GRADE: {
		"price_mult": 1.5,
		"accuracy_mod": 0.20,   # +20% accuracy
		"power_mod": 0.10,      # +10% power
		"reliability": 0.99,    # 1% misfire chance
		"color": Color(0.3, 0.9, 0.4),  # Green
	},
	Quality.STANDARD: {
		"price_mult": 1.0,
		"accuracy_mod": 0.0,
		"power_mod": 0.0,
		"reliability": 0.95,    # 5% misfire chance
		"color": Color(0.7, 0.7, 0.7),  # Gray
	},
	Quality.SURPLUS: {
		"price_mult": 0.7,
		"accuracy_mod": -0.10,  # -10% accuracy
		"power_mod": -0.05,     # -5% power
		"reliability": 0.90,    # 10% misfire chance
		"color": Color(0.9, 0.7, 0.3),  # Orange
	},
	Quality.FRONTIER: {
		"price_mult": 0.5,
		"accuracy_mod": -0.20,  # -20% accuracy
		"power_mod": -0.10,     # -10% power
		"reliability": 0.85,    # 15% misfire chance
		"color": Color(0.9, 0.4, 0.3),  # Red
	},
}

## Colony munitions quality mapping
const COLONY_QUALITY: Dictionary = {
	"Earth": Quality.MILITARY_GRADE,
	"Mars Colony": Quality.MILITARY_GRADE,
	"Lunar Base": Quality.STANDARD,
	"Ceres Station": Quality.STANDARD,
	"Vesta Refinery": Quality.STANDARD,
	"Ganymede Port": Quality.SURPLUS,
	"Europa Lab": Quality.SURPLUS,
	"Callisto Base": Quality.SURPLUS,
	"Titan Outpost": Quality.FRONTIER,
	"Triton Station": Quality.FRONTIER,
}

## Fusion torpedo availability (requires reputation threshold)
const FUSION_TORPEDO_SOURCE: String = "Mars Colony"
const FUSION_TORPEDO_REP_REQUIRED: float = 50.0  # "Respected" tier

## Get munitions quality at a location
static func get_quality_at_location(location_name: String) -> int:
	return COLONY_QUALITY.get(location_name, Quality.STANDARD)

## Get quality stats
static func get_quality_stats(quality: int) -> Dictionary:
	return QUALITY_STATS.get(quality, QUALITY_STATS[Quality.STANDARD])

## Get quality name
static func get_quality_name(quality: int) -> String:
	return QUALITY_NAMES.get(quality, "Standard")

## Get quality color for UI
static func get_quality_color(quality: int) -> Color:
	var stats := get_quality_stats(quality)
	return stats.get("color", Color.WHITE)

## Check if fusion torpedoes are available at location
static func can_buy_fusion_torpedoes(location_name: String, reputation: float) -> bool:
	if location_name != FUSION_TORPEDO_SOURCE:
		return false
	return reputation >= FUSION_TORPEDO_REP_REQUIRED

## Calculate ammo cost with quality multiplier
static func get_ammo_cost(base_cost: int, quality: int) -> int:
	var stats := get_quality_stats(quality)
	var mult: float = stats.get("price_mult", 1.0)
	return int(base_cost * mult)
