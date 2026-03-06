# Fleet/Market Tab Integration Guide

## Status: Components Extracted, Integration Pending

**Date:** 2026-03-06
**Session:** Mac/HK-47 Session 3 (Continued)

---

## What's Done ✅

Successfully extracted **6 components** (~3,621 lines) from fleet_market_tab.gd:

| Component | Lines | Commit | File |
|-----------|-------|--------|------|
| FleetListPanel | 1,113 | 1fde0a0 | `ui/components/fleet_list_panel.gd` |
| DestinationSelector | 720 | 56e268f | `ui/components/destination_selector.gd` |
| WorkerSelector | 568 | 22a4f72 | `ui/components/worker_selector.gd` |
| MissionEstimator | 420 | acf1572 | `ui/components/mission_estimator.gd` |
| DispatchConfirmation | 300 | 39b5a67 | `ui/components/dispatch_confirmation.gd` |
| SpecialActionsPanel | 500 | 64fad13 | `ui/components/special_actions_panel.gd` |

**All components:**
- Use signal-based communication (no tight coupling)
- Maintain independent state
- Have `ContentContainer` with `%unique_name_in_owner`
- Follow consistent architectural patterns
- Are committed and ready to use

---

## What's Next: Integration (Phase 8)

The original `fleet_market_tab.gd` still has all the old code (4,241 lines). Integration will:
1. Wire up the 6 components
2. Remove old extracted functions
3. Result in ~640-line coordinator

### Integration Steps

#### 1. Add Component References (lines 17-22, after existing @onready vars)

```gdscript
# Component references
var _fleet_list_panel: FleetListPanel
var _destination_selector: DestinationSelector
var _worker_selector: WorkerSelector
var _mission_estimator: MissionEstimator
var _dispatch_confirmation: DispatchConfirmation
var _special_actions_panel: SpecialActionsPanel
```

#### 2. Instantiate Components in _ready() (after line 120)

```gdscript
# Load and add FleetListPanel
var fleet_list_scene := preload("res://ui/components/fleet_list_panel.tscn")
_fleet_list_panel = fleet_list_scene.instantiate()
ships_list.add_child(_fleet_list_panel)

# Load other components (keep ready to add to dispatch_content when needed)
_destination_selector = preload("res://ui/components/destination_selector.tscn").instantiate()
_worker_selector = preload("res://ui/components/worker_selector.tscn").instantiate()
_mission_estimator = preload("res://ui/components/mission_estimator.tscn").instantiate()
_dispatch_confirmation = preload("res://ui/components/dispatch_confirmation.tscn").instantiate()
_special_actions_panel = preload("res://ui/components/special_actions_panel.tscn").instantiate()
```

#### 3. Connect Signals (after component instantiation)

```gdscript
# FleetListPanel signals
_fleet_list_panel.dispatch_requested.connect(func(ship: Ship, planning: bool, redirect: bool) -> void:
	_start_dispatch(ship, planning, redirect)
)
_fleet_list_panel.partnership_requested.connect(func(ship: Ship) -> void:
	_selected_ship = ship
	_clear_dispatch_content()
	dispatch_content.add_child(_special_actions_panel)
	_special_actions_panel.show_partnership_selection(ship)
	_show_dispatch()
)
_fleet_list_panel.station_jobs_requested.connect(func(ship: Ship) -> void:
	_selected_ship = ship
	_clear_dispatch_content()
	dispatch_content.add_child(_special_actions_panel)
	_special_actions_panel.show_station_jobs(ship)
	_show_dispatch()
)
_fleet_list_panel.supply_shop_requested.connect(func(ship: Ship) -> void:
	_selected_ship = ship
	_clear_dispatch_content()
	dispatch_content.add_child(_special_actions_panel)
	_special_actions_panel.show_supply_shop(ship)
	_show_dispatch()
)
_fleet_list_panel.needs_rebuild.connect(func() -> void:
	_mark_dirty()
)

# DestinationSelector signals
_destination_selector.asteroid_selected.connect(func(asteroid: AsteroidData) -> void:
	_selected_asteroid = asteroid
	# Show worker selector next
	_clear_dispatch_content()
	dispatch_content.add_child(_worker_selector)
	_worker_selector.show_selection(
		_selected_ship, asteroid, false,
		_is_planning_mode, _is_redirect_mode, false,
		_available_slingshot_routes, _selected_slingshot_route, _selected_transit_mode
	)
	_show_dispatch()
)
_destination_selector.colony_selected.connect(func(colony: Colony) -> void:
	# Handle colony trade dispatch
	_confirm_colony_dispatch(colony)
)
_destination_selector.selection_cancelled.connect(func() -> void:
	_hide_dispatch()
	_cancel_preview()
)

# WorkerSelector signals
_worker_selector.workers_selected.connect(func(workers: Array[Worker], deploy_units: Array, deploy_workers: Array, mission_type: String) -> void:
	_selected_workers = workers
	_selected_deploy_units = deploy_units
	_selected_deploy_workers = deploy_workers
	_selected_mission_type = mission_type
	# Show mission estimator
	if not _mission_estimator.get_parent():
		dispatch_content.add_child(_mission_estimator)
	_mission_estimator.show_estimate(
		_selected_ship, _selected_asteroid, workers, false,
		_selected_transit_mode, _available_slingshot_routes, _selected_slingshot_route
	)
	_mission_estimator.visible = true
)
_worker_selector.back_requested.connect(func() -> void:
	# Go back to destination selection
	_clear_dispatch_content()
	dispatch_content.add_child(_destination_selector)
	_destination_selector.show_selection(_selected_ship, _is_planning_mode, _is_redirect_mode)
	_show_dispatch()
)
_worker_selector.cancelled.connect(func() -> void:
	_hide_dispatch()
	_cancel_preview()
)

# MissionEstimator signals
_mission_estimator.estimate_updated.connect(func(data: Dictionary) -> void:
	# Estimate updated, no action needed
	pass
)
_mission_estimator.transit_mode_changed.connect(func(mode: Mission.TransitMode) -> void:
	_selected_transit_mode = mode
)
_mission_estimator.route_changed.connect(func(route) -> void:
	_selected_slingshot_route = route
)

# DispatchConfirmation signals
_dispatch_confirmation.mission_dispatched.connect(func(ship: Ship, mission) -> void:
	_cancel_preview()
	_return_to_map_if_needed()
	_hide_dispatch()
	_mark_dirty()
)
_dispatch_confirmation.back_requested.connect(func() -> void:
	# Go back to worker selection
	_clear_dispatch_content()
	dispatch_content.add_child(_worker_selector)
	_worker_selector.show_selection(
		_selected_ship, _selected_asteroid, false,
		_is_planning_mode, _is_redirect_mode, false,
		_available_slingshot_routes, _selected_slingshot_route, _selected_transit_mode
	)
	_show_dispatch()
)
_dispatch_confirmation.dispatch_cancelled.connect(func() -> void:
	_hide_dispatch()
	_cancel_preview()
)

# SpecialActionsPanel signals
_special_actions_panel.partnership_created.connect(func(ship1: Ship, ship2: Ship) -> void:
	_hide_dispatch()
	_mark_dirty()
)
_special_actions_panel.station_confirmed.connect(func(ship: Ship, colony: Colony, jobs: Array[String]) -> void:
	if ship.is_stationed:
		GameState.update_station_jobs(ship, jobs)
	else:
		GameState.station_ship(ship, colony, jobs)
	_hide_dispatch()
	_mark_dirty()
)
_special_actions_panel.rescue_confirmed.connect(func(ferry: Ship, target: Ship, food: float, parts: float) -> void:
	_hide_dispatch()
	_mark_dirty()
)
_special_actions_panel.supplies_purchased.connect(func(ship: Ship, purchases: Dictionary) -> void:
	var any_bought := false
	for key in purchases:
		var qty: float = purchases[key]
		if GameState.buy_supplies(ship, key, qty):
			any_bought = true
		else:
			ship.add_station_log("Failed to buy %s" % key.replace("_", " "), "warning")
	if any_bought:
		ship.add_station_log("Purchased supplies", "system")
	_hide_dispatch()
	_mark_dirty()
)
_special_actions_panel.action_cancelled.connect(func() -> void:
	_hide_dispatch()
	_cancel_preview()
)
```

#### 4. Update Call Sites

Replace old function calls with component usage:

**_rebuild_ships() → FleetListPanel**
```gdscript
# OLD:
_rebuild_ships()

# NEW:
_fleet_list_panel.rebuild_ships()
```

**_start_dispatch() → Show DestinationSelector**
```gdscript
# In _start_dispatch() function, replace _show_asteroid_selection() call:
# OLD:
_show_asteroid_selection()

# NEW:
_clear_dispatch_content()
dispatch_content.add_child(_destination_selector)
_destination_selector.show_selection(_selected_ship, _is_planning_mode, _is_redirect_mode)
_show_dispatch()
```

**Worker Selection → Show WorkerSelector (already in signal handler above)**

**Confirmation → Show DispatchConfirmation**
```gdscript
# Create new function or inline where _confirm_dispatch() was called:
_clear_dispatch_content()
dispatch_content.add_child(_dispatch_confirmation)
_dispatch_confirmation.show_confirmation(
	_selected_ship, _selected_asteroid, _selected_workers, false,
	_is_planning_mode, _is_redirect_mode,
	_selected_transit_mode, _selected_slingshot_route,
	_selected_mission_type, _selected_deploy_units, _selected_deploy_workers
)
_show_dispatch()
```

#### 5. Delete Old Functions

Remove these extracted functions (save ~3,600 lines):

- Lines 277-1417: `_rebuild_ships()` and all helpers
- Lines 1351-2419: `_show_asteroid_selection()` and helpers
- Lines 2421-2987: `_show_worker_selection()`
- Lines 2989-3004: `_update_route_button_states()`
- Lines 3006-3064: `_optimize_crew()` and style helpers
- Lines 3066-3215: `_update_estimate_display()`
- Lines 3216-3257: `_confirm_dispatch()`
- Lines 3259-3310: `_show_dispatch_confirmation()`
- Lines 3312-3334: `_queue_mission()`
- Lines 3336-3345: `_abort_and_dispatch()`
- Lines 3347-3416: `_execute_dispatch()`
- Lines 3429-3453: `_calculate_jettison_for_asymmetric_trip()`
- Lines 3461-3500: `_show_partnership_selection()`
- Lines 3502-3589: `_show_station_jobs()` and state vars
- Lines 3591-3673: `_rebuild_station_job_list()` and `_station_move_job()`
- Lines 3675-3782: `_show_fleet_rescue_dispatch()`
- Lines 3784-3896: `_show_supply_shop()`
- Line 3898-3907: `_format_number()` (if not used elsewhere)

**Expected result:** fleet_market_tab.gd reduces from 4,241 lines to ~640 lines.

---

## Testing Checklist

After integration, test these flows:

### Dispatch Flow
- [ ] Click "Dispatch" on a ship
- [ ] Select asteroid destination (mining section)
- [ ] Select colony destination (market section)
- [ ] Search/filter/sort destinations work
- [ ] Select crew (auto-select, optimization buttons)
- [ ] View mission estimate (transit modes, routes, profit)
- [ ] Confirm dispatch (queue/redirect/normal modes)
- [ ] Mission starts correctly

### Special Features
- [ ] Create partnership (eligible ships listed)
- [ ] Configure station jobs (priority reordering)
- [ ] Dispatch fleet rescue (supply selection)
- [ ] Buy supplies (quantity spinboxes, cost preview)

### Edge Cases
- [ ] Insufficient crew (auto-assignment)
- [ ] No fuel (warning displayed)
- [ ] Remote ship crew lock (filtered worker list)
- [ ] Planning mode (queue mission)
- [ ] Redirect mode (abort and redispatch)

---

## Rollback Plan

If integration has issues:
```bash
git log --oneline -10  # Find last good commit before integration
git reset --hard <commit>  # Rollback to before integration
```

All 6 components are safely committed separately, so you can always restart integration from scratch.

---

## Notes

- Components are **decoupled** - they only communicate via signals
- FleetListPanel is added directly to `ships_list` container
- Other components are added to `dispatch_content` when needed
- The coordinator (fleet_market_tab.gd) manages the dispatch flow state machine
- Old code remains in fleet_market_tab.gd until Step 5 (safe to test before deleting)

---

**Ready to integrate!** All components tested and committed. Integration is mechanical but requires attention to detail. Take your time with signal wiring to ensure proper flow.
