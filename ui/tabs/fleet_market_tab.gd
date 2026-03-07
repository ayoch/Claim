extends MarginContainer

static func _lbl() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

# Combined Fleet + Market tab with ship-centric view

@onready var ships_list: VBoxContainer = %ShipsList
@onready var dispatch_popup: PanelContainer = %DispatchPopup
@onready var dispatch_content: VBoxContainer = %DispatchContent
@onready var dispatch_buttons: HBoxContainer = %DispatchButtons
@onready var _ships_scroll: ScrollContainer = %ShipsList.get_parent()
@onready var _tab_title: Label = $VBox/Title

# Component references
var _fleet_list_panel: Node = null
var _destination_selector: Node = null
var _worker_selector: Node = null
var _mission_estimator: Node = null
var _dispatch_confirmation: Node = null
var _special_actions_panel: Node = null

var _selected_ship: Ship = null
var _selected_asteroid: AsteroidData = null
var _selected_workers: Array[Worker] = []
var _selected_transit_mode: int = 0  # Mission.TransitMode.BRACHISTOCHRONE
var _selected_mission_type: int = 0  # Mission.MissionType.MINING
var _selected_deploy_units: Array[MiningUnit] = []
var _selected_deploy_workers: Array[Worker] = []
var _sell_at_destination_markets: bool = true  # Toggle: return with ore vs sell at nearby markets
var _sort_by: String = "profit"
var _filter_type: int = -1
var _market_sort_by: String = "profit"  # Sort mode for market destinations: "profit" or "name"
var _market_search: String = ""  # Search filter for market destinations
var _mining_search: String = ""  # Search filter for mining destinations
var _available_slingshot_routes: Array = []  # Array of GravityAssist.SlingshotRoute
var _selected_slingshot_route = null  # GravityAssist.SlingshotRoute or null
var _needs_full_rebuild: bool = true
# Old ship display dictionaries removed - now handled by FleetListPanel component
var _crew_expanded: Dictionary = {}  # Ship -> bool, persists across rebuilds
var _policy_overrides_expanded: Dictionary = {}  # Ship -> bool, persists across rebuilds
var _ship_stats_expanded: Dictionary = {}  # Ship -> bool, persists across rebuilds
const PROGRESS_LERP_SPEED: float = 8.0  # How fast progress bars catch up
var _dispatch_refresh_timer: float = 0.0
const DISPATCH_REFRESH_INTERVAL: float = 5.0  # Refresh dispatch popup every 5 seconds (orbital motion is slow)
var _last_tick_msec: int = 0
const TICK_THROTTLE_MSEC: int = 100  # Only process ticks every 100ms real-time
var _on_selection_screen: bool = false  # Track if we're on the initial destination selection screen
var _on_estimate_screen: bool = false  # Track if we're on the worker selection / estimate screen
var _saved_colonies_scroll: float = 0.0  # Preserve scroll position across refreshes
var _saved_mining_scroll: float = 0.0  # Preserve scroll position across refreshes
# In-place update references for destination lists
var _colony_dest_buttons: Dictionary = {}  # Colony -> Button
var _mining_dest_buttons: Dictionary = {}  # AsteroidData -> Button
var _colony_dest_data: Array = []  # Ordered list of Colony for current view
var _mining_dest_data: Array = []  # Ordered list of AsteroidData for current view
var _mining_scroll: ScrollContainer = null  # Reference for collapsible toggle
var _colonies_scroll: ScrollContainer = null  # Reference for collapsible toggle
var _mining_header_label: Label = null  # Clickable toggle header
var _colonies_header_label: Label = null  # Clickable toggle header
var _mining_controls: HFlowContainer = null  # Filter/sort controls for mining section
var _worker_checkboxes: Dictionary = {}  # Worker -> CheckBox for programmatic toggling
var _colonies_section_expanded: int = -1  # -1 = use default (cargo-based), 0 = collapsed, 1 = expanded
var _mining_section_expanded: int = -1  # -1 = use default (cargo-based), 0 = collapsed, 1 = expanded

static func _free_children(container: Node) -> void:
	for i in range(container.get_child_count() - 1, -1, -1):
		container.get_child(i).queue_free()

func _ready() -> void:
	_cancel_preview()
	_hide_dispatch()
	EventBus.ship_purchased.connect(func(_s: Ship, _c: int) -> void: _mark_dirty())
	EventBus.mission_started.connect(func(_m: Mission) -> void: _mark_dirty())
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _mark_dirty())
	EventBus.mission_phase_changed.connect(func(_m: Mission) -> void: _mark_dirty())
	EventBus.equipment_installed.connect(func(_s: Ship, _e: Equipment) -> void: _mark_dirty())
	EventBus.equipment_broken.connect(func(_s: Ship, _e: Equipment) -> void: _mark_dirty())
	EventBus.equipment_repaired.connect(func(_s: Ship, _e: Equipment) -> void: _mark_dirty())
	EventBus.trade_mission_started.connect(func(_tm: TradeMission) -> void: _mark_dirty())
	EventBus.trade_mission_completed.connect(func(_tm: TradeMission) -> void: _mark_dirty())
	EventBus.trade_mission_phase_changed.connect(func(_tm: TradeMission) -> void: _mark_dirty())
	EventBus.ship_idle_at_destination.connect(func(_s: Ship, _m: Mission) -> void: _mark_dirty())
	EventBus.ship_idle_at_colony.connect(func(_s: Ship, _tm: TradeMission) -> void: _mark_dirty())
	EventBus.ship_breakdown.connect(func(_s: Ship, _r: String) -> void: _mark_dirty())
	EventBus.ship_derelict.connect(func(_s: Ship) -> void: _mark_dirty())
	EventBus.ship_destroyed.connect(func(_s: Ship, _b: String) -> void: _mark_dirty())
	EventBus.rescue_mission_started.connect(func(_s: Ship, _c: int) -> void: _mark_dirty())
	EventBus.rescue_mission_completed.connect(func(_s: Ship) -> void: _mark_dirty())
	EventBus.refuel_mission_started.connect(func(_s: Ship, _c: int, _f: float) -> void: _mark_dirty())
	EventBus.refuel_mission_completed.connect(func(_s: Ship, _f: float) -> void: _mark_dirty())
	EventBus.stranger_rescue_offered.connect(func(_s: Ship, _n: String) -> void: _mark_dirty())
	EventBus.stranger_rescue_completed.connect(func(_s: Ship, _n: String) -> void: _mark_dirty())
	EventBus.stranger_rescue_declined.connect(func(_s: Ship, _n: String) -> void: _mark_dirty())
	EventBus.resource_changed.connect(func(_o: ResourceTypes.OreType, _a: float) -> void: _mark_dirty())
	EventBus.money_changed.connect(func(_m: int) -> void: _mark_dirty())
	EventBus.ship_stationed.connect(func(_s: Ship, _c: Colony) -> void: _mark_dirty())
	EventBus.ship_unstationed.connect(func(_s: Ship) -> void: _mark_dirty())
	EventBus.station_job_started.connect(func(_s: Ship, _j: String, _d: String) -> void: _mark_dirty())
	EventBus.station_job_completed.connect(func(_s: Ship, _j: String, _su: String) -> void: _mark_dirty())
	EventBus.worker_hired.connect(_on_worker_hired)
	EventBus.tick.connect(_on_tick)
	EventBus.map_dispatch_to_asteroid.connect(_on_map_dispatch_asteroid)
	EventBus.map_dispatch_to_colony.connect(_on_map_dispatch_colony)
	EventBus.order_queued.connect(func(_s: Ship, _l: String, _d: float) -> void: _mark_dirty())
	EventBus.order_executed.connect(func(_s: Ship, _l: String) -> void: _mark_dirty())
	EventBus.server_state_synced.connect(func() -> void:
		# Server state synced
		if is_visible_in_tree():
			if _fleet_list_panel:
				_fleet_list_panel.rebuild_ships()
		else:
			_mark_dirty()
	)
	visibility_changed.connect(func() -> void:
		if visible and _needs_full_rebuild:
			print("[FleetTab] Became visible with dirty flag, rebuilding (ships: %d)" % GameState.ships.size())
			_needs_full_rebuild = false
			if _fleet_list_panel:
				_fleet_list_panel.rebuild_ships()
	)

	# Load and instantiate components
	_setup_components()

func _setup_components() -> void:
	# Instantiate FleetListPanel and add to ships list
	var fleet_list_scene := preload("res://ui/components/fleet_list_panel.tscn")
	_fleet_list_panel = fleet_list_scene.instantiate()
	ships_list.add_child(_fleet_list_panel)

	# Instantiate other components (keep ready to add to dispatch_content when needed)
	_destination_selector = preload("res://ui/components/destination_selector.tscn").instantiate()
	_worker_selector = preload("res://ui/components/worker_selector.tscn").instantiate()
	_mission_estimator = preload("res://ui/components/mission_estimator.tscn").instantiate()
	_dispatch_confirmation = preload("res://ui/components/dispatch_confirmation.tscn").instantiate()
	_special_actions_panel = preload("res://ui/components/special_actions_panel.tscn").instantiate()

	# Connect FleetListPanel signals
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

	# Connect DestinationSelector signals
	_destination_selector.asteroid_selected.connect(func(asteroid) -> void:
		_selected_asteroid = asteroid
		_clear_dispatch_content()
		dispatch_content.add_child(_worker_selector)
		dispatch_content.add_child(_mission_estimator)
		_worker_selector.show_selection(
			_selected_ship, asteroid, false,
			_is_planning_mode, _is_redirect_mode, false,
			_available_slingshot_routes, _selected_slingshot_route, _selected_transit_mode
		)
		_show_dispatch()
	)
	_destination_selector.colony_selected.connect(func(colony) -> void:
		_confirm_colony_dispatch(colony)
	)
	_destination_selector.salvage_target_selected.connect(func(target: SalvageTarget) -> void:
		_confirm_salvage_dispatch(target)
	)
	_destination_selector.selection_cancelled.connect(func() -> void:
		_hide_dispatch()
		_cancel_preview()
	)

	# Connect WorkerSelector signals
	_worker_selector.workers_selected.connect(func(workers: Array[Worker], deploy_units: Array, deploy_workers: Array, mission_type: String) -> void:
		_selected_workers = workers
		_selected_deploy_units = deploy_units
		_selected_deploy_workers = deploy_workers
		match mission_type:
			"collect_ore":  _selected_mission_type = Mission.MissionType.COLLECT_ORE
			"reposition":   _selected_mission_type = Mission.MissionType.REPOSITION
			"deploy_units": _selected_mission_type = Mission.MissionType.DEPLOY_UNIT
			_:              _selected_mission_type = Mission.MissionType.MINING
		_mission_estimator.show_estimate(
			_selected_ship, _selected_asteroid, workers, false,
			_selected_transit_mode, _available_slingshot_routes, _selected_slingshot_route
		)
		_mission_estimator.visible = true
	)
	_worker_selector.back_requested.connect(func() -> void:
		_clear_dispatch_content()
		dispatch_content.add_child(_destination_selector)
		_destination_selector.show_selection(_selected_ship, _is_planning_mode, _is_redirect_mode)
		_show_dispatch()
	)
	_worker_selector.cancelled.connect(func() -> void:
		_hide_dispatch()
		_cancel_preview()
	)

	# Connect MissionEstimator signals
	_mission_estimator.transit_mode_changed.connect(func(mode: int) -> void:
		_selected_transit_mode = mode
	)
	_mission_estimator.route_changed.connect(func(route) -> void:
		_selected_slingshot_route = route
	)
	_mission_estimator.confirm_requested.connect(func() -> void:
		# Show dispatch confirmation
		_clear_dispatch_content()
		dispatch_content.add_child(_dispatch_confirmation)
		_dispatch_confirmation.show_confirmation(
			_selected_ship, _selected_asteroid, _selected_workers, false,
			_is_planning_mode, _is_redirect_mode,
			_selected_transit_mode, _selected_slingshot_route,
			_selected_mission_type, _selected_deploy_units, _selected_deploy_workers
		)
		_show_dispatch()
	)
	_mission_estimator.back_requested.connect(func() -> void:
		# Go back to worker selection
		_clear_dispatch_content()
		dispatch_content.add_child(_worker_selector)
		dispatch_content.add_child(_mission_estimator)
		_worker_selector.show_selection(
			_selected_ship, _selected_asteroid, false,
			_is_planning_mode, _is_redirect_mode, false,
			_available_slingshot_routes, _selected_slingshot_route, _selected_transit_mode
		)
		_show_dispatch()
	)
	_mission_estimator.cancelled.connect(func() -> void:
		_hide_dispatch()
		_cancel_preview()
	)

	# Connect DispatchConfirmation signals
	_dispatch_confirmation.mission_dispatched.connect(func(_ship: Ship, _mission) -> void:
		_cancel_preview()
		_return_to_map_if_needed()
		_hide_dispatch()
		_mark_dirty()
	)
	_dispatch_confirmation.back_requested.connect(func() -> void:
		_clear_dispatch_content()
		dispatch_content.add_child(_worker_selector)
		dispatch_content.add_child(_mission_estimator)
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

	# Connect SpecialActionsPanel signals
	_special_actions_panel.partnership_created.connect(func(_ship1: Ship, _ship2: Ship) -> void:
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
	_special_actions_panel.rescue_confirmed.connect(func(_ferry: Ship, _target: Ship, _food: float, _parts: float) -> void:
		_hide_dispatch()
		_mark_dirty()
	)
	_special_actions_panel.supplies_purchased.connect(func(ship: Ship, purchases: Dictionary) -> void:
		var any_bought := false
		for key in purchases:
			var qty: float = purchases[key]
			if MarketManager.buy_supplies(ship, key, qty):
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

	# Initial ship list build
	_fleet_list_panel.rebuild_ships()

func _mark_dirty() -> void:
	_needs_full_rebuild = true

func _show_dispatch() -> void:
	dispatch_popup.visible = true
	_ships_scroll.visible = false
	_tab_title.visible = false

func _hide_dispatch() -> void:
	dispatch_popup.visible = false
	_ships_scroll.visible = true
	_tab_title.visible = true
	_clear_dispatch_buttons()
	_dispatched_from_map = false

func _return_to_map_if_needed() -> void:
	if _dispatched_from_map:
		_dispatched_from_map = false
		get_parent().current_tab = MAP_TAB_INDEX

func _set_dispatch_buttons(buttons: Array) -> void:
	_clear_dispatch_buttons()
	for entry in buttons:
		var btn := Button.new()
		btn.text = entry["text"]
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if entry.has("color"):
			btn.add_theme_color_override("font_color", entry["color"])
		btn.pressed.connect(entry["callback"])
		dispatch_buttons.add_child(btn)

func _clear_dispatch_buttons() -> void:
	_free_children(dispatch_buttons)

func _process(delta: float) -> void:
	# Progress bar updates now handled by FleetListPanel component
	pass

func _on_worker_hired(_worker: Worker) -> void:
	# Components manage their own state, no manual refresh needed
	pass

func _on_tick(_dt: float) -> void:
	# Skip all updates when tab is not visible (massive performance win)
	if not is_visible_in_tree():
		return

	# Throttle tick processing to real-time (not game-time, which explodes at high speed)
	var now := Time.get_ticks_msec()
	if now - _last_tick_msec < TICK_THROTTLE_MSEC:
		return
	_last_tick_msec = now

	# Refresh dispatch popup periodically to update orbital positions and fuel estimates
	if dispatch_popup.visible:
		_dispatch_refresh_timer += 0.1  # Real-time increment (this block fires every 100ms)
		if _dispatch_refresh_timer >= DISPATCH_REFRESH_INTERVAL:
			_dispatch_refresh_timer = 0.0
			# Components manage their own updates, no manual refresh needed
			return

	if _needs_full_rebuild:
		_needs_full_rebuild = false
		if not dispatch_popup.visible and _fleet_list_panel:
			_fleet_list_panel.rebuild_ships()
		return

	# Ship display updates now handled by FleetListPanel component

func _get_wrench_texture(ship: Ship) -> Texture2D:
	# Returns the appropriate wrench texture based on worst component condition,
	# or null if everything is above 70%.
	var worst: float = ship.engine_condition
	for e in ship.equipment:
		if e.max_durability > 0.0:
			worst = minf(worst, (e.durability / e.max_durability) * 100.0)
	if worst <= 20.0:
		return load("res://ui/wrenches/Wrench_red.png") as Texture2D
	elif worst <= 50.0:
		return load("res://ui/wrenches/Wrench_Orange.png") as Texture2D
	elif worst <= 70.0:
		return load("res://ui/wrenches/Wrench_Yellow.png") as Texture2D
	return null

# _rebuild_ships() removed - now handled by FleetListPanel component

# Placeholder function kept for backwards compatibility (referenced by _mark_dirty)
func _rebuild_ships() -> void:
	if _fleet_list_panel:
		_fleet_list_panel.rebuild_ships()

# Old implementation removed (887 lines) - see FleetListPanel component
# Lines 471-1357 deleted during Phase 8 integration

# Include all the helper functions from fleet_tab.gd
func _get_location_text(ship: Ship) -> String:
	if ship.is_stationed and ship.station_colony:
		return "Location: %s (stationed)" % ship.station_colony.colony_name
	if ship.is_at_earth:
		return "Location: Earth"
	if ship.docked_at_colony:
		return "Location: %s" % ship.docked_at_colony.colony_name
	if ship.current_mission:
		match ship.current_mission.status:
			Mission.Status.IDLE_AT_DESTINATION:
				return "Location: At %s" % ship.current_mission.asteroid.asteroid_name
			Mission.Status.MINING:
				return "Location: At %s" % ship.current_mission.asteroid.asteroid_name
			_:
				return "Location: Deep space (%.2f, %.2f AU)" % [ship.position_au.x, ship.position_au.y]
	if ship.current_trade_mission:
		match ship.current_trade_mission.status:
			TradeMission.Status.IDLE_AT_COLONY, TradeMission.Status.SELLING:
				return "Location: At %s" % ship.current_trade_mission.colony.colony_name
			_:
				return "Location: Deep space (%.2f, %.2f AU)" % [ship.position_au.x, ship.position_au.y]
	return "Location: Deep space (%.2f, %.2f AU)" % [ship.position_au.x, ship.position_au.y]

func _cancel_preview() -> void:
	EventBus.mission_preview_cancelled.emit()

var _is_planning_mode: bool = false    # Queue mission for after current task completes
var _is_redirect_mode: bool = false  # Abort current mission and immediately reroute
var _dispatched_from_map: bool = false  # If true, return to Map tab after dispatch
const MAP_TAB_INDEX: int = 4

func _switch_to_self() -> void:
	get_parent().current_tab = get_index()

func _on_map_dispatch_asteroid(ship: Ship, asteroid: AsteroidData) -> void:
	_selected_ship = ship
	# Only redirect if actively in transit (not idle at destination)
	var in_transit := ship.current_mission != null and (
		ship.current_mission.status == Mission.Status.TRANSIT_OUT or
		ship.current_mission.status == Mission.Status.TRANSIT_BACK or
		ship.current_mission.status == Mission.Status.REFUELING
	)
	if in_transit:
		# Ship is underway — show full dispatch panel in redirect mode
		_selected_asteroid = asteroid
		_selected_workers.clear()  # Crew doesn't change during redirect
		_selected_mission_type = Mission.MissionType.MINING
		_selected_deploy_units.clear()
		_selected_deploy_workers.clear()
		_selected_transit_mode = ship.current_mission.transit_mode  # Keep current transit mode as default
		_is_redirect_mode = true
		_sort_by = "profit"
		_filter_type = -1
		_is_planning_mode = false
		_colonies_section_expanded = -1
		_mining_section_expanded = -1
	else:
		# Docked or idle at destination — normal dispatch with crew selection
		_selected_asteroid = asteroid
		_selected_workers.clear()
		_selected_mission_type = Mission.MissionType.MINING
		_selected_deploy_units.clear()
		_selected_deploy_workers.clear()
		_selected_transit_mode = Mission.TransitMode.BRACHISTOCHRONE
		_is_redirect_mode = false
		_sort_by = "profit"
		_filter_type = -1
		_is_planning_mode = false
		_colonies_section_expanded = -1
		_mining_section_expanded = -1
		_dispatched_from_map = true
		_switch_to_self()

		# Show worker selection component
		_clear_dispatch_content()
		dispatch_content.add_child(_worker_selector)
		dispatch_content.add_child(_mission_estimator)
		_worker_selector.show_selection(
			_selected_ship, _selected_asteroid, false,
			_is_planning_mode, _is_redirect_mode, false,
			_available_slingshot_routes, _selected_slingshot_route, _selected_transit_mode
		)
		_show_dispatch()

func _on_map_dispatch_colony(ship: Ship, colony: Colony) -> void:
	_selected_ship = ship
	# Only redirect if actively in transit (not idle at colony)
	var in_transit := ship.current_trade_mission != null and (
		ship.current_trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY or
		ship.current_trade_mission.status == TradeMission.Status.TRANSIT_BACK
	)
	if in_transit:
		# Ship is underway on a trade mission — redirect
		var dist := ship.position_au.distance_to(colony.get_position_au())
		var new_transit_time := Brachistochrone.transit_time(dist, ship.get_effective_thrust())
		var fuel_out_tm := ship.calc_fuel_for_distance(dist, ship.get_cargo_total())
		var tm_return_origin := ship.station_colony.get_position_au() if (ship.is_stationed and ship.station_colony) else CelestialData.get_earth_position_au()
		var tm_return_dist := colony.get_position_au().distance_to(tm_return_origin)
		var fuel_ret_tm := ship.calc_fuel_for_distance(tm_return_dist, 0.0)
		var fuel_needed := fuel_out_tm + fuel_ret_tm
		var feasible := fuel_needed <= ship.fuel
		var avg_velocity := dist / new_transit_time if new_transit_time > 0.0 else 0.0
		var entry_t: float = clampf(ship.speed_au_per_tick / (4.0 * avg_velocity), 0.0, 0.5) if avg_velocity > 0.0 else 0.0
		var effective_transit_time := (1.0 - entry_t) * new_transit_time
		var transit_str := TimeScale.format_time(effective_transit_time)
		_dispatched_from_map = true
		_switch_to_self()
		dispatch_popup.visible = true
		if feasible:
			var cost := int(fuel_out_tm * Ship.FUEL_COST_PER_UNIT * 2.0)
			var tm_signal_delay := GameState.calc_signal_delay(ship)
			var tm_delay_suffix := ""
			if tm_signal_delay > 0.0:
				var tm_sd_mins := int(tm_signal_delay / 60.0)
				var tm_sd_secs := int(fmod(tm_signal_delay, 60.0))
				var tm_sd_str := "%dm %02ds" % [tm_sd_mins, tm_sd_secs] if tm_sd_mins > 0 else "%ds" % tm_sd_secs
				tm_delay_suffix = "\nSignal delay: %s" % tm_sd_str
			_show_redirect_confirmation(
				"Redirect %s to %s?\n\nNew transit: %s\nRedirect cost: $%s%s" % [
					ship.ship_name, colony.colony_name,
					transit_str, _format_number(cost), tm_delay_suffix
				],
				func() -> void: MissionManager.redirect_trade_mission(ship.current_trade_mission, colony)
			)
		else:
			_show_redirect_confirmation(
				"Cannot redirect %s to %s: not enough fuel for redirect + return\n\nFuel needed: %.0f  Available: %.0f\nNew transit if refueled: %s" % [
					ship.ship_name, colony.colony_name,
					fuel_needed, ship.fuel, transit_str
				],
				Callable(), false
			)
	else:
		# Docked or idle remote — normal colony dispatch
		_selected_asteroid = null
		_selected_workers.clear()
		_selected_mission_type = Mission.MissionType.MINING
		_selected_deploy_units.clear()
		_selected_deploy_workers.clear()
		_sort_by = "profit"
		_filter_type = -1
		_is_planning_mode = false
		_colonies_section_expanded = -1
		_mining_section_expanded = -1
		_dispatched_from_map = true
		_switch_to_self()
		dispatch_popup.visible = true
		_confirm_colony_dispatch(colony)

func _show_redirect_confirmation(message: String, on_confirm: Callable, feasible: bool = true) -> void:
	_clear_dispatch_content()
	var title := _lbl()
	title.text = "Redirect Ship"
	title.add_theme_font_size_override("font_size", 26)
	dispatch_content.add_child(title)
	var msg_label := _lbl()
	msg_label.text = message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dispatch_content.add_child(msg_label)
	var close_cb := func() -> void: _hide_dispatch()
	if feasible:
		var confirm_cb := func() -> void:
			on_confirm.call()
			_return_to_map_if_needed()
			_hide_dispatch()
		_set_dispatch_buttons([
			{"text": "Confirm", "callback": confirm_cb},
			{"text": "Cancel", "callback": close_cb},
		])
	else:
		_set_dispatch_buttons([
			{"text": "Close", "callback": close_cb},
		])

func _start_dispatch(ship: Ship, planning_mode: bool = false, redirect_mode: bool = false) -> void:
	_selected_ship = ship
	_selected_asteroid = null
	_selected_workers.clear()
	_selected_mission_type = Mission.MissionType.MINING
	_selected_deploy_units.clear()
	_selected_deploy_workers.clear()
	_sort_by = "profit"
	_filter_type = -1
	_is_planning_mode = planning_mode
	_is_redirect_mode = redirect_mode
	_colonies_section_expanded = -1  # Reset to cargo-based default
	_mining_section_expanded = -1

	# Show popup immediately for responsiveness
	dispatch_popup.visible = true

	# Populate content in next frame (feels instant, avoids UI lag)
	await get_tree().process_frame

	# Show destination selector component
	_clear_dispatch_content()
	dispatch_content.add_child(_destination_selector)
	_destination_selector.show_selection(ship, planning_mode, redirect_mode)
	_on_selection_screen = true
	_on_estimate_screen = false

func _clear_dispatch_content() -> void:
	_free_children(dispatch_content)

func _format_time(ticks: float) -> String:
	return TimeScale.format_time(ticks)

func _add_fleet_stat_row(grid: GridContainer, label_text: String, fmt: String, base_float: float, effective_value: float) -> void:
	var label := _lbl()
	label.text = label_text
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	label.add_theme_font_size_override("font_size", 16)
	grid.add_child(label)

	var value := _lbl()
	if abs(effective_value - base_float) > 0.001:
		value.text = "%s (base) → %s (effective)" % [fmt % base_float, fmt % effective_value]
		value.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	else:
		value.text = fmt % base_float
		value.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	value.clip_text = true
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	value.add_theme_font_size_override("font_size", 16)
	grid.add_child(value)

func _calculate_colony_profit(colony: Colony) -> int:
	# Calculate net profit for selling at this colony (revenue - fuel cost)
	if not _selected_ship:
		return 0

	var colony_pos: Vector2 = colony.get_position_au()
	var dist := _selected_ship.position_au.distance_to(colony_pos)

	# Calculate fuel cost for round trip
	var cargo_mass := _selected_ship.get_cargo_total()
	var fuel_outbound := _selected_ship.calc_fuel_for_distance(dist, cargo_mass)
	var fuel_return := _selected_ship.calc_fuel_for_distance(dist, 0.0)
	var fuel_needed := fuel_outbound + fuel_return
	var fuel_cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)

	# Calculate revenue from cargo
	var revenue := 0
	for ore_type in _selected_ship.current_cargo:
		var amount: float = _selected_ship.current_cargo[ore_type]
		var price: float = colony.get_ore_price(ore_type, GameState.market)
		revenue += int(amount * price)

	return revenue - fuel_cost

func _confirm_colony_dispatch(colony: Colony) -> void:
	_on_selection_screen = false  # Left the main selection screen
	_on_estimate_screen = false  # Not on estimate screen
	# Show confirmation dialog before dispatching
	var colony_pos: Vector2 = colony.get_position_au()
	var dist := _selected_ship.position_au.distance_to(colony_pos)
	var transit := Brachistochrone.transit_time(dist, _selected_ship.get_effective_thrust())

	# Calculate revenue
	var revenue := 0
	for ore_type in _selected_ship.current_cargo:
		var amount: float = _selected_ship.current_cargo[ore_type]
		var price: float = colony.get_ore_price(ore_type, GameState.market)
		revenue += int(amount * price)

	var confirm_text := "Dispatch to %s?\n\nDistance: %.2f AU\nTransit: %s\nRevenue: $%s" % [
		colony.colony_name, dist, _format_time(transit), _format_number(revenue)
	]

	# Create confirmation popup
	_show_confirmation_dialog(confirm_text, func() -> void:
		_select_colony_trade(colony)
	)

func _select_colony_trade(colony: Colony) -> void:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		var colony_idx := GameState.colonies.find(colony)
		if _selected_ship and _selected_ship.server_id > 0 and colony_idx >= 0:
			await BackendManager.dispatch_trade(_selected_ship.server_id, colony_idx + 1)
			_hide_dispatch()
			_mark_dirty()
		return

	var cargo := _selected_ship.current_cargo.duplicate()
	if cargo.is_empty():
		return

	if GameState.settings.get("auto_refuel", true):
		var colony_pos := colony.get_position_au()
		var dist := _selected_ship.position_au.distance_to(colony_pos)
		var fuel_needed := _selected_ship.calc_fuel_for_distance(dist)
		var fuel_cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)
		if GameState.money >= fuel_cost:
			_selected_ship.fuel = _selected_ship.fuel_capacity
			GameState.money -= fuel_cost

	var assigned: Array[Worker] = []
	_selected_ship.crew = assigned
	if _selected_ship.is_idle_remote:
		MissionManager.dispatch_idle_ship_trade(_selected_ship, colony, cargo)
	else:
		MissionManager.start_trade_mission(_selected_ship, colony, cargo)
	_hide_dispatch()
	_mark_dirty()


func _confirm_salvage_dispatch(target: SalvageTarget) -> void:
	_on_selection_screen = false
	if _selected_ship.crew.is_empty():
		_show_confirmation_dialog("No crew assigned to %s.\n\nAssign workers before dispatching a salvage mission." % _selected_ship.ship_name, Callable())
		return
	var dist := _selected_ship.position_au.distance_to(target.position_au)
	var transit := Brachistochrone.transit_time(dist, _selected_ship.get_effective_thrust())
	var equip_str := ""
	if not target.salvage_equipment.is_empty():
		var names: Array[String] = []
		for e: Equipment in target.salvage_equipment:
			names.append(e.equipment_name)
		equip_str = "\nEquipment: %s" % ", ".join(names)
	var days_left := (target.expires_at_ticks - GameState.total_ticks) / 86400.0
	var confirm_text := "Salvage %s?\n\nTransit: %s\nScrap value: $%s%s\nExpires in: %.1f days" % [
		target.target_name,
		_format_time(transit),
		_format_number(target.scrap_credits),
		equip_str,
		maxf(days_left, 0.0),
	]
	_show_confirmation_dialog(confirm_text, func() -> void:
		MissionManager.start_salvage_mission(_selected_ship, target, _selected_transit_mode)
		_hide_dispatch()
	)

func _confirm_asteroid_dispatch(asteroid: AsteroidData) -> void:
	_on_selection_screen = false  # Left the main selection screen
	_on_estimate_screen = false  # Not on estimate screen
	# Show worker selection component
	_selected_asteroid = asteroid

	_clear_dispatch_content()
	dispatch_content.add_child(_worker_selector)
	dispatch_content.add_child(_mission_estimator)
	_worker_selector.show_selection(
		_selected_ship, _selected_asteroid, false,
		_is_planning_mode, _is_redirect_mode, false,
		_available_slingshot_routes, _selected_slingshot_route, _selected_transit_mode
	)
	_show_dispatch()

func _calculate_fuel_route(destination: Colony) -> Array[String]:
	# Calculate route with fuel stops from current position to destination
	# Returns array of colony names to visit, or empty if unreachable
	const PROXIMITY_THRESHOLD := 0.1
	const MAX_HOPS := 3  # Maximum fuel stops allowed

	var cargo_mass := _selected_ship.get_cargo_total()
	var current_pos := _selected_ship.position_au
	var current_fuel := _selected_ship.fuel
	var max_fuel := _selected_ship.get_effective_fuel_capacity()
	var dest_pos: Vector2 = destination.get_position_au()

	# Check if we can reach directly
	var direct_dist := current_pos.distance_to(dest_pos)
	var direct_fuel := _selected_ship.calc_fuel_for_distance(direct_dist, cargo_mass)
	if direct_fuel <= current_fuel:
		return []  # No fuel stops needed

	# Find route with fuel stops (simple greedy algorithm)
	var route: Array[String] = []
	var visited: Array[Colony] = []
	var pos := current_pos
	var fuel := current_fuel

	for hop in range(MAX_HOPS):
		# Find best intermediate colony
		var best_colony: Colony = null
		var best_score := -999999.0

		for colony in GameState.colonies:
			if colony in visited:
				continue
			if colony == destination:
				continue  # Don't stop at destination for fuel

			var colony_pos: Vector2 = colony.get_position_au()

			# Skip if it's current location
			var dist_from_ship := _selected_ship.position_au.distance_to(colony_pos)
			if dist_from_ship < PROXIMITY_THRESHOLD:
				continue

			# Check if reachable from current position
			var dist_to_colony := pos.distance_to(colony_pos)
			var fuel_to_colony := _selected_ship.calc_fuel_for_distance(dist_to_colony, cargo_mass)
			if fuel_to_colony > fuel:
				continue  # Can't reach this colony

			# Check if destination is reachable from this colony (with full fuel)
			# Use current positions with safety margin to account for orbital motion
			var dist_colony_to_dest := colony_pos.distance_to(dest_pos)
			var fuel_colony_to_dest := _selected_ship.calc_fuel_for_distance(dist_colony_to_dest, cargo_mass)
			# Add 20% safety margin for orbital motion during transit
			if fuel_colony_to_dest > max_fuel * 0.8:
				continue  # Can't reach destination from this colony with safety margin

			# Score: prefer colonies closer to destination
			var score := -dist_colony_to_dest
			if score > best_score:
				best_score = score
				best_colony = colony

		if not best_colony:
			return []  # No valid route found

		# Add this colony to route
		route.append(best_colony.colony_name)
		visited.append(best_colony)
		pos = best_colony.get_position_au()
		fuel = max_fuel  # Refuel at colony

		# Check if we can now reach destination (with safety margin)
		var dist_to_dest := pos.distance_to(dest_pos)
		var fuel_to_dest := _selected_ship.calc_fuel_for_distance(dist_to_dest, cargo_mass)
		# Use 80% of fuel capacity as threshold to provide safety margin
		if fuel_to_dest <= fuel * 0.8:
			return route  # Success!

	return []  # Couldn't find route within MAX_HOPS

func _calculate_fuel_route_to_position(dest_pos: Vector2, cargo_mass: float) -> Array[String]:
	# Calculate route with fuel stops to reach a specific position (for asteroids)
	# Similar to _calculate_fuel_route but works with a Vector2 position instead of Colony
	const PROXIMITY_THRESHOLD := 0.1
	const MAX_HOPS := 3

	var current_pos := _selected_ship.position_au
	var current_fuel := _selected_ship.fuel
	var max_fuel := _selected_ship.get_effective_fuel_capacity()

	# Check if we can reach directly
	var direct_dist := current_pos.distance_to(dest_pos)
	var direct_fuel := _selected_ship.calc_fuel_for_distance(direct_dist, cargo_mass)
	if direct_fuel <= current_fuel:
		return []  # No fuel stops needed

	# Find route with fuel stops
	var route: Array[String] = []
	var visited: Array[Colony] = []
	var pos := current_pos
	var fuel := current_fuel

	for hop in range(MAX_HOPS):
		var best_colony: Colony = null
		var best_score := -999999.0

		for colony in GameState.colonies:
			if colony in visited:
				continue

			var colony_pos: Vector2 = colony.get_position_au()

			# Skip if it's current location
			var dist_from_ship := _selected_ship.position_au.distance_to(colony_pos)
			if dist_from_ship < PROXIMITY_THRESHOLD:
				continue

			# Check if reachable from current position
			var dist_to_colony := pos.distance_to(colony_pos)
			var fuel_to_colony := _selected_ship.calc_fuel_for_distance(dist_to_colony, cargo_mass)
			if fuel_to_colony > fuel:
				continue

			# Check if destination position is reachable from this colony
			var dist_colony_to_dest := colony_pos.distance_to(dest_pos)
			var fuel_colony_to_dest := _selected_ship.calc_fuel_for_distance(dist_colony_to_dest, cargo_mass)
			if fuel_colony_to_dest > max_fuel * 0.8:
				continue

			# Prefer colonies closer to destination
			var score := -dist_colony_to_dest
			if score > best_score:
				best_score = score
				best_colony = colony

		if not best_colony:
			return []

		route.append(best_colony.colony_name)
		visited.append(best_colony)
		pos = best_colony.get_position_au()
		fuel = max_fuel

		# Check if we can now reach destination
		var dist_to_dest := pos.distance_to(dest_pos)
		var fuel_to_dest := _selected_ship.calc_fuel_for_distance(dist_to_dest, cargo_mass)
		if fuel_to_dest <= fuel * 0.8:
			return route

	return []

func _show_confirmation_dialog(message: String, on_confirm: Callable) -> void:
	# Clear dispatch content and show confirmation
	_clear_dispatch_content()

	var title := _lbl()
	title.text = "Confirm Dispatch"
	title.add_theme_font_size_override("font_size", 26)
	dispatch_content.add_child(title)

	var msg_label := _lbl()
	msg_label.text = message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dispatch_content.add_child(msg_label)

	var _confirm_cb := func() -> void: on_confirm.call()
	var _cancel_cb := func() -> void:
		# Show destination selector component
		_clear_dispatch_content()
		dispatch_content.add_child(_destination_selector)
		_destination_selector.show_selection(_selected_ship, _is_planning_mode, _is_redirect_mode)
		_show_dispatch()
	_set_dispatch_buttons([
		{"text": "Confirm", "callback": _confirm_cb},
		{"text": "Cancel", "callback": _cancel_cb},
	])

	_show_dispatch()

func _get_matching_contracts(ship: Ship, colony: Colony) -> Array[Contract]:
	# Find active contracts that match ship's cargo and can be delivered at this colony
	var matches: Array[Contract] = []
	for contract in GameState.active_contracts:
		# Check if contract can be delivered at this colony
		if contract.delivery_colony and contract.delivery_colony != colony:
			continue  # Wrong delivery location

		# Check if ship has this ore type
		if ship.current_cargo.get(contract.ore_type, 0.0) > 0:
			matches.append(contract)

	return matches

func _add_contract_fulfillment_ui(container: VBoxContainer, ship: Ship, contract: Contract, colony: Colony) -> void:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# Contract info
	var info := _lbl()
	var ore_name := ResourceTypes.get_ore_name(contract.ore_type)
	var ship_has: float = ship.current_cargo.get(contract.ore_type, 0.0)
	var remaining := contract.get_remaining_quantity()
	var can_deliver: float = minf(ship_has, remaining)
	var contract_price_per_ton := float(contract.reward) / contract.quantity
	var spot_price := colony.get_ore_price(contract.ore_type, GameState.market)

	var price_comparison := ""
	if contract_price_per_ton > spot_price:
		var premium := ((contract_price_per_ton / spot_price) - 1.0) * 100.0
		price_comparison = " (+%.0f%% vs spot)" % premium
	else:
		var discount := (1.0 - (contract_price_per_ton / spot_price)) * 100.0
		price_comparison = " (-%.0f%% vs spot)" % discount

	info.text = "%s: %s %.1ft/%.1ft - $%.0f/t%s - %s remaining\nYou have: %.1ft | Can deliver: %.1ft" % [
		contract.issuer_name, ore_name, contract.quantity_delivered, contract.quantity,
		contract_price_per_ton, price_comparison, _format_time(contract.deadline_ticks),
		ship_has, can_deliver
	]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info)

	# Fulfillment buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)

	# Full/Partial fulfillment button
	var fulfill_btn := Button.new()
	var payment := contract.get_partial_payment(can_deliver)
	if can_deliver >= remaining:
		fulfill_btn.text = "Fulfill Contract ($%s)" % _format_number(payment)
	else:
		if contract.allows_partial:
			fulfill_btn.text = "Deliver %.1ft ($%s)" % [can_deliver, _format_number(payment)]
		else:
			fulfill_btn.text = "Requires Full Amount"
			fulfill_btn.disabled = true

	fulfill_btn.custom_minimum_size = Vector2(0, 36)
	fulfill_btn.pressed.connect(func() -> void:
		var result := GameState.fulfill_contract_from_ship(contract, ship, can_deliver)
		if result["success"]:
			_mark_dirty()
	)
	btn_row.add_child(fulfill_btn)

	# Spot market comparison
	var spot_value := int(can_deliver * spot_price)
	var spot_label := _lbl()
	spot_label.text = "Spot: $%s" % _format_number(spot_value)
	if payment > spot_value:
		spot_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	else:
		spot_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
	btn_row.add_child(spot_label)

	vbox.add_child(btn_row)
	panel.add_child(vbox)
	container.add_child(panel)


func _format_number(n: int) -> String:
	var s := str(abs(n))
	var result := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	if n < 0:
		result = "-" + result
	return result
