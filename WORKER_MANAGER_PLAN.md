# WorkerManager Extraction Plan

## Overview

Extract worker lifecycle, assignment, deployment, and management logic from `game_state.gd` into a new `WorkerManager` autoload. This is the second major extraction after MissionManager, aiming to reduce GameState from ~3,400 lines to ~2,600 lines.

## Scope Analysis

### Functions to Extract (20 total)

#### Worker Lifecycle (4 functions)
1. **hire_worker(worker)** - 4 lines - Adds worker to array, invalidates cache, emits event
2. **fire_worker(worker)** - 19 lines - Removes from all assignments, cleans up, emits event
3. **hire_worker_any_mode(worker_id)** - 8 lines - Backend routing for hiring
4. **fire_worker_any_mode(worker)** - 11 lines - Backend routing for firing

#### Worker Assignment (3 functions)
5. **assign_worker_to_ship(worker, ship)** - 23 lines - Location validation, assignment logic
6. **remove_worker_from_ship(worker, ship)** - 4 lines - Removes from ship crew
7. **get_available_workers()** - 8 lines - Returns cached available workers

#### Worker Deployment (3 functions)
8. **deploy_crew(asteroid, crew_workers, initial_supplies)** - 13 lines - Deploy crew to asteroid station
9. **recall_crew(asteroid)** - 11 lines - Recall deployed crew from asteroid
10. **get_deployed_crew_at(asteroid)** - 16 lines - Get crew deployed at specific asteroid

#### Hitchhike System (4 functions)
11. **add_to_hitchhike_pool(worker, location_name, location_pos)** - 16 lines - Add worker to hitchhike pool
12. **check_hitchhike_opportunities(ship, route_positions)** - 20 lines - Match workers to passing ships
13. **forgive_tardy_worker(worker)** - 8 lines - Forgive tardy worker
14. **dock_pay_tardy_worker(worker)** - 11 lines - Dock wages from tardy worker
15. **fire_tardy_worker(worker)** - 11 lines - Fire tardy worker with violation

#### Worker Violations (2 functions)
16. **record_worker_death_violation(worker, reason)** - 9 lines - Record death at colony
17. **record_abandonment_violation(worker, reason)** - 9 lines - Record abandonment at colony

#### Worker Skills (1 function)
18. **apply_worker_skill_event(event)** - ~20 lines - Apply skill progression events

#### Initialization (1 function)
19. **_init_starter_crew()** - 30 lines - Generate random starter crew

#### Cache Management (1 function)
20. **_invalidate_worker_cache()** - 2 lines - Mark cache dirty

**Total Estimated Lines: ~220 lines** (much smaller than MissionManager's 1,200 lines)

## Data Dependencies

### GameState Data Accessed:
- `workers: Array[Worker]` - Main worker list (KEEP IN GAMESTATE)
- `_available_workers_cache: Array[Worker]` - Cached available workers (MOVE TO WorkerManager)
- `_available_workers_dirty: bool` - Cache dirty flag (MOVE TO WorkerManager)
- `hitchhike_pool: Array[Dictionary]` - Workers waiting for rides (MOVE TO WorkerManager)
- `tardy_workers: Array[Dictionary]` - Workers on leave who didn't return (MOVE TO WorkerManager)
- `deployed_crews: Array[Dictionary]` - Crew deployed to asteroids (MOVE TO WorkerManager)
- `deployed_mining_units: Array[MiningUnit]` - For cleanup during firing (KEEP IN GAMESTATE)
- `money: int` - For wage docking (KEEP IN GAMESTATE)
- `colonies: Array[Colony]` - For violation tracking (KEEP IN GAMESTATE)

### Design Decision: Shared Data Model

Unlike MissionManager which could own missions/trade_missions arrays, WorkerManager **cannot own the workers array** because:
1. Workers are fundamental game state saved/loaded with GameState
2. Many systems need direct access to workers (UI, simulation, policies)
3. Server sync needs to update workers array directly

**Solution:** Workers array stays in GameState, WorkerManager operates on it via dependency injection (similar to how MissionManager operates on missions array through _game_state reference).

## Architecture Pattern

```gdscript
# worker_manager.gd
extends Node

var _game_state: Node = null

# Internal state owned by WorkerManager
var _available_workers_cache: Array[Worker] = []
var _available_workers_dirty: bool = true
var hitchhike_pool: Array[Dictionary] = []
var tardy_workers: Array[Dictionary] = []
var deployed_crews: Array[Dictionary] = []

func _ready() -> void:
    call_deferred("_initialize")

func _initialize() -> void:
    _game_state = get_node("/root/GameState")
    if not _game_state:
        push_error("[WorkerManager] Failed to find GameState autoload")

func hire_worker(worker: Worker) -> void:
    _game_state.workers.append(worker)
    _invalidate_worker_cache()
    EventBus.worker_hired.emit(worker)

# ... other functions
```

## Implementation Strategy

### Phase 1: Create WorkerManager Stub (1 function)
- Create `core/autoloads/worker_manager.gd`
- Add to project.godot after GameState
- Implement dependency injection pattern
- Start with simple function: **hire_worker()**
- Verify compilation and basic functionality

### Phase 2: Extract Lifecycle Functions (3 functions)
- Migrate fire_worker(), hire_worker_any_mode(), fire_worker_any_mode()
- These are core functions with many call sites
- Add forwarding stubs in GameState

### Phase 3: Extract Assignment Functions (3 functions)
- Migrate assign_worker_to_ship(), remove_worker_from_ship(), get_available_workers()
- Move cache management to WorkerManager
- Update all call sites

### Phase 4: Extract Deployment Functions (3 functions)
- Migrate deploy_crew(), recall_crew(), get_deployed_crew_at()
- Move deployed_crews array to WorkerManager
- Update simulation.gd calls

### Phase 5: Extract Hitchhike System (4 functions)
- Migrate add_to_hitchhike_pool(), check_hitchhike_opportunities(), forgive_tardy_worker(), dock_pay_tardy_worker(), fire_tardy_worker()
- Move hitchhike_pool and tardy_workers arrays to WorkerManager
- This is the most complex subsystem

### Phase 6: Extract Remaining Functions (3 functions)
- Migrate record_worker_death_violation(), record_abandonment_violation(), apply_worker_skill_event()
- Migrate _init_starter_crew()

## Call Site Analysis

### High-Impact Functions (10+ call sites):
- **get_available_workers()** - Used extensively in UI and simulation (~30+ call sites)
- **assign_worker_to_ship()** - Used in crew management UI (~15 call sites)
- **fire_worker()** - Used in worker management UI (~10 call sites)

### Medium-Impact Functions (5-10 call sites):
- **hire_worker()** - Used in hiring UI and simulation (~8 call sites)
- **remove_worker_from_ship()** - Used in crew management (~6 call sites)

### Low-Impact Functions (1-4 call sites):
- Most other functions have 1-3 call sites each

## Risks & Challenges

### High-Complexity Areas:
1. **Cache Management** - _available_workers_cache needs careful migration
2. **Hitchhike System** - Complex interactions between workers, ships, missions
3. **Deployment System** - Ties into mission system and mining units
4. **Backend Routing** - hire_worker_any_mode(), fire_worker_any_mode() need BackendManager access

### Circular Dependencies:
- Workers reference Ships via assigned_ship
- Ships reference Workers via crew array
- MiningUnits reference Workers via assigned_workers
- Missions can reference Workers via rescue_crew

**Mitigation:** Use dependency injection, keep circular references at data model level, not manager level.

## Benefits

1. **Reduced GameState complexity** - Remove ~220 lines, focus on core state
2. **Improved testability** - Worker logic isolated and testable
3. **Better organization** - Worker lifecycle separate from game state
4. **Consistent pattern** - Follows MissionManager extraction pattern

## Estimated Effort

- **Phase 1 (Stub + 1 function):** 30 minutes
- **Phase 2 (Lifecycle):** 1 hour
- **Phase 3 (Assignment):** 1.5 hours
- **Phase 4 (Deployment):** 1 hour
- **Phase 5 (Hitchhike):** 2 hours (most complex)
- **Phase 6 (Remaining):** 1 hour

**Total: ~7 hours**

## Success Criteria

- [ ] All 20 worker functions extracted to WorkerManager
- [ ] All call sites updated (estimated ~80 call sites)
- [ ] All forwarding stubs added to GameState
- [ ] Game compiles without errors
- [ ] All worker operations work correctly in both LOCAL and SERVER modes
- [ ] Cache invalidation works correctly
- [ ] Hitchhike system still functions
- [ ] Deployment system still functions
- [ ] No performance regressions

## Next Steps After WorkerManager

1. **Task #7: Extract MarketManager** (~500-800 lines)
   - Market operations, ore selling, colony trading
   - Less complex than WorkerManager

2. **Task #4: Split fleet_market_tab.gd** (4,241 lines → 5 components)
   - Largest UI file, needs modular split
   - Can be done after manager extractions

---

**Note:** This plan follows the successful MissionManager extraction pattern. Each phase can be done incrementally with commits, ensuring the game remains functional throughout the refactoring process.
