extends Control

# Testing mode - set to false for release build
const TESTING_MODE: bool = true

@onready var money_display: Label = %MoneyDisplay
@onready var tab_container: TabContainer = %TabContainer

var _settings_popup: PanelContainer = null
var _speed_control: HBoxContainer = null
var _speed_input: LineEdit = null

func _ready() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	_on_money_changed(GameState.money)

	# Only show speed control in testing mode
	if TESTING_MODE:
		_create_speed_control()

func _create_speed_control() -> void:
	# Create speed control panel in top-left corner
	_speed_control = HBoxContainer.new()
	_speed_control.position = Vector2(10, 10)
	_speed_control.add_theme_constant_override("separation", 8)
	add_child(_speed_control)

	# Speed label
	var label := Label.new()
	label.text = "Speed:"
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_speed_control.add_child(label)

	# Decrease button
	var dec_btn := Button.new()
	dec_btn.text = "-"
	dec_btn.custom_minimum_size = Vector2(32, 32)
	dec_btn.pressed.connect(func() -> void:
		TimeScale.slow_down()
		_update_speed_display()
	)
	_speed_control.add_child(dec_btn)

	# Editable speed input
	_speed_input = LineEdit.new()
	_speed_input.custom_minimum_size = Vector2(80, 32)
	_speed_input.text = str(TimeScale.speed_multiplier)
	_speed_input.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_input.text_submitted.connect(_on_speed_submitted)
	_speed_input.focus_exited.connect(_on_speed_focus_lost)
	_speed_control.add_child(_speed_input)

	# Increase button
	var inc_btn := Button.new()
	inc_btn.text = "+"
	inc_btn.custom_minimum_size = Vector2(32, 32)
	inc_btn.pressed.connect(func() -> void:
		TimeScale.speed_up()
		_update_speed_display()
	)
	_speed_control.add_child(inc_btn)

	# Preset buttons
	var preset_1x := Button.new()
	preset_1x.text = "1x"
	preset_1x.custom_minimum_size = Vector2(40, 32)
	preset_1x.pressed.connect(func() -> void:
		TimeScale.set_speed(TimeScale.SPEED_REALTIME)
		_update_speed_display()
	)
	_speed_control.add_child(preset_1x)

	var preset_20x := Button.new()
	preset_20x.text = "20x"
	preset_20x.custom_minimum_size = Vector2(48, 32)
	preset_20x.pressed.connect(func() -> void:
		TimeScale.set_speed(TimeScale.SPEED_NORMAL)
		_update_speed_display()
	)
	_speed_control.add_child(preset_20x)

	var preset_100x := Button.new()
	preset_100x.text = "100x"
	preset_100x.custom_minimum_size = Vector2(52, 32)
	preset_100x.pressed.connect(func() -> void:
		TimeScale.set_speed(TimeScale.SPEED_VERYFAST)
		_update_speed_display()
	)
	_speed_control.add_child(preset_100x)

func _on_speed_submitted(new_text: String) -> void:
	var new_speed := new_text.to_float()
	if new_speed > 0:
		TimeScale.set_speed(new_speed)
	_update_speed_display()

func _on_speed_focus_lost() -> void:
	_update_speed_display()

func _update_speed_display() -> void:
	if _speed_input:
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
