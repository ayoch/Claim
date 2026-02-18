extends Node2D

const AU_PIXELS: float = 200.0  # 1 AU = 200 pixels
const BELT_INNER_AU: float = 1.5
const BELT_OUTER_AU: float = 3.5

@onready var camera: Camera2D = $Camera2D
@onready var asteroid_markers: Node2D = $AsteroidMarkers
@onready var ship_markers: Node2D = $ShipMarkers
@onready var ship_selector_panel: HBoxContainer = %ShipSelectorPanel

var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _zoom_level: float = 1.0
const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 0.1

# Touch/pinch zoom state
var _touches: Dictionary = {}  # finger index -> position
var _last_pinch_distance: float = -1.0

# Colony markers
var _colony_markers: Array[Node2D] = []

# Planet labels (Node2D wrappers with Label children)
var _planet_labels: Array[Node2D] = []

# Label anti-overlap system
var _label_base_offsets: Dictionary = {}  # Node2D -> Vector2 (original offset from parent)

# Trajectory preview
var _preview_active: bool = false
var _preview_ship_pos: Vector2 = Vector2.ZERO
var _preview_dest_pos: Vector2 = Vector2.ZERO
var _preview_waypoint_pos: Vector2 = Vector2.ZERO
var _preview_has_waypoint: bool = false
var _preview_blink_time: float = 0.0
const PREVIEW_BLINK_PERIOD: float = 1.0  # seconds for full blink cycle

var asteroid_marker_scene: PackedScene = preload("res://solar_map/asteroid_marker.tscn")
var ship_marker_scene: PackedScene = preload("res://solar_map/ship_marker.tscn")

# Interpolation
const LERP_SPEED: float = 8.0  # lerp factor per second
var _planet_targets: Array[Vector2] = []
var _planet_positions: Array[Vector2] = []

func _ready() -> void:
	_spawn_planet_labels()
	_spawn_asteroid_markers()
	_spawn_colony_markers()
	_refresh_ship_markers()
	_refresh_ship_selector()
	EventBus.mission_started.connect(func(_m: Mission) -> void: _refresh_ships())
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _refresh_ships())
	EventBus.mission_phase_changed.connect(func(_m: Mission) -> void: _refresh_ships())
	EventBus.trade_mission_started.connect(func(_tm: TradeMission) -> void: _refresh_ships())
	EventBus.trade_mission_completed.connect(func(_tm: TradeMission) -> void: _refresh_ships())
	EventBus.trade_mission_phase_changed.connect(func(_tm: TradeMission) -> void: _refresh_ships())
	EventBus.ship_derelict.connect(func(_s: Ship) -> void: _refresh_ships())
	EventBus.rescue_mission_completed.connect(func(_s: Ship) -> void: _refresh_ships())
	EventBus.tick.connect(_on_tick)
	EventBus.mission_preview_started.connect(_on_preview_started)
	EventBus.mission_preview_cancelled.connect(_on_preview_cancelled)

func _refresh_ships() -> void:
	_refresh_ship_markers()
	_refresh_ship_selector()

func _draw() -> void:
	# Draw sun
	draw_circle(Vector2.ZERO, 15, Color(1.0, 0.9, 0.3))

	# Draw planet orbits and positions
	for i in range(CelestialData.PLANETS.size()):
		var planet: Dictionary = CelestialData.PLANETS[i]
		var orbit_au: float = planet["orbit_au"]
		var color: Color = planet["color"]
		var radius: float = planet["radius"]

		# Orbit ring (faint)
		_draw_circle_outline(Vector2.ZERO, orbit_au * AU_PIXELS, Color(color.r, color.g, color.b, 0.2), 1.0)

		# Planet dot at interpolated position
		if i < _planet_positions.size():
			draw_circle(_planet_positions[i], radius, color)

	# Draw asteroid belt (translucent annulus)
	var steps := 64
	for i in range(steps):
		var angle := (float(i) / steps) * TAU
		var next_angle := (float(i + 1) / steps) * TAU
		var inner_r := BELT_INNER_AU * AU_PIXELS
		var outer_r := BELT_OUTER_AU * AU_PIXELS
		var p1 := Vector2(cos(angle), sin(angle)) * inner_r
		var p2 := Vector2(cos(next_angle), sin(next_angle)) * inner_r
		var p3 := Vector2(cos(next_angle), sin(next_angle)) * outer_r
		var p4 := Vector2(cos(angle), sin(angle)) * outer_r
		draw_colored_polygon(PackedVector2Array([p1, p2, p3, p4]), Color(0.5, 0.4, 0.3, 0.08))

	# Draw trajectory preview if active
	if _preview_active:
		# Calculate blink alpha (oscillates between 0.3 and 1.0)
		var blink_alpha := 0.65 + 0.35 * sin(_preview_blink_time * TAU / PREVIEW_BLINK_PERIOD)

		# Draw trajectory line(s)
		var line_color := Color(0.3, 0.9, 1.0, 0.6)
		if _preview_has_waypoint:
			# Multi-leg slingshot trajectory
			draw_line(_preview_ship_pos, _preview_waypoint_pos, line_color, 2.0)
			draw_line(_preview_waypoint_pos, _preview_dest_pos, line_color, 2.0)

			# Draw slingshot waypoint indicator (cyan pulsing circle)
			var waypoint_color := Color(0.3, 0.9, 0.9, blink_alpha)
			draw_circle(_preview_waypoint_pos, 14, waypoint_color)
			draw_circle(_preview_waypoint_pos, 10, Color(0.0, 0.0, 0.0, blink_alpha * 0.5))
			# Add velocity boost arrow
			var boost_arrow_end := _preview_waypoint_pos + Vector2(20, -20)
			draw_line(_preview_waypoint_pos, boost_arrow_end, Color(0.3, 1.0, 0.9, blink_alpha), 2.0)
			# Arrowhead
			var arrow_back1 := boost_arrow_end + Vector2(-8, 4)
			var arrow_back2 := boost_arrow_end + Vector2(-4, 8)
			draw_line(boost_arrow_end, arrow_back1, Color(0.3, 1.0, 0.9, blink_alpha), 2.0)
			draw_line(boost_arrow_end, arrow_back2, Color(0.3, 1.0, 0.9, blink_alpha), 2.0)
		else:
			# Direct trajectory
			draw_line(_preview_ship_pos, _preview_dest_pos, line_color, 2.0)

		# Draw blinking indicator at ship position
		var ship_indicator_color := Color(0.3, 1.0, 0.3, blink_alpha)
		draw_circle(_preview_ship_pos, 12, ship_indicator_color)
		draw_circle(_preview_ship_pos, 8, Color(0.0, 0.0, 0.0, blink_alpha * 0.5))

		# Draw blinking indicator at destination
		var dest_indicator_color := Color(1.0, 0.9, 0.3, blink_alpha)
		draw_circle(_preview_dest_pos, 12, dest_indicator_color)
		draw_circle(_preview_dest_pos, 8, Color(0.0, 0.0, 0.0, blink_alpha * 0.5))

func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	var points := 64
	for i in range(points):
		var angle_from := (float(i) / points) * TAU
		var angle_to := (float(i + 1) / points) * TAU
		var from := center + Vector2(cos(angle_from), sin(angle_from)) * radius
		var to := center + Vector2(cos(angle_to), sin(angle_to)) * radius
		draw_line(from, to, color, width)

func _spawn_planet_labels() -> void:
	for i in range(CelestialData.PLANETS.size()):
		var planet: Dictionary = CelestialData.PLANETS[i]
		var node := Node2D.new()
		var label := Label.new()
		label.text = planet["name"]
		label.position = Vector2(planet["radius"] + 4, -8)
		label.add_theme_font_size_override("font_size", 11)
		var color: Color = planet["color"]
		label.add_theme_color_override("font_color", Color(color.r, color.g, color.b, 0.7))
		node.add_child(label)
		var pos := CelestialData.get_planet_position_au(i) * AU_PIXELS
		node.position = pos
		add_child(node)
		_planet_labels.append(node)
		_planet_positions.append(pos)
		_planet_targets.append(pos)

func _update_planet_targets() -> void:
	for i in range(mini(_planet_targets.size(), CelestialData.PLANETS.size())):
		_planet_targets[i] = CelestialData.get_planet_position_au(i) * AU_PIXELS

func _spawn_asteroid_markers() -> void:
	for asteroid in GameState.asteroids:
		var marker: Node2D = asteroid_marker_scene.instantiate()
		marker.asteroid = asteroid
		var pos := asteroid.get_position_au() * AU_PIXELS
		marker.position = pos
		marker.set_meta("target_pos", pos)
		asteroid_markers.add_child(marker)

func _spawn_colony_markers() -> void:
	for colony in GameState.colonies:
		var marker := _ColonyMarkerNode.new()
		marker.set_meta("colony", colony)
		var label := Label.new()
		label.text = colony.colony_name
		label.position = Vector2(10, -8)
		label.add_theme_font_size_override("font_size", 12)
		label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
		marker.add_child(label)
		var col_pos := colony.get_position_au() * AU_PIXELS
		marker.position = col_pos
		marker.set_meta("target_pos", col_pos)
		add_child(marker)
		_colony_markers.append(marker)

class _ColonyMarkerNode extends Node2D:
	func _draw() -> void:
		# Draw cyan diamond shape
		var s := 8.0
		var pts := PackedVector2Array([
			Vector2(0, -s), Vector2(s, 0), Vector2(0, s), Vector2(-s, 0)
		])
		draw_colored_polygon(pts, Color(0.3, 0.9, 0.9))
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0.5, 1.0, 1.0), 1.0)

func _refresh_ship_markers() -> void:
	for child in ship_markers.get_children():
		child.queue_free()

	# Track which ships already have markers to prevent duplicates
	var ships_with_markers: Dictionary = {}

	# Mining missions (only add if ship not already marked)
	for mission: Mission in GameState.missions:
		if mission.ship and mission.ship not in ships_with_markers:
			var marker: Node2D = ship_marker_scene.instantiate()
			marker.mission = mission
			ship_markers.add_child(marker)
			ships_with_markers[mission.ship] = true

	# Trade missions (only add if ship not already marked)
	for tm: TradeMission in GameState.trade_missions:
		if tm.ship and tm.ship not in ships_with_markers:
			var marker: Node2D = ship_marker_scene.instantiate()
			marker.trade_mission = tm
			ship_markers.add_child(marker)
			ships_with_markers[tm.ship] = true

	# Idle remote and derelict ships without active missions
	for s: Ship in GameState.ships:
		if s in ships_with_markers:
			continue
		# Only show if not docked (docked ships stay at Earth, don't need map marker)
		if not s.is_docked and (s.is_idle_remote or s.is_derelict):
			var marker: Node2D = ship_marker_scene.instantiate()
			marker.ship = s
			ship_markers.add_child(marker)
			ships_with_markers[s] = true

func _process(delta: float) -> void:
	var t := minf(LERP_SPEED * delta, 1.0)

	# Interpolate planet positions and labels
	for i in range(_planet_positions.size()):
		_planet_positions[i] = _planet_positions[i].lerp(_planet_targets[i], t)
		if i < _planet_labels.size():
			_planet_labels[i].position = _planet_positions[i]

	# Interpolate asteroid markers
	for marker in asteroid_markers.get_children():
		if marker.has_meta("target_pos"):
			var target: Vector2 = marker.get_meta("target_pos")
			marker.position = marker.position.lerp(target, t)

	# Interpolate colony markers
	for marker in _colony_markers:
		if marker.has_meta("target_pos"):
			var target: Vector2 = marker.get_meta("target_pos")
			marker.position = marker.position.lerp(target, t)

	# Apply label anti-overlap
	_adjust_labels_to_prevent_overlap()

	# Update preview blink animation
	if _preview_active:
		_preview_blink_time += delta
		if _preview_blink_time >= PREVIEW_BLINK_PERIOD:
			_preview_blink_time -= PREVIEW_BLINK_PERIOD

	queue_redraw()

## Adjust label positions to prevent overlaps
func _adjust_labels_to_prevent_overlap() -> void:
	# Collect all labels with their anchor points and current positions
	var labels: Array[Dictionary] = []

	# Planet labels
	for i in range(_planet_labels.size()):
		var label_node := _planet_labels[i]
		var label := label_node.get_child(0) as Label
		if label:
			labels.append({
				"node": label_node,
				"label": label,
				"anchor": label_node.position,  # Planet position
				"type": "planet"
			})

	# Colony labels
	for marker in _colony_markers:
		var label := marker.get_child(0) as Label
		if label:
			labels.append({
				"node": marker,
				"label": label,
				"anchor": marker.position,  # Colony position
				"type": "colony"
			})

	# Ship labels
	for marker in ship_markers.get_children():
		var label := marker.get_node_or_null("Label") as Label
		if label:
			labels.append({
				"node": marker,
				"label": label,
				"anchor": marker.position,  # Ship position
				"type": "ship"
			})

	# For each label, check for overlaps and adjust position
	const PADDING := 4.0  # Minimum spacing between labels
	const MAX_OFFSET := 60.0  # Maximum distance a label can move from its anchor

	for i in range(labels.size()):
		var label_a := labels[i]
		var label_control_a := label_a["label"] as Label
		var node_a := label_a["node"] as Node2D

		# Get bounding rect in world space
		var size_a := label_control_a.size
		var label_offset_a := label_control_a.position
		var rect_a := Rect2(node_a.position + label_offset_a, size_a)

		# Check against all other labels
		var accumulated_push := Vector2.ZERO
		var overlap_count := 0

		for j in range(labels.size()):
			if i == j:
				continue

			var label_b := labels[j]
			var label_control_b := label_b["label"] as Label
			var node_b := label_b["node"] as Node2D

			var size_b := label_control_b.size
			var label_offset_b := label_control_b.position
			var rect_b := Rect2(node_b.position + label_offset_b, size_b)

			# Expand rects by padding
			var expanded_a := rect_a.grow(PADDING)
			var expanded_b := rect_b.grow(PADDING)

			# Check for overlap
			if expanded_a.intersects(expanded_b):
				# Calculate push direction (away from other label)
				var center_a := rect_a.get_center()
				var center_b := rect_b.get_center()
				var push_dir := (center_a - center_b).normalized()

				# If labels are at same position, push in a consistent direction
				if push_dir.length() < 0.1:
					push_dir = Vector2(1, 0).rotated(float(i) * 0.7)  # Spread out evenly

				accumulated_push += push_dir * 2.0
				overlap_count += 1

		# Apply push to label offset
		if overlap_count > 0:
			var current_offset := label_control_a.position
			var new_offset := current_offset + accumulated_push

			# Clamp offset so label doesn't move too far from anchor
			var offset_dist := new_offset.length()
			if offset_dist > MAX_OFFSET:
				new_offset = new_offset.normalized() * MAX_OFFSET

			label_control_a.position = new_offset

func _on_tick(_dt: float) -> void:
	_update_planet_targets()
	_update_asteroid_targets()
	_update_colony_targets()

func _update_asteroid_targets() -> void:
	for marker in asteroid_markers.get_children():
		if marker.asteroid:
			marker.set_meta("target_pos", marker.asteroid.get_position_au() * AU_PIXELS)

func _update_colony_targets() -> void:
	for marker in _colony_markers:
		var colony: Colony = marker.get_meta("colony")
		if colony:
			marker.set_meta("target_pos", colony.get_position_au() * AU_PIXELS)

func _unhandled_input(event: InputEvent) -> void:
	# Mouse controls
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_start = mb.position
			else:
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_level = clampf(_zoom_level + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			camera.zoom = Vector2(_zoom_level, _zoom_level)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_level = clampf(_zoom_level - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			camera.zoom = Vector2(_zoom_level, _zoom_level)
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		camera.position -= motion.relative / camera.zoom

	# Touch controls (pan and pinch-to-zoom)
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_touches[touch.index] = touch.position
		else:
			_touches.erase(touch.index)
			_last_pinch_distance = -1.0
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_touches[drag.index] = drag.position
		if _touches.size() == 1:
			camera.position -= drag.relative / camera.zoom
		elif _touches.size() == 2:
			var points := _touches.values()
			var dist: float = (points[0] as Vector2).distance_to(points[1] as Vector2)
			if _last_pinch_distance > 0:
				var diff := dist - _last_pinch_distance
				_zoom_level = clampf(_zoom_level + diff * 0.005, ZOOM_MIN, ZOOM_MAX)
				camera.zoom = Vector2(_zoom_level, _zoom_level)
			_last_pinch_distance = dist

func _refresh_ship_selector() -> void:
	if not ship_selector_panel:
		return

	# Clear existing buttons
	for child in ship_selector_panel.get_children():
		child.queue_free()

	# Add button for each ship
	for ship in GameState.ships:
		var btn := Button.new()
		btn.text = ship.ship_name
		btn.custom_minimum_size = Vector2(120, 36)

		# Color code by status
		if ship.is_derelict:
			btn.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		elif ship.is_docked:
			btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		elif ship.is_idle_remote:
			btn.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		else:
			btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))

		btn.pressed.connect(_center_on_ship.bind(ship))
		ship_selector_panel.add_child(btn)

func _center_on_ship(ship: Ship) -> void:
	var target_pos := ship.position_au * AU_PIXELS
	camera.position = target_pos
	# Optionally zoom in a bit
	_zoom_level = 1.5
	camera.zoom = Vector2(_zoom_level, _zoom_level)

func _on_preview_started(ship: Ship, destination_pos: Vector2, slingshot_route) -> void:
	_preview_active = true
	_preview_ship_pos = ship.position_au * AU_PIXELS
	_preview_dest_pos = destination_pos * AU_PIXELS
	_preview_blink_time = 0.0

	# Setup slingshot waypoint if using gravity assist
	if slingshot_route:
		_preview_has_waypoint = true
		_preview_waypoint_pos = slingshot_route.waypoint_pos * AU_PIXELS
	else:
		_preview_has_waypoint = false

	queue_redraw()

func _on_preview_cancelled() -> void:
	_preview_active = false
	queue_redraw()
