extends Control

@onready var logo: TextureRect = %Logo

const FADE_IN_DURATION := 1.0
const HOLD_DURATION := 1.5
const FADE_OUT_DURATION := 1.0

func _ready() -> void:
	# Load the logo texture
	var logo_texture := load("res://ui/assets/dark-river-logo-cropped.png")
	if logo_texture:
		logo.texture = logo_texture

	# Size logo to 30% of viewport, centered
	var vp := get_viewport_rect().size
	var logo_h := vp.y * 0.30
	var logo_w := logo_h  # cropped image is nearly square
	logo.set_anchor_and_offset(SIDE_LEFT,   0.5, -logo_w * 0.5)
	logo.set_anchor_and_offset(SIDE_RIGHT,  0.5,  logo_w * 0.5)
	logo.set_anchor_and_offset(SIDE_TOP,    0.5, -logo_h * 0.5)
	logo.set_anchor_and_offset(SIDE_BOTTOM, 0.5,  logo_h * 0.5)

	# Start fully transparent
	logo.modulate.a = 0.0

	# Create fade animation sequence
	var tween := create_tween()
	tween.set_ease(Tween.EASE_IN_OUT)
	tween.set_trans(Tween.TRANS_CUBIC)

	# Fade in
	tween.tween_property(logo, "modulate:a", 1.0, FADE_IN_DURATION)

	# Hold
	tween.tween_interval(HOLD_DURATION)

	# Fade out
	tween.tween_property(logo, "modulate:a", 0.0, FADE_OUT_DURATION)

	# Switch to title screen when done
	tween.tween_callback(_goto_title_screen)

func _goto_title_screen() -> void:
	get_tree().change_scene_to_file("res://ui/title_screen.tscn")
