extends Node2D

const AU_PIXELS: float = 200.0
const MOVE_SMOOTHING: float = 12.0  # base lerp speed for smooth movement

var mission: Mission = null
var trade_mission: TradeMission = null
var ship: Ship = null  # for idle/derelict ships without active missions

# Cache positions for interpolation
var _target_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	if mission:
		$Label.text = mission.ship.ship_name
		_update_target()
		position = _target_pos  # snap to start
		visible = true
	elif trade_mission:
		$Label.text = trade_mission.ship.ship_name
		_update_target()
		position = _target_pos
		visible = true
	elif ship:
		$Label.text = ship.ship_name
		_target_pos = ship.position_au * AU_PIXELS
		position = _target_pos
		visible = true
	else:
		visible = false

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
	_update_target()
	# Smooth interpolation toward the target each frame
	# Use square root scaling so high speeds don't cause instant snapping
	var speed_scale := sqrt(TimeScale.speed_multiplier)
	var adjusted_lerp_speed := MOVE_SMOOTHING * speed_scale
	position = position.lerp(_target_pos, minf(adjusted_lerp_speed * delta, 1.0))
	queue_redraw()

func _update_target() -> void:
	if mission:
		_update_mining_target()
	elif trade_mission:
		_update_trade_target()
	elif ship:
		_target_pos = ship.position_au * AU_PIXELS

func _update_mining_target() -> void:
	var origin_pos := mission.origin_position_au * AU_PIXELS
	var asteroid_pos := mission.asteroid.get_position_au() * AU_PIXELS if mission.asteroid else origin_pos
	var progress := mission.get_progress()

	match mission.status:
		Mission.Status.TRANSIT_OUT:
			_target_pos = _calculate_trajectory_position(origin_pos, asteroid_pos, progress, mission.transit_mode)
		Mission.Status.MINING, Mission.Status.IDLE_AT_DESTINATION:
			_target_pos = asteroid_pos
		Mission.Status.TRANSIT_BACK:
			var return_pos := mission.return_position_au * AU_PIXELS
			_target_pos = _calculate_trajectory_position(asteroid_pos, return_pos, progress, mission.transit_mode)

func _update_trade_target() -> void:
	var origin_pos := trade_mission.origin_position_au * AU_PIXELS
	var colony_pos := trade_mission.colony.get_position_au() * AU_PIXELS
	var progress := trade_mission.get_progress()

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
		# Brachistochrone is more direct (slight curve from acceleration profile)
		var perpendicular := Vector2(-direction.y, direction.x)

		# Much smaller arc than Hohmann (5% vs 15%)
		var arc_height := distance * 0.05 * sin(progress * PI)
		var arc_offset := perpendicular * arc_height

		return start.lerp(end, progress) + arc_offset

func _draw() -> void:
	# Draw trajectory path first (behind ship marker)
	_draw_trajectory()

	# Derelict ships: red with X marker
	if ship and ship.is_derelict:
		draw_circle(Vector2.ZERO, 6, Color(0.9, 0.2, 0.2))
		# Draw X
		var s := 4.0
		draw_line(Vector2(-s, -s), Vector2(s, s), Color(1.0, 0.3, 0.3), 2.0)
		draw_line(Vector2(s, -s), Vector2(-s, s), Color(1.0, 0.3, 0.3), 2.0)
		return

	# Idle remote ships: amber
	if ship and ship.is_idle_remote:
		draw_circle(Vector2.ZERO, 6, Color(0.9, 0.7, 0.2))
		return

	var color := Color(0.3, 0.9, 0.5)
	if trade_mission:
		color = Color(0.3, 0.9, 0.9)  # Cyan for trade ships

	draw_circle(Vector2.ZERO, 6, color)
	# Draw direction indicator
	var is_transit := false
	var dir := Vector2.RIGHT

	if mission and mission.status != Mission.Status.MINING and mission.status != Mission.Status.IDLE_AT_DESTINATION:
		is_transit = true
		var origin_pos := mission.origin_position_au * AU_PIXELS
		var asteroid_pos := mission.asteroid.get_position_au() * AU_PIXELS if mission.asteroid else origin_pos
		if mission.status == Mission.Status.TRANSIT_OUT:
			dir = (asteroid_pos - origin_pos).normalized()
		else:
			var return_pos := mission.return_position_au * AU_PIXELS
			dir = (return_pos - asteroid_pos).normalized()
	elif trade_mission and trade_mission.status != TradeMission.Status.SELLING and trade_mission.status != TradeMission.Status.IDLE_AT_COLONY:
		is_transit = true
		var origin_pos := trade_mission.origin_position_au * AU_PIXELS
		var colony_pos := trade_mission.colony.get_position_au() * AU_PIXELS
		if trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY:
			dir = (colony_pos - origin_pos).normalized()
		else:
			var return_pos := trade_mission.return_position_au * AU_PIXELS
			dir = (return_pos - colony_pos).normalized()

	if is_transit:
		draw_line(Vector2.ZERO, dir * 10, Color(color.r, color.g, color.b, 0.7), 2.0)

func _draw_trajectory() -> void:
	# Draw trajectory arc for ships in transit
	# Use absolute positions (not relative to current ship position)
	var start_pos := Vector2.ZERO
	var end_pos := Vector2.ZERO
	var transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE
	var color := Color(0.3, 0.9, 0.5, 0.3)  # Translucent green
	var is_active := false

	# Determine trajectory endpoints and mode (in absolute world coordinates)
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
		color = Color(0.3, 0.9, 0.9, 0.3)  # Translucent cyan
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

	# Draw the trajectory arc relative to ship's current position
	# This makes the trajectory show the path FROM current position TO destination
	var num_points := 30
	var points := PackedVector2Array()

	for i in range(num_points + 1):
		var t := float(i) / float(num_points)
		# Calculate point in world coordinates
		var world_point := _calculate_trajectory_position(start_pos, end_pos, t, transit_mode)
		# Convert to local coordinates relative to this marker's current drawn position
		var local_point: Vector2 = world_point - position
		points.append(local_point)

	# Draw the arc with solid line
	for i in range(points.size() - 1):
		draw_line(points[i], points[i + 1], color, 1.5)
