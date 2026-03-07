extends VBoxContainer
## DispatchConfirmation Component
## Final confirmation and mission execution for ship dispatch

signal mission_dispatched(ship: Ship, mission)
signal dispatch_cancelled()
signal back_requested()

var _game_state: Node = null  # GameState reference
var _selected_ship: Ship = null
var _selected_asteroid = null  # CelestialBody
var _selected_colony: Colony = null
var _selected_workers: Array[Worker] = []
var _selected_transit_mode: Mission.TransitMode = Mission.TransitMode.BRACHISTOCHRONE
var _selected_slingshot_route = null
var _selected_mission_type: String = "mine"
var _selected_deploy_units: Array = []  # Array[MiningUnit]
var _selected_deploy_workers: Array[Worker] = []
var _is_planning_mode: bool = false
var _is_redirect_mode: bool = false

@onready var content_container: VBoxContainer = %ContentContainer

func _ready() -> void:
	_game_state = get_node("/root/GameState")

func show_confirmation(
	ship: Ship,
	destination,  # CelestialBody or Colony
	workers: Array[Worker],
	is_colony: bool,
	planning_mode: bool = false,
	redirect_mode: bool = false,
	transit_mode: Mission.TransitMode = Mission.TransitMode.BRACHISTOCHRONE,
	slingshot_route = null,
	mission_type: String = "mine",
	deploy_units: Array = [],
	deploy_workers: Array[Worker] = []
) -> void:
	_selected_ship = ship
	_selected_workers = workers
	_is_planning_mode = planning_mode
	_is_redirect_mode = redirect_mode
	_selected_transit_mode = transit_mode
	_selected_slingshot_route = slingshot_route
	_selected_mission_type = mission_type
	_selected_deploy_units = deploy_units
	_selected_deploy_workers = deploy_workers

	if is_colony:
		_selected_colony = destination
		_selected_asteroid = null
	else:
		_selected_asteroid = destination
		_selected_colony = null

	_confirm_dispatch()

func _confirm_dispatch() -> void:
	# Auto-assign crew if not enough selected
	if _selected_workers.size() < _selected_ship.min_crew:
		var available: Array[Worker] = WorkerManager.get_available_workers()
		# Sort by skill descending
		available.sort_custom(func(a: Worker, b: Worker) -> bool:
			return a.skill > b.skill
		)
		# Add highest skilled workers until min_crew reached
		for worker in available:
			if worker not in _selected_workers:
				_selected_workers.append(worker)
			if _selected_workers.size() >= _selected_ship.min_crew:
				break

	# If still not enough crew, abort
	if _selected_workers.size() < _selected_ship.min_crew:
		dispatch_cancelled.emit()
		return

	# Get mission estimate for confirmation
	var est: Dictionary = AsteroidData.estimate_mission(
		_selected_asteroid, _selected_ship, _selected_workers, -1.0, Vector2(-999, -999), _selected_transit_mode
	)

	var dist: float = _selected_ship.position_au.distance_to(_selected_asteroid.get_position_au())
	var mode_name: String = "Hohmann" if _selected_transit_mode == Mission.TransitMode.HOHMANN else "Brachistochrone"
	var profit_sign: String = "+" if est["profit"] >= 0 else ""

	var crew_names := ""
	for i in range(_selected_workers.size()):
		if i > 0:
			crew_names += ", "
		crew_names += _selected_workers[i].worker_name

	var confirm_text: String = "Dispatch to %s?\n\nMode: %s\nDistance: %.2f AU\nTransit: %s each way\nMining: %s\nCrew: %s\nEstimated Profit: %s$%s" % [
		_selected_asteroid.asteroid_name, mode_name, dist,
		_format_time(est["transit_time"]), _format_time(est["mining_time"]),
		crew_names, profit_sign, _format_number(int(abs(est["profit"])))
	]

	# Show confirmation before executing
	_show_dispatch_confirmation(confirm_text)

func _show_dispatch_confirmation(message: String) -> void:
	# Clear previous content
	for child in content_container.get_children():
		child.queue_free()

	var title := _lbl()
	if _is_planning_mode:
		title.text = "Plan Next Mission"
	elif _is_redirect_mode:
		title.text = "Redirect Ship"
	else:
		title.text = "Confirm Mission Dispatch"
	title.add_theme_font_size_override("font_size", 26)
	content_container.add_child(title)

	var msg_label := _lbl()
	msg_label.text = message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.add_child(msg_label)

	if _is_planning_mode:
		var note := _lbl()
		note.text = "The ship will depart after its current task completes, once repaired, refueled, and restocked."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
		note.add_theme_font_size_override("font_size", 17)
		content_container.add_child(note)
	elif _is_redirect_mode:
		var note := _lbl()
		note.text = "The current mission will be aborted. The ship changes course immediately from its current position."
		note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		note.add_theme_color_override("font_color", Color(0.95, 0.7, 0.3))
		note.add_theme_font_size_override("font_size", 17)
		content_container.add_child(note)

	# Add buttons
	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content_container.add_child(button_row)

	if _is_planning_mode:
		var queue_btn := Button.new()
		queue_btn.text = "Queue Destination"
		queue_btn.custom_minimum_size = Vector2(0, 44)
		queue_btn.pressed.connect(_queue_mission)
		button_row.add_child(queue_btn)
	elif _is_redirect_mode:
		var redirect_btn := Button.new()
		redirect_btn.text = "Confirm Redirect"
		redirect_btn.custom_minimum_size = Vector2(0, 44)
		redirect_btn.add_theme_color_override("font_color", Color(0.95, 0.7, 0.3))
		redirect_btn.pressed.connect(_abort_and_dispatch)
		button_row.add_child(redirect_btn)
	else:
		var confirm_btn := Button.new()
		confirm_btn.text = "Confirm Dispatch"
		confirm_btn.custom_minimum_size = Vector2(0, 44)
		confirm_btn.pressed.connect(_execute_dispatch)
		button_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 44)
	cancel_btn.pressed.connect(func() -> void:
		back_requested.emit()
	)
	button_row.add_child(cancel_btn)

func show_redirect_confirmation(message: String, on_confirm: Callable, feasible: bool = true) -> void:
	# Clear previous content
	for child in content_container.get_children():
		child.queue_free()

	var title := _lbl()
	title.text = "Redirect Ship"
	title.add_theme_font_size_override("font_size", 26)
	content_container.add_child(title)

	var msg_label := _lbl()
	msg_label.text = message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_container.add_child(msg_label)

	var button_row := HBoxContainer.new()
	button_row.add_theme_constant_override("separation", 8)
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content_container.add_child(button_row)

	if feasible:
		var confirm_btn := Button.new()
		confirm_btn.text = "Confirm"
		confirm_btn.custom_minimum_size = Vector2(0, 44)
		confirm_btn.pressed.connect(func() -> void:
			on_confirm.call()
			dispatch_cancelled.emit()  # Close the dialog
		)
		button_row.add_child(confirm_btn)

		var cancel_btn := Button.new()
		cancel_btn.text = "Cancel"
		cancel_btn.custom_minimum_size = Vector2(0, 44)
		cancel_btn.pressed.connect(func() -> void:
			dispatch_cancelled.emit()
		)
		button_row.add_child(cancel_btn)
	else:
		var close_btn := Button.new()
		close_btn.text = "Close"
		close_btn.custom_minimum_size = Vector2(0, 44)
		close_btn.pressed.connect(func() -> void:
			dispatch_cancelled.emit()
		)
		button_row.add_child(close_btn)

func _queue_mission() -> void:
	# Queue the mission to start when current task completes
	var mining_duration := 86400.0  # Default 1 day
	if _selected_asteroid and _selected_workers.size() > 0:
		var est: Dictionary = AsteroidData.estimate_mission(_selected_asteroid, _selected_ship, _selected_workers, -1)
		mining_duration = est.get("mining_time", 86400.0)

	var mission_type_int: int = Mission.MissionType.MINING
	match _selected_mission_type:
		"collect_ore": mission_type_int = Mission.MissionType.COLLECT_ORE
		"reposition":  mission_type_int = Mission.MissionType.REPOSITION
		"deploy_units": mission_type_int = Mission.MissionType.DEPLOY_UNIT

	_selected_ship.crew = _selected_workers.duplicate()
	_selected_ship.queue_mission(
		_selected_asteroid,
		_selected_transit_mode,
		mining_duration,
		_selected_slingshot_route,
		mission_type_int
	)

	# Remember crew for next dispatch
	_selected_ship.last_crew = _selected_workers.duplicate()

	mission_dispatched.emit(_selected_ship, null)

func _abort_and_dispatch() -> void:
	# Abort current mission and dispatch immediately
	# Clear current mission
	if _selected_ship.current_mission:
		_selected_ship.current_mission = null
	if _selected_ship.current_trade_mission:
		_selected_ship.current_trade_mission = null

	# Now execute normal dispatch
	_execute_dispatch()

func _execute_dispatch() -> void:
	print("=== _execute_dispatch() CALLED ===")
	# Actually execute the dispatch after confirmation
	# Check fuel (LOCAL only — server manages fuel/money server-side)
	if BackendManager.current_mode != BackendManager.BackendMode.SERVER:
		if _game_state.settings.get("auto_refuel", true):
			var fuel_to_add: float = _selected_ship.fuel_capacity - _selected_ship.fuel
			if fuel_to_add > 0:
				var fuel_cost: int = int(fuel_to_add * Ship.FUEL_COST_PER_UNIT)
				print("Auto-refuel: adding %.0f fuel, cost $%d, have $%d" % [fuel_to_add, fuel_cost, _game_state.money])
				if _game_state.money < fuel_cost:
					print("ERROR: Cannot afford fuel!")
					dispatch_cancelled.emit()
					return  # Can't afford fuel
				_selected_ship.fuel = _selected_ship.fuel_capacity
				_game_state.money -= fuel_cost
			else:
				print("Ship already has full fuel (%.0f/%.0f)" % [_selected_ship.fuel, _selected_ship.fuel_capacity])

	# Remember crew for next dispatch
	_selected_ship.crew = _selected_workers.duplicate()
	_selected_ship.last_crew = _selected_workers.duplicate()

	# SERVER mode: route to BackendManager
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		print("Dispatching in SERVER mode: ship=%s asteroid=%s" % [_selected_ship.ship_name, _selected_asteroid.asteroid_name])

		if _selected_ship.server_id == 0:
			push_error("Cannot dispatch in SERVER mode: ship has no server_id")
			dispatch_cancelled.emit()
			return

		# Find asteroid server ID (DB IDs start at 1, array indices start at 0)
		var asteroid_index: int = -1
		for i in range(_game_state.asteroids.size()):
			if _game_state.asteroids[i] == _selected_asteroid:
				asteroid_index = i
				break

		if asteroid_index < 0:
			push_error("Cannot dispatch: asteroid not found in GameState.asteroids")
			dispatch_cancelled.emit()
			return

		var server_asteroid_id: int = asteroid_index + 1
		var mission_type_int: int = Mission.MissionType.MINING
		match _selected_mission_type:
			"collect_ore": mission_type_int = Mission.MissionType.COLLECT_ORE
			"reposition":  mission_type_int = Mission.MissionType.REPOSITION
			"deploy_units": mission_type_int = Mission.MissionType.DEPLOY_UNIT
		var mining_duration: float = 86400.0  # Default 1 day
		var return_to_station: bool = false

		print("Calling BackendManager.dispatch_mission(ship_id=%d, asteroid_id=%d, type=%d)" % [_selected_ship.server_id, server_asteroid_id, mission_type_int])
		await BackendManager.dispatch_mission(_selected_ship.server_id, server_asteroid_id, mission_type_int, mining_duration, return_to_station)
		print("Dispatch call completed")
		mission_dispatched.emit(_selected_ship, null)
	else:
		# LOCAL mode: use local GameState functions
		var mission = null
		match _selected_mission_type:
			Mission.MissionType.DEPLOY_UNIT:
				mission = MissionManager.start_deploy_mission(_selected_ship, _selected_asteroid, _selected_deploy_units, _selected_deploy_workers, _selected_transit_mode, _selected_slingshot_route)
			Mission.MissionType.COLLECT_ORE:
				mission = MissionManager.start_collect_mission(_selected_ship, _selected_asteroid, _selected_transit_mode, _selected_slingshot_route)
			Mission.MissionType.REPOSITION:
				mission = MissionManager.start_mission(_selected_ship, _selected_asteroid, _selected_transit_mode, _selected_slingshot_route)
				if mission:
					mission.mission_type = Mission.MissionType.REPOSITION
			_:
				if _selected_ship.is_idle_remote:
					mission = MissionManager.dispatch_idle_ship(_selected_ship, _selected_asteroid, _selected_transit_mode, _selected_slingshot_route)
				else:
					mission = MissionManager.start_mission(_selected_ship, _selected_asteroid, _selected_transit_mode, _selected_slingshot_route)

		mission_dispatched.emit(_selected_ship, mission)

func _format_time(ticks: float) -> String:
	return TimeScale.format_time(ticks)

func _format_number(n: int) -> String:
	var s: String = str(n)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count == 3:
			result = "," + result
			count = 0
		result = s[i] + result
		count += 1
	return result

func _lbl() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 14)
	return label
