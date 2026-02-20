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
]

const CLASS_PRICES := {
	ShipClass.COURIER: 800000,
	ShipClass.HAULER: 1500000,
	ShipClass.PROSPECTOR: 1000000,
	ShipClass.EXPLORER: 1200000,
}

const CLASS_STATS := {
	ShipClass.COURIER: {
		"thrust_g": 0.5,           # Fast
		"cargo_capacity": 50.0,    # Low cargo
		"fuel_capacity": 250.0,    # Good range
		"min_crew": 2,             # Small crew
		"max_equipment_slots": 1,  # Limited mining
		"base_mass_mult": 1.5,     # Light frame (1.5x cargo vs 2.0x)
	},
	ShipClass.HAULER: {
		"thrust_g": 0.2,           # Slow
		"cargo_capacity": 200.0,   # High cargo
		"fuel_capacity": 400.0,    # Large tank needed
		"min_crew": 4,             # Large crew
		"max_equipment_slots": 2,  # Standard mining
		"base_mass_mult": 2.5,     # Heavy frame (2.5x cargo)
	},
	ShipClass.PROSPECTOR: {
		"thrust_g": 0.3,           # Balanced
		"cargo_capacity": 100.0,   # Medium cargo
		"fuel_capacity": 300.0,    # Medium tank
		"min_crew": 3,             # Medium crew
		"max_equipment_slots": 3,  # Extra mining slots
		"base_mass_mult": 2.0,     # Standard frame (2.0x cargo)
	},
	ShipClass.EXPLORER: {
		"thrust_g": 0.35,          # Slightly fast
		"cargo_capacity": 80.0,    # Lower cargo
		"fuel_capacity": 500.0,    # Huge tank for long range
		"min_crew": 3,             # Medium crew
		"max_equipment_slots": 2,  # Standard mining
		"base_mass_mult": 1.8,     # Light frame (1.8x cargo)
	},
}

static func generate_random_name() -> String:
	return SHIP_NAMES[randi() % SHIP_NAMES.size()]

static func create_ship(ship_class: ShipClass, ship_name: String = "") -> Ship:
	var ship := Ship.new()
	var stats: Dictionary = CLASS_STATS[ship_class]

	# Set class and name
	ship.ship_class = ship_class
	if ship_name.is_empty():
		ship_name = generate_random_name()
	ship.ship_name = ship_name

	# Apply stats from template
	ship.max_thrust_g = stats["thrust_g"]
	ship.thrust_setting = 1.0  # Start at 100% thrust
	ship.cargo_capacity = stats["cargo_capacity"]
	ship.fuel_capacity = stats["fuel_capacity"]
	ship.fuel = stats["fuel_capacity"]  # Start with full fuel
	ship.min_crew = stats["min_crew"]
	ship.max_equipment_slots = stats["max_equipment_slots"]
	ship.base_mass = stats["cargo_capacity"] * stats["base_mass_mult"]

	# Initialize at Earth
	ship.position_au = CelestialData.get_earth_position_au()
	ship.engine_condition = 100.0

	return ship

static func get_class_description(ship_class: ShipClass) -> String:
	match ship_class:
		ShipClass.COURIER:
			return "Fast courier with low cargo capacity. Ideal for quick deliveries and contracts."
		ShipClass.HAULER:
			return "Heavy hauler with massive cargo bay. Slow but profitable for bulk mining."
		ShipClass.PROSPECTOR:
			return "Balanced mining vessel. Extra equipment slots for mining bonuses."
		ShipClass.EXPLORER:
			return "Long-range explorer with extended fuel capacity. Good for distant operations."
		_:
			return "Unknown ship class"
