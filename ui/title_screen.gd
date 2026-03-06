extends Control

@onready var new_game_btn: Button = %NewGameButton
@onready var load_game_btn: Button = %LoadGameButton
@onready var leaderboards_btn: Button = %LeaderboardsButton
@onready var online_btn: Button = %OnlineButton
@onready var settings_btn: Button = %SettingsButton
@onready var quit_btn: Button = %QuitButton
@onready var status_icon: TextureRect = %StatusIcon
@onready var status_label: Label = %StatusLabel

# Server status icons
var icon_connected := preload("res://ui/assets/icons/ServerConnected.png")
var icon_connecting := preload("res://ui/assets/icons/Server_Connecting.png")
var icon_not_connected := preload("res://ui/assets/icons/Server_NotConnected.png")

var http_request: HTTPRequest
var _save_load_dialog: PopupPanel = null

func _ready() -> void:
	# Set up save/load dialog
	var dialog_scene := load("res://ui/save_load_dialog.tscn")
	if dialog_scene:
		_save_load_dialog = dialog_scene.instantiate()
		add_child(_save_load_dialog)
		_save_load_dialog.load_confirmed.connect(_on_load_confirmed)

	# Check if any save files exist to enable/disable Load button
	load_game_btn.disabled = not _has_any_saves()

	# Check for expired token and clear it
	_check_and_clear_expired_token()

	# Connect buttons
	new_game_btn.pressed.connect(_on_new_game)
	load_game_btn.pressed.connect(_on_load_game)
	leaderboards_btn.pressed.connect(_on_leaderboards)
	online_btn.pressed.connect(_on_online)
	settings_btn.pressed.connect(_on_settings)
	quit_btn.pressed.connect(_on_quit)

	# Check server status
	_check_server_status()

func _on_new_game() -> void:
	# CRITICAL: Switch to LOCAL mode for offline single-player
	BackendManager.switch_mode(BackendManager.BackendMode.LOCAL)

	# Delete existing save if any
	if FileAccess.file_exists("user://save_game.json"):
		DirAccess.remove_absolute("user://save_game.json")

	# Reset GameState to fresh start
	GameState.new_game()

	# Load main game scene
	get_tree().change_scene_to_file("res://ui/main_ui.tscn")

func _on_load_game() -> void:
	# CRITICAL: Switch to LOCAL mode for offline single-player
	BackendManager.switch_mode(BackendManager.BackendMode.LOCAL)

	# Open load dialog to select save
	if _save_load_dialog:
		_save_load_dialog.open_load_dialog()


func _on_load_confirmed(file_name: String) -> void:
	if GameState.load_game(file_name):
		# Load main game scene
		get_tree().change_scene_to_file("res://ui/main_ui.tscn")
	else:
		print("Failed to load save: ", file_name)


func _has_any_saves() -> bool:
	var dir := DirAccess.open("user://")
	if not dir:
		return false

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and (file_name.begins_with("save_") or file_name == "save_game.json"):
			dir.list_dir_end()
			return true
		file_name = dir.get_next()
	dir.list_dir_end()
	return false

func _on_leaderboards() -> void:
	get_tree().change_scene_to_file("res://ui/leaderboards_screen.tscn")

func _on_online() -> void:
	get_tree().change_scene_to_file("res://ui/login_screen.tscn")

func _on_settings() -> void:
	get_tree().change_scene_to_file("res://ui/settings_screen.tscn")

func _on_quit() -> void:
	get_tree().quit()


func _check_server_status() -> void:
	var server_backend = BackendManager.get_server_backend()
	if not is_instance_valid(server_backend):
		_set_server_status(false, "Server: Offline")
		return

	# If already logged in and in SERVER mode, show as connected immediately
	# (Skip the "connecting" flicker - we already know we're connected)
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER and server_backend.player_id > 0:
		_set_server_status(true, "Server: Online (Logged In)")
		return

	# Create HTTP request node
	http_request = HTTPRequest.new()
	# Use proper TLS options - accept valid certificates but bypass for self-signed
	var tls_options := TLSOptions.client()
	http_request.set_tls_options(tls_options)
	add_child(http_request)
	http_request.request_completed.connect(_on_server_status_received)

	# Set connecting state (only shown when not already logged in)
	status_icon.texture = icon_connecting
	status_label.text = "Server: Checking..."

	var url: String = server_backend.base_url + "/health"
	print("Checking server status at: ", url)

	# Set timeout to 10 seconds
	http_request.timeout = 10.0

	var error := http_request.request(url)

	if error != OK:
		print("HTTP request failed with error code: ", error)
		var error_msg := ""
		match error:
			ERR_CANT_CONNECT:
				error_msg = "Can't Connect"
			ERR_CANT_RESOLVE:
				error_msg = "Can't Resolve DNS"
			ERR_CONNECTION_ERROR:
				error_msg = "Connection Error"
			_:
				error_msg = "Error %d" % error
		_set_server_status(false, "Server: " + error_msg)


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
		status_icon.texture = icon_connected
		online_btn.disabled = false
	else:
		status_icon.texture = icon_not_connected
		online_btn.disabled = true

	status_label.text = label_text


func _check_and_clear_expired_token() -> void:
	"""Check if stored token is expired and clear it if so"""
	var server_backend = BackendManager.get_server_backend()
	if not is_instance_valid(server_backend):
		return

	var token: String = server_backend.auth_token
	if token == "":
		return

	# Parse JWT token to check expiration
	var parts := token.split(".")
	if parts.size() != 3:
		print("Invalid token format, clearing")
		server_backend.auth_token = ""
		server_backend.player_id = 0
		return

	# Decode payload (base64url)
	var payload_b64: String = parts[1]
	# Add padding if needed
	while payload_b64.length() % 4 != 0:
		payload_b64 += "="
	# Replace base64url chars with base64
	payload_b64 = payload_b64.replace("-", "+").replace("_", "/")

	var payload_bytes := Marshalls.base64_to_raw(payload_b64)
	var payload_str := payload_bytes.get_string_from_utf8()

	# Parse JSON
	var json := JSON.new()
	var parse_result := json.parse(payload_str)
	if parse_result != OK:
		print("Failed to parse token, clearing")
		server_backend.auth_token = ""
		server_backend.player_id = 0
		return

	var payload: Dictionary = json.data
	var exp: int = payload.get("exp", 0)

	if exp == 0:
		print("Token has no expiration, keeping it")
		return

	# Check if expired
	var current_time := Time.get_unix_time_from_system()
	if current_time >= exp:
		print("Token expired, clearing (expired at %d, now is %d)" % [exp, int(current_time)])
		server_backend.auth_token = ""
		server_backend.player_id = 0
		# Switch back to LOCAL mode
		BackendManager.switch_mode(BackendManager.BackendMode.LOCAL)
	else:
		var seconds_left := exp - int(current_time)
		print("Token still valid (%d seconds remaining)" % seconds_left)
