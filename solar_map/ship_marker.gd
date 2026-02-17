extends Node2D

const AU_PIXELS: float = 200.0
const MOVE_SMOOTHING: float = 8.0  # lerp speed for smooth movement

var mission: Mission = null
var trade_mission: TradeMission = null

# Cache positions for interpolation
var _target_pos: Vector2 = Vector2.ZERO

func _ready() -> void:
	if mission:
		$Label.text = mission.ship.ship_name
		_update_target()
		position = _target_pos  # snap to start
	elif trade_mission:
		$Label.text = trade_mission.ship.ship_name
		_update_target()
		position = _target_pos

func _process(delta: float) -> void:
	if not mission and not trade_mission:
		return
	_update_target()
	# Smooth interpolation toward the target each frame
	position = position.lerp(_target_pos, minf(MOVE_SMOOTHING * delta, 1.0))
	queue_redraw()

func _get_earth_pos() -> Vector2:
	return CelestialData.get_earth_position_au() * AU_PIXELS

func _update_target() -> void:
	if mission:
		_update_mining_target()
	elif trade_mission:
		_update_trade_target()

func _update_mining_target() -> void:
	var earth_pos := _get_earth_pos()
	var asteroid_pos := mission.asteroid.get_position_au() * AU_PIXELS
	var progress := mission.get_progress()

	match mission.status:
		Mission.Status.TRANSIT_OUT:
			_target_pos = earth_pos.lerp(asteroid_pos, progress)
		Mission.Status.MINING:
			_target_pos = asteroid_pos
		Mission.Status.TRANSIT_BACK:
			_target_pos = asteroid_pos.lerp(earth_pos, progress)

func _update_trade_target() -> void:
	var earth_pos := _get_earth_pos()
	var colony_pos := trade_mission.colony.get_position_au() * AU_PIXELS
	var progress := trade_mission.get_progress()

	match trade_mission.status:
		TradeMission.Status.TRANSIT_TO_COLONY:
			_target_pos = earth_pos.lerp(colony_pos, progress)
		TradeMission.Status.SELLING:
			_target_pos = colony_pos
		TradeMission.Status.TRANSIT_BACK:
			_target_pos = colony_pos.lerp(earth_pos, progress)

func update_position() -> void:
	_update_target()

func _draw() -> void:
	var color := Color(0.3, 0.9, 0.5)
	if trade_mission:
		color = Color(0.3, 0.9, 0.9)  # Cyan for trade ships

	draw_circle(Vector2.ZERO, 6, color)
	# Draw direction indicator
	var is_transit := false
	var dir := Vector2.RIGHT

	if mission and mission.status != Mission.Status.MINING:
		is_transit = true
		var earth_pos := _get_earth_pos()
		var asteroid_pos := mission.asteroid.get_position_au() * AU_PIXELS
		if mission.status == Mission.Status.TRANSIT_OUT:
			dir = (asteroid_pos - earth_pos).normalized()
		else:
			dir = (earth_pos - asteroid_pos).normalized()
	elif trade_mission and trade_mission.status != TradeMission.Status.SELLING:
		is_transit = true
		var earth_pos := _get_earth_pos()
		var colony_pos := trade_mission.colony.get_position_au() * AU_PIXELS
		if trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY:
			dir = (colony_pos - earth_pos).normalized()
		else:
			dir = (earth_pos - colony_pos).normalized()

	if is_transit:
		draw_line(Vector2.ZERO, dir * 10, Color(color.r, color.g, color.b, 0.7), 2.0)
