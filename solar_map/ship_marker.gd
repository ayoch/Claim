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
const TRAJECTORY_UPDATE_INTERVAL: float = 1.0  # Update trajectory every second (patched conics is cheap!)

# Cached draw geometry (avoid per-frame allocations in _draw)
var _rescue_tri := PackedVector2Array([Vector2(0, -8), Vector2(8, 4.8), Vector2(-8, 4.8)])
var _rescue_outline := PackedVector2Array([Vector2(0, -8), Vector2(8, 4.8), Vector2(-8, 4.8), Vector2(0, -8)])
var _transit_poly := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])
var _transit_outline := PackedVector2Array([Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO])

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
		if not s:
			# Mission has null ship - shouldn't happen, but handle gracefully
			return
		if mission.status == Mission.Status.TRANSIT_OUT or mission.status == Mission.Status.TRANSIT_BACK or mission.status == Mission.Status.REFUELING:
			_target_pos = s.position_au * AU_PIXELS
		else:
			_update_mining_target_with_progress(_smooth_progress)
	elif trade_mission:
		var s: Ship = trade_mission.ship
		if s and (trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY or trade_mission.status == TradeMission.Status.TRANSIT_BACK or trade_mission.status == TradeMission.Status.REFUELING):
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

	# Update label with current speed
	_update_label()

	# Update trajectory cache periodically
	_trajectory_update_timer += delta
	if _trajectory_update_timer >= TRAJECTORY_UPDATE_INTERVAL:
		_trajectory_update_timer = 0.0
		_update_trajectory_cache()

	queue_redraw()

func _update_label() -> void:
	var s: Ship = null
	if mission and mission.ship:
		s = mission.ship
	elif trade_mission and trade_mission.ship:
		s = trade_mission.ship
	elif ship:
		s = ship
	else:
		return  # rescue/refuel vessel — label set in _ready, don't override

	# Compute speed from mission parameters rather than ship.speed_au_per_tick.
	# ship.speed_au_per_tick uses live-tracked orbital positions for total_distance,
	# which inflates speed as the endpoints drift apart over long transits.
	# Correct formula: v = thrust * 9.81 * transit_time * min(t, 1-t)
	# (equivalent to the original brachistochrone but using only fixed mission values)
	var speed_km_s := 0.0
	var active_mission: Object = null
	if mission and (mission.status == Mission.Status.TRANSIT_OUT or mission.status == Mission.Status.TRANSIT_BACK):
		active_mission = mission
	elif trade_mission and (trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY or trade_mission.status == TradeMission.Status.TRANSIT_BACK):
		active_mission = trade_mission
	if active_mission and active_mission.transit_time > 0.0:
		var t_frac := clampf(active_mission.elapsed_ticks / active_mission.transit_time, 0.0, 1.0)
		var speed_factor := minf(t_frac, 1.0 - t_frac)
		speed_km_s = s.get_effective_thrust() * 9.81 * active_mission.transit_time * speed_factor / 1000.0

	var new_text: String
	if speed_km_s >= 0.5:
		new_text = "%s\n%.0f km/s" % [s.ship_name, speed_km_s]
	else:
		new_text = s.ship_name
	if $Label.text != new_text:
		$Label.text = new_text

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

func _update_mining_target_with_progress(_progress: float) -> void:
	# Use actual ship position from simulation (includes gravity)
	if mission and mission.ship:
		_target_pos = mission.ship.position_au * AU_PIXELS

func _update_trade_target() -> void:
	_update_trade_target_with_progress(0.0)

func _update_trade_target_with_progress(_progress: float) -> void:
	# Use actual ship position from simulation (includes gravity)
	if trade_mission and trade_mission.ship:
		_target_pos = trade_mission.ship.position_au * AU_PIXELS

func update_position() -> void:
	_update_target()

func _update_trajectory_cache() -> void:
	# Update cached trajectory points using PATCHED CONICS (like Kerbal Space Program)
	# Much cheaper than forward simulation - uses analytical conic sections
	_cached_trajectory_points.clear()

	var is_active := false
	var transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE

	# Build list of legs: each leg is [start_au, end_au]
	# First leg includes current_progress (0-1) to skip already-traveled portion
	var legs: Array = []  # Array of [Vector2, Vector2]
	var current_progress := 0.0  # Progress within first leg

	if mission:
		transit_mode = mission.transit_mode
		if mission.status == Mission.Status.TRANSIT_OUT:
			is_active = true
			current_progress = mission.get_progress()
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
			current_progress = mission.get_progress()
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
			current_progress = trade_mission.get_progress()
			var leg_start := trade_mission.get_current_leg_start_pos()
			var leg_end := trade_mission.get_current_leg_end_pos()
			legs.append([leg_start, leg_end])
		elif trade_mission.status == TradeMission.Status.TRANSIT_BACK:
			is_active = true
			current_progress = trade_mission.get_progress()
			var leg_start := trade_mission.get_current_leg_start_pos()
			var leg_end := trade_mission.get_current_leg_end_pos()
			legs.append([leg_start, leg_end])

	if not is_active:
		return

	# Get ship state
	var transit_ship: Ship = null
	if mission:
		transit_ship = mission.ship
	elif trade_mission:
		transit_ship = trade_mission.ship
	elif ship:
		transit_ship = ship
	if not transit_ship:
		return

	# PATCHED CONICS: Use analytical conic sections instead of expensive simulation
	# Determine which SOI we're in
	var soi_body := CelestialData.get_soi_body(transit_ship.position_au)
	var mu: float
	var relative_pos: Vector2
	var relative_vel: Vector2

	if soi_body["is_planet"]:
		# In a planet's SOI - orbit relative to planet
		var planet_idx: int = soi_body["body_index"]
		var planet_pos := CelestialData.get_planet_position_au(planet_idx)
		relative_pos = transit_ship.position_au - planet_pos
		relative_vel = transit_ship.velocity_au_per_tick  # Simplified: ignore planet velocity for now
		mu = CelestialData.GM_PLANETS[planet_idx]
	else:
		# In Sun's SOI (most common)
		relative_pos = transit_ship.position_au
		relative_vel = transit_ship.velocity_au_per_tick
		mu = CelestialData.GM_SUN

	# Convert state vector to orbital elements
	var elements := CelestialData.state_to_elements(relative_pos, relative_vel, mu)

	# Generate conic section points (cheap analytical calculation)
	var conic_points := CelestialData.generate_conic_points(elements, mu, 40)  # 40 points is plenty

	# Convert back to absolute positions and scale to pixels
	for point in conic_points:
		var abs_pos: Vector2
		if soi_body["is_planet"]:
			var planet_pos := CelestialData.get_planet_position_au(soi_body["body_index"])
			abs_pos = point + planet_pos
		else:
			abs_pos = point
		_cached_trajectory_points.append(abs_pos * AU_PIXELS)

func _draw_trajectory() -> void:
	# Trajectory visualization disabled
	return

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

		# Draw amber triangle (using cached geometry)
		draw_colored_polygon(_rescue_tri, color)
		draw_polyline(_rescue_outline, Color(1.0, 0.8, 0.4), 1.5)
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

		_transit_poly[0] = tip
		_transit_poly[1] = back_left
		_transit_poly[2] = back_right
		draw_colored_polygon(_transit_poly, color)
		_transit_outline[0] = tip
		_transit_outline[1] = back_left
		_transit_outline[2] = back_right
		_transit_outline[3] = tip
		draw_polyline(_transit_outline, Color(color.r * 0.7, color.g * 0.7, color.b * 0.7), 1.5)
	else:
		# Stationary or mining: draw as circle
		draw_circle(Vector2.ZERO, 6, color)
