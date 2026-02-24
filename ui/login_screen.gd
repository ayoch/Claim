extends Control

@onready var username_input: LineEdit = %UsernameInput
@onready var password_input: LineEdit = %PasswordInput
@onready var status_label: Label = %StatusLabel
@onready var login_btn: Button = %LoginButton
@onready var register_btn: Button = %RegisterButton
@onready var back_btn: Button = %BackButton

var is_processing: bool = false


func _ready() -> void:
	# Connect buttons
	login_btn.pressed.connect(_on_login)
	register_btn.pressed.connect(_on_register)
	back_btn.pressed.connect(_on_back)

	# Connect enter key to login
	username_input.text_submitted.connect(func(_text): _on_login())
	password_input.text_submitted.connect(func(_text): _on_login())

	# Focus username field
	username_input.grab_focus()


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

	# Switch to server backend
	BackendManager.switch_mode(BackendManager.BackendMode.SERVER)

	# Attempt login
	var result: Dictionary = await BackendManager.login(username, password)

	if result.get("success", false):
		_show_status("Login successful! Loading game...", Color(0.3, 0.9, 0.3))
		await get_tree().create_timer(1.0).timeout
		# Load main game scene
		get_tree().change_scene_to_file("res://ui/main_ui.tscn")
	else:
		var error_msg: String = result.get("error", "Login failed")
		_show_status("Login failed: " + error_msg, Color(0.9, 0.3, 0.3))
		_set_processing(false)
		# Switch back to local mode on failure
		BackendManager.switch_mode(BackendManager.BackendMode.LOCAL)


func _on_register() -> void:
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

	if username.length() < 3:
		_show_status("Username must be at least 3 characters", Color(0.9, 0.3, 0.3))
		return

	if password.length() < 6:
		_show_status("Password must be at least 6 characters", Color(0.9, 0.3, 0.3))
		return

	# Disable inputs while processing
	_set_processing(true)
	_show_status("Creating account...", Color(0.8, 0.8, 0.8))

	# Switch to server backend
	BackendManager.switch_mode(BackendManager.BackendMode.SERVER)

	# Attempt registration
	var result: Dictionary = await BackendManager.register(username, password)

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
	password_input.editable = not processing
	login_btn.disabled = processing
	register_btn.disabled = processing
	back_btn.disabled = processing


func _show_status(message: String, color: Color) -> void:
	status_label.text = message
	status_label.add_theme_color_override("font_color", color)
