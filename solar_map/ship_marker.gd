extends Node2D

const AU_PIXELS: float = 200.0
const MOVE_SMOOTHING: float = 8.0  # lerp speed for smooth movement

var mission: Mission = null

# Cache positions for interpolation
var _earth_pos: Vector2 = Vector2.ZERO
var _asteroid_pos: Vector2 = Vector2.ZERO
var _target_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	if mission:
		$Label.text = mission.ship.ship_name
		_earth_pos = Vector2(CelestialData.EARTH_ORBIT_AU * AU_PIXELS, 0)
		_find_asteroid_position()
		_update_target()
		position = _target_pos  # snap to start

func _process(delta: float) -> void:
	if not mission:
		return
	_update_target()
	# Smooth interpolation toward the target each frame
	position = position.lerp(_target_pos, minf(MOVE_SMOOTHING * delta, 1.0))
	queue_redraw()

func _find_asteroid_position() -> void:
	var map_view := get_parent().get_parent()  # ShipMarkers -> SolarMapView
	if map_view and map_view.has_node("AsteroidMarkers"):
		for marker in map_view.get_node("AsteroidMarkers").get_children():
			if marker.asteroid == mission.asteroid:
				_asteroid_pos = marker.position
				return
	# Fallback: calculate position
	var angle := randf() * TAU
	_asteroid_pos = Vector2(cos(angle), sin(angle)) * mission.asteroid.orbit_au * AU_PIXELS

func _update_target() -> void:
	var progress := mission.get_progress()
	match mission.status:
		Mission.Status.TRANSIT_OUT:
			_target_pos = _earth_pos.lerp(_asteroid_pos, progress)
		Mission.Status.MINING:
			_target_pos = _asteroid_pos
		Mission.Status.TRANSIT_BACK:
			_target_pos = _asteroid_pos.lerp(_earth_pos, progress)

func update_position() -> void:
	_update_target()

func _draw() -> void:
	draw_circle(Vector2.ZERO, 6, Color(0.3, 0.9, 0.5))
	# Draw direction indicator
	if mission and mission.status != Mission.Status.MINING:
		var dir := Vector2.RIGHT
		if mission.status == Mission.Status.TRANSIT_OUT:
			dir = (_asteroid_pos - _earth_pos).normalized()
		else:
			dir = (_earth_pos - _asteroid_pos).normalized()
		draw_line(Vector2.ZERO, dir * 10, Color(0.3, 0.9, 0.5, 0.7), 2.0)
