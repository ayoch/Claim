extends Control

@onready var back_btn: Button = %BackButton
@onready var tab_container: TabContainer = %TabContainer
@onready var sp_entries: VBoxContainer = %SPEntriesContainer
@onready var mp_entries: VBoxContainer = %MPEntriesContainer

func _ready() -> void:
	back_btn.pressed.connect(_on_back)

	# Load and display leaderboards
	_refresh_leaderboards()


func _refresh_leaderboards() -> void:
	# Get single player leaderboard from GameState
	var sp_leaderboard := GameState.get_local_leaderboard()
	_populate_leaderboard(sp_entries, sp_leaderboard)

	# Multiplayer tab will show "Coming Soon" overlay for now


func _populate_leaderboard(container: VBoxContainer, entries: Array) -> void:
	# Clear existing entries
	for child in container.get_children():
		child.queue_free()

	# Show message if empty
	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No leaderboard entries yet.\nSave your game to create an entry!"
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 16)
		container.add_child(empty_label)
		return

	# Add each entry
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var row := _create_leaderboard_row(i + 1, entry)
		container.add_child(row)


func _create_leaderboard_row(rank: int, entry: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()

	# Rank
	var rank_label := Label.new()
	rank_label.custom_minimum_size = Vector2(60, 0)
	rank_label.text = "#%d" % rank
	rank_label.add_theme_font_size_override("font_size", 14)
	row.add_child(rank_label)

	# Player name
	var player_label := Label.new()
	player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_label.text = entry.get("player_name", "Unknown")
	player_label.add_theme_font_size_override("font_size", 14)
	row.add_child(player_label)

	# Net worth
	var worth_label := Label.new()
	worth_label.custom_minimum_size = Vector2(150, 0)
	worth_label.text = "$%s" % _format_number(entry.get("net_worth", 0))
	worth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	worth_label.add_theme_font_size_override("font_size", 14)
	row.add_child(worth_label)

	return row


func _format_number(value: int) -> String:
	# Add commas for thousands
	var s := str(value)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result


func _on_back() -> void:
	get_tree().change_scene_to_file("res://ui/title_screen.tscn")
