extends Control

@onready var new_game_btn: Button = %NewGameButton
@onready var load_game_btn: Button = %LoadGameButton
@onready var leaderboards_btn: Button = %LeaderboardsButton
@onready var online_btn: Button = %OnlineButton
@onready var settings_btn: Button = %SettingsButton
@onready var quit_btn: Button = %QuitButton
@onready var status_light: ColorRect = %StatusLight
@onready var status_label: Label = %StatusLabel

var http_request: HTTPRequest

func _ready() -> void:
	# Check if save file exists to enable/disable Load button
	load_game_btn.disabled = not FileAccess.file_exists("user://save_game.json")

	# Connect buttons
	new_game_btn.pressed.connect(_on_new_game)
	load_game_btn.pressed.connect(_on_load_game)
	leaderboards_btn.pressed.connect(_on_leaderboards)
	quit_btn.pressed.connect(_on_quit)

	# Check server status
	_check_server_status()

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

func _on_leaderboards() -> void:
	get_tree().change_scene_to_file("res://ui/leaderboards_screen.tscn")

func _on_quit() -> void:
	get_tree().quit()


func _check_server_status() -> void:
	# Create HTTP request node
	http_request = HTTPRequest.new()
	add_child(http_request)
	http_request.request_completed.connect(_on_server_status_received)

	# For now, check localhost:3000/health (local server)
	# Later this will be changed to the production server URL
	var url := "http://localhost:3000/health"
	print("Checking server status at: ", url)
	var error := http_request.request(url)

	if error != OK:
		print("HTTP request failed with error: ", error)
		_set_server_status(false, "Server: Error")


func _on_server_status_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	print("Server response - Result: ", result, " Code: ", response_code)
	print("Response body: ", body.get_string_from_utf8())

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		_set_server_status(true, "Server: Online")
	else:
		var status_msg := "Server: "
		match result:
			HTTPRequest.RESULT_CANT_CONNECT:
				status_msg += "Can't Connect"
			HTTPRequest.RESULT_CANT_RESOLVE:
				status_msg += "Can't Resolve"
			HTTPRequest.RESULT_CONNECTION_ERROR:
				status_msg += "Connection Error"
			HTTPRequest.RESULT_TIMEOUT:
				status_msg += "Timeout"
			_:
				status_msg += "Offline (Code: %d)" % response_code
		_set_server_status(false, status_msg)

	# Clean up
	if http_request:
		http_request.queue_free()


func _set_server_status(online: bool, label_text: String) -> void:
	if online:
		status_light.color = Color(0.2, 0.8, 0.2, 1.0)  # Green
	else:
		status_light.color = Color(0.8, 0.2, 0.2, 1.0)  # Red

	status_label.text = label_text
