class_name Ship
extends Resource

const FUEL_COST_PER_UNIT: float = 5.0  # $ per unit of fuel
const EARTH_PROXIMITY_AU: float = 0.05  # within this distance counts as "at Earth"
const COLONY_PROXIMITY_AU: float = 0.02  # within this distance counts as "at colony"

@export var ship_name: String = ""
@export var ship_class: int = -1        # ShipData.ShipClass enum value
@export var docked_at_colony: Colony = null  # Which colony the ship is docked at (if any)
@export var max_thrust_g: float = 0.3   # maximum acceleration in g
@export var thrust_setting: float = 1.0 # 0.0 to 1.0, percentage of max_thrust to use
@export var cargo_capacity: float = 100.0 # tons (mass limit)
@export var cargo_volume: float = 143.0   # m³ (volume limit)
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

# Station properties
@export var is_stationed: bool = false
@export var station_colony: Colony = null
@export var station_jobs: Array[String] = []     # Priority-ordered: ["mining", "trading", "repair", ...]
@export var station_log: Array[Dictionary] = []  # [{time, message, type}] capped at 50

# Supply cargo (shared cargo capacity with ore)
@export var supplies: Dictionary = {}            # "repair_parts": float, "food": float

# Life support tracking (in game-seconds remaining)
@export var life_support_remaining: float = 2592000.0  # 30 days default

var engine_wear_per_tick: float = 0.00003

var current_mission: Mission = null
var current_trade_mission: TradeMission = null
var last_crew: Array[Worker] = []  # Remember last crew used

# Queued mission data (set destination while ship is busy)
var queued_destination: Variant = null  # AsteroidData or Colony
var queued_workers: Array[Worker] = []
var queued_transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE
var queued_mining_duration: float = 86400.0
var queued_slingshot_route = null  # GravityAssist.SlingshotRoute or null

var is_at_earth: bool:
	get:
		return position_au.distance_to(CelestialData.get_earth_position_au()) < EARTH_PROXIMITY_AU

var is_stationed_idle: bool:
	get:
		return is_stationed and not is_derelict and current_mission == null and current_trade_mission == null

var _has_active_mission: bool:
	get:
		if current_mission != null and current_mission.status != Mission.Status.IDLE_AT_DESTINATION:
			return true
		if current_trade_mission != null and current_trade_mission.status != TradeMission.Status.IDLE_AT_COLONY:
			return true
		return false

var is_docked: bool:
	get:
		# Ship is docked if it has NO mission and is either at Earth or at a colony
		if current_mission != null or current_trade_mission != null or is_derelict:
			return false
		return is_at_earth or docked_at_colony != null

## Get the colony the ship is currently docked at (if any)
func get_docked_colony() -> Colony:
	return docked_at_colony if is_docked else null

## Check if ship can access services (repairs, upgrades)
func can_access_services() -> bool:
	if not is_docked:
		return false
	# At Earth, always have services
	if is_at_earth:
		return true
	# At colony, only if it has rescue ops (= large colony with facilities)
	if docked_at_colony != null:
		return docked_at_colony.has_rescue_ops
	return false

var is_idle_remote: bool:
	get:
		# Stationed ships are never "idle remote" — they have their own management
		if is_stationed:
			return false
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
	# Ore cargo
	for amount in current_cargo.values():
		total += amount
	# Supplies (food, repair parts, etc.)
	for supply_key in supplies:
		var supply_type := SupplyData.get_supply_type_from_key(supply_key)
		if supply_type >= 0:
			var amount: float = supplies[supply_key]
			total += amount * SupplyData.get_mass_per_unit(supply_type)
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

func get_supplies_mass() -> float:
	var total := 0.0
	for supply_key in supplies:
		var supply_type := SupplyData.get_supply_type_from_key(supply_key)
		if supply_type >= 0:
			var amount: float = supplies[supply_key]
			total += amount * SupplyData.get_mass_per_unit(supply_type)
	return total

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

func get_effective_cargo_volume() -> float:
	var effective := cargo_volume
	for upgrade in upgrades:
		effective += upgrade.cargo_volume_bonus
	return effective

## Volume used by bulky cargo (mining units, supplies).
## Ore is mass-constrained, not volume-constrained — not counted here.
func get_cargo_volume_used() -> float:
	var vol := 0.0
	# Mining units being transported on an active deploy mission
	if current_mission != null and current_mission.mission_type == Mission.MissionType.DEPLOY_UNIT:
		for unit in current_mission.mining_units_to_deploy:
			vol += unit.volume
	# Supplies
	for supply_type in SupplyData.SUPPLY_INFO:
		var key: String = SupplyData.SUPPLY_INFO[supply_type]["key"]
		var amount: float = supplies.get(key, 0.0)
		vol += amount * SupplyData.SUPPLY_INFO[supply_type]["volume_per_unit"]
	return vol

func get_cargo_volume_remaining() -> float:
	return get_effective_cargo_volume() - get_cargo_volume_used()

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
	# Target: once every 2-30 trips depending on condition
	# Baseline: manufacturing defects, worker misuse — rare but always possible
	var chance := 0.00000002  # ~1 per 50 trips even with perfect maintenance
	if engine_condition < 50.0:
		# At 40% condition: 10 * 0.0000001 = 0.000001/tick → ~1 per 5 trips
		# At 30% condition: 20 * 0.0000001 = 0.000002/tick → ~1 per 2.5 trips
		# At  0% condition: 50 * 0.0000001 = 0.000005/tick → ~1 per trip
		chance += (50.0 - engine_condition) * 0.0000001
	if fuel < fuel_capacity * 0.1:
		chance += 0.0000005  # ~1 per 10 trips with critically low fuel
	# Broken equipment adds minor risk
	for e in equipment:
		if e.durability <= 0:
			chance += 0.0000002  # ~1 per 25 trips per broken piece
	return chance

func get_engine_repair_cost() -> int:
	return int((100.0 - engine_condition) * 10.0)

func get_class_name() -> String:
	if ship_class >= 0 and ship_class < ShipData.ShipClass.size():
		return ShipData.CLASS_NAMES.get(ship_class, "Unknown")
	return "Legacy"  # For old saves without ship_class

func has_queued_mission() -> bool:
	return queued_destination != null

func clear_queued_mission() -> void:
	queued_destination = null
	queued_workers.clear()
	queued_transit_mode = Mission.TransitMode.BRACHISTOCHRONE
	queued_mining_duration = 86400.0
	queued_slingshot_route = null

## Calculate life support duration based on crew size
## Assumes standard rations: food, water, O2 for N crew members
## Returns duration in game-seconds
func calculate_life_support_duration(crew_count: int) -> float:
	if crew_count <= 0:
		return 0.0
	# Assume ship carries 30 days of supplies per crew member
	var days_per_crew := 30.0
	return days_per_crew * 86400.0  # Convert to seconds

## Reset life support to full based on current crew
func reset_life_support(crew_count: int) -> void:
	life_support_remaining = calculate_life_support_duration(crew_count)

func add_station_log(message: String, type: String = "info") -> void:
	station_log.push_front({
		"time": GameState.total_ticks,
		"message": message,
		"type": type,
	})
	if station_log.size() > 50:
		station_log.resize(50)

func queue_mission(destination: Variant, workers: Array[Worker], transit_mode: int, mining_dur: float = 86400.0, slingshot_route = null) -> void:
	queued_destination = destination
	queued_workers = workers.duplicate()
	queued_transit_mode = transit_mode
	queued_mining_duration = mining_dur
	queued_slingshot_route = slingshot_route
