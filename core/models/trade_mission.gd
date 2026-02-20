class_name TradeMission
extends Resource

enum Status { TRANSIT_TO_COLONY, REFUELING, SELLING, IDLE_AT_COLONY, TRANSIT_BACK, COMPLETED }

enum WaypointType {
	GRAVITY_ASSIST,  # Existing - flyby planet
	REFUEL_STOP,     # New - stop at colony to refuel
}

enum TransitMode {
	BRACHISTOCHRONE,  # Fast, expensive fuel
	HOHMANN,          # Slow, economical fuel
}

@export var status: Status = Status.TRANSIT_TO_COLONY
@export var ship: Ship = null
@export var colony: Colony = null
@export var workers: Array[Worker] = []
@export var cargo: Dictionary = {}       # OreType -> tons (loaded at dispatch)
@export var transit_time: float = 0.0    # one-way transit in ticks
@export var elapsed_ticks: float = 0.0
@export var fuel_per_tick: float = 0.0
@export var revenue: int = 0             # filled on sell at colony
@export var origin_position_au: Vector2 = Vector2.ZERO   # where ship departed from
@export var return_position_au: Vector2 = Vector2.ZERO    # where ship returns to
@export var transit_mode: TransitMode = TransitMode.BRACHISTOCHRONE  # orbit type
@export var origin_is_earth: bool = true   # True if ship departed from Earth (for live position tracking)

# Gravity assist / multi-leg journey support
@export var outbound_waypoints: Array[Vector2] = []
@export var outbound_waypoint_planet_ids: Array[int] = []
@export var outbound_leg_times: Array[float] = []
@export var outbound_waypoint_index: int = 0
@export var return_waypoints: Array[Vector2] = []
@export var return_waypoint_planet_ids: Array[int] = []
@export var return_leg_times: Array[float] = []
@export var return_waypoint_index: int = 0

# Waypoint metadata (parallel arrays to outbound_waypoints/return_waypoints)
@export var outbound_waypoint_types: Array[int] = []
@export var outbound_waypoint_colony_refs: Array[Colony] = []
@export var outbound_waypoint_fuel_amounts: Array[float] = []
@export var outbound_waypoint_fuel_costs: Array[int] = []
@export var return_waypoint_types: Array[int] = []
@export var return_waypoint_colony_refs: Array[Colony] = []
@export var return_waypoint_fuel_amounts: Array[float] = []
@export var return_waypoint_fuel_costs: Array[int] = []

const SELL_DURATION: float = 5.0  # ticks spent at colony selling
const REFUEL_DURATION: float = 5.0  # ticks spent refueling

func get_current_phase_duration() -> float:
	match status:
		Status.TRANSIT_TO_COLONY:
			if outbound_leg_times.size() > outbound_waypoint_index:
				return outbound_leg_times[outbound_waypoint_index]
			return transit_time
		Status.TRANSIT_BACK:
			if return_leg_times.size() > return_waypoint_index:
				return return_leg_times[return_waypoint_index]
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

func get_status_text() -> String:
	var mode_suffix := " (Hohmann)" if transit_mode == TransitMode.HOHMANN else ""
	var slingshot_suffix := ""

	if status == Status.TRANSIT_TO_COLONY and outbound_waypoint_planet_ids.size() > 0:
		slingshot_suffix = " [Slingshot]"
	elif status == Status.TRANSIT_BACK and return_waypoint_planet_ids.size() > 0:
		slingshot_suffix = " [Slingshot]"

	var home := _get_home_name()
	var dest := colony.colony_name if colony else "colony"

	match status:
		Status.REFUELING:
			var colony_name := "waypoint"
			var idx := outbound_waypoint_index - 1 if outbound_waypoint_index > 0 else return_waypoint_index - 1
			var is_outbound := outbound_waypoint_index > 0
			var refs := outbound_waypoint_colony_refs if is_outbound else return_waypoint_colony_refs
			if idx >= 0 and idx < refs.size():
				var col := refs[idx]
				if col:
					colony_name = col.colony_name
			if is_outbound:
				return "Refueling at %s (%s)" % [colony_name, dest]
			return "Refueling at %s (%s)" % [colony_name, home]
		Status.TRANSIT_TO_COLONY:
			var fuel_stop_suffix := ""
			if outbound_waypoint_types.size() > 0:
				var refuel_count := outbound_waypoint_types.count(WaypointType.REFUEL_STOP)
				if refuel_count > 0:
					fuel_stop_suffix = " [%d fuel stop%s]" % [refuel_count, "s" if refuel_count > 1 else ""]
			return "%s → %s (%s)%s%s%s" % [home, dest, home, mode_suffix, slingshot_suffix, fuel_stop_suffix]
		Status.SELLING:
			return "Selling at %s (%s)" % [dest, home]
		Status.IDLE_AT_COLONY:
			return "Idle at %s (%s)" % [dest, home]
		Status.TRANSIT_BACK:
			var fuel_stop_suffix := ""
			if return_waypoint_types.size() > 0:
				var refuel_count := return_waypoint_types.count(WaypointType.REFUEL_STOP)
				if refuel_count > 0:
					fuel_stop_suffix = " [%d fuel stop%s]" % [refuel_count, "s" if refuel_count > 1 else ""]
			return "%s → %s%s%s%s" % [dest, home, mode_suffix, slingshot_suffix, fuel_stop_suffix]
		Status.COMPLETED:
			return "Trade complete at %s" % dest
	return "Unknown"

func _get_origin_pos_live() -> Vector2:
	# Live origin position — accounts for orbital movement since mission was created
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
			elif outbound_waypoint_index > 0 and outbound_waypoint_index <= outbound_waypoints.size():
				var waypoint: Vector2 = outbound_waypoints[outbound_waypoint_index - 1]
				return waypoint if waypoint != null else origin_position_au
			return _get_origin_pos_live()
		Status.TRANSIT_BACK:
			if return_waypoint_index == 0:
				return colony.get_position_au() if colony else (origin_position_au if origin_position_au != Vector2.ZERO else Vector2.ZERO)
			elif return_waypoint_index > 0 and return_waypoint_index <= return_waypoints.size():
				var waypoint: Vector2 = return_waypoints[return_waypoint_index - 1]
				return waypoint if waypoint != null else (colony.get_position_au() if colony else origin_position_au)
			return colony.get_position_au() if colony else (origin_position_au if origin_position_au != Vector2.ZERO else Vector2.ZERO)
		_:
			return _get_origin_pos_live()

func get_current_leg_end_pos() -> Vector2:
	match status:
		Status.TRANSIT_TO_COLONY:
			if outbound_waypoint_index < outbound_waypoints.size():
				var waypoint: Vector2 = outbound_waypoints[outbound_waypoint_index]
				return waypoint if waypoint != null else (colony.get_position_au() if colony else origin_position_au)
			else:
				return colony.get_position_au() if colony else (origin_position_au if origin_position_au != Vector2.ZERO else Vector2.ZERO)
		Status.TRANSIT_BACK:
			if return_waypoint_index < return_waypoints.size():
				var waypoint: Vector2 = return_waypoints[return_waypoint_index]
				return waypoint if waypoint != null else return_position_au
			else:
				# Use live position — return_position_au goes stale as bodies orbit
				if ship and ship.is_stationed and ship.station_colony:
					return ship.station_colony.get_position_au()
				else:
					return CelestialData.get_earth_position_au()
		_:
			return origin_position_au if origin_position_au != Vector2.ZERO else Vector2.ZERO
