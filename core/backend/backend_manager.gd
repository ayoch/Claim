extends Node

## BackendManager - Singleton that manages active backend (Local or Server)
## Add to project.godot as autoload: BackendManager

enum BackendMode {
	LOCAL,      # Single-player with local saves
	SERVER,     # Multiplayer with server connection
}

var current_mode: BackendMode = BackendMode.LOCAL
var _active_backend = null  # BackendInterface implementation

# Backend instances will be created on-demand
var _local_backend = null
var _server_backend = null


func _ready() -> void:
	print("BackendManager initialized")
	_initialize_backends()


func _initialize_backends() -> void:
	# Create local backend
	var LocalBackendScript = load("res://core/backend/local_backend.gd")
	_local_backend = LocalBackendScript.new()

	# Create server backend
	var ServerBackendScript = load("res://core/backend/server_backend.gd")
	_server_backend = ServerBackendScript.new()
	_server_backend.set_backend_manager(self)  # Give it reference to this Node for HTTP requests

	# Start with local mode
	switch_mode(BackendMode.LOCAL)


## Switch between local and server backends
func switch_mode(mode: BackendMode) -> void:
	current_mode = mode

	match mode:
		BackendMode.LOCAL:
			_active_backend = _local_backend
			print("Switched to LOCAL backend")
		BackendMode.SERVER:
			if _server_backend:
				_active_backend = _server_backend
				print("Switched to SERVER backend")
				# Reset local state for server mode (server is source of truth)
				GameState.reset_for_server_mode()
			else:
				push_error("Server backend not yet implemented")
				_active_backend = _local_backend
				current_mode = BackendMode.LOCAL

	EventBus.backend_mode_changed.emit(current_mode)


## Get current backend type for debugging
func get_backend_type() -> String:
	if _active_backend and _active_backend.has_method("get_backend_type"):
		return _active_backend.get_backend_type()
	return "none"


## Check if backend is ready
func is_backend_ready() -> bool:
	if _active_backend and _active_backend.has_method("is_backend_ready"):
		return _active_backend.is_backend_ready()
	return false


## Get server backend directly (for leaderboard access)
func get_server_backend():
	return _server_backend


# ══════════════════════════════════════════════════════════════════════════════
# DELEGATE ALL BACKEND OPERATIONS
# ══════════════════════════════════════════════════════════════════════════════

# Auth
func login(username: String, password: String) -> Dictionary:
	return await _active_backend.login(username, password)


func register(username: String, password: String, email: String) -> Dictionary:
	return await _active_backend.register(username, password, email)


func logout() -> void:
	_active_backend.logout()


# Game State
func get_game_state() -> Dictionary:
	return await _active_backend.get_game_state()


func save_game() -> void:
	_active_backend.save_game()


func load_game(save_name: String) -> bool:
	return _active_backend.load_game(save_name)


func get_save_files() -> Array:
	return _active_backend.get_save_files()


# Ships & Missions
func dispatch_mission(ship_id: int, asteroid_id: int, mission_type: int, mining_duration: float, return_to_station: bool):
	return await _active_backend.dispatch_mission(ship_id, asteroid_id, mission_type, mining_duration, return_to_station)


func buy_ship(ship_class: int, ship_name: String, colony_id: int):
	return await _active_backend.buy_ship(ship_class, ship_name, colony_id)


func sell_ship(ship_id: int) -> void:
	await _active_backend.sell_ship(ship_id)


# Workers
func hire_worker(worker_id: int):
	return await _active_backend.hire_worker(worker_id)


func fire_worker(worker_id: int) -> void:
	await _active_backend.fire_worker(worker_id)


func assign_worker(worker_id: int, ship_id: int) -> void:
	await _active_backend.assign_worker(worker_id, ship_id)


func unassign_worker(worker_id: int) -> void:
	await _active_backend.unassign_worker(worker_id)


# World Data
func get_colonies() -> Array:
	return await _active_backend.get_colonies()


func get_asteroids() -> Array:
	return await _active_backend.get_asteroids()


func get_market_prices() -> Dictionary:
	return await _active_backend.get_market_prices()


# Ships & Cargo
func sell_cargo(ship_id: int):
	return await _active_backend.sell_cargo(ship_id)


func dispatch_trade(ship_id: int, colony_id: int):
	return await _active_backend.dispatch_trade(ship_id, colony_id)


# Policies
func update_policies(policies: Dictionary) -> void:
	await _active_backend.update_policies(policies)


# Events
func subscribe_events(callback: Callable) -> void:
	_active_backend.subscribe_events(callback)


func unsubscribe_events() -> void:
	_active_backend.unsubscribe_events()
