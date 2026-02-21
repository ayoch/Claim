extends Node2D

static func _free_children(container: Node) -> void:
	for i in range(container.get_child_count() - 1, -1, -1):
		container.get_child(i).free()

const AU_PIXELS: float = 200.0  # 1 AU = 200 pixels
const BELT_INNER_AU: float = 1.5
const BELT_OUTER_AU: float = 3.5

@onready var camera: Camera2D = $Camera2D
@onready var asteroid_markers: Node2D = $AsteroidMarkers
@onready var ship_markers: Node2D = $ShipMarkers
@onready var ship_selector_panel: VBoxContainer = %ShipSelectorPanel
@onready var zoom_buttons: VBoxContainer = $UI/ZoomButtons

var _map_selected_ship: Ship = null
var _ship_buttons: Dictionary = {}  # Ship -> Button
var _dispatch_hint_label: Label = null

var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _following_ship: Ship = null  # Ship the camera is tracking
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
var _ships_need_refresh: bool = false  # Debounce marker rebuilds to once per frame
var _last_tick_msec: int = 0
const TICK_THROTTLE_MSEC: int = 200  # Only process ticks every 200ms real-time

# Starfield background
const STAR_TILE_SIZE: float = 1200.0  # Larger tiles = fewer tiles visible = fewer draw calls
const STARS_PER_TILE: int = 30  # Reduced from 80 for performance
var _star_cache: Dictionary = {}  # Vector2i tile coord -> Array of star dicts
var _starfield_time: float = 0.0
const STAR_TWINKLE_SPEED: float = 1.2

# Interpolation
const LERP_SPEED: float = 8.0  # lerp factor per second
var _planet_targets: Array[Vector2] = []
var _planet_positions: Array[Vector2] = []
var _orbital_update_timer: float = 0.0
const ORBITAL_UPDATE_INTERVAL: float = 0.5  # Update orbital positions twice per second instead of 60x/sec
var _label_overlap_timer: float = 0.0
const LABEL_OVERLAP_INTERVAL: float = 0.5  # Check label overlaps twice per second, not every frame

func _ready() -> void:
	_setup_zoom_buttons()
	_spawn_planet_labels()
	_spawn_asteroid_markers()
	_spawn_colony_markers()
	_refresh_ship_markers()
	_refresh_ship_selector()
	_setup_dispatch_hint_label()
	EventBus.mission_started.connect(func(m: Mission) -> void:
		if _map_selected_ship and m.ship == _map_selected_ship:
			_set_map_selected_ship(null)
		_refresh_ships()
	)
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _refresh_ships())
	EventBus.trade_mission_started.connect(func(_tm: TradeMission) -> void: _refresh_ships())
	EventBus.trade_mission_completed.connect(func(_tm: TradeMission) -> void: _refresh_ships())
	EventBus.ship_derelict.connect(func(_s: Ship) -> void: _refresh_ships())
	EventBus.rescue_mission_started.connect(func(_s: Ship, _c: int) -> void: _refresh_ships())
	EventBus.rescue_mission_completed.connect(func(_s: Ship) -> void: _refresh_ships())
	EventBus.refuel_mission_started.connect(func(_s: Ship, _c: int, _f: float) -> void: _refresh_ships())
	EventBus.refuel_mission_completed.connect(func(_s: Ship, _f: float) -> void: _refresh_ships())
	EventBus.tick.connect(_on_tick)
	EventBus.mission_preview_started.connect(_on_preview_started)
	EventBus.mission_preview_cancelled.connect(_on_preview_cancelled)

func _refresh_ships() -> void:
	# Debounce: at high speed, many signals fire per frame. Only rebuild once.
	_ships_need_refresh = true

func _get_star_tile(tile_coord: Vector2i) -> Array:
	if tile_coord in _star_cache:
		return _star_cache[tile_coord]
	# Seed-based star generation for consistent tiles
	var stars: Array = []
	var seed_val := tile_coord.x * 73856093 + tile_coord.y * 19349663
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	for _i in range(STARS_PER_TILE):
		stars.append({
			"offset": Vector2(rng.randf() * STAR_TILE_SIZE, rng.randf() * STAR_TILE_SIZE),
			"size": rng.randf_range(0.5, 2.2),
			"brightness": rng.randf_range(0.3, 1.0),
			"twinkle_phase": rng.randf() * TAU,
			"twinkle_amount": rng.randf_range(0.0, 0.35),
			"color_type": rng.randi() % 3,
		})
	_star_cache[tile_coord] = stars
	return stars

func _draw_starfield() -> void:
	# Get visible area in world coords
	var viewport_size := get_viewport_rect().size
	var cam_pos := camera.global_position
	var zoom := camera.zoom.x
	var half_view := viewport_size / (2.0 * zoom)
	var visible_rect := Rect2(cam_pos - half_view, half_view * 2.0)

	# Dark background covering visible area
	draw_rect(visible_rect, Color(0.008, 0.012, 0.018))

	# Determine which tiles are visible
	var tile_min_x := int(floor(visible_rect.position.x / STAR_TILE_SIZE))
	var tile_min_y := int(floor(visible_rect.position.y / STAR_TILE_SIZE))
	var tile_max_x := int(floor(visible_rect.end.x / STAR_TILE_SIZE))
	var tile_max_y := int(floor(visible_rect.end.y / STAR_TILE_SIZE))

	for tx in range(tile_min_x, tile_max_x + 1):
		for ty in range(tile_min_y, tile_max_y + 1):
			var tile_origin := Vector2(tx * STAR_TILE_SIZE, ty * STAR_TILE_SIZE)
			var stars := _get_star_tile(Vector2i(tx, ty))
			for star in stars:
				var pos: Vector2 = tile_origin + star["offset"]
				var base_bright: float = star["brightness"]
				var twinkle: float = star["twinkle_amount"]
				var phase: float = star["twinkle_phase"]
				var bright: float = clampf(base_bright + sin(_starfield_time + phase) * twinkle, 0.1, 1.0)
				var star_size: float = star["size"]

				var color: Color
				match star["color_type"]:
					0: color = Color(0.8, 0.85, 1.0, bright)   # blue-white
					1: color = Color(0.85, 0.9, 1.0, bright)    # cool white
					_: color = Color(0.6, 0.65, 0.75, bright)   # dim blue-grey

				draw_circle(pos, star_size, color)

func _draw() -> void:
	_draw_starfield()

	# Draw sun
	draw_circle(Vector2.ZERO, 15, Color(1.0, 0.9, 0.3))

	# Draw planet orbits and positions
	for i in range(CelestialData.PLANETS.size()):
		var planet: Dictionary = CelestialData.PLANETS[i]
		var color: Color = planet["color"]
		var radius: float = planet["radius"]
		var planet_name: String = planet["name"]

		# Draw elliptical orbit ring from Keplerian elements
		if EphemerisData.ELEMENTS.has(planet_name):
			var el: Dictionary = EphemerisData.ELEMENTS[planet_name]
			_draw_orbit_ellipse(el, Color(color.r, color.g, color.b, 0.25), 1.0)
		else:
			# Fallback: circular orbit
			var orbit_au: float = planet["orbit_au"]
			_draw_circle_outline(Vector2.ZERO, orbit_au * AU_PIXELS, Color(color.r, color.g, color.b, 0.25), 1.0)

		# Planet with glow and outline
		if i < _planet_positions.size():
			var pos: Vector2 = _planet_positions[i]
			# Outer glow
			draw_circle(pos, radius + 5, Color(color.r, color.g, color.b, 0.2))
			# Bright outline ring for visibility
			_draw_circle_outline(pos, radius + 1.5, Color(color.r, color.g, color.b, 0.7), 1.5)
			# Planet body
			draw_circle(pos, radius, color)
			# Bright highlight
			draw_circle(pos, radius * 0.4, Color(1.0, 1.0, 1.0, 0.35))

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

## Draw an elliptical orbit from Keplerian elements (Sun at focus)
func _draw_orbit_ellipse(el: Dictionary, color: Color, width: float) -> void:
	var a: float = el["a"]       # semi-major axis (AU)
	var e: float = el["e"]       # eccentricity
	var w: float = el["w"]       # longitude of perihelion (degrees)

	var b := a * sqrt(1.0 - e * e)  # semi-minor axis
	var c := a * e                    # distance from center to focus
	var w_rad := deg_to_rad(w)        # orientation angle

	var points := 96
	for i in range(points):
		var angle_from := (float(i) / points) * TAU
		var angle_to := (float(i + 1) / points) * TAU

		# Ellipse centered at origin, then shifted so Sun is at focus
		var from := Vector2(
			a * cos(angle_from) - c,
			b * sin(angle_from)
		)
		var to := Vector2(
			a * cos(angle_to) - c,
			b * sin(angle_to)
		)

		# Rotate by longitude of perihelion
		from = from.rotated(w_rad) * AU_PIXELS
		to = to.rotated(w_rad) * AU_PIXELS

		draw_line(from, to, color, width)

func _setup_zoom_buttons() -> void:
	# Big zoom row (3× step) — sits above
	var big_row := HBoxContainer.new()
	big_row.add_theme_constant_override("separation", 8)
	var big_out := Button.new()
	big_out.text = "−−"
	big_out.custom_minimum_size = Vector2(48, 44)
	big_out.pressed.connect(_zoom_out_big)
	big_row.add_child(big_out)
	var big_in := Button.new()
	big_in.text = "++"
	big_in.custom_minimum_size = Vector2(48, 44)
	big_in.pressed.connect(_zoom_in_big)
	big_row.add_child(big_in)
	zoom_buttons.add_child(big_row)

	# Small zoom row (1× step) — sits below
	var small_row := HBoxContainer.new()
	small_row.add_theme_constant_override("separation", 8)
	var btn_out := Button.new()
	btn_out.text = "-"
	btn_out.custom_minimum_size = Vector2(48, 36)
	btn_out.pressed.connect(_zoom_out)
	small_row.add_child(btn_out)
	var btn_in := Button.new()
	btn_in.text = "+"
	btn_in.custom_minimum_size = Vector2(48, 36)
	btn_in.pressed.connect(_zoom_in)
	small_row.add_child(btn_in)
	zoom_buttons.add_child(small_row)

func _zoom_in() -> void:
	_zoom_level = clampf(_zoom_level + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(_zoom_level, _zoom_level)

func _zoom_out() -> void:
	_zoom_level = clampf(_zoom_level - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(_zoom_level, _zoom_level)

func _zoom_in_big() -> void:
	_zoom_level = clampf(_zoom_level + ZOOM_STEP * 3.0, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(_zoom_level, _zoom_level)

func _zoom_out_big() -> void:
	_zoom_level = clampf(_zoom_level - ZOOM_STEP * 3.0, ZOOM_MIN, ZOOM_MAX)
	camera.zoom = Vector2(_zoom_level, _zoom_level)

func _spawn_planet_labels() -> void:
	for i in range(CelestialData.PLANETS.size()):
		var planet: Dictionary = CelestialData.PLANETS[i]
		var node := Node2D.new()
		var label := Label.new()
		label.text = planet["name"]
		var radius: float = planet["radius"]
		label.position = Vector2(radius + 6, -10)
		label.add_theme_font_size_override("font_size", 14)
		var color: Color = planet["color"]
		label.add_theme_color_override("font_color", color)
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
	_free_children(ship_markers)

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

	# Rescue mission vessels
	for target_ship: Ship in GameState.rescue_missions:
		var marker: Node2D = ship_marker_scene.instantiate()
		marker.rescue_target_ship = target_ship
		marker.rescue_data = GameState.rescue_missions[target_ship]
		marker.is_refuel_vessel = false
		ship_markers.add_child(marker)

	# Refuel mission vessels
	for target_ship: Ship in GameState.refuel_missions:
		var marker: Node2D = ship_marker_scene.instantiate()
		marker.rescue_target_ship = target_ship
		marker.rescue_data = GameState.refuel_missions[target_ship]
		marker.is_refuel_vessel = true
		ship_markers.add_child(marker)

func _process(delta: float) -> void:
	# Debounced ship marker rebuild (signals may fire many times per frame at high speed)
	if _ships_need_refresh:
		_ships_need_refresh = false
		_refresh_ship_markers()
		_refresh_ship_selector()

	_starfield_time += delta * STAR_TWINKLE_SPEED

	# Throttle orbital position updates - don't need to recalculate 60x/second
	_orbital_update_timer += delta
	if _orbital_update_timer >= ORBITAL_UPDATE_INTERVAL:
		_orbital_update_timer = 0.0
		_update_planet_targets()
		_update_asteroid_targets()
		_update_colony_targets()

	# Lerp at a rate that keeps up with high sim speeds
	# At high speed, targets jump far — use a higher lerp factor to keep up
	var t := minf(LERP_SPEED * delta, 1.0)

	# Interpolate planet positions and labels
	for i in range(_planet_positions.size()):
		var target: Vector2 = _planet_targets[i]
		var current: Vector2 = _planet_positions[i]
		# If target jumped very far (high sim speed), snap instead of lerping
		if current.distance_to(target) > 20.0:
			_planet_positions[i] = target
		else:
			_planet_positions[i] = current.lerp(target, t)
		if i < _planet_labels.size():
			_planet_labels[i].position = _planet_positions[i]

	# Interpolate asteroid markers
	for marker in asteroid_markers.get_children():
		if marker.has_meta("target_pos"):
			var target: Vector2 = marker.get_meta("target_pos")
			if marker.position.distance_to(target) > 20.0:
				marker.position = target
			else:
				marker.position = marker.position.lerp(target, t)

	# Snap colony markers directly (no lerp — moon colonies orbit too fast for lerp)
	for marker in _colony_markers:
		if marker.has_meta("target_pos"):
			marker.position = marker.get_meta("target_pos")

	# Apply label anti-overlap (throttled - O(N²) is expensive!)
	_label_overlap_timer += delta
	if _label_overlap_timer >= LABEL_OVERLAP_INTERVAL:
		_label_overlap_timer = 0.0
		_adjust_labels_to_prevent_overlap()

	# Follow selected ship
	if _following_ship:
		camera.position = _following_ship.position_au * AU_PIXELS

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
	var now := Time.get_ticks_msec()
	if now - _last_tick_msec < TICK_THROTTLE_MSEC:
		return
	_last_tick_msec = now
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
	# Cancel dispatch mode on Escape
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE and _map_selected_ship != null:
			_set_map_selected_ship(null)
			get_viewport().set_input_as_handled()
			return

	# Mouse controls
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_dragging = true
				_drag_start = mb.position
			else:
				# Check if this was a click (not a drag)
				if mb.position.distance_to(_drag_start) < 5.0:
					if _map_selected_ship != null:
						_try_dispatch_to(mb.position)
					else:
						_try_select_ship_at(mb.position)
				_dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			if _map_selected_ship != null:
				_set_map_selected_ship(null)
				get_viewport().set_input_as_handled()
				return
		elif mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_level = clampf(_zoom_level + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			camera.zoom = Vector2(_zoom_level, _zoom_level)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_level = clampf(_zoom_level - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			camera.zoom = Vector2(_zoom_level, _zoom_level)
	elif event is InputEventMouseMotion and _dragging:
		var motion := event as InputEventMouseMotion
		camera.position -= motion.relative / camera.zoom
		_following_ship = null  # Stop following on manual pan

	# Trackpad pinch-to-zoom (macOS)
	if event is InputEventMagnifyGesture:
		var magnify := event as InputEventMagnifyGesture
		_zoom_level = clampf(_zoom_level * magnify.factor, ZOOM_MIN, ZOOM_MAX)
		camera.zoom = Vector2(_zoom_level, _zoom_level)

	# Trackpad pan gesture (macOS two-finger scroll)
	if event is InputEventPanGesture:
		var pan := event as InputEventPanGesture
		camera.position += pan.delta * 20.0 / camera.zoom
		_following_ship = null  # Stop following on manual pan

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
			_following_ship = null  # Stop following on touch pan
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
	_free_children(ship_selector_panel)
	_ship_buttons.clear()

	# Add button for each ship
	for ship in GameState.ships:
		var btn := Button.new()
		btn.text = ship.ship_name
		btn.custom_minimum_size = Vector2(120, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Color code by status
		if ship.is_derelict:
			btn.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		elif ship.is_docked:
			btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		elif ship.is_idle_remote:
			btn.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		else:
			btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))

		btn.pressed.connect(_on_ship_selector_pressed.bind(ship))
		ship_selector_panel.add_child(btn)
		_ship_buttons[ship] = btn

	# Re-apply selection border if a ship is still selected
	if _map_selected_ship and _map_selected_ship in _ship_buttons:
		_apply_selection_border(_ship_buttons[_map_selected_ship], true)

func _center_on_ship(ship: Ship) -> void:
	_following_ship = ship
	camera.position = ship.position_au * AU_PIXELS

func _setup_dispatch_hint_label() -> void:
	_dispatch_hint_label = Label.new()
	_dispatch_hint_label.text = "Select destination on map (RMB to cancel)"
	_dispatch_hint_label.add_theme_font_size_override("font_size", 14)
	_dispatch_hint_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	_dispatch_hint_label.anchors_preset = Control.PRESET_BOTTOM_WIDE
	_dispatch_hint_label.anchor_top = 1.0
	_dispatch_hint_label.anchor_bottom = 1.0
	_dispatch_hint_label.offset_top = -30
	_dispatch_hint_label.offset_bottom = 0
	_dispatch_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dispatch_hint_label.visible = false
	$UI.add_child(_dispatch_hint_label)

func _on_ship_selector_pressed(ship: Ship) -> void:
	_center_on_ship(ship)
	if ship.is_docked:
		_set_map_selected_ship(ship)

func _apply_selection_border(btn: Button, selected: bool) -> void:
	if selected:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.15, 0.15, 0.15)
		style.border_color = Color(0.3, 0.9, 0.5)
		style.set_border_width_all(2)
		style.set_corner_radius_all(3)
		btn.add_theme_stylebox_override("normal", style)
		btn.add_theme_stylebox_override("hover", style)
	else:
		btn.remove_theme_stylebox_override("normal")
		btn.remove_theme_stylebox_override("hover")

func _set_map_selected_ship(ship: Ship) -> void:
	_map_selected_ship = ship
	for s in _ship_buttons:
		_apply_selection_border(_ship_buttons[s], s == ship)
	if _dispatch_hint_label:
		_dispatch_hint_label.visible = ship != null

func _try_dispatch_to(screen_pos: Vector2) -> void:
	var world_pos := camera.position + (screen_pos - get_viewport_rect().size / 2.0) / camera.zoom
	# Check asteroids
	for asteroid: AsteroidData in GameState.asteroids:
		var asteroid_px := asteroid.get_position_au() * AU_PIXELS
		if world_pos.distance_to(asteroid_px) < 40.0:
			EventBus.map_dispatch_to_asteroid.emit(_map_selected_ship, asteroid)
			_set_map_selected_ship(null)
			return
	# Check colonies
	for colony: Colony in GameState.colonies:
		var colony_px := colony.get_position_au() * AU_PIXELS
		if world_pos.distance_to(colony_px) < 40.0:
			EventBus.map_dispatch_to_colony.emit(_map_selected_ship, colony)
			_set_map_selected_ship(null)
			return
	# Empty space — no-op

func _try_select_ship_at(screen_pos: Vector2) -> void:
	# Convert screen position to world position
	var world_pos := camera.position + (screen_pos - get_viewport_rect().size / 2.0) / camera.zoom
	var best_ship: Ship = null
	var best_dist := 30.0  # Max click distance in pixels (generous for touch)
	for ship in GameState.ships:
		var ship_px := ship.position_au * AU_PIXELS
		var dist := world_pos.distance_to(ship_px)
		if dist < best_dist:
			best_dist = dist
			best_ship = ship
	if best_ship:
		_center_on_ship(best_ship)

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
