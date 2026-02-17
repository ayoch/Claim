class_name Ship
extends Resource

const FUEL_COST_PER_UNIT: float = 5.0  # $ per unit of fuel

@export var ship_name: String = ""
@export var thrust_g: float = 0.3       # acceleration in g
@export var cargo_capacity: float = 100.0 # tons
@export var fuel_capacity: float = 200.0  # fuel units
@export var fuel: float = 200.0           # current fuel
@export var min_crew: int = 3             # minimum crew to dispatch
@export var max_equipment_slots: int = 2  # equipment slot limit
@export var current_cargo: Dictionary = {} # OreType -> tons
@export var equipment: Array[Equipment] = []

var current_mission: Mission = null
var current_trade_mission: TradeMission = null
var last_crew: Array[Worker] = []  # Remember last crew used

var is_docked: bool:
	get:
		return current_mission == null and current_trade_mission == null

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

func get_cargo_remaining() -> float:
	return cargo_capacity - get_cargo_total()

func calc_fuel_for_distance(dist_au: float) -> float:
	# Fuel proportional to distance and thrust
	return dist_au * 50.0 * thrust_g
