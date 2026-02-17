extends Control

const STAR_COUNT: int = 300
const TWINKLE_SPEED: float = 1.5

var _stars: Array[Dictionary] = []
var _time: float = 0.0

func _ready() -> void:
	_generate_stars()

func _generate_stars() -> void:
	_stars.clear()
	for i in range(STAR_COUNT):
		_stars.append({
			"pos": Vector2(randf(), randf()),  # normalized 0-1
			"size": randf_range(0.5, 2.5),
			"brightness": randf_range(0.3, 1.0),
			"twinkle_phase": randf() * TAU,
			"twinkle_amount": randf_range(0.0, 0.4),
		})

func _process(delta: float) -> void:
	_time += delta * TWINKLE_SPEED
	queue_redraw()

func _draw() -> void:
	# Deep space background
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.06))

	# Subtle nebula glow
	var center := size * 0.3
	for i in range(3):
		var nebula_pos := Vector2(
			size.x * (0.2 + i * 0.3),
			size.y * (0.3 + i * 0.15)
		)
		var nebula_radius := size.x * 0.4
		var nebula_color := Color(0.08, 0.04, 0.15, 0.15) if i % 2 == 0 else Color(0.04, 0.06, 0.15, 0.12)
		draw_circle(nebula_pos, nebula_radius, nebula_color)

	# Stars
	for star in _stars:
		var pos := Vector2(star["pos"].x * size.x, star["pos"].y * size.y)
		var base_bright: float = star["brightness"]
		var twinkle: float = star["twinkle_amount"]
		var phase: float = star["twinkle_phase"]
		var bright: float = base_bright + sin(_time + phase) * twinkle
		bright = clampf(bright, 0.1, 1.0)

		var star_size: float = star["size"]

		# Slight color variation: white/blue/yellow
		var color: Color
		if base_bright > 0.8:
			color = Color(0.8, 0.85, 1.0, bright)  # blue-white (bright stars)
		elif base_bright > 0.5:
			color = Color(1.0, 1.0, 0.95, bright)   # warm white
		else:
			color = Color(0.7, 0.7, 0.8, bright)     # dim blue-grey

		if star_size > 1.8:
			# Larger stars get a soft glow
			draw_circle(pos, star_size * 2.0, Color(color.r, color.g, color.b, bright * 0.15))
		draw_circle(pos, star_size, color)
