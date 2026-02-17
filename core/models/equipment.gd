class_name Equipment
extends Resource

@export var equipment_name: String = ""
@export var type: String = ""          # "processor", "refinery"
@export var mining_bonus: float = 1.0  # multiplier
@export var cost: int = 0
@export var durability: float = 100.0
@export var max_durability: float = 100.0
@export var wear_per_tick: float = 0.5
@export var fabrication_ticks: float = 0.0  # >0 means still being fabricated

func is_functional() -> bool:
	return durability > 0.0 and fabrication_ticks <= 0.0

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
	return e
