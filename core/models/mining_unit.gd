class_name MiningUnit
extends Resource

enum UnitType {
	BASIC,
	ADVANCED,
	REFINERY,
}

const UNIT_TYPE_NAMES: Dictionary = {
	UnitType.BASIC: "Basic Mining Unit",
	UnitType.ADVANCED: "Advanced Mining Unit",
	UnitType.REFINERY: "Refinery Unit",
}

# Max durability decays at 1/10th the rate of normal wear.
# A Basic unit (0.3 wear/day) loses ~0.03 max_durability/day.
# After ~100 days of operation max_durability drops from 100 → ~97,
# but after ~1000 days it's down to ~70 and repairs become less effective.
const MAX_DURABILITY_DECAY_RATIO: float = 0.1

# Below this max_durability threshold, the unit should be recalled for rebuild
const REBUILD_THRESHOLD: float = 40.0

@export var unit_type: UnitType = UnitType.BASIC
@export var unit_name: String = ""
@export var mass: float = 0.0
@export var volume: float = 0.0   # m³
@export var workers_required: int = 1
@export var mining_multiplier: float = 1.0
@export var durability: float = 100.0
@export var max_durability: float = 100.0
@export var wear_per_day: float = 0.3
@export var cost: int = 0

# Deployment state
@export var deployed_at_asteroid: String = ""  # Empty = in inventory
@export var assigned_workers: Array[Worker] = []
@export var deployed_at_tick: float = 0.0

func is_deployed() -> bool:
	return deployed_at_asteroid != ""

func is_functional() -> bool:
	return durability > 0.0

func needs_rebuild() -> bool:
	return max_durability < REBUILD_THRESHOLD

func get_effective_multiplier() -> float:
	if not is_functional():
		return 0.0
	# Degrades below 30% of current max durability
	var threshold := max_durability * 0.3
	if threshold > 0.0 and durability < threshold:
		return mining_multiplier * (durability / threshold)
	return mining_multiplier

func get_type_name() -> String:
	return UNIT_TYPE_NAMES.get(unit_type, "Unknown")

func repair_cost() -> int:
	var missing := max_durability - durability
	if missing <= 0:
		return 0
	var cost_ratio := missing / max_durability
	return int(cost * 0.3 * cost_ratio)

func rebuild_cost() -> int:
	# Rebuilding costs 50% of the original unit price
	return int(cost * 0.5)

static func from_catalog(entry: Dictionary) -> MiningUnit:
	var u := MiningUnit.new()
	u.unit_type = entry["type"]
	u.unit_name = entry["name"]
	u.mass = entry["mass"]
	u.volume = entry.get("volume", 0.0)
	u.workers_required = entry["workers_required"]
	u.mining_multiplier = entry["mining_multiplier"]
	u.wear_per_day = entry["wear_per_day"]
	u.cost = entry["cost"]
	u.durability = 100.0
	u.max_durability = 100.0
	return u
