class_name Equipment
extends Resource

@export var equipment_name: String = ""
@export var type: String = ""          # "processor", "refinery"
@export var mining_bonus: float = 1.0  # multiplier
@export var cost: int = 0

static func from_catalog(entry: Dictionary) -> Equipment:
	var e := Equipment.new()
	e.equipment_name = entry.get("name", "")
	e.type = entry.get("type", "")
	e.mining_bonus = entry.get("mining_bonus", 1.0)
	e.cost = entry.get("cost", 0)
	return e
