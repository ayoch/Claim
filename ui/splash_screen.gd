extends Control

@onready var logo: TextureRect = %Logo

const FADE_IN_DURATION := 1.0
const HOLD_DURATION := 1.5
const FADE_OUT_DURATION := 1.0

func _ready() -> void:
	# Load the logo texture
	var logo_texture := load("res://ui/assets/dark-river-logo.png")
	if logo_texture:
		logo.texture = logo_texture

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
