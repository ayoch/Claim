class_name ShipUpgrade
extends Resource

enum UpgradeType {
	FUEL_TANK,      # Increases fuel_capacity
	ENGINE,         # Increases thrust_g or reduces fuel consumption
	CARGO_BAY,      # Increases cargo_capacity
	HULL,           # Reduces base_mass (lighter construction)
}

@export var upgrade_name: String = ""
@export var upgrade_type: UpgradeType = UpgradeType.FUEL_TANK
@export var cost: int = 0
@export var description: String = ""

# Stat modifications
@export var fuel_capacity_bonus: float = 0.0
@export var thrust_bonus: float = 0.0
@export var cargo_capacity_bonus: float = 0.0
@export var cargo_volume_bonus: float = 0.0
@export var base_mass_multiplier: float = 1.0  # <1.0 makes ship lighter
@export var fuel_efficiency_multiplier: float = 1.0  # <1.0 reduces fuel consumption

static func from_catalog(entry: Dictionary) -> ShipUpgrade:
	var u := ShipUpgrade.new()
	u.upgrade_name = entry.get("name", "")
	u.upgrade_type = entry.get("type", UpgradeType.FUEL_TANK)
	u.cost = entry.get("cost", 0)
	u.description = entry.get("description", "")
	u.fuel_capacity_bonus = entry.get("fuel_capacity_bonus", 0.0)
	u.thrust_bonus = entry.get("thrust_bonus", 0.0)
	u.cargo_capacity_bonus = entry.get("cargo_capacity_bonus", 0.0)
	u.cargo_volume_bonus = entry.get("cargo_volume_bonus", 0.0)
	u.base_mass_multiplier = entry.get("base_mass_multiplier", 1.0)
	u.fuel_efficiency_multiplier = entry.get("fuel_efficiency_multiplier", 1.0)
	return u
