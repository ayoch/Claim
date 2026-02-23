extends Control

const TEXTURE_PATH: String = "res://ui/starfields/StarfieldNebula1.png"
const PAN_SPEED: float = 12.0        # pixels per second
const SCALE_FACTOR: float = 1.4      # extra scale beyond cover — sets panning room
const ARC_CHANGE_INTERVAL_MIN: float = 4.0
const ARC_CHANGE_INTERVAL_MAX: float = 10.0
const MAX_ANGULAR_VEL: float = 0.4   # radians/s max curve rate

var _texture: Texture2D = null
var _offset: Vector2 = Vector2.ZERO
var _direction: float = 0.0          # current travel angle (radians)
var _angular_vel: float = 0.0        # how fast the arc curves
var _arc_timer: float = 0.0

func _ready() -> void:
	_texture = load(TEXTURE_PATH)
	_direction = randf() * TAU
	_angular_vel = randf_range(-MAX_ANGULAR_VEL, MAX_ANGULAR_VEL)
	_arc_timer = randf_range(ARC_CHANGE_INTERVAL_MIN, ARC_CHANGE_INTERVAL_MAX)

func _process(delta: float) -> void:
	if not _texture:
		return

	# Slowly curve the travel direction
	_direction += _angular_vel * delta

	# Occasionally pick a new arc curvature
	_arc_timer -= delta
	if _arc_timer <= 0.0:
		_angular_vel = randf_range(-MAX_ANGULAR_VEL, MAX_ANGULAR_VEL)
		_arc_timer = randf_range(ARC_CHANGE_INTERVAL_MIN, ARC_CHANGE_INTERVAL_MAX)

	# Move offset along current direction
	_offset += Vector2(cos(_direction), sin(_direction)) * PAN_SPEED * delta

	# Steer back toward center when drifting too far
	var max_off := (_get_draw_size() - size) * 0.5
	if max_off.x > 0.0 and max_off.y > 0.0:
		var norm := Vector2(_offset.x / max_off.x, _offset.y / max_off.y)
		if norm.length() > 0.65:
			var toward_center := (-_offset).angle()
			var diff := angle_difference(_direction, toward_center)
			# Steer harder the further out we are
			var steer := norm.length() * 2.0
			_direction += sign(diff) * steer * delta
			_offset.x = clampf(_offset.x, -max_off.x, max_off.x)
			_offset.y = clampf(_offset.y, -max_off.y, max_off.y)

	queue_redraw()

func _get_draw_size() -> Vector2:
	if not _texture:
		return size
	var tex_size := Vector2(_texture.get_width(), _texture.get_height())
	var cover_scale := maxf(size.x / tex_size.x, size.y / tex_size.y)
	return tex_size * cover_scale * SCALE_FACTOR

func _draw() -> void:
	if not _texture:
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.015, 0.02))
		return
	var draw_size := _get_draw_size()
	var top_left := (size - draw_size) * 0.5 + _offset
	draw_texture_rect(_texture, Rect2(top_left, draw_size), false)
