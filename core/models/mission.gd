class_name Mission
extends Resource

enum MissionType {
	MINING,          # Existing behavior (default)
	REPAIR,          # Dispatch to derelict ship, repair on arrival
	SUPPLY_RUN,      # Deliver supplies/parts to remote location
	CREW_FERRY,      # Transport workers to/from remote site
	PATROL,          # Watch area for threats, deter rivals
	DEPLOY_UNIT,     # Deploy mining units to an asteroid
	COLLECT_ORE,     # Collect stockpiled ore from an asteroid
	REPOSITION,      # Move ship to location and leave idle
}

enum Status {
	TRANSIT_OUT,
	REFUELING,
	MINING,
	IDLE_AT_DESTINATION,
	TRANSIT_BACK,
	COMPLETED,
	REPAIRING,       # Repairing a remote ship
	DELIVERING,      # Dropping off supplies
	BOARDING,        # Crew transfer
	PATROLLING,      # Watching area
	DEPLOYING,       # Deploying mining units
	COLLECTING,      # Collecting stockpiled ore
}

enum TransitMode {
	BRACHISTOCHRONE,  # Fast, expensive fuel (continuous thrust)
	HOHMANN,          # Slow, economical fuel (minimal delta-v)
}

@export var mission_type: int = MissionType.MINING
@export var status: Status = Status.TRANSIT_OUT
@export var ship: Ship = null
@export var asteroid: AsteroidData = null
@export var transit_time: float = 0.0     # ticks for the FINAL leg (or only leg if no waypoints)
@export var elapsed_ticks: float = 0.0    # ticks elapsed in current phase
@export var mining_duration: float = 86400.0 # ticks to mine (auto-calculated at mission start)
@export var fuel_per_tick: float = 0.0    # fuel consumed per tick during transit
@export var origin_position_au: Vector2 = Vector2.ZERO   # where ship departed from
@export var return_position_au: Vector2 = Vector2.ZERO    # where ship returns to
@export var transit_mode: TransitMode = TransitMode.BRACHISTOCHRONE
@export var return_to_station: bool = false       # If true, return to station colony instead of Earth
@export var destination_position_au: Vector2 = Vector2.ZERO  # For non-asteroid missions (repair, supply, patrol)
@export var station_job_duration: float = 0.0     # Duration for timed jobs (patrol, repair, etc.)
@export var destination_name: String = ""  # Fallback name when asteroid is null (e.g., return-only missions)
@export var origin_is_earth: bool = true   # True if ship departed from Earth (for live position tracking)
@export var origin_name: String = ""       # Human-readable departure location (e.g., "Earth", "Castalia", "Phobos Station")

# Deploy/collect mission support
@export var mining_units_to_deploy: Array[MiningUnit] = []
@export var workers_to_deploy: Array[Worker] = []
@export var deploy_duration: float = 3600.0  # 1 hour per unit being deployed

# Derelict rescue support (CREW_FERRY targeting a derelict fleet ship)
@export var is_derelict_rescue: bool = false
@export var rescue_crew: Array[Worker] = []
@export var supplies_to_transfer: Dictionary = {}

# Multi-leg journey: each entry is one intermediate stop; final leg uses transit_time
@export var outbound_legs: Array[WaypointLeg] = []
@export var outbound_waypoint_index: int = 0
@export var return_legs: Array[WaypointLeg] = []
@export var return_waypoint_index: int = 0

# Refueling status and duration
const REFUEL_DURATION: float = 5.0  # ticks spent refueling
var refueling_is_return: bool = false  # True when refueling during return trip

func get_current_phase_duration() -> float:
	match status:
		Status.TRANSIT_OUT:
			if outbound_waypoint_index < outbound_legs.size():
				return outbound_legs[outbound_waypoint_index].transit_time
			return transit_time
		Status.TRANSIT_BACK:
			if return_waypoint_index < return_legs.size():
				return return_legs[return_waypoint_index].transit_time
			return transit_time
		Status.MINING:
			return mining_duration
		Status.REPAIRING, Status.DELIVERING, Status.BOARDING, Status.PATROLLING:
			return station_job_duration
		Status.DEPLOYING:
			return deploy_duration
		Status.COLLECTING:
			return 1800.0  # 30 minutes to load ore
		_:
			return 0.0

func get_progress() -> float:
	var duration := get_current_phase_duration()
	if duration > 0:
		return elapsed_ticks / duration
	match status:
		Status.IDLE_AT_DESTINATION, Status.COMPLETED:
			return 1.0
		_:
			return 0.0

func _get_home_name() -> String:
	if return_to_station and ship and ship.station_colony:
		return ship.station_colony.colony_name
	return "Earth"

func has_slingshot_outbound() -> bool:
	return outbound_legs.any(func(l: WaypointLeg) -> bool: return l.planet_id >= 0)

func has_slingshot_return() -> bool:
	return return_legs.any(func(l: WaypointLeg) -> bool: return l.planet_id >= 0)

func get_status_text() -> String:
	var mode_suffix := " (Hohmann)" if transit_mode == TransitMode.HOHMANN else ""
	var slingshot_suffix := ""

	if status == Status.TRANSIT_OUT and has_slingshot_outbound():
		slingshot_suffix = " [Slingshot]"
	elif status == Status.TRANSIT_BACK and has_slingshot_return():
		slingshot_suffix = " [Slingshot]"

	var home := _get_home_name()
	var dest := asteroid.asteroid_name if asteroid else (destination_name if destination_name != "" else "deep space")

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
		Status.TRANSIT_OUT:
			var fuel_stop_suffix := ""
			var refuel_count := outbound_legs.filter(func(l: WaypointLeg) -> bool: return l.waypoint_type == WaypointLeg.WaypointType.REFUEL_STOP).size()
			if refuel_count > 0:
				fuel_stop_suffix = " [%d fuel stop%s]" % [refuel_count, "s" if refuel_count > 1 else ""]
			return "%s → %s (%s)%s%s%s" % [home, dest, home, mode_suffix, slingshot_suffix, fuel_stop_suffix]
		Status.MINING:
			return "Mining at %s (%s)" % [dest, home]
		Status.IDLE_AT_DESTINATION:
			return "Idle at %s (%s)" % [dest, home]
		Status.TRANSIT_BACK:
			var fuel_stop_suffix := ""
			var refuel_count := return_legs.filter(func(l: WaypointLeg) -> bool: return l.waypoint_type == WaypointLeg.WaypointType.REFUEL_STOP).size()
			if refuel_count > 0:
				fuel_stop_suffix = " [%d fuel stop%s]" % [refuel_count, "s" if refuel_count > 1 else ""]
			return "%s → %s%s%s%s" % [dest, home, mode_suffix, slingshot_suffix, fuel_stop_suffix]
		Status.COMPLETED:
			return "Mission complete"
		Status.REPAIRING:
			return "Repairing ship (%s)" % home
		Status.DELIVERING:
			return "Delivering supplies (%s)" % home
		Status.BOARDING:
			return "Transferring crew (%s)" % home
		Status.PATROLLING:
			return "Patrolling area (%s)" % home
		Status.DEPLOYING:
			return "Deploying units at %s (%s)" % [dest, home]
		Status.COLLECTING:
			return "Collecting ore at %s (%s)" % [dest, home]
	return "Unknown"

func _get_origin_pos_live() -> Vector2:
	if return_to_station and ship and ship.station_colony:
		return ship.station_colony.get_position_au()
	if origin_is_earth:
		return CelestialData.get_earth_position_au()
	return origin_position_au

func get_current_leg_start_pos() -> Vector2:
	match status:
		Status.TRANSIT_OUT:
			if outbound_waypoint_index == 0:
				return _get_origin_pos_live()
			elif outbound_waypoint_index <= outbound_legs.size():
				return outbound_legs[outbound_waypoint_index - 1].get_live_position()
			return _get_origin_pos_live()
		Status.TRANSIT_BACK:
			if return_waypoint_index == 0:
				return asteroid.get_position_au() if asteroid else destination_position_au
			elif return_waypoint_index <= return_legs.size():
				return return_legs[return_waypoint_index - 1].get_live_position()
			return asteroid.get_position_au() if asteroid else destination_position_au
		_:
			return _get_origin_pos_live()

func get_current_leg_end_pos() -> Vector2:
	match status:
		Status.TRANSIT_OUT:
			if outbound_waypoint_index < outbound_legs.size():
				return outbound_legs[outbound_waypoint_index].get_live_position()
			return asteroid.get_position_au() if asteroid else destination_position_au
		Status.TRANSIT_BACK:
			if return_waypoint_index < return_legs.size():
				return return_legs[return_waypoint_index].get_live_position()
			if return_to_station and ship and ship.station_colony:
				return ship.station_colony.get_position_au()
			elif not return_to_station:
				return CelestialData.get_earth_position_au()
			return return_position_au
		_:
			return origin_position_au
