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
var _cargo_labels: Dictionary = {}  # Ship -> Label for cargo display
var _location_labels: Dictionary = {}  # Ship -> Label for location display
const PROGRESS_LERP_SPEED: float = 8.0  # How fast progress bars catch up
var _dispatch_refresh_timer: float = 0.0
const DISPATCH_REFRESH_INTERVAL: float = 2.0  # Refresh dispatch popup every 2 seconds
var _on_selection_screen: bool = false  # Track if we're on the initial destination selection screen
var _on_estimate_screen: bool = false  # Track if we're on the worker selection / estimate screen
var _saved_colonies_scroll: float = 0.0  # Preserve scroll position across refreshes
var _saved_mining_scroll: float = 0.0  # Preserve scroll position across refreshes

func _ready() -> void:
	_cancel_preview()
	dispatch_popup.visible = false
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
	EventBus.rescue_mission_started.connect(func(_s: Ship, _c: int) -> void: _mark_dirty())
	EventBus.rescue_mission_completed.connect(func(_s: Ship) -> void: _mark_dirty())
	EventBus.tick.connect(_on_tick)
	_rebuild_ships()

func _mark_dirty() -> void:
	_needs_full_rebuild = true

func _process(delta: float) -> void:
	# Smooth LERP for progress bars
	for ship: Ship in _progress_bars:
		var bar: ProgressBar = _progress_bars[ship]
		if is_instance_valid(bar):
			var target_progress := 0.0
			if ship.current_mission:
				target_progress = ship.current_mission.get_progress() * 100.0
			elif ship.current_trade_mission:
				target_progress = ship.current_trade_mission.get_progress() * 100.0
			bar.value = lerp(bar.value, target_progress, PROGRESS_LERP_SPEED * delta)

func _on_tick(dt: float) -> void:
	# Refresh dispatch popup periodically to update orbital positions and fuel estimates
	if dispatch_popup.visible:
		_dispatch_refresh_timer += dt
		if _dispatch_refresh_timer >= DISPATCH_REFRESH_INTERVAL:
			_dispatch_refresh_timer = 0.0
			# Only refresh estimate screen, not selection screen (causes layout shifts)
			if _on_estimate_screen:
				# Refresh estimate display to show updated calculations
				_update_estimate_display()
				return

	if _needs_full_rebuild:
		_needs_full_rebuild = false
		if not dispatch_popup.visible:
			_rebuild_ships()
		return
	# Update labels (not progress - that's done in _process with LERP)
	for ship: Ship in _status_labels:
		var label: Label = _status_labels[ship]
		if is_instance_valid(label):
			if ship.current_mission:
				label.text = ship.current_mission.get_status_text()
			elif ship.current_trade_mission:
				label.text = ship.current_trade_mission.get_status_text()
	for ship: Ship in _detail_labels:
		var label: Label = _detail_labels[ship]
		if is_instance_valid(label):
			label.text = _build_details_text(ship)
	# Update cargo displays to show incremental amounts during mining
	for ship: Ship in _cargo_labels:
		var label: Label = _cargo_labels[ship]
		if is_instance_valid(label) and ship.get_cargo_total() > 0.01:
			var cargo_lines: Array[String] = ["Cargo (%.1ft):" % ship.get_cargo_total()]
			for ore_type in ship.current_cargo:
				var amount: float = ship.current_cargo[ore_type]
				if amount > 0.01:
					cargo_lines.append("  %s: %.1ft" % [ResourceTypes.get_ore_name(ore_type), amount])
			label.text = "\n".join(cargo_lines)
	# Update location displays to show ship positions during transit
	for ship: Ship in _location_labels:
		var label: Label = _location_labels[ship]
		if is_instance_valid(label):
			label.text = _get_location_text(ship)

func _rebuild_ships() -> void:
	_progress_bars.clear()
	_status_labels.clear()
	_detail_labels.clear()
	_cargo_labels.clear()
	_location_labels.clear()
	for child in ships_list.get_children():
		child.queue_free()

	for ship: Ship in GameState.ships:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 4)

		var header := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = "%s (%s)" % [ship.ship_name, ship.get_class_name()]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(name_label)

		if ship.is_derelict:
			var status := Label.new()
			var status_text := "STRANDED (OUT OF FUEL)" if ship.derelict_reason == "out_of_fuel" else "DERELICT (BREAKDOWN)"
			status.text = status_text
			status.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
			header.add_child(status)

			# Show refuel in progress
			if ship in GameState.refuel_missions:
				var refuel_data: Dictionary = GameState.refuel_missions[ship]
				var progress: float = float(refuel_data["elapsed_ticks"]) / float(refuel_data["transit_time"])
				var refuel_label := Label.new()
				refuel_label.text = "Refuel: %d%%" % int(progress * 100)
				refuel_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9))
				header.add_child(refuel_label)
			# Show rescue in progress
			elif ship in GameState.rescue_missions:
				var rescue_data: Dictionary = GameState.rescue_missions[ship]
				var progress: float = float(rescue_data["elapsed_ticks"]) / float(rescue_data["transit_time"])
				var rescue_label := Label.new()
				rescue_label.text = "Rescue: %d%%" % int(progress * 100)
				rescue_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
				header.add_child(rescue_label)
			else:
				var dist := ship.position_au.distance_to(CelestialData.get_earth_position_au())

				# Refuel option (cheaper, only for fuel depletion)
				if ship.derelict_reason == "out_of_fuel":
					var fuel_to_send := ship.fuel_capacity  # Send full tank
					var distance_cost := int(dist * GameState.REFUEL_COST_PER_AU)
					var fuel_cost := int(fuel_to_send * Ship.FUEL_COST_PER_UNIT)
					var refuel_cost := distance_cost + fuel_cost
					var refuel_btn := Button.new()
					refuel_btn.text = "Refuel ($%s)" % _format_number(refuel_cost)
					refuel_btn.custom_minimum_size = Vector2(0, 44)
					refuel_btn.disabled = GameState.money < refuel_cost
					refuel_btn.pressed.connect(func() -> void:
						GameState.start_refuel(ship, fuel_to_send)
						_mark_dirty()
					)
					header.add_child(refuel_btn)

				# Rescue option (expensive, for breakdowns or as alternative)
				var rescue_cost := int(dist * GameState.RESCUE_COST_PER_AU)
				var rescue_btn := Button.new()
				rescue_btn.text = "Rescue ($%s)" % _format_number(rescue_cost)
				rescue_btn.custom_minimum_size = Vector2(0, 44)
				rescue_btn.disabled = GameState.money < rescue_cost
				rescue_btn.pressed.connect(func() -> void:
					GameState.start_rescue(ship)
					_mark_dirty()
				)
				header.add_child(rescue_btn)
		elif ship.is_docked:
			var status := Label.new()
			status.text = "Docked"
			status.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
			header.add_child(status)

			var dispatch_btn := Button.new()
			dispatch_btn.text = "Dispatch"
			dispatch_btn.custom_minimum_size = Vector2(0, 44)
			dispatch_btn.pressed.connect(_start_dispatch.bind(ship))
			header.add_child(dispatch_btn)
		elif ship.is_idle_remote:
			var status := Label.new()
			if ship.current_mission and ship.current_mission.status == Mission.Status.IDLE_AT_DESTINATION:
				status.text = "Idle at " + ship.current_mission.asteroid.asteroid_name
			elif ship.current_trade_mission and ship.current_trade_mission.status == TradeMission.Status.IDLE_AT_COLONY:
				status.text = "Idle at " + ship.current_trade_mission.colony.colony_name
			else:
				status.text = "Idle (remote)"
			status.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
			header.add_child(status)
			_status_labels[ship] = status
		else:
			var status := Label.new()
			if ship.current_mission:
				status.text = ship.current_mission.get_status_text()
				status.add_theme_color_override("font_color", Color(0.8, 0.7, 0.2))
			elif ship.current_trade_mission:
				status.text = ship.current_trade_mission.get_status_text()
				status.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
			header.add_child(status)
			_status_labels[ship] = status

		vbox.add_child(header)

		# Location line
		var loc_label := Label.new()
		loc_label.text = _get_location_text(ship)
		loc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		loc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		loc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(loc_label)
		_location_labels[ship] = loc_label

		var details := Label.new()
		details.text = _build_details_text(ship)
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(details)
		_detail_labels[ship] = details

		# Action buttons for idle remote ships
		if ship.is_idle_remote:
			# Check if ship is at a colony with cargo to sell
			var at_colony: Colony = null
			if ship.current_trade_mission and ship.current_trade_mission.status == TradeMission.Status.IDLE_AT_COLONY:
				at_colony = ship.current_trade_mission.colony

			# Sell cargo button if at colony with cargo
			if at_colony and ship.get_cargo_total() > 0:
				var sell_btn := Button.new()
				var revenue := 0
				for ore_type in ship.current_cargo:
					var amount: float = ship.current_cargo[ore_type]
					var price: float = at_colony.get_ore_price(ore_type, GameState.market)
					revenue += int(amount * price)
				sell_btn.text = "Sell Cargo at %s ($%s)" % [at_colony.colony_name, _format_number(revenue)]
				sell_btn.custom_minimum_size = Vector2(0, 44)
				sell_btn.pressed.connect(func() -> void:
					var total_revenue := 0
					for ore_type in ship.current_cargo:
						var amount: float = ship.current_cargo[ore_type]
						var price: float = at_colony.get_ore_price(ore_type, GameState.market)
						total_revenue += int(amount * price)
					GameState.money += total_revenue
					ship.current_cargo.clear()
					_mark_dirty()
				)
				vbox.add_child(sell_btn)

			var action_row := HBoxContainer.new()
			action_row.add_theme_constant_override("separation", 8)

			var dispatch_btn := Button.new()
			dispatch_btn.text = "Dispatch"
			dispatch_btn.custom_minimum_size = Vector2(0, 44)
			dispatch_btn.pressed.connect(_start_dispatch.bind(ship))
			action_row.add_child(dispatch_btn)

			var return_btn := Button.new()
			return_btn.text = "Return to Earth"
			return_btn.custom_minimum_size = Vector2(0, 44)
			return_btn.pressed.connect(func() -> void:
				GameState.order_return_to_earth(ship)
				_mark_dirty()
			)
			action_row.add_child(return_btn)

			vbox.add_child(action_row)

		# Unload cargo button (docked ships with cargo)
		if ship.is_docked and ship.get_cargo_total() > 0:
			var unload_btn := Button.new()
			unload_btn.text = "Unload Cargo (%.1ft)" % ship.get_cargo_total()
			unload_btn.custom_minimum_size = Vector2(0, 44)
			unload_btn.pressed.connect(func() -> void:
				for ore_type in ship.current_cargo:
					GameState.add_resource(ore_type, ship.current_cargo[ore_type])
				ship.current_cargo.clear()
				_mark_dirty()
			)
			vbox.add_child(unload_btn)

		# Engine repair button (docked ships with engine < 100)
		if ship.is_docked and ship.engine_condition < 100.0:
			var repair_cost := ship.get_engine_repair_cost()
			var engine_btn := Button.new()
			engine_btn.text = "Repair Engine ($%s)" % _format_number(repair_cost)
			engine_btn.custom_minimum_size = Vector2(0, 44)
			engine_btn.disabled = GameState.money < repair_cost
			engine_btn.pressed.connect(func() -> void:
				GameState.repair_engine(ship)
				_mark_dirty()
			)
			vbox.add_child(engine_btn)

		# Show installed equipment with durability
		if not ship.equipment.is_empty():
			for e in ship.equipment:
				var equip_row := HBoxContainer.new()
				equip_row.add_theme_constant_override("separation", 6)

				var equip_label := Label.new()
				var dur_str := "%d%%" % int(e.durability)
				var broken_str := ""
				if e.durability <= 0:
					broken_str = " (BROKEN)"
					equip_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
				elif e.durability < 30:
					equip_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
				else:
					equip_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))

				equip_label.text = "%s (%.2fx) %s%s" % [e.equipment_name, e.mining_bonus, dur_str, broken_str]
				equip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				equip_row.add_child(equip_label)

				var dur_bar := ProgressBar.new()
				dur_bar.custom_minimum_size = Vector2(60, 0)
				dur_bar.value = e.durability
				dur_bar.max_value = e.max_durability
				equip_row.add_child(dur_bar)

				vbox.add_child(equip_row)

		# Progress bar for active transit/mining
		if not ship.is_docked and not ship.is_idle_remote and not ship.is_derelict:
			var progress := ProgressBar.new()
			if ship.current_mission:
				progress.value = ship.current_mission.get_progress() * 100.0
			elif ship.current_trade_mission:
				progress.value = ship.current_trade_mission.get_progress() * 100.0
			vbox.add_child(progress)
			_progress_bars[ship] = progress

		panel.add_child(vbox)
		ships_list.add_child(panel)

func _get_location_text(ship: Ship) -> String:
	if ship.is_at_earth:
		return "Location: Earth"
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

func _start_dispatch(ship: Ship) -> void:
	_selected_ship = ship
	_selected_asteroid = null
	_selected_workers.clear()
	_sort_by = "profit"
	_filter_type = -1
	_show_asteroid_selection()

func _show_asteroid_selection() -> void:
	_on_selection_screen = true  # We're on the main selection screen
	_on_estimate_screen = false  # Not on estimate screen

	# Save scroll positions before clearing (if they exist)
	for child in dispatch_content.get_children():
		if child is ScrollContainer:
			if child.name == "ColoniesScroll":
				_saved_colonies_scroll = child.scroll_vertical
			elif child.name == "MiningScroll":
				_saved_mining_scroll = child.scroll_vertical

	_clear_dispatch_content()

	var title := Label.new()
	title.text = "Select Destination"
	title.add_theme_font_size_override("font_size", 20)
	dispatch_content.add_child(title)

	# Show ship origin info and cargo
	var origin_label := Label.new()
	var cargo_total := _selected_ship.get_cargo_total()
	if cargo_total > 0:
		origin_label.text = "Dispatching from: %s (%.1ft cargo)" % [_get_location_text(_selected_ship), cargo_total]
	else:
		origin_label.text = "Dispatching from: %s" % _get_location_text(_selected_ship)
	origin_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	dispatch_content.add_child(origin_label)

	# If ship has cargo, show colonies first
	if cargo_total > 0:
		# Fixed header for market destinations
		var colonies_header := Label.new()
		colonies_header.text = "MARKET DESTINATIONS"
		colonies_header.add_theme_font_size_override("font_size", 18)
		colonies_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
		dispatch_content.add_child(colonies_header)

		# Scrollable list for colonies
		var colonies_scroll := ScrollContainer.new()
		colonies_scroll.name = "ColoniesScroll"
		colonies_scroll.size_flags_vertical = Control.SIZE_FILL
		colonies_scroll.custom_minimum_size = Vector2(0, 250)

		var colonies_vbox := VBoxContainer.new()
		colonies_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		colonies_vbox.add_theme_constant_override("separation", 6)

		# Filter out current location to prevent exploit (within 0.1 AU proximity)
		const PROXIMITY_THRESHOLD := 0.1
		var filtered_colonies: Array[Colony] = []
		for colony in GameState.colonies:
			var dist_to_colony := _selected_ship.position_au.distance_to(colony.get_position_au())
			if dist_to_colony > PROXIMITY_THRESHOLD:
				filtered_colonies.append(colony)

		for colony in filtered_colonies:
			var colony_pos := colony.get_position_au()
			var dist := _selected_ship.position_au.distance_to(colony_pos)
			var transit := Brachistochrone.transit_time(dist, _selected_ship.get_effective_thrust())
			var cargo_mass := _selected_ship.get_cargo_total()
			var fuel_needed := _selected_ship.calc_fuel_for_distance(dist, cargo_mass)

			# Calculate fuel route if needed
			var fuel_route: Array[String] = []
			var is_unreachable := false
			# If ship is at a colony, assume it can refuel before departing
			var available_fuel := _selected_ship.get_effective_fuel_capacity() if _selected_ship.is_idle_remote else _selected_ship.fuel
			var has_insufficient_fuel := fuel_needed > available_fuel
			if has_insufficient_fuel:
				fuel_route = _calculate_fuel_route_simple(colony)
				if fuel_route.is_empty():
					# Completely unreachable
					is_unreachable = true
					# Skip if setting is disabled
					if not GameState.settings.get("show_unreachable_destinations", false):
						continue

			# Calculate potential revenue from cargo
			var revenue := 0
			var cargo_breakdown := ""
			for ore_type in _selected_ship.current_cargo:
				var amount: float = _selected_ship.current_cargo[ore_type]
				var price: float = colony.get_ore_price(ore_type, GameState.market)
				revenue += int(amount * price)
				if cargo_breakdown != "":
					cargo_breakdown += ", "
				cargo_breakdown += "%s: $%s" % [ResourceTypes.get_ore_name(ore_type), _format_number(int(amount * price))]

			var colony_row := VBoxContainer.new()
			colony_row.add_theme_constant_override("separation", 4)

			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 80)
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.focus_mode = Control.FOCUS_NONE
			btn.flat = true
			# Disable all focus/hover visual effects
			var empty_style := StyleBoxEmpty.new()
			btn.add_theme_stylebox_override("focus", empty_style)

			var fuel_status := ""
			if is_unreachable:
				fuel_status = " [UNREACHABLE - insufficient fuel capacity]"
			elif has_insufficient_fuel:
				fuel_status = " [NEEDS REFUEL]"
			elif fuel_needed > available_fuel * 0.8:
				fuel_status = " [LOW FUEL]"

			btn.text = "%s (MARKET)\n%.2f AU | %s | Revenue: $%s%s\n%s" % [
				colony.colony_name, dist, _format_time(transit),
				_format_number(revenue), fuel_status, cargo_breakdown
			]
			btn.disabled = is_unreachable  # Disable if unreachable
			btn.pressed.connect(_select_colony_trade.bind(colony))
			colony_row.add_child(btn)

			# Show fuel stop route as clickable buttons
			if not fuel_route.is_empty():
				var route_label := Label.new()
				route_label.text = "  Fuel stops needed:"
				route_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9))
				colony_row.add_child(route_label)

				var stops_hbox := HBoxContainer.new()
				stops_hbox.add_theme_constant_override("separation", 8)
				for stop_name in fuel_route:
					# Find the colony by name
					var stop_colony: Colony = null
					for c in GameState.colonies:
						if c.colony_name == stop_name:
							stop_colony = c
							break

					if stop_colony:
						var stop_btn := Button.new()
						stop_btn.text = stop_name
						stop_btn.custom_minimum_size = Vector2(0, 36)
						stop_btn.focus_mode = Control.FOCUS_NONE
						stop_btn.pressed.connect(_select_colony_trade.bind(stop_colony))
						stops_hbox.add_child(stop_btn)

				colony_row.add_child(stops_hbox)

			colonies_vbox.add_child(colony_row)

		colonies_scroll.add_child(colonies_vbox)
		dispatch_content.add_child(colonies_scroll)

		# Restore scroll position after UI has been laid out
		if _saved_colonies_scroll > 0:
			var saved_pos := _saved_colonies_scroll
			colonies_scroll.call_deferred("set", "scroll_vertical", int(saved_pos))

		var sep := HSeparator.new()
		dispatch_content.add_child(sep)

	# Fixed header for mining destinations
	var mining_header := Label.new()
	mining_header.text = "MINING DESTINATIONS"
	mining_header.add_theme_font_size_override("font_size", 18)
	mining_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	dispatch_content.add_child(mining_header)

	# Fixed filter/sort controls
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

	# Scrollable list for mining destinations
	var mining_scroll := ScrollContainer.new()
	mining_scroll.name = "MiningScroll"
	mining_scroll.size_flags_vertical = Control.SIZE_FILL
	mining_scroll.custom_minimum_size = Vector2(0, 400)

	var mining_vbox := VBoxContainer.new()
	mining_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mining_vbox.add_theme_constant_override("separation", 6)

	# Build a dummy worker list for estimation (use available workers)
	var est_workers := GameState.get_available_workers()
	if est_workers.is_empty():
		var placeholder := Worker.new()
		placeholder.skill = 1.0
		placeholder.wage = 100
		est_workers = [placeholder]

	# Get filtered and sorted asteroid list
	var asteroids := _get_sorted_asteroids(est_workers)

	for asteroid in asteroids:
		var dist := _selected_ship.position_au.distance_to(asteroid.get_position_au())
		var transit := Brachistochrone.transit_time(dist, _selected_ship.get_effective_thrust())
		var est := AsteroidData.estimate_mission(asteroid, _selected_ship, est_workers)

		# Fuel warning and route calculation
		var fuel_one_way := _selected_ship.calc_fuel_for_distance(dist)
		var available_fuel := _selected_ship.get_effective_fuel_capacity() if _selected_ship.is_idle_remote else _selected_ship.fuel
		var fuel_warning := ""
		var fuel_route: Array[String] = []
		var is_unreachable := false

		if fuel_one_way > available_fuel:
			var current_cargo := _selected_ship.get_cargo_total()
			fuel_route = _calculate_fuel_route_to_position(asteroid.get_position_au(), current_cargo)
			if fuel_route.is_empty():
				is_unreachable = true
				fuel_warning = " [UNREACHABLE]"
				# Skip if setting is disabled
				if not GameState.settings.get("show_unreachable_destinations", false):
					continue
			else:
				fuel_warning = " [NEEDS REFUEL]"
		elif fuel_one_way > available_fuel * 0.8:
			fuel_warning = " [LOW FUEL]"

		var dest_row := VBoxContainer.new()
		dest_row.add_theme_constant_override("separation", 4)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 80)  # Taller to prevent wrapping issues
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.focus_mode = Control.FOCUS_NONE
		btn.flat = true
		# Disable all focus/hover visual effects
		var empty_style := StyleBoxEmpty.new()
		btn.add_theme_stylebox_override("focus", empty_style)

		var profit_str := "$%s" % _format_number(int(est["profit"]))

		btn.text = "%s (%s)\n%.2f AU | %s | Est: %s%s%s" % [
			asteroid.asteroid_name, asteroid.get_type_name(),
			dist, _format_time(transit),
			"+" if est["profit"] > 0 else "", profit_str, fuel_warning,
		]
		btn.disabled = is_unreachable
		btn.pressed.connect(_select_asteroid.bind(asteroid))
		dest_row.add_child(btn)

		# Show fuel stop route as clickable buttons
		if not fuel_route.is_empty():
			var route_label := Label.new()
			route_label.text = "  Fuel stops needed:"
			route_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9))
			dest_row.add_child(route_label)

			var stops_hbox := HBoxContainer.new()
			stops_hbox.add_theme_constant_override("separation", 8)
			for stop_name in fuel_route:
				var stop_colony: Colony = null
				for c in GameState.colonies:
					if c.colony_name == stop_name:
						stop_colony = c
						break

				if stop_colony:
					var stop_btn := Button.new()
					stop_btn.text = stop_name
					stop_btn.custom_minimum_size = Vector2(0, 36)
					stop_btn.focus_mode = Control.FOCUS_NONE
					stop_btn.pressed.connect(_select_colony_trade.bind(stop_colony))
					stops_hbox.add_child(stop_btn)

			dest_row.add_child(stops_hbox)

		mining_vbox.add_child(dest_row)

	mining_scroll.add_child(mining_vbox)
	dispatch_content.add_child(mining_scroll)

	# Restore scroll position after UI has been laid out
	if _saved_mining_scroll > 0:
		var saved_pos := _saved_mining_scroll
		mining_scroll.call_deferred("set", "scroll_vertical", int(saved_pos))

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 44)
	cancel.pressed.connect(func() -> void:
		_cancel_preview()
		dispatch_popup.visible = false
	)
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
				var da := _selected_ship.position_au.distance_to(a.get_position_au())
				var db := _selected_ship.position_au.distance_to(b.get_position_au())
				return da < db
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

func _select_colony_trade(colony: Colony) -> void:
	# Skip worker selection, go straight to trade mission
	var cargo := _selected_ship.current_cargo.duplicate()
	if cargo.is_empty():
		return

	# Auto-refuel from current position
	if GameState.settings.get("auto_refuel", true):
		var colony_pos := colony.get_position_au()
		var dist := _selected_ship.position_au.distance_to(colony_pos)
		var fuel_needed := _selected_ship.calc_fuel_for_distance(dist)
		var fuel_cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)
		if GameState.money < fuel_cost:
			return  # Can't afford fuel
		_selected_ship.fuel = _selected_ship.fuel_capacity
		GameState.money -= fuel_cost

	var assigned: Array[Worker] = []
	if _selected_ship.is_idle_remote:
		GameState.dispatch_idle_ship_trade(_selected_ship, colony, assigned, cargo)
	else:
		GameState.start_trade_mission(_selected_ship, colony, assigned, cargo)
	_cancel_preview()
	dispatch_popup.visible = false
	_mark_dirty()

func _show_worker_selection() -> void:
	_on_selection_screen = false  # Left the main selection screen
	_on_estimate_screen = true  # Now on the estimate screen
	_clear_dispatch_content()

	# AI-calculate optimal thrust based on company policy
	var expected_cargo := _selected_ship.cargo_capacity
	var ai_thrust := CompanyPolicy.calculate_thrust_setting(
		GameState.thrust_policy,
		_selected_ship,
		_selected_asteroid.get_position_au(),
		expected_cargo
	)
	_selected_ship.thrust_setting = ai_thrust

	# Show trajectory preview on map
	EventBus.mission_preview_started.emit(_selected_ship, _selected_asteroid.get_position_au())

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

	# Distance from ship position
	var dist := _selected_ship.position_au.distance_to(_selected_asteroid.get_position_au())
	var dist_label := Label.new()
	dist_label.text = "Distance: %.2f AU from ship" % dist
	dist_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	dispatch_content.add_child(dist_label)

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

	# Manual thrust control (hidden by default, AI-controlled)
	var thrust_control_row := HBoxContainer.new()
	thrust_control_row.name = "ThrustControlRow"
	thrust_control_row.add_theme_constant_override("separation", 8)

	var manual_thrust_btn := Button.new()
	manual_thrust_btn.name = "ManualThrustButton"
	manual_thrust_btn.text = "Manual Thrust Control"
	manual_thrust_btn.custom_minimum_size = Vector2(0, 32)
	manual_thrust_btn.toggle_mode = true
	manual_thrust_btn.pressed.connect(func() -> void:
		var slider_row = est_vbox.find_child("ThrustSliderRow", false, false)
		if slider_row:
			slider_row.visible = manual_thrust_btn.button_pressed
	)
	thrust_control_row.add_child(manual_thrust_btn)

	var ai_label := Label.new()
	ai_label.name = "AIThrustLabel"
	ai_label.text = "AI: %.0f%% (%s)" % [_selected_ship.thrust_setting * 100.0, CompanyPolicy.THRUST_POLICY_NAMES[GameState.thrust_policy]]
	ai_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	thrust_control_row.add_child(ai_label)

	est_vbox.add_child(thrust_control_row)

	# Thrust slider (hidden by default)
	var thrust_slider_row := HBoxContainer.new()
	thrust_slider_row.name = "ThrustSliderRow"
	thrust_slider_row.visible = false
	thrust_slider_row.add_theme_constant_override("separation", 8)

	var thrust_label := Label.new()
	thrust_label.text = "Thrust:"
	thrust_label.custom_minimum_size = Vector2(60, 0)
	thrust_slider_row.add_child(thrust_label)

	var thrust_slider := HSlider.new()
	thrust_slider.name = "ThrustSlider"
	thrust_slider.min_value = 0.1
	thrust_slider.max_value = 1.0
	thrust_slider.step = 0.05
	thrust_slider.value = _selected_ship.thrust_setting
	thrust_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thrust_slider.custom_minimum_size = Vector2(200, 0)
	thrust_slider.value_changed.connect(func(value: float) -> void:
		_selected_ship.thrust_setting = value
		_update_estimate_display()
	)
	thrust_slider_row.add_child(thrust_slider)

	var thrust_pct_label := Label.new()
	thrust_pct_label.name = "ThrustPctLabel"
	thrust_pct_label.text = "%.0f%%" % (_selected_ship.thrust_setting * 100.0)
	thrust_pct_label.custom_minimum_size = Vector2(50, 0)
	thrust_slider_row.add_child(thrust_pct_label)

	est_vbox.add_child(thrust_slider_row)

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
	back_btn.pressed.connect(func() -> void:
		_cancel_preview()
		_show_asteroid_selection()
	)
	btn_row.add_child(back_btn)

	var confirm := Button.new()
	confirm.text = "Confirm Dispatch"
	confirm.custom_minimum_size = Vector2(0, 44)
	confirm.pressed.connect(_execute_dispatch)
	btn_row.add_child(confirm)

	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.custom_minimum_size = Vector2(0, 44)
	cancel.pressed.connect(func() -> void:
		_cancel_preview()
		dispatch_popup.visible = false
	)
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

	# Update thrust labels
	var thrust_pct_label: Label = est_panel.find_child("ThrustPctLabel", true, false)
	if thrust_pct_label:
		thrust_pct_label.text = "%.0f%%" % (_selected_ship.thrust_setting * 100.0)

	var ai_thrust_label: Label = est_panel.find_child("AIThrustLabel", true, false)
	if ai_thrust_label:
		ai_thrust_label.text = "AI: %.0f%% (%s)" % [_selected_ship.thrust_setting * 100.0, CompanyPolicy.THRUST_POLICY_NAMES[GameState.thrust_policy]]

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

	# Fuel warning for one-way insufficiency
	var dist := _selected_ship.position_au.distance_to(_selected_asteroid.get_position_au())
	var fuel_round_trip := _selected_ship.calc_fuel_for_distance(dist)
	if fuel_round_trip > _selected_ship.fuel_capacity:
		lines.append("WARNING: Insufficient fuel capacity for round trip!")

	lines.append("")

	var breakdown: Dictionary = est["cargo_breakdown"]
	for ore_type in breakdown:
		var tons: float = breakdown[ore_type]
		var price: float = MarketData.get_ore_price(ore_type)
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
		var dist := _selected_ship.position_au.distance_to(_selected_asteroid.get_position_au())
		var fuel_needed := _selected_ship.calc_fuel_for_distance(dist)
		var fuel_cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)
		if GameState.money < fuel_cost:
			return  # Can't afford fuel
		# Refuel and charge
		_selected_ship.fuel = _selected_ship.fuel_capacity
		GameState.money -= fuel_cost
	# Remember crew for next dispatch
	_selected_ship.last_crew = _selected_workers.duplicate()

	if _selected_ship.is_idle_remote:
		GameState.dispatch_idle_ship(_selected_ship, _selected_asteroid, _selected_workers)
	else:
		GameState.start_mission(_selected_ship, _selected_asteroid, _selected_workers)
	_cancel_preview()
	dispatch_popup.visible = false
	_mark_dirty()

func _build_details_text(ship: Ship) -> String:
	var engine_str := ""
	if ship.engine_condition < 100.0:
		engine_str = "  |  Eng: %d%%" % int(ship.engine_condition)
	return "Thrust: %.1fg (%.0f%%)  |  Cargo: %.0f/%.0ft  |  Fuel: %.0f/%.0f  |  Equip: %d/%d (%.2fx)%s" % [
		ship.get_effective_thrust(), ship.thrust_setting * 100.0, ship.get_cargo_total(), ship.get_effective_cargo_capacity(),
		ship.fuel, ship.get_effective_fuel_capacity(),
		ship.equipment.size(), ship.max_equipment_slots, ship.get_mining_multiplier(),
		engine_str,
	]

func _calculate_fuel_route_simple(destination: Colony) -> Array[String]:
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
			var dist_colony_to_dest := colony_pos.distance_to(dest_pos)
			var fuel_colony_to_dest := _selected_ship.calc_fuel_for_distance(dist_colony_to_dest, cargo_mass)
			if fuel_colony_to_dest > max_fuel:
				continue  # Can't reach destination from this colony even with full tank

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

		# Check if we can now reach destination
		var dist_to_dest := pos.distance_to(dest_pos)
		var fuel_to_dest := _selected_ship.calc_fuel_for_distance(dist_to_dest, cargo_mass)
		if fuel_to_dest <= fuel:
			return route  # Success!

	return []  # Couldn't find route within MAX_HOPS

func _calculate_fuel_route_to_position(dest_pos: Vector2, cargo_mass: float) -> Array[String]:
	# Calculate route with fuel stops from current position to a specific position
	# Returns array of colony names to visit, or empty if unreachable
	const PROXIMITY_THRESHOLD := 0.1
	const MAX_HOPS := 3  # Maximum fuel stops allowed
	const SAFETY_MARGIN := 0.8  # Use 80% of max fuel to be conservative

	var current_pos := _selected_ship.position_au
	var current_fuel := _selected_ship.fuel
	var max_fuel := _selected_ship.get_effective_fuel_capacity()

	# Check if we can reach directly
	var direct_dist := current_pos.distance_to(dest_pos)
	var direct_fuel := _selected_ship.calc_fuel_for_distance(direct_dist, cargo_mass)
	if direct_fuel <= current_fuel:
		return []  # No fuel stops needed

	# Check if it's physically impossible (even with full tank and safety margin)
	if direct_fuel > max_fuel * SAFETY_MARGIN:
		# Need intermediate stops
		pass
	else:
		return []  # Direct route is possible with refuel

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

			# Check if destination is reachable from this colony (with full fuel and safety margin)
			var dist_colony_to_dest := colony_pos.distance_to(dest_pos)
			var fuel_colony_to_dest := _selected_ship.calc_fuel_for_distance(dist_colony_to_dest, cargo_mass)
			if fuel_colony_to_dest > max_fuel * SAFETY_MARGIN:
				continue  # Can't reach destination from this colony even with full tank

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
		if fuel_to_dest <= fuel * SAFETY_MARGIN:
			return route  # Success!

	return []  # Couldn't find route within MAX_HOPS

func _clear_dispatch_content() -> void:
	for child in dispatch_content.get_children():
		child.queue_free()

func _format_time(ticks: float) -> String:
	return TimeScale.format_time(ticks)

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
