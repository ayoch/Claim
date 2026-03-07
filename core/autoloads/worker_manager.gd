extends Node

## WorkerManager
## Centralized worker lifecycle, assignment, deployment, and management logic
## Extracted from GameState to improve code organization and maintainability

# Internal state owned by WorkerManager
var _available_workers_cache: Array[Worker] = []
var _available_workers_dirty: bool = true
var hitchhike_pool: Array[Dictionary] = []
var tardy_workers: Array[Dictionary] = []
var deployed_crews: Array[Dictionary] = []

# Dependencies (injected from GameState)
var _game_state: Node = null


func _ready() -> void:
	# Wait for GameState to be ready, then link dependencies
	call_deferred("_initialize")


func _initialize() -> void:
	_game_state = get_node("/root/GameState")
	if not _game_state:
		push_error("[WorkerManager] Failed to find GameState autoload")


## Transfer existing worker state from GameState
func import_worker_state_from_game_state(gs_hitchhike_pool: Array[Dictionary], gs_tardy_workers: Array[Dictionary], gs_deployed_crews: Array[Dictionary]) -> void:
	hitchhike_pool = gs_hitchhike_pool
	tardy_workers = gs_tardy_workers
	deployed_crews = gs_deployed_crews
	_invalidate_worker_cache()


## ═══════════════════════════════════════════════════════════════════
## WORKER LIFECYCLE
## ═══════════════════════════════════════════════════════════════════

## Hire a new worker (add to company roster)
func hire_worker(worker: Worker) -> void:
	if not _game_state:
		push_error("[WorkerManager] GameState not initialized")
		return

	_game_state.workers.append(worker)
	_invalidate_worker_cache()
	EventBus.worker_hired.emit(worker)


## Fire a worker (remove from company, clean up all assignments)
func fire_worker(worker: Worker) -> void:
	if not _game_state:
		push_error("[WorkerManager] GameState not initialized")
		return

	Worker.release_name(worker.worker_name)
	_game_state.workers.erase(worker)
	_invalidate_worker_cache()
	# Remove from ship crew
	if worker.assigned_ship:
		worker.assigned_ship.crew.erase(worker)
	worker.assigned_ship = null
	# Remove from any mining unit — check all deployed units in case pointer is out of sync
	if worker.assigned_mining_unit and is_instance_valid(worker.assigned_mining_unit):
		worker.assigned_mining_unit.assigned_workers.erase(worker)
	for unit in _game_state.deployed_mining_units:
		if worker in unit.assigned_workers:
			unit.assigned_workers.erase(worker)
	worker.assigned_mining_unit = null

	# Final cleanup to break all circular references
	worker.cleanup()
	EventBus.worker_fired.emit(worker)


## Mode-aware worker hiring - works in both LOCAL and SERVER modes
func hire_worker_any_mode(worker_id: int) -> void:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		# SERVER mode: route through BackendManager
		await BackendManager.hire_worker(worker_id)
		# Note: Worker will appear in GameState on next automatic state poll
		# UI should set dirty flag after await completes
	else:
		push_warning("[WorkerManager] hire_worker_any_mode() called in LOCAL mode - use hire_worker(worker) instead")


## Mode-aware worker firing - works in both LOCAL and SERVER modes
func fire_worker_any_mode(worker: Worker) -> void:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		# SERVER mode: route through BackendManager using server ID
		if worker.server_id > 0:
			BackendManager.fire_worker(worker.server_id)
			# State refresh will remove worker via polling
		else:
			push_warning("[WorkerManager] Worker %s has no server_id, cannot fire in SERVER mode" % worker.worker_name)
	else:
		# LOCAL mode: use local WorkerManager directly
		fire_worker(worker)


## ═══════════════════════════════════════════════════════════════════
## WORKER ASSIGNMENT
## ═══════════════════════════════════════════════════════════════════

## Assign a worker to a ship's crew (with location validation)
func assign_worker_to_ship(worker: Worker, ship: Ship) -> Dictionary:
	# Location validation: worker must be at same colony as ship
	if ship:
		var ship_location := ""
		if ship.docked_at_earth:
			ship_location = "Earth"
		elif ship.docked_at_colony != null:
			ship_location = ship.docked_at_colony.colony_name
		else:
			return {"success": false, "error": "Ship must be docked to assign crew"}

		if worker.home_colony != ship_location:
			return {"success": false, "error": "Worker at %s cannot crew ship at %s" % [worker.home_colony, ship_location]}

	# Proceed with assignment
	if worker.assigned_ship == ship:
		return {"success": true}
	if worker.assigned_ship:
		worker.assigned_ship.crew.erase(worker)
	worker.assigned_ship = ship
	if ship and worker not in ship.crew:
		ship.crew.append(worker)
	return {"success": true}


## Remove a worker from a ship's crew
func remove_worker_from_ship(worker: Worker, ship: Ship) -> void:
	ship.crew.erase(worker)
	if worker.assigned_ship == ship:
		worker.assigned_ship = null


## Get list of workers available for assignment (cached)
func get_available_workers() -> Array[Worker]:
	if not _game_state:
		push_error("[WorkerManager] GameState not initialized")
		return []

	if _available_workers_dirty:
		_available_workers_cache.clear()
		for w in _game_state.workers:
			if w.is_available:
				_available_workers_cache.append(w)
		_available_workers_dirty = false
	return _available_workers_cache


## ═══════════════════════════════════════════════════════════════════
## WORKER DEPLOYMENT
## ═══════════════════════════════════════════════════════════════════

## Deploy crew to an asteroid station
func deploy_crew(asteroid: AsteroidData, crew_workers: Array[Worker], initial_supplies: Dictionary) -> void:
	if not _game_state:
		push_error("[WorkerManager] GameState not initialized")
		return

	# Remove workers from available pool
	for w in crew_workers:
		pass  # Workers assigned to mining units are tracked via assigned_mining_unit
	var entry: Dictionary = {
		"asteroid": asteroid,
		"workers": crew_workers.duplicate(),
		"supplies": initial_supplies.duplicate(),
		"deployed_at": _game_state.total_ticks,
	}
	deployed_crews.append(entry)
	EventBus.crew_deployed.emit(asteroid, crew_workers)


## Recall crew from an asteroid station
func recall_crew(asteroid: AsteroidData) -> void:
	for i in range(deployed_crews.size() - 1, -1, -1):
		var entry: Dictionary = deployed_crews[i]
		if entry["asteroid"] == asteroid:
			var crew_workers: Array = entry["workers"]
			EventBus.crew_recalled.emit(asteroid, crew_workers)
			deployed_crews.remove_at(i)
			break


## Get deployed crew at a specific asteroid
func get_deployed_crew_at(asteroid: AsteroidData) -> Dictionary:
	for entry in deployed_crews:
		if entry["asteroid"] == asteroid:
			return entry
	return {}


## ═══════════════════════════════════════════════════════════════════
## HITCHHIKE SYSTEM
## ═══════════════════════════════════════════════════════════════════

## Helper: Get colony position by name
func _get_colony_position(colony_name: String) -> Vector2:
	if colony_name == "Earth":
		return CelestialData.get_earth_position_au()
	for colony in _game_state.colonies:
		if colony.colony_name == colony_name:
			return colony.get_position_au()
	return CelestialData.get_earth_position_au()  # Fallback

## Add worker to hitchhike pool when on leave
func add_to_hitchhike_pool(worker: Worker, location_name: String, location_pos: Vector2) -> void:
	if not _game_state:
		push_error("[WorkerManager] GameState not initialized")
		return

	# 35% chance worker stays put (doesn't want to go home)
	if randf() < 0.35:
		worker.leave_status = 1  # Just on leave, no ride wanted
		return
	# Skip if worker's home IS this location
	if worker.home_colony == location_name:
		worker.leave_status = 1
		return
	# Skip duplicates
	for entry in hitchhike_pool:
		if entry["worker"] == worker:
			return
	worker.leave_status = 2
	var max_wait := randf_range(7.0, 14.0) * 86400.0  # 7-14 game-days in ticks
	hitchhike_pool.append({
		"worker": worker,
		"location_name": location_name,
		"location_pos": location_pos,
		"entered_at": _game_state.total_ticks,
		"max_wait": max_wait,
	})
	EventBus.worker_waiting_for_ride.emit(worker, location_name)

## Check for hitchhike opportunities when ships arrive at colonies
func check_hitchhike_opportunities(ship: Ship, route_positions: Array[Vector2]) -> void:
	var matched: Array[Dictionary] = []
	for entry in hitchhike_pool:
		var worker: Worker = entry["worker"]
		var worker_pos: Vector2 = entry["location_pos"]
		# Must be at ship's current location (within 0.05 AU)
		if ship.position_au.distance_to(worker_pos) > 0.05:
			continue
		# Check if any route waypoint passes within 0.1 AU of worker's home colony
		var home_pos := _get_colony_position(worker.home_colony)
		for route_pos in route_positions:
			if route_pos.distance_to(home_pos) < 0.1:
				matched.append(entry)
				break
	for entry in matched:
		var worker: Worker = entry["worker"]
		hitchhike_pool.erase(entry)
		worker.leave_status = 1  # On leave (riding home)
		worker.loyalty = minf(worker.loyalty + 3.0, 100.0)
		EventBus.worker_hitched_ride.emit(worker, ship)

## Forgive a tardy worker (boost loyalty)
func forgive_tardy_worker(worker: Worker) -> void:
	for i in range(tardy_workers.size() - 1, -1, -1):
		if tardy_workers[i]["worker"] == worker:
			tardy_workers.remove_at(i)
			break
	worker.leave_status = 0
	worker.fatigue = 0.0
	worker.loyalty = minf(worker.loyalty + 5.0, 100.0)
	EventBus.worker_tardiness_resolved.emit(worker, "forgiven")

## Dock wages from a tardy worker
func dock_pay_tardy_worker(worker: Worker) -> void:
	if not _game_state:
		push_error("[WorkerManager] GameState not initialized")
		return

	for i in range(tardy_workers.size() - 1, -1, -1):
		if tardy_workers[i]["worker"] == worker:
			tardy_workers.remove_at(i)
			break
	worker.leave_status = 0
	worker.fatigue = 0.0
	worker.loyalty = maxf(worker.loyalty - 8.0, 0.0)
	# Dock 3 days wages
	_game_state.money += worker.wage * 3
	EventBus.worker_tardiness_resolved.emit(worker, "docked")

## Fire a tardy worker (with violation record)
func fire_tardy_worker(worker: Worker) -> void:
	if not _game_state:
		push_error("[WorkerManager] GameState not initialized")
		return

	# Record abandonment violation before firing
	_game_state.record_abandonment_violation(worker, "Worker %s abandoned (fired while tardy)" % worker.worker_name)

	for i in range(tardy_workers.size() - 1, -1, -1):
		if tardy_workers[i]["worker"] == worker:
			tardy_workers.remove_at(i)
			break
	worker.leave_status = 0
	EventBus.worker_tardiness_resolved.emit(worker, "fired")
	fire_worker(worker)


## ═══════════════════════════════════════════════════════════════════
## VIOLATIONS & EVENTS
## ═══════════════════════════════════════════════════════════════════

## Record worker death violation at their home colony
func record_worker_death_violation(worker: Worker, reason: String) -> void:
	if not _game_state:
		push_error("[WorkerManager] GameState not initialized")
		return

	# Record death at worker's home colony
	var colony_name: String = worker.home_colony if worker.home_colony != "" else "Earth"
	var colony: Colony = _game_state._find_colony_by_name(colony_name)
	if colony:
		colony.add_violation(reason, _game_state.total_ticks)
		print("VIOLATION recorded at %s: %s" % [colony_name, reason])
		EventBus.violation_recorded.emit(colony, reason)

## Record worker abandonment violation at their home colony
func record_abandonment_violation(worker: Worker, reason: String) -> void:
	if not _game_state:
		push_error("[WorkerManager] GameState not initialized")
		return

	# Record abandonment at worker's home colony
	var colony_name: String = worker.home_colony if worker.home_colony != "" else "Earth"
	var colony: Colony = _game_state._find_colony_by_name(colony_name)
	if colony:
		colony.add_violation(reason, _game_state.total_ticks)
		print("VIOLATION recorded at %s: %s" % [colony_name, reason])
		EventBus.violation_recorded.emit(colony, reason)

## Apply worker skill update from server event
func apply_worker_skill_event(event: Dictionary) -> void:
	if not _game_state:
		push_error("[WorkerManager] GameState not initialized")
		return

	var worker_name: String = event.get("worker_name", "")
	var skill_type_str: String = event.get("skill_type", "")
	var new_value: float = float(event.get("new_value", 0.0))

	# Find worker by name
	var found_worker: Worker = null
	for worker in _game_state.workers:
		if worker.worker_name == worker_name:
			found_worker = worker
			break

	if not found_worker:
		push_warning("apply_worker_skill_event: Worker '%s' not found" % worker_name)
		return

	# Map skill type string to int (0=pilot, 1=engineer, 2=mining)
	var skill_type_int := -1
	match skill_type_str:
		"pilot":
			found_worker.pilot_skill = new_value
			skill_type_int = 0
		"engineer":
			found_worker.engineer_skill = new_value
			skill_type_int = 1
		"mining":
			found_worker.mining_skill = new_value
			skill_type_int = 2
		_:
			push_warning("apply_worker_skill_event: Unknown skill type '%s'" % skill_type_str)
			return

	# Recalculate wage (server does this too, but we mirror it for consistency)
	var total_skill := found_worker.pilot_skill + found_worker.engineer_skill + found_worker.mining_skill
	found_worker.wage = int(80 + total_skill * 40)

	print("[WorkerManager] Worker skill updated via SSE: %s - %s → %.2f (wage: $%d)" % [
		worker_name, skill_type_str, new_value, found_worker.wage
	])

	# Emit signal for UI update (signal expects int for skill_type)
	EventBus.worker_skill_leveled.emit(found_worker, skill_type_int, new_value)


## ═══════════════════════════════════════════════════════════════════
## INITIALIZATION
## ═══════════════════════════════════════════════════════════════════

## Initialize starter crew for new game
func init_starter_crew() -> void:
	if not _game_state:
		_game_state = get_node_or_null("/root/GameState")
	if not _game_state:
		push_error("[WorkerManager] GameState not initialized")
		return

	# Hire starter crew with guaranteed specialty coverage: pilot, engineer, miner
	# Scale total workers to staff all starting ships plus a buffer of 3 spares
	var total_min_crew := 0
	for ship in _game_state.ships:
		total_min_crew += ship.min_crew
	var total_workers := total_min_crew + 3

	# First 3 workers get guaranteed primary specialties
	var primaries := [0, 1, 2]  # pilot, engineer, mining
	for i in range(total_workers):
		var worker: Worker
		if i < primaries.size():
			worker = Worker.generate_with_primary(primaries[i])
		else:
			worker = Worker.generate_random()
		_game_state.workers.append(worker)


## ═══════════════════════════════════════════════════════════════════
## CACHE MANAGEMENT
## ═══════════════════════════════════════════════════════════════════

## Mark available workers cache as dirty (needs rebuild)
func _invalidate_worker_cache() -> void:
	_available_workers_dirty = true
