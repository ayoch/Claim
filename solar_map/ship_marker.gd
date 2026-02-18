extends Node2D

const AU_PIXELS: float = 200.0
const MOVE_SMOOTHING: float = 12.0  # base lerp speed for smooth movement

var mission: Mission = null
var trade_mission: TradeMission = null
var ship: Ship = null  # for idle/derelict ships without active missions

# Cache positions for smooth motion
var _target_pos: Vector2 = Vector2.ZERO
var _smooth_progress: float = 0.0  # Frame-smoothed progress
var _velocity: Vector2 = Vector2.ZERO
var _rotation_angle: float = 0.0

# Cached trajectory to avoid recalculating every frame
var _cached_trajectory_points: PackedVector2Array = PackedVector2Array()
var _trajectory_update_timer: float = 0.0
const TRAJECTORY_UPDATE_INTERVAL: float = 0.1  # Update trajectory every 0.1 seconds

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
	elif ship:
		$Label.text = ship.ship_name
		_target_pos = ship.position_au * AU_PIXELS
		position = _target_pos
		visible = true
	else:
		visible = false

func _initialize_rotation() -> void:
	# Set initial rotation based on trajectory direction
	if mission and (mission.status == Mission.Status.TRANSIT_OUT or mission.status == Mission.Status.TRANSIT_BACK):
		var start_pos := Vector2.ZERO
		var end_pos := Vector2.ZERO
		if mission.status == Mission.Status.TRANSIT_OUT:
			start_pos = mission.origin_position_au * AU_PIXELS
			end_pos = (mission.asteroid.get_position_au() if mission.asteroid else mission.origin_position_au) * AU_PIXELS
		else:
			start_pos = (mission.asteroid.get_position_au() if mission.asteroid else mission.origin_position_au) * AU_PIXELS
			end_pos = mission.return_position_au * AU_PIXELS
		var direction := (end_pos - start_pos).normalized()
		_rotation_angle = direction.angle()
		if _smooth_progress > 0.5:
			_rotation_angle += PI  # Start with retrograde orientation if past midpoint
	elif trade_mission and (trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY or trade_mission.status == TradeMission.Status.TRANSIT_BACK):
		var start_pos := Vector2.ZERO
		var end_pos := Vector2.ZERO
		if trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY:
			start_pos = trade_mission.origin_position_au * AU_PIXELS
			end_pos = trade_mission.colony.get_position_au() * AU_PIXELS
		else:
			start_pos = trade_mission.colony.get_position_au() * AU_PIXELS
			end_pos = trade_mission.return_position_au * AU_PIXELS
		var direction := (end_pos - start_pos).normalized()
		_rotation_angle = direction.angle()
		if _smooth_progress > 0.5:
			_rotation_angle += PI

func _process(delta: float) -> void:
	if not mission and not trade_mission and not ship:
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
	# Scale with simulation speed, but use minimum at low speeds
	var progress_lerp_speed := maxf(20.0, 12.0 * TimeScale.speed_multiplier)
	_smooth_progress = lerp(_smooth_progress, actual_progress, minf(progress_lerp_speed * delta, 1.0))

	# Update target position using smooth progress
	if mission:
		_update_mining_target_with_progress(_smooth_progress)
	elif trade_mission:
		_update_trade_target_with_progress(_smooth_progress)
	else:
		_update_target()

	# Calculate velocity and rotation from trajectory
	if mission and (mission.status == Mission.Status.TRANSIT_OUT or mission.status == Mission.Status.TRANSIT_BACK):
		var start_pos := Vector2.ZERO
		var end_pos := Vector2.ZERO
		var transit_mode: int = mission.transit_mode
		if mission.status == Mission.Status.TRANSIT_OUT:
			start_pos = mission.origin_position_au * AU_PIXELS
			end_pos = (mission.asteroid.get_position_au() if mission.asteroid else mission.origin_position_au) * AU_PIXELS
		else:
			start_pos = (mission.asteroid.get_position_au() if mission.asteroid else mission.origin_position_au) * AU_PIXELS
			end_pos = mission.return_position_au * AU_PIXELS

		# Calculate tangent to trajectory curve
		_velocity = _calculate_trajectory_tangent(start_pos, end_pos, _smooth_progress, transit_mode, mission.transit_time)

		# Rotation follows velocity direction, flips at midpoint for retrograde burn
		# Always update rotation when in transit
		var target_angle := _velocity.angle()
		if _smooth_progress > 0.5:
			target_angle += PI  # Flip for deceleration burn
		# Smooth rotation - faster at low speeds to stay responsive
		var rotation_lerp_speed := maxf(20.0, 15.0 * TimeScale.speed_multiplier)
		var angle_diff := fmod(target_angle - _rotation_angle + PI, TAU) - PI
		_rotation_angle += angle_diff * minf(rotation_lerp_speed * delta, 1.0)

	elif trade_mission and (trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY or trade_mission.status == TradeMission.Status.TRANSIT_BACK):
		var start_pos := Vector2.ZERO
		var end_pos := Vector2.ZERO
		var transit_mode: int = trade_mission.transit_mode
		if trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY:
			start_pos = trade_mission.origin_position_au * AU_PIXELS
			end_pos = trade_mission.colony.get_position_au() * AU_PIXELS
		else:
			start_pos = trade_mission.colony.get_position_au() * AU_PIXELS
			end_pos = trade_mission.return_position_au * AU_PIXELS

		_velocity = _calculate_trajectory_tangent(start_pos, end_pos, _smooth_progress, transit_mode, trade_mission.transit_time)

		# Always update rotation when in transit
		var target_angle := _velocity.angle()
		if _smooth_progress > 0.5:
			target_angle += PI
		var rotation_lerp_speed := maxf(20.0, 15.0 * TimeScale.speed_multiplier)
		var angle_diff := fmod(target_angle - _rotation_angle + PI, TAU) - PI
		_rotation_angle += angle_diff * minf(rotation_lerp_speed * delta, 1.0)

	# Smooth position lerp to avoid jitter
	# Higher speed at low simulation speeds to compensate for infrequent ticks
	var position_lerp_speed := maxf(25.0, 12.0 * TimeScale.speed_multiplier)
	position = position.lerp(_target_pos, minf(position_lerp_speed * delta, 1.0))

	# Update trajectory cache periodically
	_trajectory_update_timer += delta
	if _trajectory_update_timer >= TRAJECTORY_UPDATE_INTERVAL:
		_trajectory_update_timer = 0.0
		_update_trajectory_cache()

	queue_redraw()

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
	# Only called periodically to avoid jitter from recalculating every frame
	_cached_trajectory_points.clear()

	var start_pos := Vector2.ZERO
	var end_pos := Vector2.ZERO
	var transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE
	var is_active := false

	# Determine trajectory endpoints
	if mission:
		if mission.status == Mission.Status.TRANSIT_OUT:
			start_pos = mission.origin_position_au * AU_PIXELS
			end_pos = (mission.asteroid.get_position_au() if mission.asteroid else mission.origin_position_au) * AU_PIXELS
			transit_mode = mission.transit_mode
			is_active = true
		elif mission.status == Mission.Status.TRANSIT_BACK:
			start_pos = (mission.asteroid.get_position_au() if mission.asteroid else mission.origin_position_au) * AU_PIXELS
			end_pos = mission.return_position_au * AU_PIXELS
			transit_mode = mission.transit_mode
			is_active = true
	elif trade_mission:
		if trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY:
			start_pos = trade_mission.origin_position_au * AU_PIXELS
			end_pos = trade_mission.colony.get_position_au() * AU_PIXELS
			transit_mode = trade_mission.transit_mode
			is_active = true
		elif trade_mission.status == TradeMission.Status.TRANSIT_BACK:
			start_pos = trade_mission.colony.get_position_au() * AU_PIXELS
			end_pos = trade_mission.return_position_au * AU_PIXELS
			transit_mode = trade_mission.transit_mode
			is_active = true

	if not is_active:
		return

	# Generate trajectory points in world space
	var num_points := 30
	for i in range(num_points + 1):
		var t := float(i) / float(num_points)
		var world_point := _calculate_trajectory_position(start_pos, end_pos, t, transit_mode)
		_cached_trajectory_points.append(world_point)

func _calculate_trajectory_position(start: Vector2, end: Vector2, progress: float, transit_mode: int) -> Vector2:
	# Calculate ship position along trajectory based on transit mode
	# Returns position in absolute world coordinates
	var direction := (end - start).normalized()
	var distance := start.distance_to(end)

	if transit_mode == Mission.TransitMode.HOHMANN:
		# Hohmann transfer follows an elliptical arc
		# Perpendicular to travel direction
		var perpendicular := Vector2(-direction.y, direction.x)

		# Arc bows outward (away from origin point)
		# sin creates the arc shape, peaking at progress=0.5
		var arc_height := distance * 0.15 * sin(progress * PI)  # 15% of distance
		var arc_offset := perpendicular * arc_height

		return start.lerp(end, progress) + arc_offset
	else:
		# Brachistochrone: constant thrust acceleration/deceleration
		# Progress is TIME fraction (0 to 1), but position follows S-curve
		var distance_fraction := _brachistochrone_distance_fraction(progress)

		var perpendicular := Vector2(-direction.y, direction.x)

		# Much smaller arc than Hohmann (5% vs 15%)
		var arc_height := distance * 0.05 * sin(progress * PI)
		var arc_offset := perpendicular * arc_height

		return start.lerp(end, distance_fraction) + arc_offset

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

	# Derelict ships: red with X marker
	if ship and ship.is_derelict:
		draw_circle(Vector2.ZERO, 6, Color(0.9, 0.2, 0.2))
		# Draw X
		var s := 4.0
		draw_line(Vector2(-s, -s), Vector2(s, s), Color(1.0, 0.3, 0.3), 2.0)
		draw_line(Vector2(s, -s), Vector2(-s, s), Color(1.0, 0.3, 0.3), 2.0)
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
