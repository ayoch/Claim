extends Control

const _SP_SERVER := "https://claim-production-066b.up.railway.app"

@onready var back_btn: Button = %BackButton
@onready var tab_container: TabContainer = %TabContainer
@onready var sp_entries: VBoxContainer = %SPEntriesContainer
@onready var sp_global_entries: VBoxContainer = %SPGlobalEntriesContainer
@onready var sp_global_status: Label = %SPGlobalStatusLabel
@onready var sp_global_refresh_btn: Button = %SPGlobalRefreshButton
@onready var mp_entries: VBoxContainer = %MPEntriesContainer
@onready var mp_refresh_btn: Button = %MPRefreshButton
@onready var mp_status_label: Label = %MPStatusLabel
@onready var mp_overlay: CenterContainer = %MPDisabledOverlay
@onready var mp_player_rank: Label = %MPPlayerRank

var _mp_leaderboard_cache: Array = []
var _mp_last_updated: float = 0.0
var _mp_loading: bool = false
var _sp_global_loading: bool = false


func _ready() -> void:
	back_btn.pressed.connect(_on_back)
	if mp_refresh_btn:
		mp_refresh_btn.pressed.connect(_on_mp_refresh)
	if sp_global_refresh_btn:
		sp_global_refresh_btn.pressed.connect(_on_sp_global_refresh)

	_refresh_leaderboards()


func _refresh_leaderboards() -> void:
	# My Records tab — local machine saves
	var sp_leaderboard := GameState.get_local_leaderboard()
	_populate_leaderboard(sp_entries, sp_leaderboard, "player_name")

	# SP Global tab — anyone who submitted from SP mode
	_refresh_sp_global_leaderboard()

	# Multiplayer tab
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		if mp_overlay:
			mp_overlay.visible = false
		_refresh_multiplayer_leaderboard()
	else:
		if mp_overlay:
			mp_overlay.visible = true


func _populate_leaderboard(container: VBoxContainer, entries: Array, name_key: String = "username") -> void:
	for child in container.get_children():
		child.queue_free()

	if entries.is_empty():
		var empty_label := Label.new()
		empty_label.text = "No entries yet."
		empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		empty_label.add_theme_font_size_override("font_size", 21)
		container.add_child(empty_label)
		return

	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var row := _create_leaderboard_row(i + 1, entry, name_key)
		container.add_child(row)


func _create_leaderboard_row(rank: int, entry: Dictionary, name_key: String = "username") -> HBoxContainer:
	var row := HBoxContainer.new()

	var rank_label := Label.new()
	rank_label.custom_minimum_size = Vector2(60, 0)
	rank_label.text = "#%d" % rank
	rank_label.add_theme_font_size_override("font_size", 18)
	row.add_child(rank_label)

	var player_label := Label.new()
	player_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_label.text = entry.get(name_key, entry.get("username", entry.get("player_name", "Unknown")))
	player_label.add_theme_font_size_override("font_size", 18)
	row.add_child(player_label)

	var ships_label := Label.new()
	ships_label.custom_minimum_size = Vector2(60, 0)
	ships_label.text = "%d ships" % entry.get("ships_count", 0)
	ships_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ships_label.add_theme_font_size_override("font_size", 16)
	ships_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	row.add_child(ships_label)

	var worth_label := Label.new()
	worth_label.custom_minimum_size = Vector2(160, 0)
	worth_label.text = "$%s" % _format_number(entry.get("net_worth", 0))
	worth_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	worth_label.add_theme_font_size_override("font_size", 18)
	var ship_val: int = entry.get("ship_value", 0)
	var cargo_val: int = entry.get("cargo_value", 0)
	if ship_val > 0 or cargo_val > 0:
		worth_label.tooltip_text = "Cash: $%s\nShips: $%s\nCargo: $%s" % [
			_format_number(entry.get("money", 0)),
			_format_number(ship_val),
			_format_number(cargo_val),
		]
	row.add_child(worth_label)

	return row


# ---------------------------------------------------------------------------
# SP Global leaderboard
# ---------------------------------------------------------------------------

func _on_sp_global_refresh() -> void:
	if _sp_global_loading:
		return
	_refresh_sp_global_leaderboard()


func _refresh_sp_global_leaderboard() -> void:
	if _sp_global_loading:
		return
	_sp_global_loading = true
	if sp_global_refresh_btn:
		sp_global_refresh_btn.disabled = true
	if sp_global_status:
		sp_global_status.text = "Loading..."

	# Submit current score first (fire-and-forget, only in LOCAL mode)
	if BackendManager.current_mode != BackendManager.BackendMode.SERVER:
		_submit_sp_score_async()

	var result := await _http_get_json(_SP_SERVER + "/api/leaderboard/sp?limit=100")

	_sp_global_loading = false
	if sp_global_refresh_btn:
		sp_global_refresh_btn.disabled = false

	if result.is_empty() or not result.has("entries"):
		if sp_global_status:
			sp_global_status.text = "Could not reach server"
		return

	_populate_leaderboard(sp_global_entries, result["entries"], "player_name")
	var total: int = result.get("total_players", 0)
	if sp_global_status:
		sp_global_status.text = "%d players on the board" % total


func _submit_sp_score_async() -> void:
	var name := GameState.player_name.strip_edges()
	if name.is_empty():
		return
	var body := JSON.stringify({
		"player_name": name,
		"net_worth": GameState.calculate_net_worth(),
		"ships_count": GameState.ships.size(),
		"workers_count": GameState.workers.size(),
		"game_date": GameState.get_game_date_string(),
	})
	# Fire and forget — don't await
	_http_post_json(_SP_SERVER + "/api/leaderboard/sp", body)


# Minimal async GET — returns parsed dict or empty dict on failure
func _http_get_json(url: String) -> Dictionary:
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url, [], HTTPClient.METHOD_GET)
	var response = await http.request_completed
	http.queue_free()
	var body: PackedByteArray = response[3]
	if response[1] != 200:
		return {}
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if parsed is Dictionary:
		return parsed
	return {}


# Minimal fire-and-forget POST
func _http_post_json(url: String, body: String) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	var headers := ["Content-Type: application/json"]
	http.request(url, headers, HTTPClient.METHOD_POST, body)
	await http.request_completed
	http.queue_free()


# ---------------------------------------------------------------------------
# Multiplayer leaderboard
# ---------------------------------------------------------------------------

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

	var result: Dictionary = await BackendManager.get_server_backend().get_leaderboard(100, 0)

	_mp_loading = false
	if mp_refresh_btn:
		mp_refresh_btn.disabled = false

	if result.get("entries", []).is_empty():
		_update_mp_status("Failed to load leaderboard (offline or error)")
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
	for i in range(_mp_leaderboard_cache.size()):
		var entry: Dictionary = _mp_leaderboard_cache[i]
		if entry.get("player_id", 0) == player_id:
			mp_player_rank.text = "Your Rank: #%d | Net Worth: $%s" % [
				i + 1,
				_format_number(entry.get("net_worth", 0))
			]
			return
	mp_player_rank.text = "Your Rank: Not in top 100"


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

func _on_back() -> void:
	get_tree().change_scene_to_file("res://ui/title_screen.tscn")


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


func _format_timestamp(unix_time: float) -> String:
	var datetime := Time.get_datetime_dict_from_unix_time(int(unix_time))
	return "%02d:%02d:%02d" % [datetime["hour"], datetime["minute"], datetime["second"]]
