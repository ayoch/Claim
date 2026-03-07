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
	SALVAGE,         # Board and strip a derelict ship
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
	SALVAGING,       # Actively stripping a wreck
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

# Salvage mission support
@export var salvage_target: SalvageTarget = null

# Derelict rescue support (CREW_FERRY targeting a derelict fleet ship)
@export var is_derelict_rescue: bool = false
@export var rescue_crew: Array[Worker] = []
@export var supplies_to_transfer: Dictionary = {}

# Multi-leg journey: each entry is one intermediate stop; final leg uses transit_time
@export var outbound_legs: Array[WaypointLeg] = []
@export var outbound_waypoint_index: int = 0
@export var return_legs: Array[WaypointLeg] = []
@export var return_waypoint_index: int = 0

# Partnership support
@export var is_partnership_shadow: bool = false  # True for follower missions
@export var partnership_leader_ship_name: String = ""  # Name of leader ship (for sync)
var partnership_leader_mission: Mission = null  # Runtime reference to leader's mission

# Trajectory visualization (cached curve, calculated once)
var outbound_trajectory_points: PackedVector2Array = []  # Curve from origin to destination
var return_trajectory_points: PackedVector2Array = []    # Curve from destination back
var trajectory_dirty: bool = true  # Recalculate on next access if true

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
		Status.SALVAGING:
			return SalvageTarget.SALVAGE_DURATION
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
			var refuel_count := 0
			for leg in outbound_legs:
				if leg.waypoint_type == WaypointLeg.WaypointType.REFUEL_STOP:
					refuel_count += 1
			if refuel_count > 0:
				fuel_stop_suffix = " [%d fuel stop%s]" % [refuel_count, "s" if refuel_count > 1 else ""]
			return "%s → %s (%s)%s%s%s" % [home, dest, home, mode_suffix, slingshot_suffix, fuel_stop_suffix]
		Status.MINING:
			return "Mining at %s (%s)" % [dest, home]
		Status.IDLE_AT_DESTINATION:
			return "Idle at %s (%s)" % [dest, home]
		Status.TRANSIT_BACK:
			var fuel_stop_suffix := ""
			var refuel_count := 0
			for leg in return_legs:
				if leg.waypoint_type == WaypointLeg.WaypointType.REFUEL_STOP:
					refuel_count += 1
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
		Status.SALVAGING:
			return "Salvaging %s (%s)" % [destination_name, home]
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
				# Prefer static predicted position if set, else use dynamic asteroid position
				return destination_position_au if destination_position_au != Vector2.ZERO else (asteroid.get_position_au() if asteroid else Vector2.ZERO)
			elif return_waypoint_index <= return_legs.size():
				return return_legs[return_waypoint_index - 1].get_live_position()
			return destination_position_au if destination_position_au != Vector2.ZERO else (asteroid.get_position_au() if asteroid else Vector2.ZERO)
		_:
			return _get_origin_pos_live()

func get_current_leg_end_pos() -> Vector2:
	match status:
		Status.TRANSIT_OUT:
			if outbound_waypoint_index < outbound_legs.size():
				return outbound_legs[outbound_waypoint_index].get_live_position()
			# Prefer static predicted position if set, else use dynamic asteroid position
			return destination_position_au if destination_position_au != Vector2.ZERO else (asteroid.get_position_au() if asteroid else Vector2.ZERO)
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

## Calculate trajectory visualization curves (called once per mission)
func calculate_trajectory_curves(num_samples: int = 40) -> void:
	if not ship:
		return

	# Outbound trajectory
	outbound_trajectory_points.clear()
	var start_pos := origin_position_au
	var end_pos := destination_position_au

	if start_pos == Vector2.ZERO or end_pos == Vector2.ZERO:
		trajectory_dirty = false
		return

	var total_distance := start_pos.distance_to(end_pos)
	if total_distance < 0.001:
		trajectory_dirty = false
		return

	# Multi-leg journey (slingshots, fuel stops)
	if outbound_legs.size() > 0:
		var current_start: Vector2 = start_pos
		var thrust: float = ship.get_effective_thrust()

		# Draw each leg
		for leg in outbound_legs:
			var leg_end: Vector2 = leg.get_live_position()
			var leg_distance: float = current_start.distance_to(leg_end)

			if leg_distance < 0.001:
				current_start = leg_end
				continue

			# Each leg is a Brachistochrone segment (even with Hohmann, individual legs are thrusted)
			var leg_direction: Vector2 = (leg_end - current_start).normalized()
			var leg_time: float = leg.transit_time
			var samples_per_leg: int = max(10, num_samples / (outbound_legs.size() + 1))

			for i in range(samples_per_leg + 1):
				var t: float = (float(i) / samples_per_leg) * leg_time
				var distance_traveled: float = Brachistochrone.distance_at_time(t, thrust, leg_time, leg_distance)
				var pos: Vector2 = current_start + leg_direction * distance_traveled
				outbound_trajectory_points.append(pos)

			current_start = leg_end

		# Final leg from last waypoint to destination
		var final_distance: float = current_start.distance_to(end_pos)
		if final_distance >= 0.001:
			var final_direction: Vector2 = (end_pos - current_start).normalized()
			for i in range(num_samples + 1):
				var t: float = (float(i) / num_samples) * transit_time
				var distance_traveled: float = Brachistochrone.distance_at_time(t, thrust, transit_time, final_distance)
				var pos: Vector2 = current_start + final_direction * distance_traveled
				outbound_trajectory_points.append(pos)
	elif transit_mode == TransitMode.HOHMANN:
		# Hohmann transfer: elliptical arc
		_calculate_hohmann_arc(start_pos, end_pos, num_samples, outbound_trajectory_points)
	else:
		# Brachistochrone: straight line with velocity variation
		var direction: Vector2 = (end_pos - start_pos).normalized()
		var thrust: float = ship.get_effective_thrust()

		for i in range(num_samples + 1):
			var t: float = (float(i) / num_samples) * transit_time
			var distance_traveled: float = Brachistochrone.distance_at_time(t, thrust, transit_time, total_distance)
			var pos: Vector2 = start_pos + direction * distance_traveled
			outbound_trajectory_points.append(pos)

	# Return trajectory (if not staying at destination)
	return_trajectory_points.clear()
	if return_position_au != Vector2.ZERO and destination_position_au != Vector2.ZERO:
		var return_start := destination_position_au
		var return_end := return_position_au
		var return_distance := return_start.distance_to(return_end)

		if return_distance >= 0.001:
			# Multi-leg return (fuel stops)
			if return_legs.size() > 0:
				var current_start: Vector2 = return_start
				var thrust: float = ship.get_effective_thrust()

				# Draw each return leg
				for leg in return_legs:
					var leg_end: Vector2 = leg.get_live_position()
					var leg_distance: float = current_start.distance_to(leg_end)

					if leg_distance < 0.001:
						current_start = leg_end
						continue

					var leg_direction: Vector2 = (leg_end - current_start).normalized()
					var leg_time: float = leg.transit_time
					var samples_per_leg: int = max(10, num_samples / (return_legs.size() + 1))

					for i in range(samples_per_leg + 1):
						var t: float = (float(i) / samples_per_leg) * leg_time
						var distance_traveled: float = Brachistochrone.distance_at_time(t, thrust, leg_time, leg_distance)
						var pos: Vector2 = current_start + leg_direction * distance_traveled
						return_trajectory_points.append(pos)

					current_start = leg_end

				# Final return leg from last waypoint to destination
				var final_distance: float = current_start.distance_to(return_end)
				if final_distance >= 0.001:
					var final_direction: Vector2 = (return_end - current_start).normalized()
					for i in range(num_samples + 1):
						var t: float = (float(i) / num_samples) * transit_time
						var distance_traveled: float = Brachistochrone.distance_at_time(t, thrust, transit_time, final_distance)
						var pos: Vector2 = current_start + final_direction * distance_traveled
						return_trajectory_points.append(pos)
			elif transit_mode == TransitMode.HOHMANN:
				# Hohmann return arc
				_calculate_hohmann_arc(return_start, return_end, num_samples, return_trajectory_points)
			else:
				# Brachistochrone return
				var return_direction: Vector2 = (return_end - return_start).normalized()
				var thrust: float = ship.get_effective_thrust()
				for i in range(num_samples + 1):
					var t: float = (float(i) / num_samples) * transit_time
					var distance_traveled: float = Brachistochrone.distance_at_time(t, thrust, transit_time, return_distance)
					var pos: Vector2 = return_start + return_direction * distance_traveled
					return_trajectory_points.append(pos)

	trajectory_dirty = false

## Calculate a Hohmann transfer elliptical arc
func _calculate_hohmann_arc(start_pos: Vector2, end_pos: Vector2, num_samples: int, output: PackedVector2Array) -> void:
	# Sun at origin (0, 0)
	var r1: float = start_pos.length()  # Inner orbit radius
	var r2: float = end_pos.length()    # Outer orbit radius

	# Special case: if radii are nearly equal, use straight line
	if abs(r2 - r1) < 0.01:
		var direction: Vector2 = (end_pos - start_pos).normalized()
		var distance: float = start_pos.distance_to(end_pos)
		for i in range(num_samples + 1):
			var progress: float = float(i) / num_samples
			var pos: Vector2 = start_pos + direction * (distance * progress)
			output.append(pos)
		return

	# Elliptical transfer orbit parameters
	var a: float = (r1 + r2) / 2.0  # Semi-major axis
	var c: float = (r2 - r1) / 2.0  # Distance from center to focus
	var b: float = sqrt(a * a - c * c)  # Semi-minor axis

	# Ellipse center (offset from sun toward outer orbit)
	var transfer_direction: Vector2 = (end_pos - start_pos).normalized()
	var center_offset: Vector2 = c * transfer_direction

	# Start angle and end angle on the ellipse
	var angle_start: float = start_pos.angle()
	var angle_end: float = end_pos.angle()

	# Ensure we go the "short way" around (less than 180 degrees)
	var angle_diff: float = angle_end - angle_start
	if angle_diff > PI:
		angle_diff -= TAU
	elif angle_diff < -PI:
		angle_diff += TAU

	# Sample points along the elliptical arc
	for i in range(num_samples + 1):
		var progress: float = float(i) / num_samples
		var angle: float = angle_start + angle_diff * progress

		# Parametric ellipse equation (rotated to match transfer direction)
		var ellipse_angle: float = progress * PI  # We traverse half the ellipse (0 to π)
		var x: float = a * cos(ellipse_angle)
		var y: float = b * sin(ellipse_angle)

		# Rotate to match actual transfer direction
		var rotation: float = transfer_direction.angle()
		var rotated_x: float = x * cos(rotation) - y * sin(rotation)
		var rotated_y: float = x * sin(rotation) + y * cos(rotation)

		# Offset from center (which is offset from sun)
		var pos: Vector2 = center_offset + Vector2(rotated_x, rotated_y)

		output.append(pos)


## Cleanup method to break circular references
## Call this when removing a mission to prevent memory leaks
func cleanup() -> void:
	# Break ship reference (ship also references this mission)
	ship = null

	# Break partnership leader reference
	partnership_leader_mission = null

	# Clear worker arrays (workers reference missions)
	rescue_crew.clear()
	workers_to_deploy.clear()

	# Clear mining units array (units may reference workers)
	mining_units_to_deploy.clear()

	# Clear waypoint legs (contain WaypointLeg resources)
	outbound_legs.clear()
	return_legs.clear()

	# Clear trajectory cache
	outbound_trajectory_points.clear()
	return_trajectory_points.clear()
