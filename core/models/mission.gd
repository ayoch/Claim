class_name Mission
extends Resource

enum Status {
	TRANSIT_OUT,
	MINING,
	IDLE_AT_DESTINATION,
	TRANSIT_BACK,
	COMPLETED,
}

enum TransitMode {
	BRACHISTOCHRONE,  # Fast, expensive fuel (continuous thrust)
	HOHMANN,          # Slow, economical fuel (minimal delta-v)
}

@export var status: Status = Status.TRANSIT_OUT
@export var ship: Ship = null
@export var workers: Array[Worker] = []
@export var asteroid: AsteroidData = null
@export var transit_time: float = 0.0     # ticks for one-way transit
@export var elapsed_ticks: float = 0.0    # ticks elapsed in current phase
@export var mining_duration: float = 30.0 # ticks to mine before returning
@export var fuel_per_tick: float = 0.0    # fuel consumed per tick during transit
@export var origin_position_au: Vector2 = Vector2.ZERO   # where ship departed from
@export var return_position_au: Vector2 = Vector2.ZERO    # where ship returns to
@export var transit_mode: TransitMode = TransitMode.BRACHISTOCHRONE  # orbit type

# Gravity assist / multi-leg journey support
@export var outbound_waypoints: Array[Vector2] = []      # intermediate positions (e.g., planet flyby)
@export var outbound_waypoint_planet_ids: Array[int] = []  # which planets for gravity assists
@export var outbound_leg_times: Array[float] = []         # transit time for each leg
@export var outbound_waypoint_index: int = 0              # current leg (0 = first leg)
@export var return_waypoints: Array[Vector2] = []
@export var return_waypoint_planet_ids: Array[int] = []
@export var return_leg_times: Array[float] = []
@export var return_waypoint_index: int = 0

func get_progress() -> float:
	match status:
		Status.TRANSIT_OUT:
			# For multi-leg journeys, use current leg's time
			if outbound_leg_times.size() > outbound_waypoint_index:
				var leg_time: float = outbound_leg_times[outbound_waypoint_index]
				return elapsed_ticks / leg_time if leg_time > 0 else 1.0
			else:
				return elapsed_ticks / transit_time if transit_time > 0 else 1.0
		Status.TRANSIT_BACK:
			# For multi-leg journeys, use current leg's time
			if return_leg_times.size() > return_waypoint_index:
				var leg_time: float = return_leg_times[return_waypoint_index]
				return elapsed_ticks / leg_time if leg_time > 0 else 1.0
			else:
				return elapsed_ticks / transit_time if transit_time > 0 else 1.0
		Status.MINING:
			return elapsed_ticks / mining_duration if mining_duration > 0 else 1.0
		Status.IDLE_AT_DESTINATION:
			return 1.0
		Status.COMPLETED:
			return 1.0
	return 0.0

func get_status_text() -> String:
	var mode_suffix := " (Hohmann)" if transit_mode == TransitMode.HOHMANN else ""
	var slingshot_suffix := ""

	# Add slingshot indicator if using waypoints
	if status == Status.TRANSIT_OUT and outbound_waypoint_planet_ids.size() > 0:
		slingshot_suffix = " [Slingshot]"
	elif status == Status.TRANSIT_BACK and return_waypoint_planet_ids.size() > 0:
		slingshot_suffix = " [Slingshot]"

	match status:
		Status.TRANSIT_OUT:
			if asteroid:
				return "In transit to " + asteroid.asteroid_name + mode_suffix + slingshot_suffix
			return "In transit" + mode_suffix + slingshot_suffix
		Status.MINING:
			if asteroid:
				return "Mining at " + asteroid.asteroid_name
			return "Mining"
		Status.IDLE_AT_DESTINATION:
			if asteroid:
				return "Idle at " + asteroid.asteroid_name
			return "Idle"
		Status.TRANSIT_BACK:
			if asteroid:
				return "Returning from " + asteroid.asteroid_name + mode_suffix + slingshot_suffix
			return "Returning to Earth" + mode_suffix + slingshot_suffix
		Status.COMPLETED:
			return "Mission complete"
	return "Unknown"

func get_current_leg_start_pos() -> Vector2:
	# Get the starting position for the current transit leg
	match status:
		Status.TRANSIT_OUT:
			if outbound_waypoint_index == 0:
				return origin_position_au
			elif outbound_waypoint_index > 0 and outbound_waypoint_index <= outbound_waypoints.size():
				return outbound_waypoints[outbound_waypoint_index - 1]
			return origin_position_au
		Status.TRANSIT_BACK:
			if return_waypoint_index == 0:
				return asteroid.get_position_au() if asteroid else origin_position_au
			elif return_waypoint_index > 0 and return_waypoint_index <= return_waypoints.size():
				return return_waypoints[return_waypoint_index - 1]
			return asteroid.get_position_au() if asteroid else origin_position_au
		_:
			return origin_position_au

func get_current_leg_end_pos() -> Vector2:
	# Get the ending position for the current transit leg
	match status:
		Status.TRANSIT_OUT:
			if outbound_waypoint_index < outbound_waypoints.size():
				return outbound_waypoints[outbound_waypoint_index]
			else:
				return asteroid.get_position_au() if asteroid else origin_position_au
		Status.TRANSIT_BACK:
			if return_waypoint_index < return_waypoints.size():
				return return_waypoints[return_waypoint_index]
			else:
				return return_position_au
		_:
			return origin_position_au
