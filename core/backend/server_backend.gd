class_name ServerBackend
extends BackendInterface

## Server-based multiplayer backend implementation
## Makes HTTP requests to Python/FastAPI server

var base_url: String = "https://claim-production-066b.up.railway.app"
var auth_token: String = ""
var player_id: int = 0
var saved_username: String = ""
var is_admin: bool = false

# Reference to BackendManager (Node) for adding HTTP nodes to tree
var _backend_manager: Node = null

# Persistent auth storage
const AUTH_SAVE_PATH: String = "user://auth_data.json"

# HTTP request queue (reuse nodes for efficiency)
var _http_pool: Array[HTTPRequest] = []
const MAX_POOL_SIZE: int = 5

# Server-Sent Events (Phase 2)
var _sse_http: HTTPRequest = null
var _sse_connected: bool = false
var _sse_buffer: String = ""  # Buffer for partial SSE messages


func set_backend_manager(manager: Node) -> void:
	_backend_manager = manager
	_load_auth_data()


func _load_auth_data() -> void:
	"""Load saved auth token and username from disk"""
	if not FileAccess.file_exists(AUTH_SAVE_PATH):
		return

	var file := FileAccess.open(AUTH_SAVE_PATH, FileAccess.READ)
	if not file:
		return

	var json_string := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_result := json.parse(json_string)
	if parse_result != OK:
		return

	var data: Dictionary = json.data
	auth_token = data.get("auth_token", "")
	player_id = data.get("player_id", 0)
	saved_username = data.get("username", "")
	is_admin = data.get("is_admin", false)


func _save_auth_data(username: String) -> void:
	"""Save auth token and username to disk"""
	var data := {
		"auth_token": auth_token,
		"player_id": player_id,
		"username": username,
		"is_admin": is_admin
	}

	var file := FileAccess.open(AUTH_SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_warning("Failed to save auth data")
		return

	file.store_string(JSON.stringify(data))
	file.close()


func _clear_auth_data() -> void:
	"""Clear saved auth data"""
	if FileAccess.file_exists(AUTH_SAVE_PATH):
		DirAccess.remove_absolute(AUTH_SAVE_PATH)


func has_saved_session() -> bool:
	"""Check if there's a saved auth session"""
	return auth_token != "" and player_id > 0


func get_saved_username() -> String:
	"""Get the saved username"""
	return saved_username

# ══════════════════════════════════════════════════════════════════════════════
# AUTHENTICATION
# ══════════════════════════════════════════════════════════════════════════════

func login(username: String, password: String) -> Dictionary:
	var http := _get_http_request()
	# OAuth2 expects form data, not JSON
	var headers := ["Content-Type: application/x-www-form-urlencoded"]
	var body := "username=%s&password=%s" % [username.uri_encode(), password.uri_encode()]

	var result := await _http_request_async(http, base_url + "/auth/login", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if result["success"]:
		var data: Dictionary = result["data"]
		var token_value = data.get("access_token", "")
		auth_token = str(token_value) if token_value != null else ""
		# Extract player_id from token or fetch from /auth/me
		# For now, we'll fetch the player info after login
		await _fetch_player_info()
		# Save auth data for persistent login
		_save_auth_data(username)
		return {
			"success": true,
			"token": auth_token,
			"player_id": player_id,
			"error": ""
		}
	else:
		return {
			"success": false,
			"token": "",
			"player_id": 0,
			"error": result.get("error", "Login failed")
		}


func register(username: String, password: String, email: String) -> Dictionary:
	var http := _get_http_request()
	var headers := ["Content-Type: application/json"]
	var body := JSON.stringify({"username": username, "password": password, "email": email})

	var result := await _http_request_async(http, base_url + "/auth/register", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if result["success"]:
		var data: Dictionary = result["data"]
		return {
			"success": true,
			"player_id": data.get("id", 0),
			"error": ""
		}
	else:
		return {
			"success": false,
			"player_id": 0,
			"error": result.get("error", "Registration failed")
		}


func logout() -> void:
	auth_token = ""
	player_id = 0
	saved_username = ""
	_clear_auth_data()


# ══════════════════════════════════════════════════════════════════════════════
# GAME STATE
# ══════════════════════════════════════════════════════════════════════════════

func get_game_state() -> Dictionary:
	var http := _get_http_request()
	var headers := _auth_headers()

	var result := await _http_request_async(http, base_url + "/game/state", headers, HTTPClient.METHOD_GET, "")
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to get game state: " + str(err))
		return {}


## Accept a contract by server ID
func accept_contract(contract_server_id: int) -> Dictionary:
	var http := _get_http_request()
	var headers := _auth_headers()
	var url := base_url + "/game/contracts/%d/accept" % contract_server_id
	var result := await _http_request_async(http, url, headers, HTTPClient.METHOD_POST, "")
	_return_http_request(http)
	if result["success"]:
		return result["data"]
	else:
		push_warning("Failed to accept contract %d: %s" % [contract_server_id, str(result.get("error", ""))])
		return {}


## Get shared world state (all players' ships for multiplayer)
func get_world_state() -> Dictionary:
	var http := _get_http_request()
	var headers := _auth_headers()

	var result := await _http_request_async(http, base_url + "/game/world", headers, HTTPClient.METHOD_GET, "")
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to get world state: " + str(err))
		return {}


func save_game() -> void:
	# Server saves continuously - this is a no-op for server mode
	# In multiplayer, state is always on server
	pass


func load_game(save_name: String) -> bool:
	# Server mode doesn't have local save files
	# Game state is always loaded from server on login
	push_warning("load_game() not supported in server mode")
	return false


func get_save_files() -> Array:
	# No local save files in server mode
	return []


# ══════════════════════════════════════════════════════════════════════════════
# SHIPS & MISSIONS
# ══════════════════════════════════════════════════════════════════════════════

func dispatch_mission(ship_id: int, asteroid_id: int, mission_type: int, mining_duration: float, return_to_station: bool):
	var http := _get_http_request()
	var headers := _auth_headers()
	var body := JSON.stringify({
		"ship_id": ship_id,
		"asteroid_id": asteroid_id,
		"mission_type": mission_type,
		"mining_duration": mining_duration,
		"return_to_station": return_to_station
	})

	var result := await _http_request_async(http, base_url + "/game/dispatch", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to dispatch mission: " + str(err))
		return null


func buy_ship(ship_class: int, ship_name: String, colony_id: int):
	var http := _get_http_request()
	var headers := _auth_headers()
	var body := JSON.stringify({
		"ship_class": ship_class,
		"ship_name": ship_name,
		"colony_id": colony_id
	})

	var result := await _http_request_async(http, base_url + "/game/buy-ship", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to buy ship: " + str(err))
		return null


func sell_ship(ship_id: int) -> void:
	var http := _get_http_request()
	var headers := _auth_headers()

	var result := await _http_request_async(http, base_url + "/api/ships/%d" % ship_id, headers, HTTPClient.METHOD_DELETE)
	_return_http_request(http)

	if not result["success"]:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to sell ship: " + str(err))


# ══════════════════════════════════════════════════════════════════════════════
# MINING UNITS (RIGS / MUDs)
# ══════════════════════════════════════════════════════════════════════════════

func purchase_rig(unit_name: String):
	var http := _get_http_request()
	var headers := _auth_headers()
	var body := JSON.stringify({"rig_name": unit_name})

	var result := await _http_request_async(http, base_url + "/game/buy-rig", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		push_warning("Failed to purchase rig: " + str(result.get("error", "Unknown error")))
		return null


func repair_rig(rig_id: int) -> bool:
	var http := _get_http_request()
	var headers := _auth_headers()
	var body := JSON.stringify({"rig_id": rig_id})

	var result := await _http_request_async(http, base_url + "/game/repair-rig", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if result["success"]:
		return true
	else:
		push_warning("Failed to repair rig: " + str(result.get("error", "Unknown error")))
		return false


func rebuild_rig(rig_id: int) -> bool:
	var http := _get_http_request()
	var headers := _auth_headers()
	var body := JSON.stringify({"rig_id": rig_id})

	var result := await _http_request_async(http, base_url + "/game/rebuild-rig", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if result["success"]:
		return true
	else:
		push_warning("Failed to rebuild rig: " + str(result.get("error", "Unknown error")))
		return false


func recall_rig(rig_id: int) -> bool:
	var http := _get_http_request()
	var headers := _auth_headers()
	var body := JSON.stringify({"rig_id": rig_id})

	var result := await _http_request_async(http, base_url + "/game/recall-rig", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if result["success"]:
		return true
	else:
		push_warning("Failed to recall rig: " + str(result.get("error", "Unknown error")))
		return false


# ══════════════════════════════════════════════════════════════════════════════
# WORKERS
# ══════════════════════════════════════════════════════════════════════════════

func get_available_workers() -> Array:
	var http := _get_http_request()
	var headers := _auth_headers()

	var result := await _http_request_async(http, base_url + "/game/available-workers", headers, HTTPClient.METHOD_GET)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		push_warning("Failed to get available workers: " + str(result.get("error", "Unknown error")))
		return []


func hire_worker(worker_id: int):
	var http := _get_http_request()
	var headers := _auth_headers()
	var body := JSON.stringify({"worker_id": worker_id})

	var result := await _http_request_async(http, base_url + "/game/hire", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to hire worker: " + str(err))
		return null


func fire_worker(worker_id: int) -> void:
	var http := _get_http_request()
	var headers := _auth_headers()

	var result := await _http_request_async(http, base_url + "/game/fire/%d" % worker_id, headers, HTTPClient.METHOD_POST)
	_return_http_request(http)

	if not result["success"]:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to fire worker: " + str(err))


func assign_worker(worker_id: int, ship_id: int) -> void:
	var http := _get_http_request()
	var headers := _auth_headers()
	var body := JSON.stringify({"ship_id": ship_id})

	var result := await _http_request_async(http, base_url + "/api/workers/%d/assign" % worker_id, headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if not result["success"]:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to assign worker: " + str(err))


func unassign_worker(worker_id: int) -> void:
	var http := _get_http_request()
	var headers := _auth_headers()

	var result := await _http_request_async(http, base_url + "/api/workers/%d/unassign" % worker_id, headers, HTTPClient.METHOD_POST)
	_return_http_request(http)

	if not result["success"]:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to unassign worker: " + str(err))


# ══════════════════════════════════════════════════════════════════════════════
# EQUIPMENT
# ══════════════════════════════════════════════════════════════════════════════

func buy_equipment(ship_id: int, equipment_name: String):
	var http := _get_http_request()
	var headers := _auth_headers()
	var body := JSON.stringify({
		"ship_id": ship_id,
		"equipment_name": equipment_name
	})

	var result := await _http_request_async(http, base_url + "/game/buy-equipment", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to buy equipment: " + str(err))
		return null


func sell_equipment(equipment_id: int) -> void:
	var http := _get_http_request()
	var headers := _auth_headers()
	var body := JSON.stringify({"equipment_id": equipment_id})

	var result := await _http_request_async(http, base_url + "/game/sell-equipment", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if not result["success"]:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to sell equipment: " + str(err))


# ══════════════════════════════════════════════════════════════════════════════
# WORLD DATA
# ══════════════════════════════════════════════════════════════════════════════

func get_colonies() -> Array:
	var http := _get_http_request()
	var headers := _auth_headers()

	var result := await _http_request_async(http, base_url + "/api/colonies", headers, HTTPClient.METHOD_GET)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to get colonies: " + str(err))
		return []


func get_asteroids() -> Array:
	var http := _get_http_request()
	var headers := _auth_headers()

	var result := await _http_request_async(http, base_url + "/api/asteroids", headers, HTTPClient.METHOD_GET)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to get asteroids: " + str(err))
		return []


func get_market_prices() -> Dictionary:
	var http := _get_http_request()
	var headers := _auth_headers()

	var result := await _http_request_async(http, base_url + "/api/market/prices", headers, HTTPClient.METHOD_GET)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to get market prices: " + str(err))
		return {}


# ══════════════════════════════════════════════════════════════════════════════
# POLICIES
# ══════════════════════════════════════════════════════════════════════════════

func update_policies(policies: Dictionary) -> void:
	var http := _get_http_request()
	var headers := _auth_headers()
	var body := JSON.stringify(policies)

	var result := await _http_request_async(http, base_url + "/game/policies", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if not result["success"]:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to update policies: " + str(err))


func sell_cargo(ship_id: int):
	var http := _get_http_request()
	var headers := _auth_headers()

	var result := await _http_request_async(http, base_url + "/game/sell-cargo/%d" % ship_id, headers, HTTPClient.METHOD_POST)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		push_warning("Failed to sell cargo: " + str(result.get("error", "Unknown error")))
		return null


func dispatch_trade(ship_id: int, colony_id: int):
	var http := _get_http_request()
	var headers := _auth_headers()

	var url := base_url + "/game/dispatch-trade?ship_id=%d&colony_id=%d" % [ship_id, colony_id]
	var result := await _http_request_async(http, url, headers, HTTPClient.METHOD_POST)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		push_warning("Failed to dispatch trade mission: " + str(result.get("error", "Unknown error")))
		return null


func attack_ship(attacker_ship_id: int, target_ship_id: int):
	var http := _get_http_request()
	var headers := _auth_headers()

	var url := base_url + "/game/attack?attacker_ship_id=%d&target_ship_id=%d" % [attacker_ship_id, target_ship_id]
	var result := await _http_request_async(http, url, headers, HTTPClient.METHOD_POST)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		push_warning("Attack failed: " + str(result.get("error", "Unknown error")))
		return null


# ══════════════════════════════════════════════════════════════════════════════
# UTILITY
# ══════════════════════════════════════════════════════════════════════════════

func is_backend_ready() -> bool:
	# Quick sync check - assumes server is ready if we have a token
	# For a real check, would need to ping /health endpoint
	return auth_token != ""


func get_backend_type() -> String:
	return "server"


## Fetch current player info from /auth/me
func _fetch_player_info() -> void:
	var http := _get_http_request()
	var headers := _auth_headers()

	var result := await _http_request_async(http, base_url + "/auth/me", headers, HTTPClient.METHOD_GET)
	_return_http_request(http)

	if result["success"]:
		var data: Dictionary = result["data"]
		player_id = data.get("id", 0)
		is_admin = data.get("is_admin", false)


## Get leaderboard entries sorted by net worth
## Returns: Array of { rank, player_id, username, net_worth, money, ship_value, ships_count, workers_count }
func get_leaderboard(limit: int = 100, offset: int = 0) -> Dictionary:
	var http := _get_http_request()
	var headers := _auth_headers()
	var url := base_url + "/api/leaderboard?limit=%d&offset=%d" % [limit, offset]

	var result := await _http_request_async(http, url, headers, HTTPClient.METHOD_GET)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to get leaderboard: " + str(err))
		return {"entries": [], "total_players": 0}


## Get player's rank and stats
## Returns: { rank, player_id, username, net_worth, money, ship_value, ships_count, workers_count }
func get_player_rank(player_id: int) -> Dictionary:
	var http := _get_http_request()
	var headers := _auth_headers()
	var url := base_url + "/api/leaderboard/player/%d" % player_id

	var result := await _http_request_async(http, url, headers, HTTPClient.METHOD_GET)
	_return_http_request(http)

	if result["success"]:
		return result["data"]
	else:
		var err = result.get("error", "Unknown error")
		push_warning("Failed to get player rank: " + str(err))
		return {}


# ══════════════════════════════════════════════════════════════════════════════
# INTERNAL HELPERS
# ══════════════════════════════════════════════════════════════════════════════

func _auth_headers() -> Array:
	var headers := ["Content-Type: application/json"]
	if auth_token != "":
		headers.append("Authorization: Bearer " + auth_token)
	return headers


func _get_http_request() -> HTTPRequest:
	if _http_pool.is_empty():
		var http := HTTPRequest.new()
		http.set_tls_options(TLSOptions.client())
		http.timeout = 10.0
		return http
	else:
		return _http_pool.pop_back()


func _return_http_request(http: HTTPRequest) -> void:
	if _http_pool.size() < MAX_POOL_SIZE:
		_http_pool.append(http)
	else:
		http.queue_free()


## Make async HTTP request and return result
## Returns: { "success": bool, "data": Variant, "error": String }
func _http_request_async(http: HTTPRequest, url: String, headers: Array, method: int, body: String = "") -> Dictionary:
	if not _backend_manager:
		push_error("ServerBackend: _backend_manager not set!")
		return {
			"success": false,
			"data": null,
			"error": "Backend manager not initialized"
		}

	# Add to tree temporarily for request
	_backend_manager.add_child(http)

	var error := http.request(url, headers, method, body)
	if error != OK:
		_backend_manager.remove_child(http)
		http.queue_free()
		return {
			"success": false,
			"data": null,
			"error": "HTTP request failed: %d" % error
		}

	# Wait for completion
	var response: Array = await http.request_completed

	# Remove from tree
	_backend_manager.remove_child(http)

	var result: int = response[0]
	var response_code: int = response[1]
	var response_headers: PackedStringArray = response[2]
	var response_body: PackedByteArray = response[3]

	if result != HTTPRequest.RESULT_SUCCESS:
		var error_msg := "HTTP request failed: "
		match result:
			HTTPRequest.RESULT_CANT_CONNECT:
				error_msg += "Can't connect to server"
			HTTPRequest.RESULT_CANT_RESOLVE:
				error_msg += "Can't resolve domain name"
			HTTPRequest.RESULT_CONNECTION_ERROR:
				error_msg += "Connection error"
			HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
				error_msg += "TLS/SSL certificate error"
			HTTPRequest.RESULT_NO_RESPONSE:
				error_msg += "No response from server"
			HTTPRequest.RESULT_TIMEOUT:
				error_msg += "Request timeout"
			_:
				error_msg += "Unknown error (code %d)" % result

		return {
			"success": false,
			"data": null,
			"error": error_msg,
			"result": result,
			"response_code": response_code
		}

	if response_code < 200 or response_code >= 300:
		var error_msg: String = "HTTP %d" % response_code
		var body_text := response_body.get_string_from_utf8()
		if body_text != "":
			var json := JSON.new()
			if json.parse(body_text) == OK:
				if json.data is Dictionary:
					var detail = json.data.get("detail", null)
					if detail != null and detail is String:
						error_msg = detail
					elif detail != null:
						error_msg = str(detail)
				elif json.data is String:
					error_msg = json.data
		return {
			"success": false,
			"data": null,
			"error": error_msg
		}

	# Parse JSON response
	var body_text := response_body.get_string_from_utf8()
	if body_text == "":
		return {"success": true, "data": null, "error": ""}

	var json := JSON.new()
	if json.parse(body_text) != OK:
		return {
			"success": false,
			"data": null,
			"error": "Failed to parse JSON response"
		}

	return {
		"success": true,
		"data": json.data,
		"error": ""
	}


# ══════════════════════════════════════════════════════════════════════════════
# SERVER-SENT EVENTS (Phase 2)
# ══════════════════════════════════════════════════════════════════════════════

## Subscribe to server event stream
func subscribe_events(callback: Callable) -> void:
	if not _backend_manager:
		push_error("ServerBackend: Cannot subscribe to events - backend_manager not set")
		return

	if _sse_connected:
		return

	# Create HTTPRequest for SSE stream
	_sse_http = HTTPRequest.new()
	_sse_http.set_tls_options(TLSOptions.client())
	_sse_http.timeout = 30.0  # Longer timeout for SSE stream
	_backend_manager.add_child(_sse_http)

	# Connect to chunk_received signal for streaming response
	_sse_http.request_completed.connect(_on_sse_closed)

	var url := base_url + "/events/stream"
	var headers := ["Authorization: Bearer " + auth_token]

	var error := _sse_http.request(url, headers)

	if error != OK:
		push_error("Failed to start SSE request: %d" % error)
		_sse_http.queue_free()
		_sse_http = null
		return

	_sse_connected = true
	_sse_buffer = ""

	# Poll for data using _process in BackendManager or a Timer
	# For now, we'll use request_completed which fires when connection closes
	# TODO: Implement proper streaming chunk processing


## Unsubscribe from server events
func unsubscribe_events() -> void:
	if _sse_http:
		_sse_http.cancel_request()
		_sse_http.queue_free()
		_sse_http = null

	_sse_connected = false
	_sse_buffer = ""


func _on_sse_closed(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray) -> void:
	if result == HTTPRequest.RESULT_SUCCESS and response_code == 200:
		# Parse any final events in body
		var body_text := body.get_string_from_utf8()
		if body_text != "":
			_parse_sse_data(body_text)

	_sse_connected = false

	# Auto-reconnect after 1 second if we're still in SERVER mode
	if _backend_manager:
		await _backend_manager.get_tree().create_timer(1.0).timeout
		if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
			subscribe_events(Callable())  # Reconnect


func _parse_sse_data(data: String) -> void:
	"""Parse Server-Sent Events data format"""
	_sse_buffer += data

	var lines := _sse_buffer.split("\n")
	var event_data := ""

	for line in lines:
		if line.begins_with("data: "):
			event_data = line.substr(6)  # Remove "data: " prefix

			# Try to parse as JSON
			var json := JSON.new()
			if json.parse(event_data) == OK and json.data is Dictionary:
				var event: Dictionary = json.data
				_handle_server_event(event)

	# Clear buffer after processing
	_sse_buffer = ""


func _handle_server_event(event: Dictionary) -> void:
	"""Route server events to GameState"""
	var event_type: String = event.get("type", "")

	match event_type:
		"connected":
			pass  # Connection established

		"mission_completed":
			pass  # GameState will handle via polling for now

		"payroll_deducted":
			# Update money directly
			if event.has("new_balance"):
				GameState.money = int(event["new_balance"])

		"worker_skill_leveled":
			WorkerManager.apply_worker_skill_event(event)

		"market_update":
			MarketManager.apply_market_update_event(event)

		"pvp_combat":
			GameState.apply_pvp_combat_event(event)

		"world_reset_warning":
			GameState.apply_world_reset_warning(event)

		"world_reset_complete":
			GameState.apply_world_reset_complete(event)

		_:
			pass  # Unhandled event type


# ══════════════════════════════════════════════════════════════════════════════
# BUG REPORTS
# ══════════════════════════════════════════════════════════════════════════════

func submit_bug_report(title: String, description: String, category: String, game_version: String) -> Dictionary:
	"""Submit a bug report to the server (no auth required)"""
	var http := _get_http_request()
	var headers := ["Content-Type: application/json"]  # No auth required

	var body := JSON.stringify({
		"title": title,
		"description": description,
		"category": category,
		"game_version": game_version,
		"backend_mode": "server",
		"reporter_username": saved_username if saved_username != "" else "Anonymous"
	})

	var result := await _http_request_async(http, base_url + "/api/bug-reports", headers, HTTPClient.METHOD_POST, body)
	_return_http_request(http)

	if result["success"]:
		return {"success": true, "error": ""}
	else:
		return {"success": false, "error": result.get("error", "Failed to submit bug report")}
