extends Control

# Testing mode - set to false for release build
const TESTING_MODE: bool = true

@onready var money_display: Label = %MoneyDisplay
@onready var net_worth_display: Label = %NetWorthDisplay
@onready var tab_container: TabContainer = %TabContainer
@onready var top_bar_button_row: HBoxContainer = $VBox/TopBar/VBox/ButtonRow
@onready var speed_bar: PanelContainer = $VBox/SpeedBar
@onready var date_display: Label = %DateDisplay
@onready var save_btn: Button = $VBox/TopBar/VBox/ButtonRow/SaveBtn

var _settings_popup: PanelContainer = null
var _speed_input: LineEdit = null
var _speed_label: Label = null
var _stored_speed: float = 0.0
var _is_speed_paused: bool = false
var _date_update_timer: float = 0.0
const DATE_UPDATE_INTERVAL: float = 0.2  # Update date 5 times per second
var _net_worth_update_timer: float = 0.0
const NET_WORTH_UPDATE_INTERVAL: float = 1.0  # Update net worth once per second
var _save_load_dialog: PopupPanel = null
var _bug_report_dialog: AcceptDialog = null

# Loading overlay (SERVER mode only)
var _loading_overlay: Control = null
var _initial_state_loaded: bool = false
var _loading_timeout_timer: float = 0.0
const LOADING_TIMEOUT: float = 15.0  # Force-dismiss overlay after 15s if server never responds

# Server state polling (Phase 1)
var _server_poll_timer: float = 0.0
const SERVER_POLL_INTERVAL: float = 2.0  # Poll server every 2 seconds
var _polling_server: bool = false  # Prevents overlapping async calls

# Server speed display polling
var _server_speed_poll_timer: float = 0.0
const SERVER_SPEED_POLL_INTERVAL: float = 2.0  # Poll server speed every 2 seconds
var _polling_server_speed: bool = false

func _ready() -> void:
	# Position window lower on screen
	var screen_size := DisplayServer.screen_get_size()
	var window_size := DisplayServer.window_get_size()
	var new_pos := Vector2i(
		(screen_size.x - window_size.x) / 2,  # Centered horizontally
		(screen_size.y - window_size.y) / 2 + 150  # Centered vertically + 150 pixels down
	)
	DisplayServer.window_set_position(new_pos)

	EventBus.money_changed.connect(_on_money_changed)
	_on_money_changed(GameState.money)

	# Update net worth when relevant changes occur
	EventBus.ship_purchased.connect(func(_s: Ship, _c: int) -> void: _update_net_worth())
	EventBus.ship_sold.connect(func(_id: int) -> void: _update_net_worth())
	EventBus.resource_changed.connect(func(_type, _amount) -> void: _update_net_worth())
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _update_net_worth())
	EventBus.trade_mission_completed.connect(func(_tm: TradeMission) -> void: _update_net_worth())

	_update_net_worth()

	# Wire up Main Menu button
	var main_menu_btn: Button = top_bar_button_row.get_node("MainMenuBtn")
	if main_menu_btn:
		main_menu_btn.pressed.connect(_on_main_menu)

	# Wire up Save button visibility (signal already connected in .tscn)
	if save_btn:
		# Hide save button in multiplayer mode
		save_btn.visible = (BackendManager.current_mode == BackendManager.BackendMode.LOCAL)

	# Listen for backend mode changes
	EventBus.backend_mode_changed.connect(_on_backend_mode_changed)

	# Set up save/load dialog
	var dialog_scene := load("res://ui/save_load_dialog.tscn")
	if dialog_scene:
		_save_load_dialog = dialog_scene.instantiate()
		add_child(_save_load_dialog)
		_save_load_dialog.save_confirmed.connect(_on_save_confirmed)
		_save_load_dialog.load_confirmed.connect(_on_load_confirmed)

	# Set up bug report dialog
	var bug_dialog_scene := load("res://ui/bug_report_dialog.tscn")
	if bug_dialog_scene:
		_bug_report_dialog = bug_dialog_scene.instantiate()
		add_child(_bug_report_dialog)

	# Speed bar visible in both LOCAL and SERVER modes
	_setup_speed_bar()

	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		# Start server state polling (Phase 1)
		_server_poll_timer = 0.0  # Poll immediately on load
		_server_speed_poll_timer = 0.0  # Poll server speed immediately

		# Subscribe to server events (Phase 2)
		var server_backend = BackendManager.get_server_backend()
		if server_backend:
			server_backend.subscribe_events(Callable())

		_show_loading_overlay()

	_update_date_display()


func _exit_tree() -> void:
	# Cleanup server event subscription
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		var server_backend = BackendManager.get_server_backend()
		if server_backend:
			server_backend.unsubscribe_events()


func _process(delta: float) -> void:
	# Server state polling (Phase 1)
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		_server_poll_timer += delta
		if _server_poll_timer >= SERVER_POLL_INTERVAL and not _polling_server:
			_server_poll_timer = 0.0
			_poll_server_state()  # Async call (doesn't block)

		# Force-dismiss loading overlay if server is unresponsive
		if not _initial_state_loaded and _loading_overlay:
			_loading_timeout_timer += delta
			if _loading_timeout_timer >= LOADING_TIMEOUT:
				push_warning("Server did not respond within %.0fs — dismissing loading overlay" % LOADING_TIMEOUT)
				_initial_state_loaded = true
				_hide_loading_overlay()

		# Poll server speed for display
		_server_speed_poll_timer += delta
		if _server_speed_poll_timer >= SERVER_SPEED_POLL_INTERVAL and not _polling_server_speed:
			_server_speed_poll_timer = 0.0
			_poll_server_speed()  # Async call (doesn't block)

	# Throttle date display updates - doesn't need to be every frame
	_date_update_timer += delta
	if _date_update_timer >= DATE_UPDATE_INTERVAL:
		_update_date_display()
		_date_update_timer = 0.0

	# Throttle net worth updates - once per second is enough
	_net_worth_update_timer += delta
	if _net_worth_update_timer >= NET_WORTH_UPDATE_INTERVAL:
		_update_net_worth()
		_net_worth_update_timer = 0.0

	# Update speed display continuously to catch keyboard shortcuts
	if _speed_input and TimeScale.get_speed_display() != _speed_input.text:
		_update_speed_display()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		# Block speed controls for non-admins in SERVER mode
		var in_server_mode := BackendManager.current_mode == BackendManager.BackendMode.SERVER
		var is_speed_control: bool = event.keycode in [KEY_SPACE, KEY_1, KEY_2]

		if in_server_mode and is_speed_control and not BackendManager.is_admin():
			# Non-admin in SERVER mode - block speed controls
			get_viewport().set_input_as_handled()
			return

		if event.keycode == KEY_SPACE:
			_toggle_pause_speed()
			get_viewport().set_input_as_handled()

		# Speed control (1/2 keys)
		elif event.keycode == KEY_1 or event.keycode == KEY_2:
			if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
				# In SERVER mode (admin only - checked above), send speed changes to server
				_adjust_server_speed(event.keycode)
				get_viewport().set_input_as_handled()
			else:
				# In LOCAL mode, use TimeScale (existing behavior handled by TimeScale autoload)
				pass

func _toggle_pause_speed() -> void:
	# Space toggles between 1x and previous speed
	if TimeScale.speed_multiplier == 1.0 and _is_speed_paused:
		# At 1x and we stored a speed - restore it
		if _stored_speed > 0 and _stored_speed != 1.0:
			TimeScale.set_speed(_stored_speed)
		_is_speed_paused = false
	else:
		# Not at 1x, or at 1x but haven't stored - go to 1x
		_stored_speed = TimeScale.speed_multiplier
		TimeScale.set_speed(1.0)
		_is_speed_paused = true
	_update_speed_display()

func _update_date_display() -> void:
	if date_display:
		date_display.text = GameState.get_game_date_string()

func _setup_speed_bar() -> void:
	var hbox: HFlowContainer = speed_bar.get_node("HBox")

	# Speed display label on the left
	_speed_label = Label.new()
	_speed_label.text = TimeScale.get_speed_display()
	_speed_label.add_theme_font_size_override("font_size", 18)
	_speed_label.add_theme_color_override("font_color", Color(0.9, 0.9, 0.6))
	_speed_label.custom_minimum_size = Vector2(80, 0)
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(_speed_label)
	hbox.move_child(_speed_label, 0)

	# Wire decrease button
	var dec_btn: Button = hbox.get_node("DecBtn")
	dec_btn.pressed.connect(func() -> void:
		if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
			_adjust_server_speed(KEY_1)
		else:
			TimeScale.slow_down()
		_update_speed_display()
	)

	# Wire speed input
	_speed_input = hbox.get_node("SpeedInput")
	_speed_input.text = TimeScale.get_speed_display()
	_speed_input.text_submitted.connect(_on_speed_submitted)
	_speed_input.focus_exited.connect(_on_speed_focus_lost)

	# Wire increase button
	var inc_btn: Button = hbox.get_node("IncBtn")
	inc_btn.pressed.connect(func() -> void:
		if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
			_adjust_server_speed(KEY_2)
		else:
			TimeScale.speed_up()
		_update_speed_display()
	)

	# Wire preset buttons
	hbox.get_node("Preset1x").pressed.connect(func() -> void:
		if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
			_set_server_speed(1.0)
		else:
			TimeScale.set_speed(TimeScale.SPEED_REALTIME)
		_update_speed_display()
	)
	hbox.get_node("Preset20x").pressed.connect(func() -> void:
		if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
			_set_server_speed(100.0)
		else:
			TimeScale.set_speed(TimeScale.SPEED_NORMAL)
		_update_speed_display()
	)
	hbox.get_node("Preset100x").pressed.connect(func() -> void:
		if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
			_set_server_speed(100000.0)
		else:
			TimeScale.set_speed(TimeScale.SPEED_VERYFAST)
		_update_speed_display()
	)

func _on_speed_submitted(new_text: String) -> void:
	var new_speed := new_text.to_float()
	if new_speed > 0:
		if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
			_set_server_speed(new_speed)
		else:
			TimeScale.set_speed(new_speed)
	_update_speed_display()

func _on_speed_focus_lost() -> void:
	_update_speed_display()

func _update_speed_display() -> void:
	if _speed_input:
		# Release focus before updating to prevent triggering events
		if _speed_input.has_focus():
			_speed_input.release_focus()
		_speed_input.text = TimeScale.get_speed_display()
	if _speed_label:
		_speed_label.text = TimeScale.get_speed_display()

func _on_money_changed(amount: int) -> void:
	money_display.text = "$%s" % _format_number(amount)


func _update_net_worth() -> void:
	if net_worth_display:
		var net_worth := GameState.calculate_net_worth()
		net_worth_display.text = "Net Worth: $%s" % _format_number(net_worth)


func _on_main_menu() -> void:
	# Return to title screen
	# Note: Does NOT change backend mode - player can return to same mode
	get_tree().change_scene_to_file("res://ui/title_screen.tscn")


func _on_backend_mode_changed(mode: int) -> void:
	# Show/hide Save button based on mode
	if save_btn:
		save_btn.visible = (mode == BackendManager.BackendMode.LOCAL)

	# Show/hide speed controls based on mode and admin status
	# Speed controls only available to admins in SERVER mode
	if speed_bar:
		if mode == BackendManager.BackendMode.SERVER:
			speed_bar.visible = BackendManager.is_admin()
		else:
			speed_bar.visible = true

func _on_save_pressed() -> void:
	if _save_load_dialog:
		_save_load_dialog.open_save_dialog()


func _on_save_confirmed(save_name: String) -> void:
	GameState.save_game(save_name)
	print("Game saved as: ", save_name)


func _on_load_confirmed(file_name: String) -> void:
	if GameState.load_game(file_name):
		print("Game loaded from: ", file_name)
		# Refresh UI after loading
		EventBus.money_changed.emit(GameState.money)
		_update_net_worth()
	else:
		print("Failed to load: ", file_name)

func _on_settings_pressed() -> void:
	_show_settings()

func _on_exit_pressed() -> void:
	get_tree().quit()

func _show_settings() -> void:
	if _settings_popup and is_instance_valid(_settings_popup):
		_settings_popup.queue_free()
		_settings_popup = null
		return

	_settings_popup = PanelContainer.new()
	_settings_popup.anchors_preset = Control.PRESET_CENTER
	_settings_popup.custom_minimum_size = Vector2(400, 200)

	# Add opaque dark background
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.12, 0.16, 1.0)  # Dark blue-gray, fully opaque
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.border_color = Color(0.3, 0.4, 0.5, 1.0)  # Lighter border
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 20
	style.content_margin_top = 20
	style.content_margin_right = 20
	style.content_margin_bottom = 20
	_settings_popup.add_theme_stylebox_override("panel", style)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 26)
	vbox.add_child(title)

	var refuel_check := CheckBox.new()
	refuel_check.text = "Auto-refuel ships (costs money)"
	refuel_check.custom_minimum_size = Vector2(0, 44)
	refuel_check.button_pressed = GameState.settings.get("auto_refuel", true)
	refuel_check.toggled.connect(func(on: bool) -> void:
		GameState.settings["auto_refuel"] = on
	)
	vbox.add_child(refuel_check)

	var unreachable_check := CheckBox.new()
	unreachable_check.text = "Show unreachable destinations"
	unreachable_check.custom_minimum_size = Vector2(0, 44)
	unreachable_check.button_pressed = GameState.settings.get("show_unreachable_destinations", false)
	unreachable_check.toggled.connect(func(on: bool) -> void:
		GameState.settings["show_unreachable_destinations"] = on
	)
	vbox.add_child(unreachable_check)

	var auto_sell_earth_check := CheckBox.new()
	auto_sell_earth_check.text = "Auto-sell ore when ships return to Earth"
	auto_sell_earth_check.custom_minimum_size = Vector2(0, 44)
	auto_sell_earth_check.button_pressed = GameState.settings.get("auto_sell_at_earth", true)
	auto_sell_earth_check.toggled.connect(func(on: bool) -> void:
		GameState.settings["auto_sell_at_earth"] = on
	)
	vbox.add_child(auto_sell_earth_check)

	var auto_sell_check := CheckBox.new()
	auto_sell_check.text = "Auto-sell cargo at colony markets"
	auto_sell_check.custom_minimum_size = Vector2(0, 44)
	auto_sell_check.button_pressed = GameState.settings.get("auto_sell_at_markets", false)
	auto_sell_check.toggled.connect(func(on: bool) -> void:
		GameState.settings["auto_sell_at_markets"] = on
	)
	vbox.add_child(auto_sell_check)

	var date_label := Label.new()
	date_label.text = "Date format:"
	date_label.add_theme_font_size_override("font_size", 21)
	vbox.add_child(date_label)

	var date_formats := {
		"us": "MM/DD/YYYY (US)",
		"uk": "DD/MM/YYYY (UK)",
		"eu": "DD.MM.YYYY (EU)",
		"iso": "YYYY-MM-DD (ISO)",
	}
	var current_fmt: String = GameState.settings.get("date_format", "us")
	var date_option := OptionButton.new()
	date_option.custom_minimum_size = Vector2(0, 44)
	var idx := 0
	for key in date_formats:
		date_option.add_item(date_formats[key], idx)
		date_option.set_item_metadata(idx, key)
		if key == current_fmt:
			date_option.selected = idx
		idx += 1
	date_option.item_selected.connect(func(item_idx: int) -> void:
		var fmt_key: String = date_option.get_item_metadata(item_idx)
		GameState.settings["date_format"] = fmt_key
	)
	vbox.add_child(date_option)

	# Account Settings button (server mode only)
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		var account_btn := Button.new()
		account_btn.text = "⚙️ Account Settings"
		account_btn.custom_minimum_size = Vector2(0, 44)
		account_btn.pressed.connect(func() -> void:
			_show_account_settings_dialog()
		)
		vbox.add_child(account_btn)

	# Report Bug button
	var bug_report_btn := Button.new()
	bug_report_btn.text = "🐛 Report a Bug"
	bug_report_btn.custom_minimum_size = Vector2(0, 44)
	bug_report_btn.pressed.connect(func() -> void:
		if _bug_report_dialog:
			_bug_report_dialog.open_dialog()
			_settings_popup.queue_free()
			_settings_popup = null
	)
	vbox.add_child(bug_report_btn)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 44)
	close_btn.pressed.connect(func() -> void:
		_settings_popup.queue_free()
		_settings_popup = null
	)
	vbox.add_child(close_btn)

	_settings_popup.add_child(vbox)
	add_child(_settings_popup)
	_settings_popup.position = (size - _settings_popup.custom_minimum_size) / 2


func _show_account_settings_dialog() -> void:
	"""Show dialog for account settings (add email, change password)"""
	var server_backend = BackendManager.get_server_backend()
	if not server_backend:
		return

	# Fetch current player info to get email
	var http := HTTPRequest.new()
	add_child(http)
	var url: String = server_backend.base_url + "/auth/me"
	var headers := ["Authorization: Bearer " + server_backend.auth_token]
	http.request(url, headers, HTTPClient.METHOD_GET)
	var result: Array = await http.request_completed
	http.queue_free()

	var current_email: String = ""
	var response_code: int = result[1]
	if response_code == 200:
		var response_body: PackedByteArray = result[3]
		var json := JSON.new()
		if json.parse(response_body.get_string_from_utf8()) == OK:
			var data: Dictionary = json.data
			current_email = data.get("email", "")

	# Build dialog
	var dialog := AcceptDialog.new()
	dialog.title = "Account Settings"
	dialog.dialog_text = ""
	dialog.min_size = Vector2(400, 250)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	# Show current email
	var current_email_label := Label.new()
	if current_email != "":
		current_email_label.text = "Current email: " + current_email
		current_email_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	else:
		current_email_label.text = "No email on file"
		current_email_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
	current_email_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(current_email_label)

	# Add/Change Email Section
	var email_label := Label.new()
	email_label.text = "Add or change email:"
	email_label.add_theme_font_size_override("font_size", 16)
	vbox.add_child(email_label)

	var email_input := LineEdit.new()
	email_input.placeholder_text = "your-email@example.com"
	email_input.custom_minimum_size = Vector2(300, 32)
	vbox.add_child(email_input)

	var add_email_btn := Button.new()
	add_email_btn.text = "Update Email"
	add_email_btn.custom_minimum_size = Vector2(0, 32)
	add_email_btn.pressed.connect(func() -> void:
		var email: String = email_input.text.strip_edges()
		if email == "":
			return
		_add_email_to_account(email)
		dialog.hide()
	)
	vbox.add_child(add_email_btn)

	dialog.add_child(vbox)
	add_child(dialog)
	dialog.popup_centered()


func _add_email_to_account(email: String) -> void:
	"""Add email to account via server"""
	var server_backend = BackendManager.get_server_backend()
	if not server_backend:
		return

	var http := HTTPRequest.new()
	add_child(http)

	var url: String = server_backend.base_url + "/account/add-email"
	var headers := ["Authorization: Bearer " + server_backend.auth_token, "Content-Type: application/json"]
	var body: String = JSON.stringify({"email": email})

	var error := http.request(url, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		print("[MainUI] Failed to send add-email request: ", error)
		http.queue_free()
		return

	var result: Array = await http.request_completed
	http.queue_free()

	var response_code: int = result[1]
	if response_code == 200:
		print("[MainUI] Email added successfully: ", email)
	else:
		var response_body: PackedByteArray = result[3]
		var body_str: String = response_body.get_string_from_utf8()
		print("[MainUI] Failed to add email - Code: %d, Body: %s" % [response_code, body_str])


func _format_number(n: int) -> String:
	var s := str(abs(n))
	var result := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	if n < 0:
		result = "-" + result
	return result


# ══════════════════════════════════════════════════════════════════════════════
# SERVER STATE POLLING (Phase 1)
# ══════════════════════════════════════════════════════════════════════════════

func _poll_server_state() -> void:
	_polling_server = true

	# Fetch both personal state and shared world state
	var server_data := await BackendManager.get_game_state()

	var world_data: Dictionary = {}
	var server_backend = BackendManager.get_server_backend()
	if server_backend:
		world_data = await server_backend.get_world_state()

	_polling_server = false

	if server_data.is_empty():
		return

	# Apply server state to local GameState (own ships, workers, money)
	GameState.apply_server_state(server_data)

	if not _initial_state_loaded:
		_initial_state_loaded = true
		_hide_loading_overlay()
		# Fetch offline notifications (events that happened while logged out)
		var server_backend = BackendManager.get_server_backend()
		if server_backend:
			var notifs: Array = await server_backend.get_notifications()
			if not notifs.is_empty():
				EventBus.server_notifications_received.emit(notifs)

	# Apply world state (all players' ships for multiplayer visibility)
	if not world_data.is_empty():
		GameState.apply_world_state(world_data)


func _poll_server_speed() -> void:
	_polling_server_speed = true

	var server_backend = BackendManager.get_server_backend()
	if not server_backend:
		_polling_server_speed = false
		return

	var http := HTTPRequest.new()
	http.set_tls_options(TLSOptions.client())
	http.timeout = 10.0
	add_child(http)

	var url: String = server_backend.base_url + "/admin/speed"
	var headers: Array = [
		"Authorization: Bearer " + server_backend.auth_token
	]

	http.request(url, headers, HTTPClient.METHOD_GET)
	var result: Array = await http.request_completed

	http.queue_free()
	_polling_server_speed = false

	var http_result: int = result[0]
	var response_code: int = result[1]

	if http_result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		var response_body: PackedByteArray = result[3]
		var json := JSON.new()
		if json.parse(response_body.get_string_from_utf8()) == OK:
			var data: Dictionary = json.data
			var speed: float = data.get("speed", 1.0)
			if not _initial_speed_synced:
				# First poll after login: server speed is authoritative. Sync UI to it.
				_initial_speed_synced = true
				_current_server_speed = speed
				CelestialData.scale_server_rate(TimeScale.speed_multiplier, speed)
				TimeScale.speed_multiplier = speed
				_update_speed_display()
			# Always keep step index in sync for 1/2 key stepping
			_server_speed_index = SERVER_SPEED_STEPS.find(speed)
			if _server_speed_index < 0:
				_server_speed_index = 0
				for i in range(SERVER_SPEED_STEPS.size()):
					if SERVER_SPEED_STEPS[i] <= speed:
						_server_speed_index = i


# ══════════════════════════════════════════════════════════════════════════════
# SERVER SPEED CONTROL (Testing Feature)
# ══════════════════════════════════════════════════════════════════════════════

var _current_server_speed: float = 1.0
const SERVER_SPEED_STEPS: Array[float] = [1.0, 10.0, 100.0, 1000.0, 10000.0, 100000.0, 200000.0]
var _server_speed_index: int = 0
var _initial_speed_synced: bool = false  # True after first poll sets UI to server's actual speed

func _adjust_server_speed(keycode: int) -> void:
	if keycode == KEY_2:
		# Increase speed
		_server_speed_index = min(_server_speed_index + 1, SERVER_SPEED_STEPS.size() - 1)
	elif keycode == KEY_1:
		# Decrease speed
		_server_speed_index = max(_server_speed_index - 1, 0)

	var new_speed := SERVER_SPEED_STEPS[_server_speed_index]
	if new_speed != _current_server_speed:
		_set_server_speed(new_speed)


func _set_server_speed(speed: float) -> void:
	# Immediately rescale the orbital dead-reckoning rate so planets don't jerk
	# for the 1-2 polls it takes the server to confirm the new speed.
	CelestialData.scale_server_rate(_current_server_speed, speed)
	_current_server_speed = speed
	TimeScale.speed_multiplier = speed

	# Call server admin endpoint
	var server_backend = BackendManager.get_server_backend()
	if not server_backend:
		print("[MainUI] Cannot set server speed - no server backend")
		return

	var http := HTTPRequest.new()
	http.set_tls_options(TLSOptions.client())
	http.timeout = 10.0
	add_child(http)

	var url: String = server_backend.base_url + "/admin/set-speed"
	var headers: Array = [
		"Content-Type: application/json",
		"Authorization: Bearer " + server_backend.auth_token
	]
	var body: String = JSON.stringify({"multiplier": speed})

	http.request(url, headers, HTTPClient.METHOD_POST, body)
	var response: Array = await http.request_completed

	http.queue_free()

	var result: int = response[0]
	var response_code: int = response[1]
	var response_body: PackedByteArray = response[3]

	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		print("[MainUI] Server speed set to %.0fx" % speed)
	else:
		var error_msg := "Failed to set server speed: "
		match result:
			HTTPRequest.RESULT_CANT_CONNECT:
				error_msg += "Can't connect to server"
			HTTPRequest.RESULT_CANT_RESOLVE:
				error_msg += "Can't resolve domain"
			HTTPRequest.RESULT_CONNECTION_ERROR:
				error_msg += "Connection error"
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
				error_msg += "TLS/SSL error"
			HTTPRequest.RESULT_TIMEOUT:
				error_msg += "Request timeout"
			_:
				var body_str: String = response_body.get_string_from_utf8()
				error_msg += "HTTP %d - %s" % [response_code, body_str if body_str != "" else "Unknown error"]
		print("[MainUI] " + error_msg)


# ══════════════════════════════════════════════════════════════════════════════
# LOADING OVERLAY
# ══════════════════════════════════════════════════════════════════════════════

func _show_loading_overlay() -> void:
	_loading_overlay = Control.new()
	_loading_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.mouse_filter = Control.MOUSE_FILTER_STOP

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.06, 0.06, 0.08, 1.0)
	_loading_overlay.add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_overlay.add_child(center)

	var label := Label.new()
	label.text = "Reticulating splines..."
	label.add_theme_font_size_override("font_size", 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(label)

	add_child(_loading_overlay)


func _hide_loading_overlay() -> void:
	if _loading_overlay and is_instance_valid(_loading_overlay):
		_loading_overlay.queue_free()
		_loading_overlay = null
