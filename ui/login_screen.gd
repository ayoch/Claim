extends Control

@onready var username_input: LineEdit = %UsernameInput
@onready var email_input: LineEdit = %EmailInput
@onready var password_input: LineEdit = %PasswordInput
@onready var status_label: Label = %StatusLabel
@onready var login_btn: Button = %LoginButton
@onready var register_btn: Button = %RegisterButton
@onready var back_btn: Button = %BackButton

var is_processing: bool = false
var continue_session_btn: Button = null


func _ready() -> void:
	# Switch to SERVER mode once at the start (prevents multiple resets)
	BackendManager.switch_mode(BackendManager.BackendMode.SERVER)

	# Hide email field - only needed for registration
	email_input.visible = false
	if email_input.get_parent() and email_input.get_parent().get_class() == "VBoxContainer":
		# Also hide the email label if it exists
		var email_label = email_input.get_parent().get_node_or_null("EmailLabel")
		if email_label:
			email_label.visible = false

	# Connect buttons
	login_btn.pressed.connect(_on_login)
	register_btn.pressed.connect(_on_go_to_register)
	back_btn.pressed.connect(_on_back)

	# Connect enter key to login
	username_input.text_submitted.connect(func(_text): _on_login())
	password_input.text_submitted.connect(func(_text): _on_login())

	# Load saved username if exists
	_load_saved_username()

	# Check for saved session and show "Continue as..." button if exists
	await _check_saved_session()

	# Focus appropriate field: password if username filled, otherwise username
	if username_input.text.strip_edges() != "":
		password_input.grab_focus()
	else:
		username_input.grab_focus()


func _load_saved_username() -> void:
	"""Load and populate saved username"""
	var server_backend = BackendManager.get_server_backend()
	if server_backend:
		var saved_user: String = server_backend.get_saved_username()
		if saved_user != "":
			username_input.text = saved_user


func _check_saved_session() -> void:
	"""Check if there's a saved session and show continue button if so"""
	var server_backend = BackendManager.get_server_backend()
	if not server_backend or not server_backend.has_saved_session():
		return

	# Create "Continue as [username]" button
	continue_session_btn = Button.new()
	continue_session_btn.text = "Continue as " + server_backend.get_saved_username()
	continue_session_btn.custom_minimum_size = Vector2(200, 40)

	# Position it above the login button
	var login_parent = login_btn.get_parent()
	var login_index = login_btn.get_index()
	login_parent.add_child(continue_session_btn)
	login_parent.move_child(continue_session_btn, login_index)

	# Connect to session restore
	continue_session_btn.pressed.connect(_on_continue_session)


func _on_continue_session() -> void:
	"""User clicked 'Continue as...' button - restore saved session"""
	# Hide the continue button since they chose to use it
	if continue_session_btn:
		continue_session_btn.visible = false
	await _try_auto_login()


func _try_auto_login() -> void:
	"""Attempt auto-login with saved session token"""
	var server_backend = BackendManager.get_server_backend()

	if not server_backend:
		return

	if not server_backend.has_saved_session():
		return

	_show_status("Restoring session...", Color(0.8, 0.8, 0.8))
	_set_processing(true)

	# Verify token is still valid by fetching game state
	var state: Dictionary = await BackendManager.get_game_state()

	if state.has("player_id") and state.get("player_id", 0) > 0:
		# Token is valid, proceed to game
		_show_status("Session restored! Loading game...", Color(0.3, 0.9, 0.3))
		get_tree().change_scene_to_file("res://ui/main_ui.tscn")
	else:
		# Token expired or invalid, clear token but keep username
		server_backend.auth_token = ""
		server_backend.player_id = 0
		server_backend._clear_auth_data()
		_show_status("Session expired. Please log in.", Color(0.9, 0.6, 0.3))
		_set_processing(false)
		# Focus password field since username is already filled
		password_input.grab_focus()


func _on_login() -> void:
	if is_processing:
		return

	var username := username_input.text.strip_edges()
	var password := password_input.text

	# Validation
	if username.is_empty():
		_show_status("Username is required", Color(0.9, 0.3, 0.3))
		return

	if password.is_empty():
		_show_status("Password is required", Color(0.9, 0.3, 0.3))
		return

	# Disable inputs while processing
	_set_processing(true)
	_show_status("Logging in...", Color(0.8, 0.8, 0.8))

	# Attempt login (already in SERVER mode from _ready)
	var result: Dictionary = await BackendManager.login(username, password)

	if result.get("success", false):
		_show_status("Login successful! Loading game...", Color(0.3, 0.9, 0.3))
		get_tree().change_scene_to_file("res://ui/main_ui.tscn")
	else:
		var error_msg: String = result.get("error", "Login failed")
		_show_status("Login failed: " + error_msg, Color(0.9, 0.3, 0.3))
		_set_processing(false)
		# Switch back to local mode on failure
		BackendManager.switch_mode(BackendManager.BackendMode.LOCAL)


func _on_go_to_register() -> void:
	"""Navigate to registration screen"""
	get_tree().change_scene_to_file("res://ui/register_screen.tscn")


func _on_register() -> void:
	if is_processing:
		return

	var username := username_input.text.strip_edges()
	var email := email_input.text.strip_edges()
	var password := password_input.text

	# Validation
	if username.is_empty():
		_show_status("Username is required", Color(0.9, 0.3, 0.3))
		return

	if email.is_empty():
		_show_status("Email is required", Color(0.9, 0.3, 0.3))
		return

	if password.is_empty():
		_show_status("Password is required", Color(0.9, 0.3, 0.3))
		return

	if username.length() < 3:
		_show_status("Username must be at least 3 characters", Color(0.9, 0.3, 0.3))
		return

	# Basic email validation
	if not email.contains("@") or not email.contains("."):
		_show_status("Please enter a valid email address", Color(0.9, 0.3, 0.3))
		return

	if password.length() < 12:
		_show_status("Password: 12+ chars, upper, lower, number", Color(0.9, 0.3, 0.3))
		return

	# Disable inputs while processing
	_set_processing(true)
	_show_status("Creating account...", Color(0.8, 0.8, 0.8))

	# Switch to server backend
	BackendManager.switch_mode(BackendManager.BackendMode.SERVER)

	# Attempt registration
	var result: Dictionary = await BackendManager.register(username, password, email)

	if result.get("success", false):
		_show_status("Account created! Logging in...", Color(0.3, 0.9, 0.3))
		await get_tree().create_timer(1.0).timeout

		# Auto-login after successful registration
		var login_result: Dictionary = await BackendManager.login(username, password)
		if login_result.get("success", false):
			_show_status("Login successful! Loading game...", Color(0.3, 0.9, 0.3))
			await get_tree().create_timer(1.0).timeout
			get_tree().change_scene_to_file("res://ui/main_ui.tscn")
		else:
			_show_status("Account created but login failed. Please try logging in manually.", Color(0.9, 0.6, 0.3))
			_set_processing(false)
	else:
		var error_msg: String = result.get("error", "Registration failed")
		_show_status("Registration failed: " + error_msg, Color(0.9, 0.3, 0.3))
		_set_processing(false)
		# Switch back to local mode on failure
		BackendManager.switch_mode(BackendManager.BackendMode.LOCAL)


func _on_back() -> void:
	get_tree().change_scene_to_file("res://ui/title_screen.tscn")


func _set_processing(processing: bool) -> void:
	is_processing = processing
	username_input.editable = not processing
	email_input.editable = not processing
	password_input.editable = not processing
	login_btn.disabled = processing
	register_btn.disabled = processing
	back_btn.disabled = processing


func _show_status(message: String, color: Color) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", color)
