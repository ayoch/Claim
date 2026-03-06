# Fleet/Market Tab Component Split Plan

## Overview

Split the monolithic `fleet_market_tab.gd` (4,241 lines, 59 functions) into **5 modular components** for better maintainability and performance.

**Current File:** `ui/tabs/fleet_market_tab.gd` (4,241 lines)
**Target:** 5 component files + 1 coordinator (est. 800-1,000 lines each)
**Estimated Effort:** 3-5 days
**Complexity:** Very High

---

## Current Structure Analysis

### State Variables (64+)
- **Selection state:** _selected_ship, _selected_asteroid, _selected_workers, _selected_transit_mode, etc.
- **UI caching:** _progress_bars, _status_labels, _detail_labels, _cargo_labels, _signal_labels (5 dictionaries)
- **Expansion state:** _crew_expanded, _policy_overrides_expanded, _ship_stats_expanded (3 dictionaries)
- **Sorting/filtering:** _sort_by, _filter_type, _market_sort_by, _market_search, _mining_search
- **Destination lists:** _colony_dest_buttons, _mining_dest_buttons, _colony_dest_data, _mining_dest_data
- **Worker selection:** _worker_checkboxes (Dictionary), _selected_deploy_workers
- **Scroll positions:** _saved_colonies_scroll, _saved_mining_scroll
- **Screen state:** _on_selection_screen, _on_estimate_screen
- **Section expansion:** _colonies_section_expanded, _mining_section_expanded

### Signal Connections (28+ in _ready)
All EventBus signals for ship/mission/trade/resource events

### Functions by Category (59 total)

**1. UI Lifecycle (7):**
- _ready, _process, _mark_dirty, _show_dispatch, _hide_dispatch, _set_dispatch_buttons, _clear_dispatch_buttons

**2. Ship List Display (4):**
- _rebuild_ships, _get_location_text, _get_wrench_texture, _build_details_text

**3. Destination Selection (9):**
- _show_asteroid_selection, _toggle_colonies_section, _toggle_mining_section, _update_destination_labels
- _get_sorted_asteroids, _calculate_adjusted_profit, _get_ore_summary
- _select_asteroid, _select_colony_trade

**4. Worker Selection (5):**
- _show_worker_selection, _update_route_button_states, _optimize_crew
- _apply_selection_style, _apply_crew_style

**5. Estimation & Dispatch (9):**
- _update_estimate_display, _confirm_dispatch, _show_dispatch_confirmation
- _queue_mission, _abort_and_dispatch, _execute_dispatch
- _calculate_jettison_for_asymmetric_trip
- _cancel_preview, _clear_dispatch_content

**6. Special Features (7):**
- _show_partnership_selection, _show_station_jobs, _rebuild_station_job_list, _station_move_job
- _show_fleet_rescue_dispatch, _show_supply_shop

**7. Event Handlers (3):**
- _on_tick, _on_worker_hired, _on_map_dispatch_asteroid, _on_map_dispatch_colony

**8. Utilities (2):**
- _format_time, _format_number

**9. Navigation (3):**
- _return_to_map_if_needed, _switch_to_self, _show_redirect_confirmation, _start_dispatch

---

## Proposed Component Architecture

### Component 1: FleetListPanel.gd (~800 lines)
**Responsibility:** Display list of all ships with status, cargo, location

**State:**
- _progress_bars, _status_labels, _detail_labels, _location_labels, _cargo_labels, _signal_labels
- _crew_expanded, _policy_overrides_expanded, _ship_stats_expanded

**Functions (10):**
- _rebuild_ships()
- _get_location_text()
- _get_wrench_texture()
- _build_details_text()
- _update_ship_progress() (NEW - extracted from _process)
- _update_ship_status() (NEW - extracted from _on_tick)
- _toggle_crew_section() (NEW)
- _toggle_policy_section() (NEW)
- _toggle_stats_section() (NEW)
- _format_cargo_text() (NEW)

**Signals Emitted:**
- ship_selected(ship: Ship)
- dispatch_requested(ship: Ship)
- rescue_requested(target_ship: Ship)

**UI Elements:**
- Ships list VBoxContainer
- Ship cards with progress bars, status icons, expandable sections

---

### Component 2: DestinationSelector.gd (~900 lines)
**Responsibility:** Choose mining asteroid or trading colony

**State:**
- _selected_asteroid, _selected_colony
- _sort_by, _filter_type, _market_sort_by, _market_search, _mining_search
- _colony_dest_buttons, _mining_dest_buttons, _colony_dest_data, _mining_dest_data
- _saved_colonies_scroll, _saved_mining_scroll
- _colonies_section_expanded, _mining_section_expanded
- _mining_scroll, _colonies_scroll, _mining_header_label, _colonies_header_label, _mining_controls

**Functions (12):**
- _show_asteroid_selection()
- _toggle_colonies_section()
- _toggle_mining_section()
- _update_destination_labels()
- _get_sorted_asteroids()
- _calculate_adjusted_profit()
- _get_ore_summary()
- _select_asteroid()
- _select_colony_trade()
- _apply_mining_search() (NEW)
- _apply_market_search() (NEW)
- _sort_destinations() (NEW)

**Signals Emitted:**
- asteroid_selected(asteroid: AsteroidData)
- colony_selected(colony: Colony)
- selection_cancelled()

**UI Elements:**
- Mining destinations list (collapsible, searchable, sortable)
- Market destinations list (collapsible, searchable, sortable)
- Filter/sort controls

---

### Component 3: WorkerSelector.gd (~600 lines)
**Responsibility:** Select crew for mission

**State:**
- _selected_workers, _selected_deploy_workers, _worker_checkboxes

**Functions (6):**
- _show_worker_selection()
- _optimize_crew()
- _apply_crew_style()
- _toggle_worker() (NEW)
- _update_worker_summary() (NEW)
- _validate_crew_selection() (NEW)

**Signals Emitted:**
- workers_selected(workers: Array[Worker])
- selection_cancelled()

**UI Elements:**
- Available workers list with checkboxes
- Skill distribution display
- Optimize buttons (mining, piloting, engineering)

---

### Component 4: MissionEstimator.gd (~700 lines)
**Responsibility:** Calculate and display journey estimates

**State:**
- _selected_transit_mode, _available_slingshot_routes, _selected_slingshot_route
- _sell_at_destination_markets

**Functions (8):**
- _update_estimate_display()
- _update_route_button_states()
- _calculate_jettison_for_asymmetric_trip()
- _calculate_journey_time() (NEW)
- _calculate_fuel_usage() (NEW)
- _calculate_profit_estimate() (NEW)
- _select_transit_mode() (NEW)
- _select_slingshot_route() (NEW)

**Signals Emitted:**
- estimate_updated(data: Dictionary)
- transit_mode_changed(mode: int)

**UI Elements:**
- Route selection (Brachistochrone, Hohmann, Slingshot)
- Journey estimate display (time, fuel, profit, risk)
- Sell-at-destination toggle

---

### Component 5: DispatchConfirmation.gd (~400 lines)
**Responsibility:** Final confirmation and mission execution

**State:**
- _selected_mission_type, _selected_deploy_units

**Functions (7):**
- _confirm_dispatch()
- _show_dispatch_confirmation()
- _queue_mission()
- _abort_and_dispatch()
- _execute_dispatch()
- _show_redirect_confirmation()
- _build_confirmation_summary() (NEW)

**Signals Emitted:**
- mission_dispatched(ship: Ship, mission: Mission)
- dispatch_cancelled()

**UI Elements:**
- Confirmation dialog with mission summary
- Queue/Abort/Confirm buttons

---

### Component 6: SpecialActionsPanel.gd (~500 lines)
**Responsibility:** Partnership, station jobs, rescue, supply shop

**State:**
- (minimal - mostly transient)

**Functions (7):**
- _show_partnership_selection()
- _show_station_jobs()
- _rebuild_station_job_list()
- _station_move_job()
- _show_fleet_rescue_dispatch()
- _show_supply_shop()
- _format_number()

**Signals Emitted:**
- partnership_created(ship1: Ship, ship2: Ship)
- station_job_changed(ship: Ship, jobs: Array)
- rescue_dispatched(rescuer: Ship, target: Ship)
- supplies_purchased(ship: Ship, supplies: Dictionary)

**UI Elements:**
- Partnership selection dialog
- Station jobs editor
- Fleet rescue dispatch
- Supply shop

---

### Coordinator: FleetMarketTab.gd (NEW, ~400 lines)
**Responsibility:** Coordinate between components, manage dispatch flow state machine

**State:**
- _dispatch_popup, _current_ship, _dispatch_state (enum)
- References to all 6 components

**Functions (12):**
- _ready()
- _process()
- _mark_dirty()
- _show_dispatch()
- _hide_dispatch()
- _start_dispatch()
- _cancel_preview()
- _on_component_signal() (multiple handlers)
- _switch_to_selection()
- _switch_to_worker_selection()
- _switch_to_estimate()
- _switch_to_confirmation()

**Dispatch State Machine:**
```
IDLE → DESTINATION_SELECTION → WORKER_SELECTION → ESTIMATION → CONFIRMATION → EXECUTING → IDLE
```

---

## Implementation Strategy

### Phase 1: Create Component Skeletons (Day 1, 4-6 hours)
1. Create 6 new .gd files with basic structure
2. Create 6 new .tscn files with placeholder UI
3. Define all signal interfaces
4. Set up coordinator to instantiate components
5. Test that components load without errors

### Phase 2: Extract Fleet List (Day 1-2, 4-6 hours)
6. Move ship display state to FleetListPanel
7. Extract _rebuild_ships() and related functions
8. Wire up ship_selected signal
9. Test ship list displays correctly
10. Commit

### Phase 3: Extract Destination Selector (Day 2, 6-8 hours)
11. Move destination selection state to DestinationSelector
12. Extract _show_asteroid_selection() and related functions
13. Wire up asteroid_selected/colony_selected signals
14. Test destination filtering, sorting, search
15. Commit

### Phase 4: Extract Worker Selector (Day 2-3, 4-5 hours)
16. Move worker selection state to WorkerSelector
17. Extract _show_worker_selection() and related functions
18. Wire up workers_selected signal
19. Test worker selection, optimization buttons
20. Commit

### Phase 5: Extract Mission Estimator (Day 3, 5-6 hours)
21. Move estimation state to MissionEstimator
22. Extract _update_estimate_display() and related functions
23. Wire up estimate_updated signal
24. Test route selection, profit calculations
25. Commit

### Phase 6: Extract Dispatch Confirmation (Day 3, 3-4 hours)
26. Move confirmation state to DispatchConfirmation
27. Extract _confirm_dispatch() and related functions
28. Wire up mission_dispatched signal
29. Test dispatch flow end-to-end
30. Commit

### Phase 7: Extract Special Actions (Day 4, 4-5 hours)
31. Move special features to SpecialActionsPanel
32. Extract partnership, station, rescue, supply functions
33. Wire up all special action signals
34. Test each special feature
35. Commit

### Phase 8: Polish & Testing (Day 4-5, 6-8 hours)
36. Add missing error handling
37. Test all signal connections
38. Test full dispatch flow
39. Test edge cases (no crew, no fuel, banned colony, etc.)
40. Performance testing (4,000+ line file → 6 smaller files)
41. Update documentation
42. Final commit

---

## Risks & Challenges

### High-Risk Areas:
1. **State synchronization** - 64+ variables must be correctly distributed
2. **Signal timing** - Components must emit/receive signals in correct order
3. **UI update throttling** - Performance optimization must be preserved
4. **Scroll position preservation** - Must maintain during component switches
5. **Worker checkbox state** - Fragile reference management
6. **Dispatch flow state machine** - Complex transitions between screens

### Mitigation:
- Incremental approach with commits after each component
- Extensive testing of each component before moving to next
- Keep original file as reference (rename to fleet_market_tab_BACKUP.gd)
- Add debug logging to track state transitions

---

## Benefits

1. **Maintainability** - Each component is ~400-900 lines (manageable)
2. **Testability** - Components can be tested in isolation
3. **Performance** - Only active component needs updates (not all 4,241 lines)
4. **Reusability** - Components could be reused in other UI contexts
5. **Clarity** - Responsibilities clearly separated
6. **Collaboration** - Different developers can work on different components

---

## Success Criteria

- [ ] All 6 components created and functional
- [ ] Original fleet_market_tab.gd deleted (or kept as backup)
- [ ] All EventBus signal connections working
- [ ] Full dispatch flow works (ship selection → destination → workers → estimate → confirm)
- [ ] Special features work (partnership, station jobs, rescue, supply shop)
- [ ] Performance is same or better than original
- [ ] No regressions in functionality
- [ ] Code is more maintainable (smaller files, clearer responsibilities)

---

**Status:** Ready to begin (requires user approval)
**Created:** 2026-03-06
**Complexity:** Very High (3-5 days estimated)
