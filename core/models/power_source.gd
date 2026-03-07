class_name PowerSource
extends RefCounted

enum SourceType {
	SOLAR_ARRAY,
	FUSION_REACTOR,
}

const SOURCE_NAMES := {
	SourceType.SOLAR_ARRAY: "Solar Array",
	SourceType.FUSION_REACTOR: "Fusion Reactor",
}

const SOURCE_DESCRIPTIONS := {
	SourceType.SOLAR_ARRAY: "Photovoltaic panels. Cheap, zero fuel cost, but output drops as 1/r² from Sun. Useless beyond 4 AU.",
	SourceType.FUSION_REACTOR: "Compact D-T fusion plant. Full output anywhere in the system. Degrades over time; critically damaged units risk catastrophic containment failure.",
}

const BASE_PRICES := {
	SourceType.SOLAR_ARRAY: 80000,
	SourceType.FUSION_REACTOR: 600000,
}

# Power output in abstract units (fuel processors consume these)
const BASE_OUTPUT := {
	SourceType.SOLAR_ARRAY: 2.0,    # At 1 AU; scales with 1/r²
	SourceType.FUSION_REACTOR: 8.0, # Constant anywhere
}

# Durability wear per game-day when deployed
const WEAR_PER_DAY := {
	SourceType.SOLAR_ARRAY: 0.05,   # Micrometeorite impacts, thermal cycling
	SourceType.FUSION_REACTOR: 0.5, # Plasma erosion, tritium depletion
}

# How many durability points max_durability loses each repair cycle
const MAX_DUR_LOSS_PER_REPAIR := {
	SourceType.SOLAR_ARRAY: 2.0,
	SourceType.FUSION_REACTOR: 5.0,
}

# When max_durability falls below this, unit needs a full rebuild at a colony
const REBUILD_THRESHOLD: float = 60.0

# Reactor explosion window: starts when durability falls below this fraction of max_durability
const REACTOR_DANGER_THRESHOLD: float = 0.20
# Max per-tick explosion chance (reached at 0% durability)
const REACTOR_MAX_EXPLODE_CHANCE_PER_TICK: float = 0.005  # 0.5%/tick

@export var source_type: SourceType = SourceType.SOLAR_ARRAY
@export var source_name: String = ""
@export var durability: float = 100.0
@export var max_durability: float = 100.0
@export var cost: int = 0

# Set when deployed; empty string = in inventory
@export var deployed_at_asteroid: String = ""

func is_deployed() -> bool:
	return deployed_at_asteroid != ""

func is_functional() -> bool:
	return durability > 0.0

func needs_rebuild() -> bool:
	return max_durability < REBUILD_THRESHOLD

## Compute current power output.
## solar_intensity: 1.0 at 1 AU, scales as 1/r² (pass asteroid.orbit_au for correct value).
## Ignored for FUSION_REACTOR.
func get_output(solar_intensity: float = 1.0) -> float:
	if not is_functional():
		return 0.0
	var efficiency := durability / max_durability
	match source_type:
		SourceType.SOLAR_ARRAY:
			return BASE_OUTPUT[source_type] * solar_intensity * efficiency
		SourceType.FUSION_REACTOR:
			return BASE_OUTPUT[source_type] * efficiency
	return 0.0

## Per-tick explosion probability for a damaged fusion reactor.
## Returns 0.0 for solar arrays.
func get_explosion_chance_per_tick() -> float:
	if source_type != SourceType.FUSION_REACTOR:
		return 0.0
	if not is_functional():
		return REACTOR_MAX_EXPLODE_CHANCE_PER_TICK
	var danger_floor := max_durability * REACTOR_DANGER_THRESHOLD
	if durability >= danger_floor:
		return 0.0
	# Scale linearly from 0 at danger_floor to max at 0
	var severity := 1.0 - (durability / danger_floor)
	return severity * REACTOR_MAX_EXPLODE_CHANCE_PER_TICK

## Repair the unit. Restores durability to max_durability, then reduces max_durability.
## Returns repair cost in credits.
func calc_repair_cost() -> int:
	if durability >= max_durability:
		return 0
	var missing := max_durability - durability
	var cost_per_point: float = BASE_PRICES[source_type] / 200.0  # ~0.5% of purchase price per point
	return int(missing * cost_per_point)

func apply_repair() -> void:
	durability = max_durability
	max_durability = maxf(max_durability - MAX_DUR_LOSS_PER_REPAIR[source_type], 10.0)

## Rebuild cost — charged when recalling to colony for full restoration.
func calc_rebuild_cost() -> int:
	return int(BASE_PRICES[source_type] * 0.4)

func apply_rebuild() -> void:
	max_durability = 100.0
	durability = 100.0

static func create(type: SourceType) -> PowerSource:
	var ps := PowerSource.new()
	ps.source_type = type
	ps.source_name = SOURCE_NAMES[type]
	ps.cost = BASE_PRICES[type]
	ps.durability = 100.0
	ps.max_durability = 100.0
	return ps
