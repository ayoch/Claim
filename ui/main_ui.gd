extends Control

# Testing mode - set to false for release build
const TESTING_MODE: bool = true

@onready var money_display: Label = %MoneyDisplay
@onready var tab_container: TabContainer = %TabContainer
@onready var top_bar_hbox: HBoxContainer = $VBox/TopBar/HBox
@onready var speed_bar: PanelContainer = $VBox/SpeedBar
@onready var date_display: Label = %DateDisplay

var _settings_popup: PanelContainer = null
var _speed_input: LineEdit = null
var _stored_speed: float = 0.0
var _is_speed_paused: bool = false
var _date_update_timer: float = 0.0
const DATE_UPDATE_INTERVAL: float = 0.2  # Update date 5 times per second

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

	if TESTING_MODE:
		_setup_speed_bar()
	else:
		speed_bar.visible = false

	_update_date_display()

func _process(delta: float) -> void:
	# Throttle date display updates - doesn't need to be every frame
	_date_update_timer += delta
	if _date_update_timer >= DATE_UPDATE_INTERVAL:
		_update_date_display()
		_date_update_timer = 0.0

	# Update speed display continuously to catch keyboard shortcuts
	if _speed_input and TimeScale.get_speed_display() != _speed_input.text:
		_update_speed_display()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_SPACE:
			_toggle_pause_speed()
			get_viewport().set_input_as_handled()

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

	# Wire decrease button
	var dec_btn: Button = hbox.get_node("DecBtn")
	dec_btn.pressed.connect(func() -> void:
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
		TimeScale.speed_up()
		_update_speed_display()
	)

	# Wire preset buttons
	hbox.get_node("Preset1x").pressed.connect(func() -> void:
		TimeScale.set_speed(TimeScale.SPEED_REALTIME)
		_update_speed_display()
	)
	hbox.get_node("Preset20x").pressed.connect(func() -> void:
		TimeScale.set_speed(TimeScale.SPEED_NORMAL)
		_update_speed_display()
	)
	hbox.get_node("Preset100x").pressed.connect(func() -> void:
		TimeScale.set_speed(TimeScale.SPEED_VERYFAST)
		_update_speed_display()
	)

func _on_speed_submitted(new_text: String) -> void:
	var new_speed := new_text.to_float()
	if new_speed > 0:
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

func _on_money_changed(amount: int) -> void:
	money_display.text = "$%s" % _format_number(amount)

func _on_save_pressed() -> void:
	GameState.save_game()

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

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)

	var title := Label.new()
	title.text = "SETTINGS"
	title.add_theme_font_size_override("font_size", 20)
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

	var auto_sell_check := CheckBox.new()
	auto_sell_check.text = "Auto-sell cargo at markets"
	auto_sell_check.custom_minimum_size = Vector2(0, 44)
	auto_sell_check.button_pressed = GameState.settings.get("auto_sell_at_markets", false)
	auto_sell_check.toggled.connect(func(on: bool) -> void:
		GameState.settings["auto_sell_at_markets"] = on
	)
	vbox.add_child(auto_sell_check)

	var date_label := Label.new()
	date_label.text = "Date format:"
	date_label.add_theme_font_size_override("font_size", 16)
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
