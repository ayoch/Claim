class_name Ship
extends Resource

const FUEL_COST_PER_UNIT: float = 5.0  # $ per unit of fuel
const EARTH_PROXIMITY_AU: float = 0.05  # within this distance counts as "at Earth"

@export var ship_name: String = ""
@export var ship_class: int = -1        # ShipData.ShipClass enum value
@export var max_thrust_g: float = 0.3   # maximum acceleration in g
@export var thrust_setting: float = 1.0 # 0.0 to 1.0, percentage of max_thrust to use
@export var cargo_capacity: float = 100.0 # tons
@export var fuel_capacity: float = 200.0  # fuel units
@export var fuel: float = 200.0           # current fuel
@export var min_crew: int = 3             # minimum crew to dispatch
@export var max_equipment_slots: int = 2  # equipment slot limit
@export var current_cargo: Dictionary = {} # OreType -> tons
@export var equipment: Array[Equipment] = []
@export var upgrades: Array[ShipUpgrade] = []  # Installed ship upgrades
@export var position_au: Vector2 = Vector2.ZERO  # persistent solar system position
@export var velocity_au_per_tick: Vector2 = Vector2.ZERO  # current velocity vector
@export var speed_au_per_tick: float = 0.0  # current speed magnitude
@export var engine_condition: float = 100.0       # degrades during transit
@export var is_derelict: bool = false
@export var derelict_reason: String = ""  # "out_of_fuel" or "breakdown"
@export var base_mass: float = 0.0  # tons, auto-calculated if zero

var engine_wear_per_tick: float = 0.02

var current_mission: Mission = null
var current_trade_mission: TradeMission = null
var last_crew: Array[Worker] = []  # Remember last crew used

var is_at_earth: bool:
	get:
		return position_au.distance_to(CelestialData.get_earth_position_au()) < EARTH_PROXIMITY_AU

var _has_active_mission: bool:
	get:
		if current_mission != null and current_mission.status != Mission.Status.IDLE_AT_DESTINATION:
			return true
		if current_trade_mission != null and current_trade_mission.status != TradeMission.Status.IDLE_AT_COLONY:
			return true
		return false

var is_docked: bool:
	get:
		# Ship is only docked if it has NO mission at all and is at Earth
		return current_mission == null and current_trade_mission == null and is_at_earth and not is_derelict

var is_idle_remote: bool:
	get:
		# Ship is idle remote if it has a mission but in idle state, or no mission and not at Earth
		if current_mission and current_mission.status == Mission.Status.IDLE_AT_DESTINATION:
			return true
		if current_trade_mission and current_trade_mission.status == TradeMission.Status.IDLE_AT_COLONY:
			return true
		return current_mission == null and current_trade_mission == null and not is_at_earth and not is_derelict

func get_mining_multiplier() -> float:
	var mult := 1.0
	for e in equipment:
		mult *= e.get_effective_bonus()
	return mult

func get_cargo_total() -> float:
	var total := 0.0
	for amount in current_cargo.values():
		total += amount
	return total

func cleanup_cargo() -> void:
	# Remove zero or near-zero cargo entries to prevent dictionary bloat
	var to_remove: Array = []
	for ore_type in current_cargo:
		if current_cargo[ore_type] < 0.01:
			to_remove.append(ore_type)
	for ore_type in to_remove:
		current_cargo.erase(ore_type)

func get_cargo_remaining() -> float:
	return get_effective_cargo_capacity() - get_cargo_total()

func get_base_mass() -> float:
	# Auto-calculate if not set (backward compatibility)
	var raw_mass := base_mass if base_mass > 0.0 else cargo_capacity * 2.0

	# Apply upgrade multipliers
	var mass_multiplier := 1.0
	for upgrade in upgrades:
		mass_multiplier *= upgrade.base_mass_multiplier

	return raw_mass * mass_multiplier

func get_effective_thrust() -> float:
	var max_thrust := max_thrust_g
	for upgrade in upgrades:
		max_thrust += upgrade.thrust_bonus
	# Apply thrust setting (0.0 to 1.0)
	return max_thrust * thrust_setting

func get_effective_fuel_capacity() -> float:
	var effective := fuel_capacity
	for upgrade in upgrades:
		effective += upgrade.fuel_capacity_bonus
	return effective

func get_effective_cargo_capacity() -> float:
	var effective := cargo_capacity
	for upgrade in upgrades:
		effective += upgrade.cargo_capacity_bonus
	return effective

func calc_fuel_for_distance(dist_au: float, cargo_mass: float = -1.0) -> float:
	# Fuel proportional to mass, distance, and thrust (F=ma physics)
	var cargo := cargo_mass if cargo_mass >= 0.0 else get_cargo_total()
	var total_mass := get_base_mass() + cargo
	var fuel_efficiency_constant := 0.35  # Balanced: 1 AU round trip ~= 90 fuel (45% of 200 capacity)

	# Apply upgrade efficiency multipliers
	var efficiency_multiplier := 1.0
	for upgrade in upgrades:
		efficiency_multiplier *= upgrade.fuel_efficiency_multiplier

	return dist_au * get_effective_thrust() * total_mass * fuel_efficiency_constant * efficiency_multiplier

func get_breakdown_chance_per_tick() -> float:
	# Higher chance when engine condition is low or fuel is critically low
	var chance := 0.0
	if engine_condition < 50.0:
		chance += (50.0 - engine_condition) * 0.001  # up to 5% per tick at 0 condition
	if fuel < fuel_capacity * 0.1:
		chance += 0.005
	# Broken equipment adds risk
	for e in equipment:
		if e.durability <= 0:
			chance += 0.002
	return chance

func get_engine_repair_cost() -> int:
	return int((100.0 - engine_condition) * 10.0)

func get_class_name() -> String:
	if ship_class >= 0 and ship_class < ShipData.ShipClass.size():
		return ShipData.CLASS_NAMES.get(ship_class, "Unknown")
	return "Legacy"  # For old saves without ship_class
