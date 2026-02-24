extends PopupPanel

## Save/Load dialog for managing multiple save files
## Modes: SAVE (create/overwrite save) or LOAD (select and load save)

enum Mode { SAVE, LOAD }

@onready var title_label: Label = %TitleLabel
@onready var save_list: VBoxContainer = %SaveList
@onready var name_input: LineEdit = %NameInput
@onready var name_container: HBoxContainer = %NameContainer
@onready var confirm_btn: Button = %ConfirmButton
@onready var cancel_btn: Button = %CancelButton

var current_mode: Mode = Mode.SAVE
var selected_save: Dictionary = {}

signal save_confirmed(save_name: String)
signal load_confirmed(save_file: String)

func _ready() -> void:
	confirm_btn.pressed.connect(_on_confirm)
	cancel_btn.pressed.connect(_on_cancel)
	name_input.text_submitted.connect(func(_text): _on_confirm())


func open_save_dialog() -> void:
	current_mode = Mode.SAVE
	title_label.text = "Save Game"
	name_container.visible = true
	name_input.text = _generate_default_name()
	name_input.grab_focus()
	confirm_btn.text = "Save"
	_refresh_save_list()
	popup_centered()


func open_load_dialog() -> void:
	current_mode = Mode.LOAD
	title_label.text = "Load Game"
	name_container.visible = false
	confirm_btn.text = "Load"
	confirm_btn.disabled = true
	selected_save = {}
	_refresh_save_list()
	popup_centered()


func _generate_default_name() -> String:
	# Generate name like "Save 2024-02-24 14:32"
	var datetime := Time.get_datetime_dict_from_system()
	return "Save %04d-%02d-%02d %02d:%02d" % [
		datetime["year"], datetime["month"], datetime["day"],
		datetime["hour"], datetime["minute"]
	]


func _refresh_save_list() -> void:
	# Clear existing list
	for child in save_list.get_children():
		child.queue_free()

	# Get all save files
	var saves := _get_all_saves()

	if saves.is_empty():
		var label := Label.new()
		label.text = "No saved games found"
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		save_list.add_child(label)
		return

	# Sort by timestamp (newest first)
	saves.sort_custom(func(a, b): return a["timestamp"] > b["timestamp"])

	# Create entry for each save
	for save_data in saves:
		var entry := _create_save_entry(save_data)
		save_list.add_child(entry)


func _create_save_entry(save_data: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, 50)

	# Format display text
	var save_name: String = save_data.get("name", "Unknown")
	var timestamp: int = save_data.get("timestamp", 0)
	var net_worth: int = save_data.get("net_worth", 0)
	var datetime := Time.get_datetime_dict_from_unix_time(timestamp)

	btn.text = "%s\n%04d-%02d-%02d %02d:%02d  |  Net Worth: $%s" % [
		save_name,
		datetime["year"], datetime["month"], datetime["day"],
		datetime["hour"], datetime["minute"],
		_format_number(net_worth)
	]

	# In LOAD mode, clicking selects the save
	if current_mode == Mode.LOAD:
		btn.pressed.connect(func():
			selected_save = save_data
			confirm_btn.disabled = false
		)
	# In SAVE mode, clicking fills the name input to overwrite
	else:
		btn.pressed.connect(func():
			name_input.text = save_name
			name_input.grab_focus()
		)

	panel.add_child(btn)
	return panel


func _get_all_saves() -> Array:
	var saves: Array = []
	var dir := DirAccess.open("user://")
	if not dir:
		return saves

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".json") and file_name.begins_with("save_"):
			var metadata := _load_save_metadata(file_name)
			if not metadata.is_empty():
				metadata["file_name"] = file_name
				saves.append(metadata)
		file_name = dir.get_next()
	dir.list_dir_end()

	return saves


func _load_save_metadata(file_name: String) -> Dictionary:
	var file := FileAccess.open("user://" + file_name, FileAccess.READ)
	if not file:
		return {}

	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return {}

	var data: Dictionary = json.data
	# Extract metadata
	return {
		"name": data.get("save_name", "Unknown"),
		"timestamp": data.get("save_timestamp", 0),
		"net_worth": data.get("net_worth", 0),
		"player_name": data.get("player_name", "Player"),
	}


func _on_confirm() -> void:
	if current_mode == Mode.SAVE:
		var save_name := name_input.text.strip_edges()
		if save_name.is_empty():
			return
		save_confirmed.emit(save_name)
	else:  # LOAD
		if selected_save.is_empty():
			return
		var file_name: String = selected_save.get("file_name", "")
		if file_name.is_empty():
			return
		load_confirmed.emit(file_name)

	hide()


func _on_cancel() -> void:
	hide()


func _format_number(value: int) -> String:
	var s := str(value)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result
