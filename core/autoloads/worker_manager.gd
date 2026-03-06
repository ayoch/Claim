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


## ═══════════════════════════════════════════════════════════════════
## CACHE MANAGEMENT
## ═══════════════════════════════════════════════════════════════════

## Mark available workers cache as dirty (needs rebuild)
func _invalidate_worker_cache() -> void:
	_available_workers_dirty = true
