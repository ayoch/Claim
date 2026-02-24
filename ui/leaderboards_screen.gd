extends Control

@onready var back_btn: Button = %BackButton
@onready var tab_container: TabContainer = %TabContainer
@onready var sp_entries: VBoxContainer = %SPEntriesContainer
@onready var mp_entries: VBoxContainer = %MPEntriesContainer
@onready var mp_refresh_btn: Button = %MPRefreshButton
@onready var mp_status_label: Label = %MPStatusLabel
@onready var mp_overlay: CenterContainer = %MPDisabledOverlay
@onready var mp_player_rank: Label = %MPPlayerRank

# Cached multiplayer leaderboard
var _mp_leaderboard_cache: Array = []
var _mp_last_updated: float = 0.0
var _mp_loading: bool = false

func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	if mp_refresh_btn:
		mp_refresh_btn.pressed.connect(_on_mp_refresh)

	# Load and display leaderboards
	_refresh_leaderboards()


func _refresh_leaderboards() -> void:
	# Get single player leaderboard from GameState
	var sp_leaderboard := GameState.get_local_leaderboard()
	_populate_leaderboard(sp_entries, sp_leaderboard)

	# Load multiplayer leaderboard if logged in
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		if mp_overlay:
			mp_overlay.visible = false
		_refresh_multiplayer_leaderboard()
	else:
		# Show offline message
		if mp_overlay:
			mp_overlay.visible = true


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


func _on_mp_refresh() -> void:
	if _mp_loading:
		return
	_refresh_multiplayer_leaderboard()


func _refresh_multiplayer_leaderboard() -> void:
	if _mp_loading:
		return

	_mp_loading = true
	if mp_refresh_btn:
		mp_refresh_btn.disabled = true
	_update_mp_status("Loading...")

	# Fetch from server
	var result: Dictionary = await BackendManager.get_server_backend().get_leaderboard(100, 0)

	_mp_loading = false
	if mp_refresh_btn:
		mp_refresh_btn.disabled = false

	if result.get("entries", []).is_empty():
		_update_mp_status("Failed to load leaderboard (offline or error)")
		# Show cached data if available
		if not _mp_leaderboard_cache.is_empty():
			_populate_leaderboard(mp_entries, _mp_leaderboard_cache)
			_update_player_rank()
	else:
		_mp_leaderboard_cache = result["entries"]
		_mp_last_updated = Time.get_unix_time_from_system()
		_populate_leaderboard(mp_entries, _mp_leaderboard_cache)
		_update_mp_status("Last updated: %s" % _format_timestamp(_mp_last_updated))
		_update_player_rank()


func _update_mp_status(text: String) -> void:
	if mp_status_label:
		mp_status_label.text = text


func _update_player_rank() -> void:
	if not mp_player_rank:
		return

	var server_backend = BackendManager.get_server_backend()
	if not server_backend:
		return

	var player_id: int = server_backend.player_id
	if player_id == 0:
		mp_player_rank.text = "Your Rank: Not logged in"
		return

	# Find player in leaderboard
	for i in range(_mp_leaderboard_cache.size()):
		var entry: Dictionary = _mp_leaderboard_cache[i]
		if entry.get("player_id", 0) == player_id:
			mp_player_rank.text = "Your Rank: #%d | Net Worth: $%s" % [
				i + 1,
				_format_number(entry.get("net_worth", 0))
			]
			return

	# Player not in top 100
	mp_player_rank.text = "Your Rank: Not in top 100"


func _format_timestamp(unix_time: float) -> String:
	var datetime := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return "%02d:%02d:%02d" % [datetime["hour"], datetime["minute"], datetime["second"]]
