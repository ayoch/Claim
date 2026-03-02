class_name BackendInterface
extends RefCounted

## Abstract backend interface for game operations
## Implementations: LocalBackend (single-player), ServerBackend (multiplayer)

# ══════════════════════════════════════════════════════════════════════════════
# AUTHENTICATION (Server only - local auto-succeeds)
# ══════════════════════════════════════════════════════════════════════════════

## Login with username/password
## Returns: { "success": bool, "token": String, "player_id": int, "error": String }
func login(username: String, password: String) -> Dictionary:
	push_error("BackendInterface.login() not implemented")
	return {"success": false, "error": "Not implemented"}

## Register new account
## Returns: { "success": bool, "player_id": int, "error": String }
func register(username: String, password: String, email: String) -> Dictionary:
	push_error("BackendInterface.register() not implemented")
	return {"success": false, "error": "Not implemented"}

## Logout and clear session
func logout() -> void:
	push_error("BackendInterface.logout() not implemented")


# ══════════════════════════════════════════════════════════════════════════════
# GAME STATE
# ══════════════════════════════════════════════════════════════════════════════

## Get current game state (money, ships, workers, missions, etc.)
## Returns: Dictionary with full game state
func get_game_state() -> Dictionary:
	push_error("BackendInterface.get_game_state() not implemented")
	return {}

## Save current game state
func save_game() -> void:
	push_error("BackendInterface.save_game() not implemented")

## Load game from save file (local only - multiplayer doesn't have save files)
## Returns: true if loaded successfully
func load_game(save_name: String) -> bool:
	push_error("BackendInterface.load_game() not implemented")
	return false

## Get list of available save files (local only)
## Returns: Array of save file names
func get_save_files() -> Array:
	push_error("BackendInterface.get_save_files() not implemented")
	return []


# ══════════════════════════════════════════════════════════════════════════════
# SHIPS & MISSIONS
# ══════════════════════════════════════════════════════════════════════════════

## Dispatch ship on mission
## Returns: Mission object/dictionary or null on failure
func dispatch_mission(
	ship_id: int,
	asteroid_id: int,
	mission_type: int,
	mining_duration: float,
	return_to_station: bool
) :
	push_error("BackendInterface.dispatch_mission() not implemented")
	return null

## Purchase new ship
## Returns: Ship object/dictionary or null on failure
func buy_ship(ship_class: int, ship_name: String, colony_id: int) :
	push_error("BackendInterface.buy_ship() not implemented")
	return null

## Sell ship (removes from fleet)
func sell_ship(ship_id: int) -> void:
	push_error("BackendInterface.sell_ship() not implemented")


# ══════════════════════════════════════════════════════════════════════════════
# WORKERS
# ══════════════════════════════════════════════════════════════════════════════

## Hire worker from colony
## Returns: Worker object/dictionary or null on failure
func hire_worker(colony_id: int) :
	push_error("BackendInterface.hire_worker() not implemented")
	return null

## Fire worker
func fire_worker(worker_id: int) -> void:
	push_error("BackendInterface.fire_worker() not implemented")

## Assign worker to ship
func assign_worker(worker_id: int, ship_id: int) -> void:
	push_error("BackendInterface.assign_worker() not implemented")

## Unassign worker from ship
func unassign_worker(worker_id: int) -> void:
	push_error("BackendInterface.unassign_worker() not implemented")


# ══════════════════════════════════════════════════════════════════════════════
# WORLD DATA (Asteroids, Colonies, Market)
# ══════════════════════════════════════════════════════════════════════════════

## Get list of all colonies
## Returns: Array of colony dictionaries
func get_colonies() -> Array:
	push_error("BackendInterface.get_colonies() not implemented")
	return []

## Get list of all asteroids
## Returns: Array of asteroid dictionaries
func get_asteroids() -> Array:
	push_error("BackendInterface.get_asteroids() not implemented")
	return []

## Get current market prices
## Returns: Dictionary of ore prices { "iron": 100, "nickel": 150, ... }
func get_market_prices() -> Dictionary:
	push_error("BackendInterface.get_market_prices() not implemented")
	return {}


# ══════════════════════════════════════════════════════════════════════════════
# POLICIES
# ══════════════════════════════════════════════════════════════════════════════

## Update company policies
## policies: { "thrust_policy": int, "supply_policy": int, etc. }
func update_policies(policies: Dictionary) -> void:
	push_error("BackendInterface.update_policies() not implemented")


# ══════════════════════════════════════════════════════════════════════════════
# REAL-TIME EVENTS (Server only - local emits signals directly)
# ══════════════════════════════════════════════════════════════════════════════

## Subscribe to real-time game events (SSE for server, local signals for local)
## callback: Callable that receives event dictionaries
func subscribe_events(callback: Callable) -> void:
	push_error("BackendInterface.subscribe_events() not implemented")

## Unsubscribe from events
func unsubscribe_events() -> void:
	push_error("BackendInterface.unsubscribe_events() not implemented")


# ══════════════════════════════════════════════════════════════════════════════
# UTILITY
# ══════════════════════════════════════════════════════════════════════════════

## Check if backend is connected/ready
func is_backend_ready() -> bool:
	push_error("BackendInterface.is_connected() not implemented")
	return false

## Get backend type for debugging
func get_backend_type() -> String:
	push_error("BackendInterface.get_backend_type() not implemented")
	return "unknown"
