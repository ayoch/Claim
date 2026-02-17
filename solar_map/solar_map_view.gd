extends Node2D

const AU_PIXELS: float = 200.0  # 1 AU = 200 pixels
const BELT_INNER_AU: float = 1.5
const BELT_OUTER_AU: float = 3.5

@onready var camera: Camera2D = $Camera2D
@onready var asteroid_markers: Node2D = $AsteroidMarkers
@onready var ship_markers: Node2D = $ShipMarkers

var _drag_start: Vector2 = Vector2.ZERO
var _dragging: bool = false
var _zoom_level: float = 1.0
const ZOOM_MIN: float = 0.3
const ZOOM_MAX: float = 3.0
const ZOOM_STEP: float = 0.1

# Touch/pinch zoom state
var _touches: Dictionary = {}  # finger index -> position
var _last_pinch_distance: float = -1.0

var asteroid_marker_scene: PackedScene = preload("res://solar_map/asteroid_marker.tscn")
var ship_marker_scene: PackedScene = preload("res://solar_map/ship_marker.tscn")

func _ready() -> void:
	_spawn_asteroid_markers()
	EventBus.mission_started.connect(func(_m: Mission) -> void: _refresh_ship_markers())
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _refresh_ship_markers())
	EventBus.tick.connect(_on_tick)

func _draw() -> void:
	# Draw sun
	draw_circle(Vector2.ZERO, 15, Color(1.0, 0.9, 0.3))

	# Draw Earth orbit
	_draw_circle_outline(Vector2.ZERO, CelestialData.EARTH_ORBIT_AU * AU_PIXELS, Color(0.2, 0.4, 0.8, 0.3), 1.0)

	# Draw Earth marker
	var earth_pos := Vector2(CelestialData.EARTH_ORBIT_AU * AU_PIXELS, 0)
	draw_circle(earth_pos, 6, Color(0.2, 0.5, 1.0))

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

func _draw_circle_outline(center: Vector2, radius: float, color: Color, width: float) -> void:
	var points := 64
	for i in range(points):
		var angle_from := (float(i) / points) * TAU
		var angle_to := (float(i + 1) / points) * TAU
		var from := center + Vector2(cos(angle_from), sin(angle_from)) * radius
		var to := center + Vector2(cos(angle_to), sin(angle_to)) * radius
		draw_line(from, to, color, width)

func _spawn_asteroid_markers() -> void:
	for asteroid in GameState.asteroids:
		var marker: Node2D = asteroid_marker_scene.instantiate()
		marker.asteroid = asteroid
		# Place at orbit distance, spread around the circle
		var angle := randf() * TAU
		marker.position = Vector2(cos(angle), sin(angle)) * asteroid.orbit_au * AU_PIXELS
		asteroid_markers.add_child(marker)

func _refresh_ship_markers() -> void:
	for child in ship_markers.get_children():
		child.queue_free()
	for mission: Mission in GameState.missions:
		var marker: Node2D = ship_marker_scene.instantiate()
		marker.mission = mission
		ship_markers.add_child(marker)

func _on_tick(_dt: float) -> void:
	_update_ship_positions()
	queue_redraw()

func _update_ship_positions() -> void:
	for marker in ship_markers.get_children():
		if marker.has_method("update_position"):
			marker.update_position()

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
			# Wheel up = zoom in (increase zoom value)
			_zoom_level = clampf(_zoom_level + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
			camera.zoom = Vector2(_zoom_level, _zoom_level)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			# Wheel down = zoom out (decrease zoom value)
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
			# Single finger drag = pan
			camera.position -= drag.relative / camera.zoom
		elif _touches.size() == 2:
			# Two finger pinch = zoom
			var points := _touches.values()
			var dist: float = (points[0] as Vector2).distance_to(points[1] as Vector2)
			if _last_pinch_distance > 0:
				var diff := dist - _last_pinch_distance
				_zoom_level = clampf(_zoom_level + diff * 0.005, ZOOM_MIN, ZOOM_MAX)
				camera.zoom = Vector2(_zoom_level, _zoom_level)
			_last_pinch_distance = dist
