class_name FuelProcessor
extends RefCounted

enum ProcessorType {
	BASIC,
	ADVANCED,
}

const PROCESSOR_NAMES := {
	ProcessorType.BASIC: "Basic Fuel Processor",
	ProcessorType.ADVANCED: "Advanced Fuel Processor",
}

const PROCESSOR_DESCRIPTIONS := {
	ProcessorType.BASIC: "Electrolyzes water ice into liquid hydrogen/oxygen propellant. Requires a power source. Only operable at water-ice bearing asteroids.",
	ProcessorType.ADVANCED: "High-throughput processor with integrated cracking unit. 50% more output per unit power, lower per-ton degradation.",
}

const BASE_PRICES := {
	ProcessorType.BASIC: 200000,
	ProcessorType.ADVANCED: 450000,
}

# Fuel output per power unit per game-day (in ship fuel units)
const OUTPUT_PER_POWER_PER_DAY := {
	ProcessorType.BASIC: 1.0,
	ProcessorType.ADVANCED: 1.5,
}

# Worker bonus: each assigned worker adds this fraction to output
const WORKER_OUTPUT_BONUS: float = 0.20  # +20% per worker

# Durability wear per game-day when deployed and running
const WEAR_PER_DAY := {
	ProcessorType.BASIC: 0.20,
	ProcessorType.ADVANCED: 0.25,
}

# Max durability lost per repair cycle
const MAX_DUR_LOSS_PER_REPAIR: float = 3.0

const REBUILD_THRESHOLD: float = 60.0

@export var processor_type: ProcessorType = ProcessorType.BASIC
@export var processor_name: String = ""
@export var durability: float = 100.0
@export var max_durability: float = 100.0
@export var cost: int = 0

@export var deployed_at_asteroid: String = ""
@export var assigned_workers: Array[Worker] = []

func is_deployed() -> bool:
	return deployed_at_asteroid != ""

func is_functional() -> bool:
	return durability > 0.0

func needs_rebuild() -> bool:
	return max_durability < REBUILD_THRESHOLD

## Fuel produced per game-day given available power and current condition.
func get_daily_output(power_available: float) -> float:
	if not is_functional() or power_available <= 0.0:
		return 0.0
	var worker_bonus := 1.0 + (assigned_workers.size() * WORKER_OUTPUT_BONUS)
	var efficiency := durability / max_durability
	return OUTPUT_PER_POWER_PER_DAY[processor_type] * power_available * worker_bonus * efficiency

func calc_repair_cost() -> int:
	if durability >= max_durability:
		return 0
	var missing := max_durability - durability
	var cost_per_point: float = BASE_PRICES[processor_type] / 200.0
	return int(missing * cost_per_point)

func apply_repair() -> void:
	durability = max_durability
	max_durability = maxf(max_durability - MAX_DUR_LOSS_PER_REPAIR, 10.0)

func calc_rebuild_cost() -> int:
	return int(BASE_PRICES[processor_type] * 0.4)

func apply_rebuild() -> void:
	max_durability = 100.0
	durability = 100.0

static func create(type: ProcessorType) -> FuelProcessor:
	var fp := FuelProcessor.new()
	fp.processor_type = type
	fp.processor_name = PROCESSOR_NAMES[type]
	fp.cost = BASE_PRICES[type]
	fp.durability = 100.0
	fp.max_durability = 100.0
	return fp
