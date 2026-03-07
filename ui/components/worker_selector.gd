extends VBoxContainer
## WorkerSelector Component
## Handles mission type selection, deploy unit selection, and crew selection for ship missions

signal workers_selected(workers: Array[Worker], deploy_units: Array, deploy_workers: Array, mission_type: String)
signal back_requested()
signal cancelled()

var _game_state: Node = null  # GameState reference
var _selected_ship: Ship = null
var _selected_asteroid = null
var _selected_colony = null
var _available_slingshot_routes: Array = []
var _selected_slingshot_route = null
var _selected_transit_mode: Mission.TransitMode = Mission.TransitMode.BRACHISTOCHRONE
var _is_planning_mode: bool = false
var _is_redirect_mode: bool = false
var _is_fleet_rescue: bool = false

# State
var _selected_workers: Array[Worker] = []
var _selected_deploy_units: Array = []  # Array[MiningUnit]
var _selected_deploy_workers: Array[Worker] = []
var _worker_checkboxes: Dictionary = {}
var _selected_mission_type: String = "mine"  # "mine", "reposition", "deploy_units", "collect_ore"

@onready var content_container: VBoxContainer = %ContentContainer

func _ready() -> void:
	_game_state = get_node("/root/GameState")

func show_selection(
	ship: Ship,
	destination,  # CelestialBody or Colony
	is_colony: bool,
	planning_mode: bool = false,
	redirect_mode: bool = false,
	fleet_rescue: bool = false,
	slingshot_routes: Array = [],
	selected_route = null,
	transit_mode: Mission.TransitMode = Mission.TransitMode.BRACHISTOCHRONE
) -> void:
	_selected_ship = ship
	_is_planning_mode = planning_mode
	_is_redirect_mode = redirect_mode
	_is_fleet_rescue = fleet_rescue
	_available_slingshot_routes = slingshot_routes
	_selected_slingshot_route = selected_route
	_selected_transit_mode = transit_mode

	if is_colony:
		_selected_colony = destination
		_selected_asteroid = null
	else:
		_selected_asteroid = destination
		_selected_colony = null

	_build_ui()

func show_visible() -> void:
	visible = true

func hide_visible() -> void:
	visible = false

func _build_ui() -> void:
	# Clear previous content
	for child in content_container.get_children():
		child.queue_free()

	_selected_workers.clear()
	_selected_deploy_units.clear()
	_selected_deploy_workers.clear()
	_worker_checkboxes.clear()

	# Title
	var title := _lbl()
	if _selected_colony:
		title.text = "Select Crew for Trade to %s" % _selected_colony.name
	elif _is_fleet_rescue:
		title.text = "Select Crew for Fleet Rescue"
	else:
		title.text = "Select Crew & Mission Type"
	title.add_theme_font_size_override("font_size", 20)
	content_container.add_child(title)

	# Mission type buttons (only for asteroid missions, not trade/rescue)
	if _selected_asteroid and not _is_fleet_rescue:
		_build_mission_type_selection()

	# Deploy unit selection (if applicable)
	if _selected_mission_type in ["deploy_units", "collect_ore"]:
		_build_deploy_unit_selection()

	# Crew selection
	_build_crew_selection()

func _build_mission_type_selection() -> void:
	var type_label := _lbl()
	type_label.text = "Mission Type:"
	type_label.add_theme_font_size_override("font_size", 16)
	type_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	content_container.add_child(type_label)

	var type_hbox := HFlowContainer.new()
	type_hbox.add_theme_constant_override("h_separation", 8)

	# Mine button
	var mine_btn := Button.new()
	mine_btn.text = "Mine Asteroid"
	mine_btn.custom_minimum_size = Vector2(0, 36)
	mine_btn.toggle_mode = true
	mine_btn.button_pressed = (_selected_mission_type == "mine")
	mine_btn.pressed.connect(func() -> void:
		_selected_mission_type = "mine"
		_build_ui()
	)
	type_hbox.add_child(mine_btn)

	# Reposition button
	var repos_btn := Button.new()
	repos_btn.text = "Reposition Ship"
	repos_btn.custom_minimum_size = Vector2(0, 36)
	repos_btn.toggle_mode = true
	repos_btn.button_pressed = (_selected_mission_type == "reposition")
	repos_btn.pressed.connect(func() -> void:
		_selected_mission_type = "reposition"
		_build_ui()
	)
	type_hbox.add_child(repos_btn)

	# Deploy units button
	var deploy_btn := Button.new()
	deploy_btn.text = "Deploy Mining Units"
	deploy_btn.custom_minimum_size = Vector2(0, 36)
	deploy_btn.toggle_mode = true
	deploy_btn.button_pressed = (_selected_mission_type == "deploy_units")
	deploy_btn.pressed.connect(func() -> void:
		_selected_mission_type = "deploy_units"
		_build_ui()
	)
	type_hbox.add_child(deploy_btn)

	# Collect ore button (only show if there are deployed units)
	var deployed_units: Array = _get_deployed_units_at_asteroid()
	if not deployed_units.is_empty():
		var collect_btn := Button.new()
		collect_btn.text = "Collect Ore from Units"
		collect_btn.custom_minimum_size = Vector2(0, 36)
		collect_btn.toggle_mode = true
		collect_btn.button_pressed = (_selected_mission_type == "collect_ore")
		collect_btn.pressed.connect(func() -> void:
			_selected_mission_type = "collect_ore"
			_build_ui()
		)
		type_hbox.add_child(collect_btn)

	content_container.add_child(type_hbox)

func _build_deploy_unit_selection() -> void:
	var units_label := _lbl()
	units_label.text = "Select Mining Units:"
	units_label.add_theme_font_size_override("font_size", 16)
	units_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	content_container.add_child(units_label)

	if _selected_mission_type == "deploy_units":
		# Show available units on ship
		var available_units: Array = _game_state.get_available_mining_units(_selected_ship)
		if available_units.is_empty():
			var none_label := _lbl()
			none_label.text = "No mining units available in cargo"
			none_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
			content_container.add_child(none_label)
		else:
			var cargo_used: int = 0
			for unit in _selected_deploy_units:
				cargo_used += unit.cargo_space

			var cargo_info := _lbl()
			cargo_info.text = "Cargo space: %d/%d used" % [cargo_used, _selected_ship.cargo_space]
			cargo_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			content_container.add_child(cargo_info)

			var units_scroll := ScrollContainer.new()
			units_scroll.custom_minimum_size = Vector2(0, 150)
			units_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			var units_vbox := VBoxContainer.new()
			units_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			units_scroll.add_child(units_vbox)
			content_container.add_child(units_scroll)

			for unit in available_units:
				var unit_btn := Button.new()
				unit_btn.flat = true
				unit_btn.custom_minimum_size = Vector2(0, 36)
				unit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				unit_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
				unit_btn.focus_mode = Control.FOCUS_NONE
				unit_btn.text = "%s (Cargo: %d, Workers: %d)" % [unit.name, unit.cargo_space, unit.required_workers]

				var is_selected: bool = unit in _selected_deploy_units
				if is_selected:
					unit_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))

				unit_btn.pressed.connect(func() -> void:
					if unit in _selected_deploy_units:
						_selected_deploy_units.erase(unit)
					else:
						# Check cargo space
						var total_cargo: int = cargo_used + unit.cargo_space
						if total_cargo > _selected_ship.cargo_space:
							return  # Not enough space
						_selected_deploy_units.append(unit)
					_build_ui()
				)
				units_vbox.add_child(unit_btn)

	elif _selected_mission_type == "collect_ore":
		# Show deployed units at asteroid
		var deployed_units: Array = _get_deployed_units_at_asteroid()
		if deployed_units.is_empty():
			var none_label := _lbl()
			none_label.text = "No deployed units at this asteroid"
			none_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
			content_container.add_child(none_label)
		else:
			var units_scroll := ScrollContainer.new()
			units_scroll.custom_minimum_size = Vector2(0, 150)
			units_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
			var units_vbox := VBoxContainer.new()
			units_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			units_scroll.add_child(units_vbox)
			content_container.add_child(units_scroll)

			for unit in deployed_units:
				var unit_btn := Button.new()
				unit_btn.flat = true
				unit_btn.custom_minimum_size = Vector2(0, 36)
				unit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				unit_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
				unit_btn.focus_mode = Control.FOCUS_NONE

				var ore_amount: float = unit.stockpiled_ore
				var capacity_pct := 0.0
				if unit.stockpile_capacity > 0:
					capacity_pct = (ore_amount / unit.stockpile_capacity) * 100.0
				unit_btn.text = "%s - %.1ft ore (%.0f%% full)" % [unit.name, ore_amount, capacity_pct]

				var is_selected: bool = unit in _selected_deploy_units
				if is_selected:
					unit_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))

				unit_btn.pressed.connect(func() -> void:
					if unit in _selected_deploy_units:
						_selected_deploy_units.erase(unit)
					else:
						_selected_deploy_units.append(unit)
					_build_ui()
				)
				units_vbox.add_child(unit_btn)

	# Worker assignment for deployed units
	if not _selected_deploy_units.is_empty():
		var workers_label := _lbl()
		workers_label.text = "Assign Workers to Units:"
		workers_label.add_theme_font_size_override("font_size", 16)
		workers_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		content_container.add_child(workers_label)

		var total_required: int = 0
		for unit in _selected_deploy_units:
			total_required += unit.required_workers

		var worker_info := _lbl()
		worker_info.text = "Required workers: %d (selected: %d)" % [total_required, _selected_deploy_workers.size()]
		worker_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		content_container.add_child(worker_info)

		var available_workers: Array[Worker] = _get_available_workers_for_deploy()
		var worker_scroll := ScrollContainer.new()
		worker_scroll.custom_minimum_size = Vector2(0, 150)
		worker_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var worker_vbox := VBoxContainer.new()
		worker_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		worker_scroll.add_child(worker_vbox)
		content_container.add_child(worker_scroll)

		for worker in available_workers:
			var worker_btn := Button.new()
			worker_btn.flat = true
			worker_btn.custom_minimum_size = Vector2(0, 36)
			worker_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			worker_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			worker_btn.focus_mode = Control.FOCUS_NONE
			worker_btn.text = "%s  |  %s" % [worker.worker_name, worker.get_specialties_text()]

			var is_selected: bool = worker in _selected_deploy_workers
			if is_selected:
				worker_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))

			worker_btn.pressed.connect(func() -> void:
				if worker in _selected_deploy_workers:
					_selected_deploy_workers.erase(worker)
				else:
					_selected_deploy_workers.append(worker)
				_build_ui()
			)
			worker_vbox.add_child(worker_btn)

func _build_crew_selection() -> void:
	var crew_label := _lbl()
	crew_label.text = "Select Crew for Ship:"
	crew_label.add_theme_font_size_override("font_size", 16)
	crew_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	content_container.add_child(crew_label)

	# Crew requirements
	var req_text: String = "Min crew: %d  |  Max crew: %d  |  Selected: %d" % [
		_selected_ship.min_crew,
		_selected_ship.max_crew,
		_selected_workers.size()
	]
	var req_label := _lbl()
	req_label.text = req_text
	req_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	content_container.add_child(req_label)

	# Get available workers (filtering by location)
	var available: Array[Worker] = []

	# If ship is stationed at a remote colony, only show workers at that colony
	if _selected_ship.is_stationed and _selected_ship.station_colony:
		var ship_loc: String = _selected_ship.station_colony.colony_name
		for worker in _game_state.workers:
			if worker.is_available:
				available.append(worker)
			elif worker.assigned_mining_unit != null:
				# Skip deployed workers
				pass
			elif worker.assigned_ship:
				var w_ship: Ship = worker.assigned_ship
				if w_ship.is_stationed and w_ship.station_colony:
					var w_loc: String = w_ship.station_colony.colony_name
					if w_loc == ship_loc:
						available.append(worker)
	else:
		# Ship is at Earth or in transit - show all idle workers
		for worker in _game_state.workers:
			if worker.is_available:
				available.append(worker)

	# Crew lock warning (if ship is stationed remotely)
	if _selected_ship.is_stationed and _selected_ship.station_colony:
		var lock_warning := _lbl()
		lock_warning.text = "⚠ Ship is remote - only showing workers at same location"
		lock_warning.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
		lock_warning.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content_container.add_child(lock_warning)

	if available.is_empty():
		var none_label := _lbl()
		none_label.text = "No available workers"
		none_label.add_theme_color_override("font_color", Color(0.9, 0.5, 0.3))
		content_container.add_child(none_label)
		return

	# Optimization buttons
	var opt_row := HFlowContainer.new()
	opt_row.add_theme_constant_override("h_separation", 8)

	var auto_btn := Button.new()
	auto_btn.text = "Auto Select"
	auto_btn.flat = true
	auto_btn.focus_mode = Control.FOCUS_NONE
	auto_btn.custom_minimum_size = Vector2(0, 32)
	auto_btn.pressed.connect(func() -> void:
		_optimize_crew(available, "auto")
	)
	opt_row.add_child(auto_btn)

	var miners_btn := Button.new()
	miners_btn.text = "Best Miners"
	miners_btn.flat = true
	miners_btn.focus_mode = Control.FOCUS_NONE
	miners_btn.custom_minimum_size = Vector2(0, 32)
	miners_btn.pressed.connect(func() -> void:
		_optimize_crew(available, "miner")
	)
	opt_row.add_child(miners_btn)

	var pilots_btn := Button.new()
	pilots_btn.text = "Best Pilots"
	pilots_btn.flat = true
	pilots_btn.focus_mode = Control.FOCUS_NONE
	pilots_btn.custom_minimum_size = Vector2(0, 32)
	pilots_btn.pressed.connect(func() -> void:
		_optimize_crew(available, "pilot")
	)
	opt_row.add_child(pilots_btn)

	var engineers_btn := Button.new()
	engineers_btn.text = "Best Engineers"
	engineers_btn.flat = true
	engineers_btn.focus_mode = Control.FOCUS_NONE
	engineers_btn.custom_minimum_size = Vector2(0, 32)
	engineers_btn.pressed.connect(func() -> void:
		_optimize_crew(available, "engineer")
	)
	opt_row.add_child(engineers_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear"
	clear_btn.flat = true
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.custom_minimum_size = Vector2(0, 32)
	clear_btn.pressed.connect(func() -> void:
		_optimize_crew(available, "clear")
	)
	opt_row.add_child(clear_btn)

	content_container.add_child(opt_row)

	# Scrollable crew list
	var crew_scroll := ScrollContainer.new()
	crew_scroll.custom_minimum_size = Vector2(0, 200)
	crew_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crew_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	crew_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var crew_vbox := VBoxContainer.new()
	crew_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crew_vbox.add_theme_constant_override("separation", 4)
	crew_scroll.add_child(crew_vbox)
	content_container.add_child(crew_scroll)

	# Auto-select: pre-select last crew, or first min_crew workers
	_worker_checkboxes.clear()
	var should_preselect := func(worker: Worker) -> bool:
		if _selected_ship.last_crew.size() > 0:
			return worker in _selected_ship.last_crew
		# No history: select the first min_crew workers
		var idx: int = available.find(worker)
		return idx >= 0 and idx < _selected_ship.min_crew

	for worker in available:
		var preselect: bool = should_preselect.call(worker)
		if preselect and worker not in _selected_workers:
			_selected_workers.append(worker)

		var crew_btn := Button.new()
		crew_btn.flat = true
		crew_btn.custom_minimum_size = Vector2(0, 40)
		crew_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		crew_btn.clip_text = true
		crew_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		crew_btn.focus_mode = Control.FOCUS_NONE
		crew_btn.text = "%s  |  %s  |  $%d/pay" % [
			worker.worker_name, worker.get_specialties_text(), worker.wage
		]
		_apply_crew_style(crew_btn, preselect)
		crew_btn.pressed.connect(func() -> void:
			if worker in _selected_workers:
				_selected_workers.erase(worker)
				_apply_crew_style(crew_btn, false)
			else:
				_selected_workers.append(worker)
				_apply_crew_style(crew_btn, true)
			workers_selected.emit(_selected_workers, _selected_deploy_units, _selected_deploy_workers, _selected_mission_type)
		)
		crew_vbox.add_child(crew_btn)
		_worker_checkboxes[worker] = crew_btn

	# Emit initial selection if workers were pre-selected
	if not _selected_workers.is_empty():
		call_deferred("emit_signal", "workers_selected", _selected_workers, _selected_deploy_units, _selected_deploy_workers, _selected_mission_type)

func _optimize_crew(available: Array[Worker], mode: String) -> void:
	_selected_workers.clear()

	match mode:
		"clear":
			pass  # Already cleared
		"auto":
			# Select best all-around crew based on average skill
			var sorted: Array[Worker] = available.duplicate()
			sorted.sort_custom(func(a: Worker, b: Worker) -> bool:
				var avg_a: float = (a.skills.miner + a.skills.pilot + a.skills.engineer) / 3.0
				var avg_b: float = (b.skills.miner + b.skills.pilot + b.skills.engineer) / 3.0
				return avg_a > avg_b
			)
			for i in range(mini(_selected_ship.min_crew, sorted.size())):
				_selected_workers.append(sorted[i])
		"miner":
			var sorted: Array[Worker] = available.duplicate()
			sorted.sort_custom(func(a: Worker, b: Worker) -> bool:
				return a.skills.miner > b.skills.miner
			)
			for i in range(mini(_selected_ship.min_crew, sorted.size())):
				_selected_workers.append(sorted[i])
		"pilot":
			var sorted: Array[Worker] = available.duplicate()
			sorted.sort_custom(func(a: Worker, b: Worker) -> bool:
				return a.skills.pilot > b.skills.pilot
			)
			for i in range(mini(_selected_ship.min_crew, sorted.size())):
				_selected_workers.append(sorted[i])
		"engineer":
			var sorted: Array[Worker] = available.duplicate()
			sorted.sort_custom(func(a: Worker, b: Worker) -> bool:
				return a.skills.engineer > b.skills.engineer
			)
			for i in range(mini(_selected_ship.min_crew, sorted.size())):
				_selected_workers.append(sorted[i])

	# Update button styles
	for worker in _worker_checkboxes:
		var btn: Button = _worker_checkboxes[worker]
		_apply_crew_style(btn, worker in _selected_workers)

	workers_selected.emit(_selected_workers, _selected_deploy_units, _selected_deploy_workers, _selected_mission_type)

func _apply_crew_style(btn: Button, selected: bool) -> void:
	if selected:
		btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.3))
	else:
		btn.remove_theme_color_override("font_color")

func _get_deployed_units_at_asteroid() -> Array:
	var units: Array = []
	if not _selected_asteroid:
		return units
	for unit in _game_state.deployed_mining_units:
		if unit.deployed_at_body == _selected_asteroid:
			units.append(unit)
	return units

func _get_available_workers_for_deploy() -> Array[Worker]:
	var workers: Array[Worker] = []
	for worker in _game_state.workers:
		if worker.is_available:
			workers.append(worker)
	return workers

func _lbl() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 14)
	return label
