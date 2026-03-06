class_name TradeMission
extends Resource

enum Status { TRANSIT_TO_COLONY, REFUELING, SELLING, IDLE_AT_COLONY, TRANSIT_BACK, COMPLETED }

enum TransitMode {
	BRACHISTOCHRONE,  # Fast, expensive fuel
	HOHMANN,          # Slow, economical fuel
}

@export var status: Status = Status.TRANSIT_TO_COLONY
@export var ship: Ship = null
@export var colony: Colony = null
@export var cargo: Dictionary = {}       # OreType -> tons (loaded at dispatch)
@export var transit_time: float = 0.0    # final leg transit time (or only leg if no waypoints)
@export var elapsed_ticks: float = 0.0
@export var fuel_per_tick: float = 0.0
@export var revenue: int = 0             # filled on sell at colony
@export var origin_position_au: Vector2 = Vector2.ZERO
@export var return_position_au: Vector2 = Vector2.ZERO
@export var transit_mode: TransitMode = TransitMode.BRACHISTOCHRONE
@export var origin_is_earth: bool = true
@export var origin_name: String = ""

# Multi-leg journey: each entry is one intermediate stop; final leg uses transit_time
@export var outbound_legs: Array[WaypointLeg] = []
@export var outbound_waypoint_index: int = 0
@export var return_legs: Array[WaypointLeg] = []
@export var return_waypoint_index: int = 0

const SELL_DURATION: float = 5.0   # ticks spent at colony selling
const REFUEL_DURATION: float = 5.0  # ticks spent refueling
var refueling_is_return: bool = false  # True when refueling during return trip

func get_current_phase_duration() -> float:
	match status:
		Status.TRANSIT_TO_COLONY:
			if outbound_waypoint_index < outbound_legs.size():
				return outbound_legs[outbound_waypoint_index].transit_time
			return transit_time
		Status.TRANSIT_BACK:
			if return_waypoint_index < return_legs.size():
				return return_legs[return_waypoint_index].transit_time
			return transit_time
		Status.SELLING:
			return SELL_DURATION
		_:
			return 0.0

func get_progress() -> float:
	var duration := get_current_phase_duration()
	if duration > 0:
		return elapsed_ticks / duration
	match status:
		Status.IDLE_AT_COLONY, Status.COMPLETED:
			return 1.0
		_:
			return 0.0

func _get_home_name() -> String:
	if ship and ship.is_stationed and ship.station_colony:
		return ship.station_colony.colony_name
	return "Earth"

func has_slingshot_outbound() -> bool:
	return outbound_legs.any(func(l: WaypointLeg) -> bool: return l.planet_id >= 0)

func has_slingshot_return() -> bool:
	return return_legs.any(func(l: WaypointLeg) -> bool: return l.planet_id >= 0)

func get_status_text() -> String:
	var mode_suffix := " (Hohmann)" if transit_mode == TransitMode.HOHMANN else ""
	var slingshot_suffix := ""

	if status == Status.TRANSIT_TO_COLONY and has_slingshot_outbound():
		slingshot_suffix = " [Slingshot]"
	elif status == Status.TRANSIT_BACK and has_slingshot_return():
		slingshot_suffix = " [Slingshot]"

	var home := _get_home_name()
	var dest := colony.colony_name if colony else "colony"

	match status:
		Status.REFUELING:
			var colony_name := "waypoint"
			var idx := outbound_waypoint_index - 1 if outbound_waypoint_index > 0 else return_waypoint_index - 1
			var is_outbound := outbound_waypoint_index > 0
			var legs := outbound_legs if is_outbound else return_legs
			if idx >= 0 and idx < legs.size() and legs[idx].colony_ref:
				colony_name = legs[idx].colony_ref.colony_name
			if is_outbound:
				return "Refueling at %s (%s)" % [colony_name, dest]
			return "Refueling at %s (%s)" % [colony_name, home]
		Status.TRANSIT_TO_COLONY:
			var fuel_stop_suffix := ""
			var refuel_count := outbound_legs.filter(func(l: WaypointLeg) -> bool: return l.waypoint_type == WaypointLeg.WaypointType.REFUEL_STOP).size()
			if refuel_count > 0:
				fuel_stop_suffix = " [%d fuel stop%s]" % [refuel_count, "s" if refuel_count > 1 else ""]
			return "%s → %s (%s)%s%s%s" % [home, dest, home, mode_suffix, slingshot_suffix, fuel_stop_suffix]
		Status.SELLING:
			return "Selling at %s (%s)" % [dest, home]
		Status.IDLE_AT_COLONY:
			return "Idle at %s (%s)" % [dest, home]
		Status.TRANSIT_BACK:
			var fuel_stop_suffix := ""
			var refuel_count := return_legs.filter(func(l: WaypointLeg) -> bool: return l.waypoint_type == WaypointLeg.WaypointType.REFUEL_STOP).size()
			if refuel_count > 0:
				fuel_stop_suffix = " [%d fuel stop%s]" % [refuel_count, "s" if refuel_count > 1 else ""]
			return "%s → %s%s%s%s" % [dest, home, mode_suffix, slingshot_suffix, fuel_stop_suffix]
		Status.COMPLETED:
			return "Trade complete at %s" % dest
	return "Unknown"

func _get_origin_pos_live() -> Vector2:
	if ship and ship.is_stationed and ship.station_colony:
		return ship.station_colony.get_position_au()
	if origin_is_earth:
		return CelestialData.get_earth_position_au()
	return origin_position_au if origin_position_au != Vector2.ZERO else Vector2.ZERO

func get_current_leg_start_pos() -> Vector2:
	match status:
		Status.TRANSIT_TO_COLONY:
			if outbound_waypoint_index == 0:
				return _get_origin_pos_live()
			elif outbound_waypoint_index <= outbound_legs.size():
				return outbound_legs[outbound_waypoint_index - 1].get_live_position()
			return _get_origin_pos_live()
		Status.TRANSIT_BACK:
			if return_waypoint_index == 0:
				return colony.get_position_au() if colony else (origin_position_au if origin_position_au != Vector2.ZERO else Vector2.ZERO)
			elif return_waypoint_index <= return_legs.size():
				return return_legs[return_waypoint_index - 1].get_live_position()
			return colony.get_position_au() if colony else (origin_position_au if origin_position_au != Vector2.ZERO else Vector2.ZERO)
		_:
			return _get_origin_pos_live()

func get_current_leg_end_pos() -> Vector2:
	match status:
		Status.TRANSIT_TO_COLONY:
			if outbound_waypoint_index < outbound_legs.size():
				return outbound_legs[outbound_waypoint_index].get_live_position()
			return colony.get_position_au() if colony else (origin_position_au if origin_position_au != Vector2.ZERO else Vector2.ZERO)
		Status.TRANSIT_BACK:
			if return_waypoint_index < return_legs.size():
				return return_legs[return_waypoint_index].get_live_position()
			if ship and ship.is_stationed and ship.station_colony:
				return ship.station_colony.get_position_au()
			else:
				return CelestialData.get_earth_position_au()
		_:
			return origin_position_au if origin_position_au != Vector2.ZERO else Vector2.ZERO


## Cleanup method to break circular references
## Call this when removing a trade mission to prevent memory leaks
func cleanup() -> void:
	# Break ship reference (ship also references this trade mission)
	ship = null

	# Break colony reference
	colony = null

	# Clear cargo dictionary
	cargo.clear()

	# Clear waypoint legs (contain WaypointLeg resources)
	outbound_legs.clear()
	return_legs.clear()
