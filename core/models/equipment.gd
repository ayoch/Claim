class_name Equipment
extends Resource

@export var equipment_name: String = ""
@export var type: String = ""          # "processor", "refinery", "weapon"
@export var mining_bonus: float = 1.0  # multiplier
@export var cost: int = 0
@export var durability: float = 100.0
@export var max_durability: float = 100.0
@export var wear_per_tick: float = 0.5
@export var fabrication_ticks: float = 0.0  # >0 means still being fabricated

# Weapon properties (0/empty = not a weapon)
@export var weapon_power: int = 0           # Damage rating (0 = not a weapon, 1-50 = weapon damage)
@export var weapon_range: float = 0.0       # AU (0.0 = not a weapon)
@export var weapon_accuracy: float = 0.0    # 0.0-1.0 hit chance
@export var weapon_role: String = ""        # "offensive", "defensive", "dual"
@export var fire_rate: String = ""          # "fast", "slow", "very_slow", "limited"
@export var ammo_capacity: int = 0          # 0 = unlimited, >0 = torpedo launchers
@export var current_ammo: int = 0           # Current loaded torpedoes
@export var ammo_cost: int = 0              # Cost to reload 1 torpedo
@export var ammo_quality: int = 1           # MunitionsData.Quality enum (1 = STANDARD default)
@export var mining_speed_bonus: float = 0.0 # For mining laser: 0.2 = +20% mining speed
@export var mass: float = 0.0               # Equipment mass in tonnes

func is_functional() -> bool:
	return durability > 0.0 and fabrication_ticks <= 0.0

func is_weapon() -> bool:
	return weapon_power > 0 and weapon_range > 0.0

func has_ammo() -> bool:
	return ammo_capacity > 0

func needs_reload() -> bool:
	return has_ammo() and current_ammo < ammo_capacity

func get_effective_bonus() -> float:
	if not is_functional():
		return 1.0
	return mining_bonus

func repair_cost() -> int:
	var missing := max_durability - durability
	if missing <= 0:
		return 0
	# Cost scales with equipment value and damage
	var cost_ratio := missing / max_durability
	return int(cost * 0.3 * cost_ratio)

func is_fabricating() -> bool:
	return fabrication_ticks > 0.0

static func from_catalog(entry: Dictionary) -> Equipment:
	var e := Equipment.new()
	e.equipment_name = entry.get("name", "")
	e.type = entry.get("type", "")
	e.mining_bonus = entry.get("mining_bonus", 1.0)
	e.cost = entry.get("cost", 0)
	e.wear_per_tick = entry.get("wear_per_tick", 0.5)
	e.fabrication_ticks = entry.get("fabrication_ticks", 0.0)
	e.durability = 100.0
	e.max_durability = 100.0

	# Weapon properties
	e.weapon_power = entry.get("weapon_power", 0)
	e.weapon_range = entry.get("weapon_range", 0.0)
	e.weapon_accuracy = entry.get("weapon_accuracy", 0.0)
	e.weapon_role = entry.get("weapon_role", "")
	e.fire_rate = entry.get("fire_rate", "")
	e.ammo_capacity = entry.get("ammo_capacity", 0)
	e.current_ammo = entry.get("ammo_capacity", 0)  # Start with full ammo
	e.ammo_cost = entry.get("ammo_cost", 0)
	e.mining_speed_bonus = entry.get("mining_speed_bonus", 0.0)
	e.mass = entry.get("mass", 0.0)

	return e
