extends MarginContainer

@onready var ships_list: VBoxContainer = %ShipsList
@onready var dispatch_popup: PanelContainer = %DispatchPopup
@onready var dispatch_content: VBoxContainer = %DispatchContent

var _selected_ship: Ship = null
var _selected_asteroid: AsteroidData = null
var _selected_workers: Array[Worker] = []
var _sort_by: String = "profit"  # "profit", "distance", "name"
var _filter_type: int = -1  # -1 = all, otherwise AsteroidData.BodyType value
var _needs_full_rebuild: bool = true
var _progress_bars: Dictionary = {}  # Ship -> ProgressBar
var _status_labels: Dictionary = {}  # Ship -> Label
var _detail_labels: Dictionary = {}  # Ship -> Label

func _ready() -> void:
	dispatch_popup.visible = false
	EventBus.mission_started.connect(func(_m: Mission) -> void: _mark_dirty())
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _mark_dirty())
	EventBus.mission_phase_changed.connect(func(_m: Mission) -> void: _mark_dirty())
	EventBus.equipment_installed.connect(func(_s: Ship, _e: Equipment) -> void: _mark_dirty())
	EventBus.tick.connect(_on_tick)
	_rebuild_ships()

func _mark_dirty() -> void:
	_needs_full_rebuild = true

func _on_tick(_dt: float) -> void:
	if _needs_full_rebuild:
		_needs_full_rebuild = false
		if not dispatch_popup.visible:
			_rebuild_ships()
		return
	# Just update progress bars, status labels, and fuel in place
	for ship: Ship in _progress_bars:
		var bar: ProgressBar = _progress_bars[ship]
		if ship.current_mission and is_instance_valid(bar):
			bar.value = ship.current_mission.get_progress() * 100.0
	for ship: Ship in _status_labels:
		var label: Label = _status_labels[ship]
		if ship.current_mission and is_instance_valid(label):
			label.text = ship.current_mission.get_status_text()
	for ship: Ship in _detail_labels:
		var label: Label = _detail_labels[ship]
		if is_instance_valid(label):
			label.text = _build_details_text(ship)

func _rebuild_ships() -> void:
	_progress_bars.clear()
	_status_labels.clear()
	_detail_labels.clear()
	for child in ships_list.get_children():
		child.queue_free()

	for ship: Ship in GameState.ships:
		var panel := PanelContainer.new()
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)

		var header := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = ship.ship_name
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(name_label)

		if ship.is_docked:
			var status := Label.new()
			status.text = "Docked"
			status.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
			header.add_child(status)

			var dispatch_btn := Button.new()
			dispatch_btn.text = "Dispatch"
			dispatch_btn.custom_minimum_size = Vector2(0, 44)
			dispatch_btn.pressed.connect(_start_dispatch.bind(ship))
			header.add_child(dispatch_btn)
		else:
			var status := Label.new()
			status.text = ship.current_mission.get_status_text()
			status.add_theme_color_override("font_color", Color(0.8, 0.7, 0.2))
			header.add_child(status)
			_status_labels[ship] = status

		vbox.add_child(header)

		var details := Label.new()
		details.text = _build_details_text(ship)
		vbox.add_child(details)
		_detail_labels[ship] = details

		# Show installed equipment names
		if not ship.equipment.is_empty():
			var equip_names: Array[String] = []
			for e in ship.equipment:
				equip_names.append(e.equipment_name)
			var equip_label := Label.new()
			equip_label.text = "Equipped: %s" % ", ".join(equip_names)
			equip_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
			vbox.add_child(equip_label)

		if not ship.is_docked and ship.current_mission:
			var progress := ProgressBar.new()
			progress.value = ship.current_mission.get_progress() * 100.0
			vbox.add_child(progress)
			_progress_bars[ship] = progress

		panel.add_child(vbox)
		ships_list.add_child(panel)

func _start_dispatch(ship: Ship) -> void:
	_selected_ship = ship
	_selected_asteroid = null
	_selected_workers.clear()
	_sort_by = "profit"
	_filter_type = -1
	_show_asteroid_selection()

func _show_asteroid_selection() -> void:
	_clear_dispatch_content()

	var title := Label.new()
	title.text = "Select Destination"
	title.add_theme_font_size_override("font_size", 20)
	dispatch_content.add_child(title)

	# Filter/sort controls
	var controls := HBoxContainer.new()
	controls.add_theme_constant_override("separation", 8)

	var sort_btn := OptionButton.new()
	sort_btn.add_item("Best Profit")
	sort_btn.add_item("Nearest")
	sort_btn.add_item("Name A-Z")
	sort_btn.custom_minimum_size = Vector2(0, 44)
	sort_btn.item_selected.connect(func(idx: int) -> void:
		_sort_by = ["profit", "distance", "name"][idx]
		_show_asteroid_selection()
	)
	match _sort_by:
		"profit": sort_btn.selected = 0
		"distance": sort_btn.selected = 1
		"name": sort_btn.selected = 2
	controls.add_child(sort_btn)

	var filter_btn := OptionButton.new()
	filter_btn.add_item("All Types")
	for bt in AsteroidData.BodyType.values():
		filter_btn.add_item(AsteroidData.BODY_TYPE_NAMES[bt])
	filter_btn.custom_minimum_size = Vector2(0, 44)
	filter_btn.selected = 0 if _filter_type == -1 else _filter_type + 1
	filter_btn.item_selected.connect(func(idx: int) -> void:
		_filter_type = idx - 1  # -1 = all
		_show_asteroid_selection()
	)
	controls.add_child(filter_btn)

	dispatch_content.add_child(controls)

	# Build a dummy worker list for estimation (use available workers)
	var est_workers := GameState.get_available_workers()
	if est_workers.is_empty():
		var placeholder := Worker.new()
		placeholder.skill = 1.0
		placeholder.wage = 100
		est_workers = [placeholder]

	# Get filtered and sorted asteroid list
	var asteroids := _get_sorted_asteroids(est_workers)

	# Scrollable list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 400)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 6)

	for asteroid in asteroids:
		var dist := Brachistochrone.distance_to(asteroid)
		var transit := Brachistochrone.transit_time(dist, _selected_ship.thrust_g)
		var est := AsteroidData.estimate_mission(asteroid, _selected_ship, est_workers)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 64)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT

		var profit_str := "$%s" % _format_number(int(est["profit"]))

		btn.text = "%s (%s)\n%.2f AU | %s | Est: %s%s" % [
			asteroid.asteroid_name, asteroid.get_type_name(),
			asteroid.orbit_au, _format_time(transit),
			"+" if est["profit"] > 0 else "", profit_str,
		]
		btn.pressed.connect(_select_asteroid.bind(asteroid))
		list_vbox.add_child(btn)

	scroll.add_child(list_vbox)
	dispatch_content.add_child(scroll)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 44)
	cancel.pressed.connect(func() -> void: dispatch_popup.visible = false)
	dispatch_content.add_child(cancel)

	dispatch_popup.visible = true

func _get_sorted_asteroids(est_workers: Array[Worker]) -> Array[AsteroidData]:
	var filtered: Array[AsteroidData] = []
	for a in GameState.asteroids:
		if _filter_type >= 0 and a.body_type != _filter_type:
			continue
		filtered.append(a)

	match _sort_by:
		"profit":
			filtered.sort_custom(func(a: AsteroidData, b: AsteroidData) -> bool:
				var ea := AsteroidData.estimate_mission(a, _selected_ship, est_workers)
				var eb := AsteroidData.estimate_mission(b, _selected_ship, est_workers)
				return ea["profit"] > eb["profit"]
			)
		"distance":
			filtered.sort_custom(func(a: AsteroidData, b: AsteroidData) -> bool:
				return a.orbit_au < b.orbit_au
			)
		"name":
			filtered.sort_custom(func(a: AsteroidData, b: AsteroidData) -> bool:
				return a.asteroid_name.naturalcasecmp_to(b.asteroid_name) < 0
			)
	return filtered

func _get_ore_summary(asteroid: AsteroidData) -> String:
	var parts: Array[String] = []
	for ore_type in asteroid.ore_yields:
		parts.append(ResourceTypes.get_ore_name(ore_type))
	return ", ".join(parts)

func _select_asteroid(asteroid: AsteroidData) -> void:
	_selected_asteroid = asteroid
	_show_worker_selection()

func _show_worker_selection() -> void:
	_clear_dispatch_content()

	var title := Label.new()
	title.text = "Assign Workers"
	title.add_theme_font_size_override("font_size", 20)
	dispatch_content.add_child(title)

	var dest_label := Label.new()
	dest_label.text = "Destination: %s (%s)" % [
		_selected_asteroid.asteroid_name, _selected_asteroid.get_type_name()
	]
	dispatch_content.add_child(dest_label)

	var ore_label := Label.new()
	ore_label.text = "Resources: %s" % _get_ore_summary(_selected_asteroid)
	dispatch_content.add_child(ore_label)

	var sep := HSeparator.new()
	dispatch_content.add_child(sep)

	var crew_label := Label.new()
	crew_label.text = "Minimum crew: %d" % _selected_ship.min_crew
	crew_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	dispatch_content.add_child(crew_label)

	var available := GameState.get_available_workers()
	if available.size() < _selected_ship.min_crew:
		var label := Label.new()
		label.text = "Not enough workers! Need %d, have %d available. Hire more first." % [
			_selected_ship.min_crew, available.size()
		]
		label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dispatch_content.add_child(label)
	else:
		# Auto-select: pre-select last crew, or first min_crew workers
		var should_preselect := func(worker: Worker) -> bool:
			if _selected_ship.last_crew.size() > 0:
				return worker in _selected_ship.last_crew
			# No history: select the first min_crew workers
			var idx := available.find(worker)
			return idx >= 0 and idx < _selected_ship.min_crew

		for worker in available:
			var preselect: bool = should_preselect.call(worker)
			if preselect and worker not in _selected_workers:
				_selected_workers.append(worker)

			var check := CheckBox.new()
			check.custom_minimum_size = Vector2(0, 44)
			check.text = "%s  |  Skill: %.2f  |  $%d/pay" % [
				worker.worker_name, worker.skill, worker.wage
			]
			check.button_pressed = preselect
			check.toggled.connect(func(on: bool) -> void:
				if on and worker not in _selected_workers:
					_selected_workers.append(worker)
				elif not on:
					_selected_workers.erase(worker)
				_update_estimate_display()
			)
			dispatch_content.add_child(check)
		# Show initial estimate if workers were pre-selected
		if not _selected_workers.is_empty():
			call_deferred("_update_estimate_display")

	# Estimate display
	var est_panel := PanelContainer.new()
	est_panel.name = "EstimatePanel"
	var est_vbox := VBoxContainer.new()
	est_vbox.add_theme_constant_override("separation", 4)

	var est_title := Label.new()
	est_title.text = "MISSION ESTIMATE"
	est_title.add_theme_font_size_override("font_size", 14)
	est_vbox.add_child(est_title)

	var est_details := Label.new()
	est_details.name = "EstimateDetails"
	est_details.text = "Select workers to see estimate"
	est_vbox.add_child(est_details)

	est_panel.add_child(est_vbox)
	dispatch_content.add_child(est_panel)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(0, 44)
	back_btn.pressed.connect(_show_asteroid_selection)
	btn_row.add_child(back_btn)

	var confirm := Button.new()
	confirm.text = "Confirm Dispatch"
	confirm.custom_minimum_size = Vector2(0, 44)
	confirm.pressed.connect(_confirm_dispatch)
	btn_row.add_child(confirm)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 44)
	cancel.pressed.connect(func() -> void: dispatch_popup.visible = false)
	btn_row.add_child(cancel)

	dispatch_content.add_child(btn_row)

func _update_estimate_display() -> void:
	var est_panel := dispatch_content.find_child("EstimatePanel", true, false)
	if not est_panel:
		return
	var est_label: Label = est_panel.find_child("EstimateDetails", true, false)
	if not est_label:
		return

	if _selected_workers.size() < _selected_ship.min_crew:
		est_label.text = "Need at least %d crew (%d selected)" % [
			_selected_ship.min_crew, _selected_workers.size()
		]
		est_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
		return

	var est := AsteroidData.estimate_mission(
		_selected_asteroid, _selected_ship, _selected_workers
	)

	var lines: Array[String] = []
	lines.append("Transit: %s each way" % _format_time(est["transit_time"]))
	lines.append("Mining: %s  |  Total: %s" % [
		_format_time(est["mining_time"]), _format_time(est["total_time"])
	])
	lines.append("Cargo: %.0f / %.0f t" % [est["cargo_total"], _selected_ship.cargo_capacity])

	# Fuel cost
	if GameState.settings.get("auto_refuel", true):
		var fuel_cost: float = est.get("fuel_cost", 0.0)
		lines.append("Fuel cost: $%s" % _format_number(int(fuel_cost)))

	lines.append("")

	var breakdown: Dictionary = est["cargo_breakdown"]
	for ore_type in breakdown:
		var tons: float = breakdown[ore_type]
		var price: int = MarketData.get_ore_price(ore_type)
		lines.append("  %s: %.1ft = $%s" % [
			ResourceTypes.get_ore_name(ore_type), tons, _format_number(int(tons * price))
		])

	lines.append("")
	lines.append("Revenue: $%s" % _format_number(int(est["revenue"])))
	lines.append("Wages: -$%s" % _format_number(int(est["wage_cost"])))
	if GameState.settings.get("auto_refuel", true):
		lines.append("Fuel: -$%s" % _format_number(int(est.get("fuel_cost", 0.0))))

	var profit_text := "$%s" % _format_number(int(abs(est["profit"])))
	if est["profit"] >= 0:
		lines.append("Profit: +%s" % profit_text)
	else:
		lines.append("LOSS: -%s" % profit_text)

	est_label.text = "\n".join(lines)

	if est["profit"] < 0:
		est_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	elif est["profit"] < 500:
		est_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	else:
		est_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))

func _confirm_dispatch() -> void:
	if _selected_workers.size() < _selected_ship.min_crew:
		return
	# Check fuel
	if GameState.settings.get("auto_refuel", true):
		var dist := Brachistochrone.distance_to(_selected_asteroid)
		var fuel_needed := _selected_ship.calc_fuel_for_distance(dist)
		var fuel_cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)
		if GameState.money < fuel_cost:
			return  # Can't afford fuel
		# Refuel and charge
		_selected_ship.fuel = _selected_ship.fuel_capacity
		GameState.money -= fuel_cost
	# Remember crew for next dispatch
	_selected_ship.last_crew = _selected_workers.duplicate()
	GameState.start_mission(_selected_ship, _selected_asteroid, _selected_workers)
	dispatch_popup.visible = false
	_mark_dirty()

func _build_details_text(ship: Ship) -> String:
	return "Thrust: %.1fg  |  Cargo: %.0ft  |  Fuel: %.0f/%.0f  |  Equip: %d/%d (%.2fx)" % [
		ship.thrust_g, ship.cargo_capacity, ship.fuel, ship.fuel_capacity,
		ship.equipment.size(), ship.max_equipment_slots, ship.get_mining_multiplier()
	]

func _clear_dispatch_content() -> void:
	for child in dispatch_content.get_children():
		child.queue_free()

func _format_time(ticks: float) -> String:
	var total_seconds := int(ticks)
	var minutes := total_seconds / 60
	var seconds := total_seconds % 60
	if minutes > 0:
		return "%dm %ds" % [minutes, seconds]
	return "%ds" % seconds

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
