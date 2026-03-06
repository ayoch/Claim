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
## CACHE MANAGEMENT
## ═══════════════════════════════════════════════════════════════════

## Mark available workers cache as dirty (needs rebuild)
func _invalidate_worker_cache() -> void:
	_available_workers_dirty = true
