extends Control

@onready var money_display: Label = %MoneyDisplay
@onready var tab_container: TabContainer = %TabContainer

var _settings_popup: PanelContainer = null

func _ready() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	_on_money_changed(GameState.money)

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
