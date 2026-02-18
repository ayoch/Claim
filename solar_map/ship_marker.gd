extends Node2D

const AU_PIXELS: float = 200.0
const MOVE_SMOOTHING: float = 12.0  # base lerp speed for smooth movement

var mission: Mission = null
var trade_mission: TradeMission = null
var ship: Ship = null  # for idle/derelict ships without active missions
var rescue_target_ship: Ship = null  # for rescue/refuel vessel markers
var rescue_data: Dictionary = {}  # { source_pos, transit_time, elapsed_ticks, ... }
var is_refuel_vessel: bool = false  # true = refuel, false = rescue

# Cache positions for smooth motion
var _target_pos: Vector2 = Vector2.ZERO
var _smooth_progress: float = 0.0  # Frame-smoothed progress
var _velocity: Vector2 = Vector2.ZERO
var _rotation_angle: float = 0.0
var _anim_time: float = 0.0  # For visual animations (pulsing, etc.)

# Cached trajectory to avoid recalculating every frame
var _cached_trajectory_points: PackedVector2Array = PackedVector2Array()
var _trajectory_update_timer: float = 0.0
const TRAJECTORY_UPDATE_INTERVAL: float = 0.033  # Update trajectory every frame (~30fps)

func _ready() -> void:
	if mission:
		$Label.text = mission.ship.ship_name
		_smooth_progress = mission.get_progress()
		_update_target()
		position = _target_pos  # snap to start
		_update_trajectory_cache()  # Initialize trajectory
		_initialize_rotation()  # Set initial rotation angle
		visible = true
	elif trade_mission:
		$Label.text = trade_mission.ship.ship_name
		_smooth_progress = trade_mission.get_progress()
		_update_target()
		position = _target_pos
		_update_trajectory_cache()  # Initialize trajectory
		_initialize_rotation()  # Set initial rotation angle
		visible = true
	elif rescue_target_ship:
		var prefix := "Refuel" if is_refuel_vessel else "Rescue"
		$Label.text = "%s → %s" % [prefix, rescue_target_ship.ship_name]
		$Label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
		_update_rescue_target()
		position = _target_pos
		visible = true
	elif ship:
		$Label.text = ship.ship_name
		_target_pos = ship.position_au * AU_PIXELS
		position = _target_pos
		visible = true
	else:
		visible = false

func _initialize_rotation() -> void:
	# Set initial rotation from ship's actual velocity, or fallback to direction
	var init_ship: Ship = null
	if mission and (mission.status == Mission.Status.TRANSIT_OUT or mission.status == Mission.Status.TRANSIT_BACK):
		init_ship = mission.ship
	elif trade_mission and (trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY or trade_mission.status == TradeMission.Status.TRANSIT_BACK):
		init_ship = trade_mission.ship

	if init_ship and init_ship.velocity_au_per_tick.length_squared() > 0.0:
		_rotation_angle = init_ship.velocity_au_per_tick.angle()
	elif init_ship:
		# Velocity not set yet — use current leg direction
		var start_pos := Vector2.ZERO
		var end_pos := Vector2.ZERO
		if mission:
			start_pos = mission.get_current_leg_start_pos()
			end_pos = mission.get_current_leg_end_pos()
		elif trade_mission:
			start_pos = trade_mission.get_current_leg_start_pos()
			end_pos = trade_mission.get_current_leg_end_pos()
		var direction := (end_pos - start_pos).normalized()
		_rotation_angle = direction.angle()

	if _smooth_progress > 0.5:
		_rotation_angle += PI

func _process(delta: float) -> void:
	_anim_time += delta
	if not mission and not trade_mission and not ship and not rescue_target_ship:
		visible = false
		return
	# Hide completed missions (marker will be freed on next refresh)
	if mission and mission.status == Mission.Status.COMPLETED:
		visible = false
		return
	if trade_mission and trade_mission.status == TradeMission.Status.COMPLETED:
		visible = false
		return
	visible = true

	# Smooth progress toward actual tick-based progress
	var actual_progress := 0.0
	if mission:
		actual_progress = mission.get_progress()
	elif trade_mission:
		actual_progress = trade_mission.get_progress()

	# Smooth progress to avoid jitter while preserving acceleration
	# Much higher minimum at low speeds to smooth infrequent tick updates
	var progress_lerp_speed := maxf(50.0, 12.0 * TimeScale.speed_multiplier)
	_smooth_progress = lerp(_smooth_progress, actual_progress, minf(progress_lerp_speed * delta, 1.0))

	# Update target position — use ship.position_au directly for transit
	# (simulation already updates this each tick via _update_ship_transit_physics)
	if mission:
		var s: Ship = mission.ship
		if s and (mission.status == Mission.Status.TRANSIT_OUT or mission.status == Mission.Status.TRANSIT_BACK):
			_target_pos = s.position_au * AU_PIXELS
		else:
			_update_mining_target_with_progress(_smooth_progress)
	elif trade_mission:
		var s: Ship = trade_mission.ship
		if s and (trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY or trade_mission.status == TradeMission.Status.TRANSIT_BACK):
			_target_pos = s.position_au * AU_PIXELS
		else:
			_update_trade_target_with_progress(_smooth_progress)
	elif rescue_target_ship:
		_update_rescue_target()
	else:
		_update_target()

	# Calculate rotation from ship's actual velocity vector
	var transit_ship: Ship = null
	if mission and (mission.status == Mission.Status.TRANSIT_OUT or mission.status == Mission.Status.TRANSIT_BACK):
		transit_ship = mission.ship
	elif trade_mission and (trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY or trade_mission.status == TradeMission.Status.TRANSIT_BACK):
		transit_ship = trade_mission.ship

	if transit_ship:
		_velocity = transit_ship.velocity_au_per_tick
		var target_angle: float
		if _velocity.length_squared() > 0.0:
			target_angle = _velocity.angle()
		else:
			# Fallback: point toward current leg end when velocity not yet set
			var end_pos := Vector2.ZERO
			if mission:
				end_pos = mission.get_current_leg_end_pos() * AU_PIXELS
			elif trade_mission:
				end_pos = trade_mission.get_current_leg_end_pos() * AU_PIXELS
			var dir := (end_pos - position).normalized()
			target_angle = dir.angle() if dir.length_squared() > 0.0 else _rotation_angle
		# Flip for deceleration burn (ship flies backward in second half)
		if _smooth_progress > 0.5:
			target_angle += PI
		# Smooth rotation
		var rotation_lerp_speed := maxf(40.0, 15.0 * TimeScale.speed_multiplier)
		var angle_diff := fmod(target_angle - _rotation_angle + PI, TAU) - PI
		_rotation_angle += angle_diff * minf(rotation_lerp_speed * delta, 1.0)

	# Smooth position lerp to avoid jitter
	# Very aggressive at low speeds to smooth between infrequent tick updates
	var position_lerp_speed := maxf(50.0, 12.0 * TimeScale.speed_multiplier)
	position = position.lerp(_target_pos, minf(position_lerp_speed * delta, 1.0))

	# Update trajectory cache periodically
	_trajectory_update_timer += delta
	if _trajectory_update_timer >= TRAJECTORY_UPDATE_INTERVAL:
		_trajectory_update_timer = 0.0
		_update_trajectory_cache()

	queue_redraw()

func _update_rescue_target() -> void:
	if not rescue_target_ship:
		return
	# Refresh data from GameState
	var data_dict: Dictionary
	if is_refuel_vessel:
		if rescue_target_ship not in GameState.refuel_missions:
			visible = false
			return
		data_dict = GameState.refuel_missions[rescue_target_ship]
	else:
		if rescue_target_ship not in GameState.rescue_missions:
			visible = false
			return
		data_dict = GameState.rescue_missions[rescue_target_ship]

	var source_pos: Vector2 = data_dict.get("source_pos", CelestialData.get_earth_position_au())
	var elapsed: float = data_dict["elapsed_ticks"]
	var total: float = data_dict["transit_time"]
	var progress := clampf(elapsed / total, 0.0, 1.0) if total > 0 else 0.0

	var source_px := source_pos * AU_PIXELS
	var target_px := rescue_target_ship.position_au * AU_PIXELS
	_target_pos = source_px.lerp(target_px, progress)

func _update_target() -> void:
	if mission:
		_update_mining_target()
	elif trade_mission:
		_update_trade_target()
	elif ship:
		_target_pos = ship.position_au * AU_PIXELS

func _update_mining_target() -> void:
	var progress := mission.get_progress()
	_update_mining_target_with_progress(progress)

func _update_mining_target_with_progress(progress: float) -> void:
	var origin_pos := mission.origin_position_au * AU_PIXELS
	var asteroid_pos := mission.asteroid.get_position_au() * AU_PIXELS if mission.asteroid else origin_pos

	match mission.status:
		Mission.Status.TRANSIT_OUT:
			_target_pos = _calculate_trajectory_position(origin_pos, asteroid_pos, progress, mission.transit_mode)
		Mission.Status.MINING, Mission.Status.IDLE_AT_DESTINATION:
			_target_pos = asteroid_pos
		Mission.Status.TRANSIT_BACK:
			var return_pos := mission.return_position_au * AU_PIXELS
			_target_pos = _calculate_trajectory_position(asteroid_pos, return_pos, progress, mission.transit_mode)

func _update_trade_target() -> void:
	var progress := trade_mission.get_progress()
	_update_trade_target_with_progress(progress)

func _update_trade_target_with_progress(progress: float) -> void:
	var origin_pos := trade_mission.origin_position_au * AU_PIXELS
	var colony_pos := trade_mission.colony.get_position_au() * AU_PIXELS

	match trade_mission.status:
		TradeMission.Status.TRANSIT_TO_COLONY:
			_target_pos = _calculate_trajectory_position(origin_pos, colony_pos, progress, trade_mission.transit_mode)
		TradeMission.Status.SELLING, TradeMission.Status.IDLE_AT_COLONY:
			_target_pos = colony_pos
		TradeMission.Status.TRANSIT_BACK:
			var return_pos := trade_mission.return_position_au * AU_PIXELS
			_target_pos = _calculate_trajectory_position(colony_pos, return_pos, progress, trade_mission.transit_mode)

func update_position() -> void:
	_update_target()

func _update_trajectory_cache() -> void:
	# Update cached trajectory points for drawing
	_cached_trajectory_points.clear()

	var is_active := false
	var transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE

	# Build list of legs: each leg is [start_au, end_au]
	var legs: Array = []  # Array of [Vector2, Vector2]

	if mission:
		transit_mode = mission.transit_mode
		if mission.status == Mission.Status.TRANSIT_OUT:
			is_active = true
			# Current leg
			var leg_start := mission.get_current_leg_start_pos()
			var leg_end := mission.get_current_leg_end_pos()
			legs.append([leg_start, leg_end])
			# Remaining legs after current waypoint
			var wi := mission.outbound_waypoint_index
			while wi < mission.outbound_waypoints.size():
				var next_start := mission.outbound_waypoints[wi]
				var next_end: Vector2
				if wi + 1 < mission.outbound_waypoints.size():
					next_end = mission.outbound_waypoints[wi + 1]
				else:
					next_end = mission.asteroid.get_position_au() if mission.asteroid else mission.origin_position_au
				legs.append([next_start, next_end])
				wi += 1
		elif mission.status == Mission.Status.TRANSIT_BACK:
			is_active = true
			var leg_start := mission.get_current_leg_start_pos()
			var leg_end := mission.get_current_leg_end_pos()
			legs.append([leg_start, leg_end])
			var wi := mission.return_waypoint_index
			while wi < mission.return_waypoints.size():
				var next_start := mission.return_waypoints[wi]
				var next_end: Vector2
				if wi + 1 < mission.return_waypoints.size():
					next_end = mission.return_waypoints[wi + 1]
				else:
					next_end = mission.return_position_au
				legs.append([next_start, next_end])
				wi += 1
	elif trade_mission:
		transit_mode = trade_mission.transit_mode
		if trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY:
			is_active = true
			var leg_start := trade_mission.get_current_leg_start_pos()
			var leg_end := trade_mission.get_current_leg_end_pos()
			legs.append([leg_start, leg_end])
		elif trade_mission.status == TradeMission.Status.TRANSIT_BACK:
			is_active = true
			var leg_start := trade_mission.get_current_leg_start_pos()
			var leg_end := trade_mission.get_current_leg_end_pos()
			legs.append([leg_start, leg_end])

	if not is_active or legs.is_empty():
		return

	# Generate trajectory points for each leg
	var num_points_per_leg := 30
	for leg in legs:
		var start_px: Vector2 = leg[0] * AU_PIXELS
		var end_px: Vector2 = leg[1] * AU_PIXELS
		for i in range(num_points_per_leg + 1):
			var t := float(i) / float(num_points_per_leg)
			var world_point := _calculate_trajectory_position(start_px, end_px, t, transit_mode)
			_cached_trajectory_points.append(world_point)

func _calculate_trajectory_position(start: Vector2, end: Vector2, progress: float, transit_mode: int) -> Vector2:
	# Calculate ship position along trajectory based on transit mode
	# Returns position in absolute world coordinates
	var direction := (end - start).normalized()
	var distance := start.distance_to(end)

	if transit_mode == Mission.TransitMode.HOHMANN:
		# Hohmann: linear interpolation (matches simulation physics)
		return start.lerp(end, progress)
	else:
		# Brachistochrone: S-curve position (matches simulation physics)
		var distance_fraction := _brachistochrone_distance_fraction(progress)
		return start.lerp(end, distance_fraction)

func _brachistochrone_distance_fraction(time_fraction: float) -> float:
	# Convert time progress to distance progress for constant-acceleration trajectory
	# Physics: x(t) = (1/2)*a*t² during acceleration, symmetric during deceleration
	# Results in S-curve: slow start, fast middle, slow end
	if time_fraction <= 0.5:
		# Acceleration phase: quadratic growth
		# At t=0.25: distance = 2*(0.25)² = 0.125 (12.5%)
		return 2.0 * time_fraction * time_fraction
	else:
		# Deceleration phase: mirror of acceleration
		# At t=0.75: distance = 1 - 2*(0.25)² = 0.875 (87.5%)
		var t_from_end := 1.0 - time_fraction
		return 1.0 - 2.0 * t_from_end * t_from_end

func _get_velocity_multiplier(time_fraction: float) -> float:
	# Derivative of brachistochrone distance fraction = velocity profile
	# Shows acceleration in first half, deceleration in second half
	if time_fraction <= 0.5:
		# Acceleration phase: derivative of 2*t² = 4*t
		# Velocity increases linearly from 0 to max at t=0.5
		return 4.0 * time_fraction
	else:
		# Deceleration phase: derivative of 1 - 2*(1-t)² = 4*(1-t)
		# Velocity decreases linearly from max to 0
		return 4.0 * (1.0 - time_fraction)

func _calculate_trajectory_tangent(start: Vector2, end: Vector2, progress: float, transit_mode: int, transit_time: float) -> Vector2:
	# Calculate the tangent (velocity vector) to the trajectory curve at the given progress
	# Returns a vector pointing in the direction of travel with magnitude = speed

	var direction := (end - start).normalized()
	var distance := start.distance_to(end)

	if transit_mode == Mission.TransitMode.HOHMANN:
		# Hohmann has curved path - calculate tangent to the elliptical arc
		var perpendicular := Vector2(-direction.y, direction.x)
		# Arc derivative: height varies as cos(progress * PI) * PI
		var arc_derivative := distance * 0.15 * cos(progress * PI) * PI

		# Linear component (constant velocity along straight path)
		var linear_component := direction
		# Arc component (perpendicular, varies with progress)
		var arc_component := perpendicular * arc_derivative

		# Total tangent = linear + arc components
		var tangent := linear_component + arc_component
		return tangent.normalized() * (distance / transit_time)
	else:
		# Brachistochrone: tangent includes both linear motion and arc curvature
		var perpendicular := Vector2(-direction.y, direction.x)

		# Distance fraction derivative (velocity profile from S-curve)
		var velocity_scale := _get_velocity_multiplier(progress)

		# Arc derivative: small arc with cos variation
		var arc_derivative := distance * 0.05 * cos(progress * PI) * PI

		# Linear component scaled by velocity profile
		var linear_component := direction * velocity_scale
		# Arc component (perpendicular)
		var arc_component := perpendicular * arc_derivative

		# Total tangent
		var tangent := linear_component + arc_component
		# Scale to actual velocity magnitude
		return tangent.normalized() * velocity_scale * (distance / transit_time)

func _draw_trajectory() -> void:
	# Draw cached trajectory path
	if _cached_trajectory_points.size() < 2:
		return

	# Determine color based on mission type
	var color := Color(0.3, 0.9, 0.5, 0.4)  # Green for mining
	if trade_mission:
		color = Color(0.3, 0.9, 0.9, 0.4)  # Cyan for trade

	# Draw trajectory in world space, converted to local coordinates
	# Using cached points so it doesn't jitter
	for i in range(_cached_trajectory_points.size() - 1):
		var local_start := _cached_trajectory_points[i] - position
		var local_end := _cached_trajectory_points[i + 1] - position
		draw_line(local_start, local_end, color, 2.0)

func _draw() -> void:
	# Draw trajectory first (behind ship)
	_draw_trajectory()

	# Rescue/refuel vessel: amber triangle + trajectory line
	if rescue_target_ship:
		var color := Color(0.9, 0.6, 0.2)
		# Draw trajectory line from source to target
		var data_dict: Dictionary
		if is_refuel_vessel:
			data_dict = GameState.refuel_missions.get(rescue_target_ship, {})
		else:
			data_dict = GameState.rescue_missions.get(rescue_target_ship, {})
		if not data_dict.is_empty():
			var source_pos: Vector2 = data_dict.get("source_pos", CelestialData.get_earth_position_au())
			var source_px := source_pos * AU_PIXELS - position
			var target_px := rescue_target_ship.position_au * AU_PIXELS - position
			draw_line(source_px, target_px, Color(color.r, color.g, color.b, 0.3), 1.5)

		# Draw amber triangle
		var s := 8.0
		var pts := PackedVector2Array([
			Vector2(0, -s), Vector2(s, s * 0.6), Vector2(-s, s * 0.6)
		])
		draw_colored_polygon(pts, color)
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(1.0, 0.8, 0.4), 1.5)
		return

	# Derelict ships: red with X marker and pulsing glow
	if ship and ship.is_derelict:
		# Pulsing outer glow for visibility
		var pulse := 0.4 + 0.3 * sin(_anim_time * 4.0)
		draw_circle(Vector2.ZERO, 14, Color(0.9, 0.1, 0.1, pulse * 0.4))
		draw_circle(Vector2.ZERO, 8, Color(0.9, 0.2, 0.2))
		# Draw X
		var s := 5.0
		draw_line(Vector2(-s, -s), Vector2(s, s), Color(1.0, 0.4, 0.4), 2.5)
		draw_line(Vector2(s, -s), Vector2(-s, s), Color(1.0, 0.4, 0.4), 2.5)
		# Draw "SOS" label
		$Label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))
		return

	# Idle remote ships: amber circle (no rotation)
	if ship and ship.is_idle_remote:
		draw_circle(Vector2.ZERO, 6, Color(0.9, 0.7, 0.2))
		return

	var color := Color(0.3, 0.9, 0.5)
	if trade_mission:
		color = Color(0.3, 0.9, 0.9)  # Cyan for trade ships

	# Determine if ship is in transit
	var is_transit := false
	if mission and mission.status != Mission.Status.MINING and mission.status != Mission.Status.IDLE_AT_DESTINATION:
		is_transit = true
	elif trade_mission and trade_mission.status != TradeMission.Status.SELLING and trade_mission.status != TradeMission.Status.IDLE_AT_COLONY:
		is_transit = true

	# Draw ship as a triangle pointing in direction of travel when in transit
	if is_transit:
		# Triangle pointing in direction of rotation
		var forward := Vector2(cos(_rotation_angle), sin(_rotation_angle))
		var right := Vector2(-forward.y, forward.x)

		var tip := forward * 10.0
		var back_left := -forward * 6.0 + right * 5.0
		var back_right := -forward * 6.0 - right * 5.0

		draw_colored_polygon(PackedVector2Array([tip, back_left, back_right]), color)
		# Outline for visibility
		draw_polyline(PackedVector2Array([tip, back_left, back_right, tip]), Color(color.r * 0.7, color.g * 0.7, color.b * 0.7), 1.5)
	else:
		# Stationary or mining: draw as circle
		draw_circle(Vector2.ZERO, 6, color)
