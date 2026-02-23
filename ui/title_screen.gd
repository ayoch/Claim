extends Control

@onready var new_game_btn: Button = %NewGameButton
@onready var load_game_btn: Button = %LoadGameButton
@onready var online_btn: Button = %OnlineButton
@onready var settings_btn: Button = %SettingsButton
@onready var quit_btn: Button = %QuitButton

func _ready() -> void:
	# Check if save file exists to enable/disable Load button
	load_game_btn.disabled = not FileAccess.file_exists("user://save_game.json")

	# Connect buttons
	new_game_btn.pressed.connect(_on_new_game)
	load_game_btn.pressed.connect(_on_load_game)
	quit_btn.pressed.connect(_on_quit)

func _on_new_game() -> void:
	# Delete existing save if any
	if FileAccess.file_exists("user://save_game.json"):
		DirAccess.remove_absolute("user://save_game.json")

	# Reset GameState to fresh start
	GameState._ready()

	# Load main game scene
	get_tree().change_scene_to_file("res://ui/main_ui.tscn")

func _on_load_game() -> void:
	# Load the save file
	if GameState.load_game():
		# Load main game scene
		get_tree().change_scene_to_file("res://ui/main_ui.tscn")
	else:
		# Show error (for now just disable the button)
		load_game_btn.disabled = true

func _on_quit() -> void:
	get_tree().quit()
