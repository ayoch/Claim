class_name ShipData
extends RefCounted

enum ShipClass {
	COURIER,    # Fast, low cargo, high fuel efficiency
	HAULER,     # Slow, high cargo, moderate fuel
	PROSPECTOR, # Balanced - starting ship
	EXPLORER,   # Long range, moderate everything
}

const CLASS_NAMES := {
	ShipClass.COURIER: "Courier",
	ShipClass.HAULER: "Hauler",
	ShipClass.PROSPECTOR: "Prospector",
	ShipClass.EXPLORER: "Explorer",
}

# Ship class templates with base stats
# Evocative ship names for random generation
const SHIP_NAMES := [
	"Headstrong in the Gale",
	"Lambent Saffron",
	"Alleged Street Poet",
	"Liberty She Pirouettes",
	"Abandon Propriety",
	"Anomaly Point",
	"Sacred Bullshit",
	"Grave Goods",
	"Frogblast the Vent Core",
	"They're Everywhere",
	"Phaistos",
	"Jeirrut",
	"A Searing Epiphany",
	"Squandered Fortune",
	"Laziness in Action",
	"Wandering Minstrel",
	"Faith Like a Candle",
	"Slurry",
	"Dastardly Cur",
]

const CLASS_PRICES := {
	ShipClass.COURIER: 800000,
	ShipClass.HAULER: 1500000,
	ShipClass.PROSPECTOR: 1000000,
	ShipClass.EXPLORER: 1200000,
}

# GDD §8.2 canonical ship specs
const CLASS_STATS := {
	ShipClass.COURIER: {
		"thrust_g": 0.38,          # g
		"cargo_capacity": 38.0,    # tonnes (mass limit)
		"cargo_volume": 54.0,      # m³ (volume limit)
		"fuel_capacity": 46.5,     # fuel units (propellant equivalent)
		"dry_mass": 73.4,          # tonnes (ship structural mass)
		"min_crew": 2,
		"max_equipment_slots": 3,
	},
	ShipClass.HAULER: {
		"thrust_g": 0.19,
		"cargo_capacity": 412.0,
		"cargo_volume": 584.0,
		"fuel_capacity": 237.0,
		"dry_mass": 488.2,
		"min_crew": 5,
		"max_equipment_slots": 5,
	},
	ShipClass.PROSPECTOR: {
		"thrust_g": 0.31,
		"cargo_capacity": 107.0,
		"cargo_volume": 143.0,
		"fuel_capacity": 118.0,
		"dry_mass": 214.8,
		"min_crew": 3,
		"max_equipment_slots": 4,
	},
	ShipClass.EXPLORER: {
		"thrust_g": 0.47,
		"cargo_capacity": 63.0,
		"cargo_volume": 91.0,
		"fuel_capacity": 192.0,
		"dry_mass": 141.6,
		"min_crew": 2,
		"max_equipment_slots": 4,
	},
}

static var _used_ship_names: Dictionary = {}

static func generate_random_name() -> String:
	var available: Array[String] = []
	for n in SHIP_NAMES:
		if not _used_ship_names.has(n):
			available.append(n)
	# Fall back to full list if all names exhausted
	if available.is_empty():
		available = SHIP_NAMES.duplicate()
	var chosen: String = available[randi() % available.size()]
	_used_ship_names[chosen] = true
	return chosen

static func release_name(ship_name: String) -> void:
	_used_ship_names.erase(ship_name)

## Apply per-ship variance to a stat, rounded to 1 decimal
static func _vary(base: float, spread: float) -> float:
	return snappedf(base * randf_range(1.0 - spread, 1.0 + spread), 0.1)

static func create_ship(ship_class: ShipClass, ship_name: String = "") -> Ship:
	var ship := Ship.new()
	var stats: Dictionary = CLASS_STATS[ship_class]

	ship.ship_class = ship_class
	if ship_name.is_empty():
		ship_name = generate_random_name()
	ship.ship_name = ship_name

	# Per-ship variance per GDD §8.2
	ship.base_mass = _vary(stats["dry_mass"], 0.05)           # ±5%
	ship.max_thrust_g = _vary(stats["thrust_g"], 0.05)        # ±5%
	ship.thrust_setting = 1.0
	ship.cargo_capacity = _vary(stats["cargo_capacity"], 0.10) # ±10%
	ship.cargo_volume = _vary(stats["cargo_volume"], 0.10)     # ±10%
	ship.fuel_capacity = _vary(stats["fuel_capacity"], 0.08)   # ±8%
	ship.fuel = ship.fuel_capacity
	ship.min_crew = stats["min_crew"]
	# Upgrade slots: base ±1 slot
	ship.max_equipment_slots = clampi(
		stats["max_equipment_slots"] + (randi() % 3) - 1, 1, 8)

	ship.position_au = CelestialData.get_earth_position_au()
	ship.engine_condition = 100.0

	# Start with basic provisions (1 unit = 100kg)
	ship.supplies["food"] = 3.0  # ~30 days for 3 crew (0.084 units/day)
	ship.supplies["repair_parts"] = 10.0

	return ship

static func get_class_description(ship_class: ShipClass) -> String:
	match ship_class:
		ShipClass.COURIER:
			return "Fast light courier (0.38g, 38t cargo). Quick deliveries and contracts. Crew 2."
		ShipClass.HAULER:
			return "Heavy bulk hauler (0.19g, 412t cargo). Slow but high throughput. Crew 5."
		ShipClass.PROSPECTOR:
			return "Balanced mining vessel (0.31g, 107t cargo). Good slot count for equipment. Crew 3."
		ShipClass.EXPLORER:
			return "High-thrust long-range ship (0.47g, 63t cargo, 192 fuel). Ideal for deep belt. Crew 2."
		_:
			return "Unknown ship class"
