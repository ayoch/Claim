extends MarginContainer

# Combined Fleet + Market tab with ship-centric view

@onready var ships_list: VBoxContainer = %ShipsList
@onready var dispatch_popup: PanelContainer = %DispatchPopup
@onready var dispatch_content: VBoxContainer = %DispatchContent

var _selected_ship: Ship = null
var _selected_asteroid: AsteroidData = null
var _selected_workers: Array[Worker] = []
var _selected_transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE
var _sell_at_destination_markets: bool = false  # Toggle: return with ore vs sell at nearby markets
var _sort_by: String = "profit"
var _filter_type: int = -1
var _needs_full_rebuild: bool = true
var _progress_bars: Dictionary = {}
var _status_labels: Dictionary = {}
var _detail_labels: Dictionary = {}
var _cargo_labels: Dictionary = {}  # Ship -> Label for cargo display
const PROGRESS_LERP_SPEED: float = 8.0  # How fast progress bars catch up
var _dispatch_refresh_timer: float = 0.0
const DISPATCH_REFRESH_INTERVAL: float = 2.0  # Refresh dispatch popup every 2 seconds

func _ready() -> void:
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
	EventBus.resource_changed.connect(func(_o: ResourceTypes.OreType, _a: float) -> void: _mark_dirty())
	EventBus.money_changed.connect(func(_m: int) -> void: _mark_dirty())
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
			# Refresh destination list to show updated distances/fuel
			_show_asteroid_selection()
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

func _rebuild_ships() -> void:
	_progress_bars.clear()
	_status_labels.clear()
	_detail_labels.clear()
	_cargo_labels.clear()
	for child in ships_list.get_children():
		child.queue_free()

	for ship: Ship in GameState.ships:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 4)

		# === SHIP HEADER ===
		var header := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = ship.ship_name
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
			status.text = "Docked at Earth"
			status.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
			header.add_child(status)
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

		# === LOCATION & DETAILS ===
		var loc_label := Label.new()
		loc_label.text = _get_location_text(ship)
		loc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		loc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		loc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(loc_label)

		var details := Label.new()
		details.text = _build_details_text(ship)
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(details)
		_detail_labels[ship] = details

		# === CARGO DISPLAY ===
		if ship.get_cargo_total() > 0.01:
			var cargo_label := Label.new()
			var cargo_lines: Array[String] = ["Cargo (%.1ft):" % ship.get_cargo_total()]
			for ore_type in ship.current_cargo:
				var amount: float = ship.current_cargo[ore_type]
				# Only show ore types with meaningful amounts (skip near-zero from floating point)
				if amount > 0.01:
					cargo_lines.append("  %s: %.1ft" % [ResourceTypes.get_ore_name(ore_type), amount])
			cargo_label.text = "\n".join(cargo_lines)
			cargo_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
			vbox.add_child(cargo_label)
			_cargo_labels[ship] = cargo_label  # Store reference for updates

		# === ACTION BUTTONS ===

		# Docked ships: Dispatch and Unload
		if ship.is_docked:
			var btn_row := HBoxContainer.new()
			btn_row.add_theme_constant_override("separation", 8)

			var dispatch_btn := Button.new()
			dispatch_btn.text = "Dispatch"
			dispatch_btn.custom_minimum_size = Vector2(0, 44)
			dispatch_btn.pressed.connect(_start_dispatch.bind(ship))
			btn_row.add_child(dispatch_btn)

			# Unload cargo button
			if ship.get_cargo_total() > 0:
				var unload_btn := Button.new()
				unload_btn.text = "Unload to Stockpile"
				unload_btn.custom_minimum_size = Vector2(0, 44)
				unload_btn.pressed.connect(func() -> void:
					for ore_type in ship.current_cargo:
						GameState.add_resource(ore_type, ship.current_cargo[ore_type])
					ship.current_cargo.clear()
					_mark_dirty()
				)
				btn_row.add_child(unload_btn)

			vbox.add_child(btn_row)

		# Idle remote ships: Sell at colony, Dispatch, Return
		if ship.is_idle_remote:
			var at_colony: Colony = null
			if ship.current_trade_mission and ship.current_trade_mission.status == TradeMission.Status.IDLE_AT_COLONY:
				at_colony = ship.current_trade_mission.colony

			# Contract fulfillment and cargo selling options
			if at_colony and ship.get_cargo_total() > 0:
				# Check for matching contracts
				var matching_contracts := _get_matching_contracts(ship, at_colony)

				# Show contract options if any match
				if not matching_contracts.is_empty():
					var contract_header := Label.new()
					contract_header.text = "Available Contracts at %s:" % at_colony.colony_name
					contract_header.add_theme_font_size_override("font_size", 14)
					contract_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
					vbox.add_child(contract_header)

					for contract in matching_contracts:
						_add_contract_fulfillment_ui(vbox, ship, contract, at_colony)

					var sep := HSeparator.new()
					vbox.add_child(sep)

				# Spot market sell button
				var sell_btn := Button.new()
				var revenue := 0
				for ore_type in ship.current_cargo:
					var amount: float = ship.current_cargo[ore_type]
					var price: float = at_colony.get_ore_price(ore_type, GameState.market)
					revenue += int(amount * price)
				sell_btn.text = "Sell All on Spot Market ($%s)" % _format_number(revenue)
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

		# === EQUIPMENT ===
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

		# === PROGRESS BAR ===
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

# Include all the helper functions from fleet_tab.gd
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

	# Show ship origin info and cargo
	var origin_label := Label.new()
	var cargo_total := _selected_ship.get_cargo_total()
	if cargo_total > 0:
		origin_label.text = "Dispatching from: %s (%.1ft cargo)" % [_get_location_text(_selected_ship), cargo_total]
	else:
		origin_label.text = "Dispatching from: %s" % _get_location_text(_selected_ship)
	origin_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	dispatch_content.add_child(origin_label)

	# Scrollable list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.custom_minimum_size = Vector2(0, 400)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 6)

	# If ship has cargo, show colonies first
	if cargo_total > 0:
		var colonies_header := Label.new()
		colonies_header.text = "MARKET DESTINATIONS (Best Profit First)"
		colonies_header.add_theme_font_size_override("font_size", 18)
		colonies_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
		list_vbox.add_child(colonies_header)

		# Sort colonies by profit (revenue - fuel cost)
		var sorted_colonies := GameState.colonies.duplicate()
		sorted_colonies.sort_custom(func(a: Colony, b: Colony) -> bool:
			var profit_a := _calculate_colony_profit(a)
			var profit_b := _calculate_colony_profit(b)
			return profit_a > profit_b  # Highest profit first
		)

		# Filter out current location to prevent exploit (within 0.1 AU proximity)
		const PROXIMITY_THRESHOLD := 0.1
		var filtered_colonies: Array[Colony] = []
		for colony in sorted_colonies:
			var dist_to_colony := _selected_ship.position_au.distance_to(colony.get_position_au())
			if dist_to_colony > PROXIMITY_THRESHOLD:
				filtered_colonies.append(colony)

		for colony in filtered_colonies:
			var colony_pos: Vector2 = colony.get_position_au()
			var dist := _selected_ship.position_au.distance_to(colony_pos)
			var transit := Brachistochrone.transit_time(dist, _selected_ship.thrust_g)

			# Calculate WORST-CASE round-trip fuel (loaded outbound, empty return)
			var cargo_mass := _selected_ship.get_cargo_total()
			var fuel_outbound := _selected_ship.calc_fuel_for_distance(dist, cargo_mass)
			var fuel_return := _selected_ship.calc_fuel_for_distance(dist, 0.0)
			var fuel_needed := fuel_outbound + fuel_return

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

			var fuel_status := ""
			var has_insufficient_fuel := fuel_needed > _selected_ship.fuel
			var has_cargo := cargo_mass > 0

			# Calculate fuel route if needed
			var fuel_route: Array[String] = []
			var is_unreachable := false
			if has_insufficient_fuel:
				fuel_route = _calculate_fuel_route(colony)
				if fuel_route.is_empty():
					# Completely unreachable - skip this destination
					continue
				fuel_status = " [NEEDS REFUEL]"
			elif fuel_needed > _selected_ship.fuel * 0.9:
				fuel_status = " [CRITICAL FUEL - %.0f needed]" % fuel_needed

			# Create row container for destination + jettison buttons
			var colony_row := VBoxContainer.new()
			colony_row.add_theme_constant_override("separation", 4)

			var btn := Button.new()
			btn.custom_minimum_size = Vector2(0, 80)
			btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			btn.text = "%s (MARKET)\n%.2f AU | %s | Revenue: $%s%s\n%s" % [
				colony.colony_name, dist, _format_time(transit),
				_format_number(revenue), fuel_status, cargo_breakdown
			]
			btn.pressed.connect(func() -> void:
				_confirm_colony_dispatch(colony)
			)
			colony_row.add_child(btn)

			# Show fuel stop route if needed
			if not fuel_route.is_empty():
				var route_label := Label.new()
				route_label.text = "  Route: " + " → ".join(fuel_route) + " → " + colony.colony_name
				route_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9))
				route_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				colony_row.add_child(route_label)

			# ALWAYS show action buttons if ship has cargo
			if has_cargo:
				var jettison_row := HBoxContainer.new()
				jettison_row.add_theme_constant_override("separation", 8)

				var jettison_label := Label.new()
				jettison_label.text = "  Jettison cargo:"
				jettison_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
				jettison_row.add_child(jettison_label)

				# Smart jettison button (minimum needed)
				var smart_btn := Button.new()
				smart_btn.text = "Dump to Fit"
				smart_btn.custom_minimum_size = Vector2(0, 36)
				smart_btn.tooltip_text = "Jettison minimum cargo needed to make this trip"
				smart_btn.pressed.connect(func() -> void:
					var jettisoned := GameState.jettison_cargo_for_trip(_selected_ship, dist, 0.0)  # Empty on return
					_show_asteroid_selection()  # Refresh the list
					print("Jettisoned %.1f tons to make trip viable" % jettisoned)
				)
				jettison_row.add_child(smart_btn)

				# Dump all button
				var dump_all_btn := Button.new()
				dump_all_btn.text = "Dump All (%.0ft)" % cargo_mass
				dump_all_btn.custom_minimum_size = Vector2(0, 36)
				dump_all_btn.tooltip_text = "Jettison all cargo (lost forever)"
				dump_all_btn.pressed.connect(func() -> void:
					GameState.jettison_all_cargo(_selected_ship)
					_show_asteroid_selection()  # Refresh the list
				)
				jettison_row.add_child(dump_all_btn)

				colony_row.add_child(jettison_row)

			list_vbox.add_child(colony_row)

		var sep := HSeparator.new()
		list_vbox.add_child(sep)

	# Mining destinations header
	var mining_header := Label.new()
	mining_header.text = "MINING DESTINATIONS"
	mining_header.add_theme_font_size_override("font_size", 18)
	mining_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	list_vbox.add_child(mining_header)

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

	# Market strategy toggle
	var market_toggle := Button.new()
	market_toggle.toggle_mode = true
	market_toggle.button_pressed = _sell_at_destination_markets
	market_toggle.text = "Sell at Dest. Markets" if _sell_at_destination_markets else "Return w/ Ore"
	market_toggle.custom_minimum_size = Vector2(180, 44)
	market_toggle.tooltip_text = "Toggle: Return with ore vs sell at markets near destination"
	market_toggle.toggled.connect(func(pressed: bool) -> void:
		_sell_at_destination_markets = pressed
		market_toggle.text = "Sell at Dest. Markets" if pressed else "Return w/ Ore"
		_show_asteroid_selection()
	)
	controls.add_child(market_toggle)

	list_vbox.add_child(controls)

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
		var asteroid_pos: Vector2 = asteroid.get_position_au()
		var dist_outbound := _selected_ship.position_au.distance_to(asteroid_pos)

		# Get base estimate for mining
		var est := AsteroidData.estimate_mission(asteroid, _selected_ship, est_workers)

		# Calculate based on market strategy
		var return_pos: Vector2
		var dist_return: float
		var revenue: float
		var strategy_label := ""

		if _sell_at_destination_markets:
			# Find nearest colony to asteroid
			var nearest_colony: Colony = null
			var nearest_dist := 999999.0
			for colony in GameState.colonies:
				var d := asteroid_pos.distance_to(colony.get_position_au())
				if d < nearest_dist:
					nearest_dist = d
					nearest_colony = colony

			if nearest_colony:
				return_pos = nearest_colony.get_position_au()
				dist_return = nearest_dist
				strategy_label = " → %s" % nearest_colony.colony_name

				# Calculate revenue at colony prices (with scarcity multiplier)
				revenue = 0.0
				var cargo_breakdown: Dictionary = est["cargo_breakdown"]
				for ore_type in cargo_breakdown:
					var tons: float = cargo_breakdown[ore_type]
					var colony_price := nearest_colony.get_ore_price(ore_type, GameState.market)
					revenue += tons * colony_price
			else:
				# Fallback: return to current position
				return_pos = _selected_ship.position_au
				dist_return = dist_outbound
				revenue = est["revenue"]
		else:
			# Return with ore to current position
			return_pos = _selected_ship.position_au
			dist_return = dist_outbound
			revenue = est["revenue"]
			strategy_label = " (round trip)"

		# Calculate transit times
		var transit_out := Brachistochrone.transit_time(dist_outbound, _selected_ship.thrust_g)
		var transit_ret := Brachistochrone.transit_time(dist_return, _selected_ship.thrust_g)
		var total_transit := transit_out + transit_ret

		# Fuel calculation
		var current_cargo := _selected_ship.get_cargo_total()
		var fuel_outbound := _selected_ship.calc_fuel_for_distance(dist_outbound, current_cargo)
		var fuel_return := _selected_ship.calc_fuel_for_distance(dist_return, est["cargo_total"])
		var total_fuel_needed := fuel_outbound + fuel_return
		var custom_fuel_cost := total_fuel_needed * Ship.FUEL_COST_PER_UNIT

		# Wages for total mission time
		var total_time: float = total_transit + est["mining_time"]
		var payroll_cycles: float = total_time / 60.0
		var wage_per_tick := 0.0
		for w in est_workers:
			wage_per_tick += w.wage
		var custom_wage_cost := wage_per_tick * payroll_cycles

		# Final profit
		var adjusted_profit := revenue - custom_wage_cost - custom_fuel_cost

		var fuel_warning := ""
		var has_insufficient_fuel := total_fuel_needed > _selected_ship.fuel
		var has_cargo := current_cargo > 0

		if has_insufficient_fuel:
			fuel_warning = " [INSUFFICIENT FUEL - WILL STRAND!]"
		elif total_fuel_needed > _selected_ship.fuel * 0.9:
			fuel_warning = " [CRITICAL FUEL - %.0f needed]" % total_fuel_needed

		var profit_str := "$%s" % _format_number(int(adjusted_profit))

		# Create row container for destination + jettison buttons
		var dest_row := VBoxContainer.new()
		dest_row.add_theme_constant_override("separation", 4)

		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 64)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

		# Show distance and strategy
		var dist_text := ""
		if absf(dist_outbound - dist_return) < 0.01:
			dist_text = "%.2f AU%s" % [dist_outbound, strategy_label]
		else:
			dist_text = "%.2f AU out, %.2f AU%s" % [dist_outbound, dist_return, strategy_label]

		btn.text = "%s (%s)\n%s | %s | Est: %s%s%s" % [
			asteroid.asteroid_name, asteroid.get_type_name(),
			dist_text, _format_time(total_transit),
			"+" if adjusted_profit > 0 else "", profit_str, fuel_warning,
		]
		btn.pressed.connect(func() -> void:
			_confirm_asteroid_dispatch(asteroid)
		)
		dest_row.add_child(btn)

		# Add "Get Fuel" button if destination is unreachable
		if has_insufficient_fuel:
			var fuel_btn := _create_get_fuel_button()
			if fuel_btn:
				dest_row.add_child(fuel_btn)

		# ALWAYS show action buttons if ship has cargo
		if has_cargo:
			var jettison_row := HBoxContainer.new()
			jettison_row.add_theme_constant_override("separation", 8)

			var jettison_label := Label.new()
			jettison_label.text = "  Jettison cargo:"
			jettison_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
			jettison_row.add_child(jettison_label)

			# Smart jettison button (minimum needed)
			var smart_btn := Button.new()
			smart_btn.text = "Dump to Fit"
			smart_btn.custom_minimum_size = Vector2(0, 36)
			smart_btn.tooltip_text = "Jettison minimum cargo needed to make this trip"
			var capture_dist_out := dist_outbound
			var capture_dist_ret := dist_return
			smart_btn.pressed.connect(func() -> void:
				# Custom jettison for asymmetric trips
				var needed := _calculate_jettison_for_asymmetric_trip(capture_dist_out, capture_dist_ret)
				if needed > 0:
					var current := _selected_ship.get_cargo_total()
					var ratio := needed / current
					for ore_type in _selected_ship.current_cargo.keys():
						var amount: float = _selected_ship.current_cargo[ore_type]
						_selected_ship.current_cargo[ore_type] = amount * (1.0 - ratio)
					EventBus.cargo_jettisoned.emit(_selected_ship, needed)
				_show_asteroid_selection()  # Refresh the list
				print("Jettisoned %.1f tons to make trip viable" % needed)
			)
			jettison_row.add_child(smart_btn)

			# Dump all button
			var dump_all_btn := Button.new()
			dump_all_btn.text = "Dump All (%.0ft)" % current_cargo
			dump_all_btn.custom_minimum_size = Vector2(0, 36)
			dump_all_btn.tooltip_text = "Jettison all cargo (lost forever)"
			dump_all_btn.pressed.connect(func() -> void:
				GameState.jettison_all_cargo(_selected_ship)
				_show_asteroid_selection()  # Refresh the list
			)
			jettison_row.add_child(dump_all_btn)

			dest_row.add_child(jettison_row)

		list_vbox.add_child(dest_row)

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
				var profit_a := _calculate_adjusted_profit(a, est_workers)
				var profit_b := _calculate_adjusted_profit(b, est_workers)
				return profit_a > profit_b
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

func _calculate_adjusted_profit(asteroid: AsteroidData, est_workers: Array[Worker]) -> float:
	# Calculate profit based on current market strategy
	var asteroid_pos: Vector2 = asteroid.get_position_au()
	var dist_outbound := _selected_ship.position_au.distance_to(asteroid_pos)

	# Get base estimate for mining
	var est := AsteroidData.estimate_mission(asteroid, _selected_ship, est_workers)

	# Calculate based on market strategy
	var dist_return: float
	var revenue: float

	if _sell_at_destination_markets:
		# Find nearest colony to asteroid
		var nearest_colony: Colony = null
		var nearest_dist := 999999.0
		for colony in GameState.colonies:
			var d := asteroid_pos.distance_to(colony.get_position_au())
			if d < nearest_dist:
				nearest_dist = d
				nearest_colony = colony

		if nearest_colony:
			dist_return = nearest_dist

			# Calculate revenue at colony prices (with scarcity multiplier)
			revenue = 0.0
			var cargo_breakdown: Dictionary = est["cargo_breakdown"]
			for ore_type in cargo_breakdown:
				var tons: float = cargo_breakdown[ore_type]
				var colony_price := nearest_colony.get_ore_price(ore_type, GameState.market)
				revenue += tons * colony_price
		else:
			# Fallback: return to current position
			dist_return = dist_outbound
			revenue = est["revenue"]
	else:
		# Return with ore to current position
		dist_return = dist_outbound
		revenue = est["revenue"]

	# Calculate transit times
	var transit_out := Brachistochrone.transit_time(dist_outbound, _selected_ship.thrust_g)
	var transit_ret := Brachistochrone.transit_time(dist_return, _selected_ship.thrust_g)
	var total_transit := transit_out + transit_ret

	# Fuel calculation
	var current_cargo := _selected_ship.get_cargo_total()
	var fuel_outbound := _selected_ship.calc_fuel_for_distance(dist_outbound, current_cargo)
	var fuel_return := _selected_ship.calc_fuel_for_distance(dist_return, est["cargo_total"])
	var total_fuel_needed := fuel_outbound + fuel_return
	var custom_fuel_cost := total_fuel_needed * Ship.FUEL_COST_PER_UNIT

	# Wages for total mission time
	var total_time: float = total_transit + est["mining_time"]
	var payroll_cycles: float = total_time / 60.0
	var wage_per_tick := 0.0
	for w in est_workers:
		wage_per_tick += w.wage
	var custom_wage_cost := wage_per_tick * payroll_cycles

	# Final profit
	return revenue - custom_wage_cost - custom_fuel_cost

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
		var colony_pos: Vector2 = colony.get_position_au()
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
	dispatch_popup.visible = false
	_mark_dirty()

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

	# Transit mode selection buttons
	var mode_hbox := HBoxContainer.new()
	mode_hbox.name = "TransitModeButtons"
	mode_hbox.add_theme_constant_override("separation", 8)

	var brach_btn := Button.new()
	brach_btn.name = "BrachButton"
	brach_btn.text = "Fast (Brachistochrone)"
	brach_btn.custom_minimum_size = Vector2(0, 36)
	brach_btn.toggle_mode = true
	brach_btn.button_pressed = true
	brach_btn.pressed.connect(func() -> void:
		_selected_transit_mode = Mission.TransitMode.BRACHISTOCHRONE
		_update_estimate_display()
	)
	mode_hbox.add_child(brach_btn)

	var hohmann_btn := Button.new()
	hohmann_btn.name = "HohmannButton"
	hohmann_btn.text = "Economical (Hohmann)"
	hohmann_btn.custom_minimum_size = Vector2(0, 36)
	hohmann_btn.toggle_mode = true
	hohmann_btn.button_pressed = false
	hohmann_btn.pressed.connect(func() -> void:
		_selected_transit_mode = Mission.TransitMode.HOHMANN
		_update_estimate_display()
	)
	mode_hbox.add_child(hohmann_btn)

	est_vbox.add_child(mode_hbox)

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

	# Get estimate with current transit mode
	var est := AsteroidData.estimate_mission(
		_selected_asteroid, _selected_ship, _selected_workers, 30.0, Vector2(-999, -999), _selected_transit_mode
	)

	# Update transit mode button states
	var mode_hbox := est_panel.find_child("TransitModeButtons", true, false)
	if mode_hbox:
		var brach_btn: Button = mode_hbox.find_child("BrachButton", false, false)
		var hohmann_btn: Button = mode_hbox.find_child("HohmannButton", false, false)
		if brach_btn and hohmann_btn:
			brach_btn.button_pressed = (_selected_transit_mode == Mission.TransitMode.BRACHISTOCHRONE)
			hohmann_btn.button_pressed = (_selected_transit_mode == Mission.TransitMode.HOHMANN)
			# Disable Hohmann if not viable (insufficient fuel)
			hohmann_btn.disabled = not est.get("hohmann_available", false)
			if hohmann_btn.disabled and _selected_transit_mode == Mission.TransitMode.HOHMANN:
				# Auto-switch to brachistochrone if Hohmann becomes invalid
				_selected_transit_mode = Mission.TransitMode.BRACHISTOCHRONE
				brach_btn.button_pressed = true
				hohmann_btn.button_pressed = false
				# Recalculate
				est = AsteroidData.estimate_mission(
					_selected_asteroid, _selected_ship, _selected_workers, 30.0, Vector2(-999, -999), _selected_transit_mode
				)

	var mode_name := "HOHMANN (Fuel-Efficient)" if _selected_transit_mode == Mission.TransitMode.HOHMANN else "BRACHISTOCHRONE (Fast)"

	var lines: Array[String] = []
	lines.append("Mode: %s" % mode_name)
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
	# Auto-assign crew if not enough selected
	if _selected_workers.size() < _selected_ship.min_crew:
		var available := GameState.get_available_workers()
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
		return

	# Get mission estimate for confirmation
	var est := AsteroidData.estimate_mission(
		_selected_asteroid, _selected_ship, _selected_workers, 30.0, Vector2(-999, -999), _selected_transit_mode
	)

	var dist := _selected_ship.position_au.distance_to(_selected_asteroid.get_position_au())
	var mode_name := "Hohmann" if _selected_transit_mode == Mission.TransitMode.HOHMANN else "Brachistochrone"
	var profit_sign := "+" if est["profit"] >= 0 else ""

	var crew_names := ""
	for i in range(_selected_workers.size()):
		if i > 0:
			crew_names += ", "
		crew_names += _selected_workers[i].worker_name

	var confirm_text := "Dispatch to %s?\n\nMode: %s\nDistance: %.2f AU\nTransit: %s each way\nMining: %s\nCrew: %s\nEstimated Profit: %s$%s" % [
		_selected_asteroid.asteroid_name, mode_name, dist,
		_format_time(est["transit_time"]), _format_time(est["mining_time"]),
		crew_names, profit_sign, _format_number(int(abs(est["profit"])))
	]

	# Show confirmation before executing
	_show_dispatch_confirmation(confirm_text)

func _show_dispatch_confirmation(message: String) -> void:
	# Clear and show confirmation
	_clear_dispatch_content()

	var title := Label.new()
	title.text = "Confirm Mission Dispatch"
	title.add_theme_font_size_override("font_size", 20)
	dispatch_content.add_child(title)

	var msg_label := Label.new()
	msg_label.text = message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.custom_minimum_size = Vector2(400, 0)
	dispatch_content.add_child(msg_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)

	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm Dispatch"
	confirm_btn.custom_minimum_size = Vector2(0, 44)
	confirm_btn.pressed.connect(func() -> void:
		_execute_dispatch()
	)
	btn_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 44)
	cancel_btn.pressed.connect(func() -> void:
		_show_worker_selection()  # Go back to worker selection
	)
	btn_row.add_child(cancel_btn)

	dispatch_content.add_child(btn_row)

	dispatch_popup.visible = true

func _execute_dispatch() -> void:
	# Actually execute the dispatch after confirmation
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
		GameState.dispatch_idle_ship(_selected_ship, _selected_asteroid, _selected_workers, _selected_transit_mode)
	else:
		GameState.start_mission(_selected_ship, _selected_asteroid, _selected_workers, _selected_transit_mode)
	dispatch_popup.visible = false
	_mark_dirty()

func _build_details_text(ship: Ship) -> String:
	var engine_str := ""
	if ship.engine_condition < 100.0:
		engine_str = "  |  Eng: %d%%" % int(ship.engine_condition)
	return "Thrust: %.1fg  |  Cargo: %.0f/%.0ft  |  Fuel: %.0f/%.0f  |  Equip: %d/%d (%.2fx)%s" % [
		ship.thrust_g, ship.get_cargo_total(), ship.get_effective_cargo_capacity(),
		ship.fuel, ship.get_effective_fuel_capacity(),
		ship.equipment.size(), ship.max_equipment_slots, ship.get_mining_multiplier(),
		engine_str,
	]

func _calculate_jettison_for_asymmetric_trip(dist_outbound: float, dist_return: float) -> float:
	# Calculate minimum cargo to jettison for asymmetric trip
	var current_cargo := _selected_ship.get_cargo_total()

	# Binary search for minimum jettison
	var low := 0.0
	var high := current_cargo
	var needed_jettison := current_cargo

	for _i in range(10):
		var mid := (low + high) / 2.0
		var remaining_cargo := current_cargo - mid

		# Fuel needed: outbound with current cargo, return fully loaded
		var fuel_out := _selected_ship.calc_fuel_for_distance(dist_outbound, remaining_cargo)
		var fuel_ret := _selected_ship.calc_fuel_for_distance(dist_return, _selected_ship.cargo_capacity)
		var total_fuel := fuel_out + fuel_ret

		if total_fuel <= _selected_ship.fuel:
			needed_jettison = mid
			high = mid
		else:
			low = mid

	return needed_jettison

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
	# Show confirmation dialog before dispatching
	var colony_pos: Vector2 = colony.get_position_au()
	var dist := _selected_ship.position_au.distance_to(colony_pos)
	var transit := Brachistochrone.transit_time(dist, _selected_ship.thrust_g)

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

func _confirm_asteroid_dispatch(asteroid: AsteroidData) -> void:
	# Show confirmation dialog before dispatching to asteroid
	_selected_asteroid = asteroid
	_show_worker_selection()

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

func _show_confirmation_dialog(message: String, on_confirm: Callable) -> void:
	# Clear dispatch content and show confirmation
	_clear_dispatch_content()

	var title := Label.new()
	title.text = "Confirm Dispatch"
	title.add_theme_font_size_override("font_size", 20)
	dispatch_content.add_child(title)

	var msg_label := Label.new()
	msg_label.text = message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.custom_minimum_size = Vector2(400, 0)
	dispatch_content.add_child(msg_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)

	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm"
	confirm_btn.custom_minimum_size = Vector2(0, 44)
	confirm_btn.pressed.connect(func() -> void:
		on_confirm.call()
	)
	btn_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 44)
	cancel_btn.pressed.connect(func() -> void:
		_show_asteroid_selection()  # Go back to selection
	)
	btn_row.add_child(cancel_btn)

	dispatch_content.add_child(btn_row)

	dispatch_popup.visible = true

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
	var info := Label.new()
	var ore_name := ResourceTypes.get_ore_name(contract.ore_type)
	var ship_has: float = ship.current_cargo.get(contract.ore_type, 0.0)
	var remaining := contract.get_remaining_quantity()
	var can_deliver := minf(ship_has, remaining)
	var contract_price_per_ton := float(contract.reward) / contract.quantity
	var spot_price := colony.get_ore_price(contract.ore_type, GameState.market)

	var price_comparison := ""
	if contract_price_per_ton > spot_price:
		var premium := ((contract_price_per_ton / spot_price) - 1.0) * 100.0
		price_comparison = " (+%.0f%% vs spot)" % premium
	else:
		var discount := (1.0 - (contract_price_per_ton / spot_price)) * 100.0
		price_comparison = " (-%.0f%% vs spot)" % discount

	info.text = "%s: %s %.1ft/%.1ft - $%.0f/t%s - %.0f ticks\nYou have: %.1ft | Can deliver: %.1ft" % [
		contract.issuer_name, ore_name, contract.quantity_delivered, contract.quantity,
		contract_price_per_ton, price_comparison, contract.deadline_ticks,
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
	var spot_label := Label.new()
	spot_label.text = "Spot: $%s" % _format_number(spot_value)
	if payment > spot_value:
		spot_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	else:
		spot_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
	btn_row.add_child(spot_label)

	vbox.add_child(btn_row)
	panel.add_child(vbox)
	container.add_child(panel)
