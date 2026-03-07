extends VBoxContainer

## Destination Selector Component
## Choose mining asteroid or trading colony destination
## Extracted from fleet_market_tab.gd _show_asteroid_selection() (758 lines) + helpers

signal asteroid_selected(asteroid: AsteroidData)
signal colony_selected(colony: Colony)
signal salvage_target_selected(target: SalvageTarget)
signal selection_cancelled()

# Ship context (set by parent)
var _selected_ship: Ship = null
var _is_planning_mode: bool = false
var _is_redirect_mode: bool = false

# Selection state
var _selected_asteroid: AsteroidData = null
var _selected_colony: Colony = null

# Sorting/filtering
var _sort_by: String = "profit"  # profit, distance, name
var _filter_type: int = -1  # -1 = all, else AsteroidData.BodyType
var _market_sort_by: String = "profit"  # profit, name
var _market_search: String = ""
var _mining_search: String = ""
var _sell_at_destination_markets: bool = false  # Market strategy toggle

# Destination lists
var _colony_dest_buttons: Dictionary = {}  # Colony -> {dist, time, revenue, warning, btn}
var _mining_dest_buttons: Dictionary = {}  # AsteroidData -> {dist, time, profit, warning, btn}
var _colony_dest_data: Array = []
var _mining_dest_data: Array = []

# Section expansion
var _colonies_section_expanded: int = -1  # -1 = auto, 0 = collapsed, 1 = expanded
var _mining_section_expanded: int = -1

# Scroll preservation
var _saved_colonies_scroll: float = 0.0
var _saved_mining_scroll: float = 0.0

# UI references
var _mining_scroll: ScrollContainer = null
var _colonies_scroll: ScrollContainer = null
var _mining_header_label: Label = null
var _colonies_header_label: Label = null
var _mining_controls: HFlowContainer = null

# Content container
@onready var content_container: VBoxContainer = %ContentContainer

## Show destination selection UI
func show_selection(ship: Ship, planning_mode: bool = false, redirect_mode: bool = false) -> void:
	_selected_ship = ship
	_is_planning_mode = planning_mode
	_is_redirect_mode = redirect_mode

	# Save scroll positions before clearing
	for child in content_container.get_children():
		if child is ScrollContainer:
			if child.name == "ColoniesScroll":
				_saved_colonies_scroll = child.scroll_vertical
			elif child.name == "MiningScroll":
				_saved_mining_scroll = child.scroll_vertical

	_free_children(content_container)
	_colony_dest_buttons.clear()
	_colony_dest_data.clear()
	_mining_dest_buttons.clear()
	_mining_dest_data.clear()

	var title := _lbl()
	if _is_planning_mode:
		title.text = "Plan Next Mission — Select Destination"
	elif _is_redirect_mode:
		title.text = "Redirect — Select Destination"
	else:
		title.text = "Select Destination"
	title.add_theme_font_size_override("font_size", 26)
	content_container.add_child(title)

	# Show ship origin and cargo
	var origin_label := _lbl()
	var ore_total: float = _selected_ship.get_ore_total()
	var origin_prefix := "Current position:" if _is_redirect_mode else "Dispatching from:"
	if ore_total > 0:
		origin_label.text = "%s %s (%.1ft ore)" % [origin_prefix, _get_location_text(_selected_ship), ore_total]
	else:
		origin_label.text = "%s %s" % [origin_prefix, _get_location_text(_selected_ship)]
	origin_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	origin_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_container.add_child(origin_label)

	# Determine layout priority
	var has_cargo_for_selling := ore_total > 0
	var colonies_expanded: bool
	var mining_expanded: bool
	if _colonies_section_expanded >= 0:
		colonies_expanded = _colonies_section_expanded == 1
	else:
		colonies_expanded = has_cargo_for_selling
	if _mining_section_expanded >= 0:
		mining_expanded = _mining_section_expanded == 1
	else:
		mining_expanded = not has_cargo_for_selling

	# === FLEET SHIPS NEEDING HELP ===
	_build_fleet_rescue_section()

	# === SALVAGE TARGETS ===
	_build_salvage_section()

	# === MARKET DESTINATIONS SECTION ===
	_build_market_section(colonies_expanded, ore_total)

	var sep0 := HSeparator.new()
	content_container.add_child(sep0)

	# === MINING DESTINATIONS SECTION ===
	_build_mining_section(mining_expanded)

## Build fleet rescue section
func _build_fleet_rescue_section() -> void:
	var derelict_fleet_ships: Array[Ship] = []
	for s in GameState.ships:
		if s != _selected_ship and s.is_derelict and not s.is_stationed:
			derelict_fleet_ships.append(s)

	if derelict_fleet_ships.is_empty():
		return

	var fleet_header := _lbl()
	fleet_header.text = "FLEET SHIPS NEEDING HELP"
	fleet_header.add_theme_font_size_override("font_size", 23)
	fleet_header.add_theme_color_override("font_color", Color(0.9, 0.4, 0.2))
	content_container.add_child(fleet_header)

	for derelict in derelict_fleet_ships:
		var dist_d := _selected_ship.position_au.distance_to(derelict.position_au)
		var transit_d := Brachistochrone.transit_time(dist_d, _selected_ship.get_effective_thrust())
		var fuel_needed_d := _selected_ship.calc_fuel_for_distance(dist_d) * 2.0
		var feasible_d := fuel_needed_d <= _selected_ship.fuel

		var rescue_btn := Button.new()
		var reason := "(out of fuel)" if derelict.derelict_reason == "out_of_fuel" else "(breakdown)"
		rescue_btn.text = "%s %s — %s, fuel: %.0ft/%.0ft" % [
			derelict.ship_name, reason,
			TimeScale.format_time(transit_d),
			fuel_needed_d, _selected_ship.fuel
		]
		rescue_btn.custom_minimum_size = Vector2(0, 44)
		rescue_btn.disabled = not feasible_d
		if not feasible_d:
			rescue_btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		else:
			rescue_btn.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
		rescue_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rescue_btn.pressed.connect(func() -> void:
			# TODO: Emit fleet_rescue_requested signal instead
			pass
		)
		content_container.add_child(rescue_btn)

	var sep := HSeparator.new()
	content_container.add_child(sep)

## Build salvage targets section
func _build_salvage_section() -> void:
	if GameState.salvage_targets.is_empty():
		return

	var header := _lbl()
	header.text = "SALVAGE TARGETS"
	header.add_theme_font_size_override("font_size", 23)
	header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	content_container.add_child(header)

	for target: SalvageTarget in GameState.salvage_targets:
		_add_salvage_button(target)

	content_container.add_child(HSeparator.new())

## Add single salvage target button
func _add_salvage_button(target: SalvageTarget) -> void:
	var dist := _selected_ship.position_au.distance_to(target.position_au)
	var transit := Brachistochrone.transit_time(dist, _selected_ship.get_effective_thrust())
	var fuel_needed := _selected_ship.calc_fuel_for_distance(dist, _selected_ship.get_cargo_total()) * 2.0
	var feasible := fuel_needed <= _selected_ship.fuel
	var days_remaining := (target.expires_at_ticks - GameState.total_ticks) / 86400.0

	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 4)

	var name_label := _lbl()
	name_label.text = target.target_name
	name_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	row.add_child(name_label)

	var data_row := HBoxContainer.new()
	data_row.add_theme_constant_override("separation", 8)

	var time_label := _lbl()
	time_label.text = TimeScale.format_time(transit)
	time_label.custom_minimum_size = Vector2(100, 0)
	time_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	data_row.add_child(time_label)

	var value_label := _lbl()
	value_label.text = "$%s scrap" % _format_number(target.scrap_credits)
	value_label.custom_minimum_size = Vector2(120, 0)
	value_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	data_row.add_child(value_label)

	var expire_label := _lbl()
	expire_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	expire_label.add_theme_font_size_override("font_size", 16)
	expire_label.text = "%.1fd left" % maxf(days_remaining, 0.0)
	if days_remaining < 5.0:
		expire_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))
	else:
		expire_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	data_row.add_child(expire_label)

	row.add_child(data_row)

	if not target.salvage_equipment.is_empty():
		var equip_names: Array[String] = []
		for e: Equipment in target.salvage_equipment:
			equip_names.append("%s (%.0f%%)" % [e.equipment_name, e.durability])
		var equip_label := _lbl()
		equip_label.add_theme_font_size_override("font_size", 16)
		equip_label.text = "Equipment: %s" % ", ".join(equip_names)
		equip_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
		equip_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(equip_label)

	var btn := Button.new()
	btn.text = "Dispatch Salvage"
	btn.custom_minimum_size = Vector2(0, 36)
	btn.focus_mode = Control.FOCUS_NONE
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.disabled = not feasible
	if not feasible:
		btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
	btn.pressed.connect(func() -> void:
		salvage_target_selected.emit(target)
	)
	row.add_child(btn)

	content_container.add_child(row)
	content_container.add_child(HSeparator.new())

## Build market destinations section
func _build_market_section(expanded: bool, ore_total: float) -> void:
	var colonies_header := _lbl()
	_colonies_header_label = colonies_header
	colonies_header.text = "MARKET DESTINATIONS %s" % ("▾" if expanded else "▸")
	colonies_header.add_theme_font_size_override("font_size", 23)
	colonies_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
	colonies_header.mouse_filter = Control.MOUSE_FILTER_STOP
	colonies_header.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle_colonies_section()
	)
	content_container.add_child(colonies_header)

	# Market controls (search + sort)
	var market_controls := HFlowContainer.new()
	market_controls.visible = expanded
	market_controls.add_theme_constant_override("h_separation", 8)

	var market_sort_btn := OptionButton.new()
	market_sort_btn.add_item("Best Profit")
	market_sort_btn.add_item("Name A-Z")
	market_sort_btn.custom_minimum_size = Vector2(0, 44)
	market_sort_btn.focus_mode = Control.FOCUS_NONE
	market_sort_btn.item_selected.connect(func(idx: int) -> void:
		_market_sort_by = ["profit", "name"][idx]
		show_selection(_selected_ship, _is_planning_mode, _is_redirect_mode)
	)
	market_sort_btn.selected = 0 if _market_sort_by == "profit" else 1
	market_controls.add_child(market_sort_btn)

	var market_search_field := LineEdit.new()
	market_search_field.placeholder_text = "Search markets..."
	market_search_field.custom_minimum_size = Vector2(200, 44)
	market_search_field.focus_mode = Control.FOCUS_CLICK
	market_search_field.text = _market_search
	market_search_field.text_changed.connect(func(new_text: String) -> void:
		_market_search = new_text.strip_edges()
		show_selection(_selected_ship, _is_planning_mode, _is_redirect_mode)
	)
	market_controls.add_child(market_search_field)

	content_container.add_child(market_controls)

	var colonies_scroll := ScrollContainer.new()
	_colonies_scroll = colonies_scroll
	colonies_scroll.name = "ColoniesScroll"
	colonies_scroll.size_flags_vertical = Control.SIZE_FILL
	colonies_scroll.custom_minimum_size = Vector2(0, 400 if expanded else 0)
	colonies_scroll.visible = expanded
	colonies_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var colonies_vbox := VBoxContainer.new()
	colonies_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	colonies_vbox.add_theme_constant_override("separation", 6)

	# Filter and sort colonies
	var filtered_colonies: Array[Colony] = []
	var search_lower := _market_search.to_lower()
	for colony in GameState.colonies:
		if _market_search != "" and not colony.colony_name.to_lower().contains(search_lower):
			continue
		filtered_colonies.append(colony)

	# Sort by profit or name
	match _market_sort_by:
		"profit":
			filtered_colonies.sort_custom(func(a: Colony, b: Colony) -> bool:
				var profit_a := _calculate_colony_profit(a)
				var profit_b := _calculate_colony_profit(b)
				return profit_a > profit_b
			)
		"name":
			filtered_colonies.sort_custom(func(a: Colony, b: Colony) -> bool:
				return a.colony_name.naturalcasecmp_to(b.colony_name) < 0
			)

	# Filter out current location (within 0.1 AU)
	const PROXIMITY_THRESHOLD := 0.1
	var final_colonies: Array[Colony] = []
	for colony in filtered_colonies:
		var dist_to_colony := _selected_ship.position_au.distance_to(colony.get_position_au())
		if dist_to_colony > PROXIMITY_THRESHOLD:
			final_colonies.append(colony)

	for colony in final_colonies:
		_add_colony_button(colonies_vbox, colony)

	colonies_scroll.add_child(colonies_vbox)
	content_container.add_child(colonies_scroll)

	# Restore scroll position
	if _saved_colonies_scroll > 0:
		var saved_pos := _saved_colonies_scroll
		colonies_scroll.call_deferred("set", "scroll_vertical", int(saved_pos))

## Add single colony button
func _add_colony_button(container: VBoxContainer, colony: Colony) -> void:
	var colony_pos: Vector2 = colony.get_position_au()
	var dist := _selected_ship.position_au.distance_to(colony_pos)
	var transit := Brachistochrone.transit_time(dist, _selected_ship.get_effective_thrust())

	var cargo_mass := _selected_ship.get_cargo_total()
	var fuel_outbound := _selected_ship.calc_fuel_for_distance(dist, cargo_mass)
	var fuel_return := _selected_ship.calc_fuel_for_distance(dist, 0.0)
	var fuel_needed := fuel_outbound + fuel_return

	var revenue := 0
	var earth_revenue := 0
	var cargo_breakdown := ""
	for ore_type in _selected_ship.current_cargo:
		var amount: float = _selected_ship.current_cargo[ore_type]
		if amount <= 0.0:
			continue
		var colony_price: float = colony.get_ore_price(ore_type, GameState.market)
		var earth_price: float = GameState.market.get_price(ore_type, "Earth")
		revenue += int(amount * colony_price)
		earth_revenue += int(amount * earth_price)
		var diff_pct := ((colony_price - earth_price) / earth_price) * 100.0 if earth_price > 0.0 else 0.0
		var diff_str := (" (%+.0f%%)" % diff_pct) if absf(diff_pct) >= 0.5 else ""
		if cargo_breakdown != "":
			cargo_breakdown += "  "
		cargo_breakdown += "%s $%d/t%s" % [ResourceTypes.get_ore_name(ore_type), int(colony_price), diff_str]

	var fuel_status := ""
	var available_fuel := _selected_ship.get_effective_fuel_capacity() if _selected_ship.is_idle_remote else _selected_ship.fuel
	var has_insufficient_fuel := fuel_needed > available_fuel

	var colony_row := VBoxContainer.new()
	colony_row.add_theme_constant_override("separation", 4)

	var name_label := _lbl()
	name_label.text = "%s (MARKET)" % colony.colony_name
	name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
	colony_row.add_child(name_label)

	var data_row := HBoxContainer.new()
	data_row.add_theme_constant_override("separation", 8)

	var col_dist_label := _lbl()
	col_dist_label.custom_minimum_size = Vector2(120, 0)
	col_dist_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	var col_dv := Brachistochrone.delta_v_km_s(dist, _selected_ship.get_effective_thrust())
	col_dist_label.text = "%.0f km/s Δv" % col_dv
	data_row.add_child(col_dist_label)

	var col_time_label := _lbl()
	col_time_label.custom_minimum_size = Vector2(100, 0)
	col_time_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	col_time_label.text = TimeScale.format_time(transit)
	data_row.add_child(col_time_label)

	var col_revenue_label := _lbl()
	col_revenue_label.custom_minimum_size = Vector2(120, 0)
	col_revenue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	col_revenue_label.text = "$%s" % _format_number(revenue)
	col_revenue_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	data_row.add_child(col_revenue_label)

	var col_warning_label := _lbl()
	col_warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col_warning_label.add_theme_font_size_override("font_size", 16)
	if has_insufficient_fuel:
		fuel_status = " [NEEDS REFUEL]"
	elif fuel_needed > available_fuel * 0.9:
		fuel_status = " [CRITICAL]"
	col_warning_label.text = fuel_status
	if "CRITICAL" in fuel_status:
		col_warning_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	elif fuel_status != "":
		col_warning_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
	data_row.add_child(col_warning_label)

	colony_row.add_child(data_row)

	if cargo_breakdown != "":
		var cargo_label := _lbl()
		cargo_label.text = cargo_breakdown
		cargo_label.add_theme_font_size_override("font_size", 16)
		cargo_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5))
		cargo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		colony_row.add_child(cargo_label)

		var vs_earth := revenue - earth_revenue
		if vs_earth != 0:
			var vs_label := _lbl()
			vs_label.add_theme_font_size_override("font_size", 16)
			var sign := "+" if vs_earth >= 0 else ""
			vs_label.text = "vs Earth: %s$%s" % [sign, _format_number(vs_earth)]
			if vs_earth > 0:
				vs_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
			else:
				vs_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))
			colony_row.add_child(vs_label)

	var btn := Button.new()
	btn.text = "Sell Here"
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.custom_minimum_size = Vector2(0, 36)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void:
		_select_colony_trade(colony)
	)
	colony_row.add_child(btn)

	_colony_dest_buttons[colony] = {
		"dist": col_dist_label, "time": col_time_label,
		"revenue": col_revenue_label, "warning": col_warning_label,
		"btn": btn,
	}
	_colony_dest_data.append(colony)
	container.add_child(colony_row)
	container.add_child(HSeparator.new())

## Build mining destinations section
func _build_mining_section(expanded: bool) -> void:
	var mining_header := _lbl()
	_mining_header_label = mining_header
	mining_header.text = "MINING DESTINATIONS %s" % ("▾" if expanded else "▸")
	mining_header.add_theme_font_size_override("font_size", 23)
	mining_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	mining_header.mouse_filter = Control.MOUSE_FILTER_STOP
	mining_header.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle_mining_section()
	)
	content_container.add_child(mining_header)

	# Fixed filter/sort controls
	var controls := HFlowContainer.new()
	_mining_controls = controls
	controls.visible = expanded
	controls.add_theme_constant_override("h_separation", 8)

	var sort_btn := OptionButton.new()
	sort_btn.add_item("Best Profit")
	sort_btn.add_item("Nearest")
	sort_btn.add_item("Name A-Z")
	sort_btn.custom_minimum_size = Vector2(0, 44)
	sort_btn.focus_mode = Control.FOCUS_NONE
	sort_btn.item_selected.connect(func(idx: int) -> void:
		_sort_by = ["profit", "distance", "name"][idx]
		show_selection(_selected_ship, _is_planning_mode, _is_redirect_mode)
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
	filter_btn.focus_mode = Control.FOCUS_NONE
	filter_btn.selected = 0 if _filter_type == -1 else _filter_type + 1
	filter_btn.item_selected.connect(func(idx: int) -> void:
		_filter_type = idx - 1
		show_selection(_selected_ship, _is_planning_mode, _is_redirect_mode)
	)
	controls.add_child(filter_btn)

	var market_toggle := Button.new()
	market_toggle.toggle_mode = true
	market_toggle.button_pressed = _sell_at_destination_markets
	market_toggle.text = "Local Market" if _sell_at_destination_markets else "Return w/ Ore"
	market_toggle.custom_minimum_size = Vector2(0, 44)
	market_toggle.tooltip_text = "Toggle: Return with ore vs sell at markets near destination"
	market_toggle.focus_mode = Control.FOCUS_NONE
	market_toggle.toggled.connect(func(pressed: bool) -> void:
		_sell_at_destination_markets = pressed
		market_toggle.text = "Local Market" if pressed else "Return w/ Ore"
		show_selection(_selected_ship, _is_planning_mode, _is_redirect_mode)
	)
	controls.add_child(market_toggle)

	var mining_search_field := LineEdit.new()
	mining_search_field.placeholder_text = "Search asteroids..."
	mining_search_field.custom_minimum_size = Vector2(200, 44)
	mining_search_field.focus_mode = Control.FOCUS_CLICK
	mining_search_field.text = _mining_search
	mining_search_field.text_changed.connect(func(new_text: String) -> void:
		_mining_search = new_text.strip_edges()
		show_selection(_selected_ship, _is_planning_mode, _is_redirect_mode)
	)
	controls.add_child(mining_search_field)

	content_container.add_child(controls)

	var mining_scroll := ScrollContainer.new()
	_mining_scroll = mining_scroll
	mining_scroll.name = "MiningScroll"
	mining_scroll.size_flags_vertical = Control.SIZE_FILL
	mining_scroll.custom_minimum_size = Vector2(0, 400 if expanded else 0)
	mining_scroll.visible = expanded
	mining_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var mining_vbox := VBoxContainer.new()
	mining_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mining_vbox.add_theme_constant_override("separation", 6)

	var est_workers := WorkerManager.get_available_workers()
	if est_workers.is_empty():
		var placeholder := Worker.new()
		placeholder.mining_skill = 1.0
		placeholder.wage = 100
		est_workers = [placeholder]

	var asteroids := _get_sorted_asteroids(est_workers)

	for asteroid in asteroids:
		_add_asteroid_button(mining_vbox, asteroid, est_workers)

	mining_scroll.add_child(mining_vbox)
	content_container.add_child(mining_scroll)

	# Restore scroll position
	if _saved_mining_scroll > 0:
		var saved_pos := _saved_mining_scroll
		mining_scroll.call_deferred("set", "scroll_vertical", int(saved_pos))

## Add single asteroid button
func _add_asteroid_button(container: VBoxContainer, asteroid: AsteroidData, est_workers: Array[Worker]) -> void:
	var asteroid_pos: Vector2 = asteroid.get_position_au()
	var dist_outbound := _selected_ship.position_au.distance_to(asteroid_pos)

	var est := AsteroidData.estimate_mission(
		asteroid, _selected_ship, est_workers, -1.0, Vector2(-999, -999), Mission.TransitMode.BRACHISTOCHRONE
	)

	var dist_return: float
	var revenue: float
	if _sell_at_destination_markets:
		var nearest_colony: Colony = null
		var nearest_dist := 999999.0
		for colony in GameState.colonies:
			var d := asteroid_pos.distance_to(colony.get_position_au())
			if d < nearest_dist:
				nearest_dist = d
				nearest_colony = colony
		if nearest_colony:
			dist_return = nearest_dist
			revenue = 0.0
			var cargo_breakdown: Dictionary = est["cargo_breakdown"]
			for ore_type in cargo_breakdown:
				var tons: float = cargo_breakdown[ore_type]
				revenue += tons * nearest_colony.get_ore_price(ore_type, GameState.market)
		else:
			dist_return = dist_outbound
			revenue = est["revenue"]
	else:
		dist_return = dist_outbound
		revenue = est["revenue"]

	var total_transit: float
	var adjusted_profit: float
	var current_cargo := _selected_ship.get_cargo_total()

	if absf(dist_outbound - dist_return) < 0.01 and not _sell_at_destination_markets:
		adjusted_profit = est["profit"]
		var transit_one_way := Brachistochrone.transit_time(dist_outbound, _selected_ship.get_effective_thrust())
		total_transit = transit_one_way * 2.0
	else:
		var transit_out := Brachistochrone.transit_time(dist_outbound, _selected_ship.get_effective_thrust())
		var transit_ret := Brachistochrone.transit_time(dist_return, _selected_ship.get_effective_thrust())
		total_transit = transit_out + transit_ret
		var fuel_out := _selected_ship.calc_fuel_for_distance(dist_outbound, current_cargo)
		var fuel_ret := _selected_ship.calc_fuel_for_distance(dist_return, est["cargo_total"])
		var custom_fuel_cost := (fuel_out + fuel_ret) * Ship.FUEL_COST_PER_UNIT
		var total_time: float = total_transit + est["mining_time"]
		var payroll_cycles: float = total_time / Simulation.PAYROLL_INTERVAL
		var wage_per_tick := 0.0
		for w in est_workers:
			wage_per_tick += w.wage
		adjusted_profit = revenue - wage_per_tick * payroll_cycles - custom_fuel_cost

	var dest_row := VBoxContainer.new()
	dest_row.add_theme_constant_override("separation", 4)

	var name_label := _lbl()
	name_label.text = "%s (%s)" % [asteroid.asteroid_name, asteroid.get_type_name()]
	dest_row.add_child(name_label)

	var data_row := HBoxContainer.new()
	data_row.add_theme_constant_override("separation", 8)

	var dist_label := _lbl()
	dist_label.custom_minimum_size = Vector2(220, 0)
	dist_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	data_row.add_child(dist_label)

	var time_label := _lbl()
	time_label.custom_minimum_size = Vector2(100, 0)
	time_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	data_row.add_child(time_label)

	var profit_label := _lbl()
	profit_label.custom_minimum_size = Vector2(120, 0)
	profit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	data_row.add_child(profit_label)

	var warning_label := _lbl()
	warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	warning_label.add_theme_font_size_override("font_size", 16)
	data_row.add_child(warning_label)

	dest_row.add_child(data_row)

	var thrust := _selected_ship.get_effective_thrust()
	var dv_out := Brachistochrone.delta_v_km_s(dist_outbound, thrust)
	var dv_ret := Brachistochrone.delta_v_km_s(dist_return, thrust)
	dist_label.text = "%.0f out %.0f ret Δv" % [dv_out, dv_ret]
	time_label.text = TimeScale.format_time(total_transit)
	var profit_str := "$%s" % _format_number(int(adjusted_profit))
	profit_label.text = "%s%s" % ["+" if adjusted_profit > 0 else "", profit_str]
	if adjusted_profit >= 0:
		profit_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	else:
		profit_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))

	var btn := Button.new()
	btn.text = "Select" if (_is_planning_mode or _is_redirect_mode) else "Dispatch"
	btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	btn.custom_minimum_size = Vector2(0, 36)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(func() -> void:
		_select_asteroid(asteroid)
	)
	dest_row.add_child(btn)

	_mining_dest_buttons[asteroid] = {
		"dist": dist_label, "time": time_label,
		"profit": profit_label, "warning": warning_label,
		"btn": btn,
	}
	_mining_dest_data.append(asteroid)
	container.add_child(dest_row)
	container.add_child(HSeparator.new())

## Toggle colonies section
func _toggle_colonies_section() -> void:
	if not is_instance_valid(_colonies_scroll):
		return
	var expanding := not _colonies_scroll.visible
	_colonies_section_expanded = 1 if expanding else 0
	_colonies_scroll.visible = expanding
	_colonies_scroll.custom_minimum_size = Vector2(0, 400 if expanding else 0)
	if is_instance_valid(_colonies_header_label):
		var base_text := _colonies_header_label.text.split(" ▾")[0].split(" ▸")[0]
		_colonies_header_label.text = "%s %s" % [base_text, "▾" if expanding else "▸"]

## Toggle mining section
func _toggle_mining_section() -> void:
	if not is_instance_valid(_mining_scroll):
		return
	var expanding := not _mining_scroll.visible
	_mining_section_expanded = 1 if expanding else 0
	_mining_scroll.visible = expanding
	_mining_scroll.custom_minimum_size = Vector2(0, 400 if expanding else 0)
	if is_instance_valid(_mining_controls):
		_mining_controls.visible = expanding
	if is_instance_valid(_mining_header_label):
		var base_text := _mining_header_label.text.split(" ▾")[0].split(" ▸")[0]
		_mining_header_label.text = "%s %s" % [base_text, "▾" if expanding else "▸"]

## Get sorted asteroids by profit/distance/name
func _get_sorted_asteroids(est_workers: Array[Worker]) -> Array[AsteroidData]:
	var filtered: Array[AsteroidData] = []
	var search_lower := _mining_search.to_lower()
	for a in GameState.asteroids:
		if _filter_type >= 0 and a.body_type != _filter_type:
			continue
		if _mining_search != "" and not a.asteroid_name.to_lower().contains(search_lower):
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

## Calculate adjusted profit for an asteroid
func _calculate_adjusted_profit(asteroid: AsteroidData, est_workers: Array[Worker]) -> float:
	var asteroid_pos: Vector2 = asteroid.get_position_au()
	var dist_outbound := _selected_ship.position_au.distance_to(asteroid_pos)

	var est := AsteroidData.estimate_mission(
		asteroid, _selected_ship, est_workers, -1.0, Vector2(-999, -999), Mission.TransitMode.BRACHISTOCHRONE
	)

	var dist_return: float
	var revenue: float

	if _sell_at_destination_markets:
		var nearest_colony: Colony = null
		var nearest_dist := 999999.0
		for colony in GameState.colonies:
			var d := asteroid_pos.distance_to(colony.get_position_au())
			if d < nearest_dist:
				nearest_dist = d
				nearest_colony = colony
		if nearest_colony:
			dist_return = nearest_dist
			revenue = 0.0
			var cargo_breakdown: Dictionary = est["cargo_breakdown"]
			for ore_type in cargo_breakdown:
				var tons: float = cargo_breakdown[ore_type]
				revenue += tons * nearest_colony.get_ore_price(ore_type, GameState.market)
		else:
			dist_return = dist_outbound
			revenue = est["revenue"]
	else:
		dist_return = dist_outbound
		revenue = est["revenue"]

	if absf(dist_outbound - dist_return) < 0.01 and not _sell_at_destination_markets:
		return est["profit"]

	var transit_out := Brachistochrone.transit_time(dist_outbound, _selected_ship.get_effective_thrust())
	var transit_ret := Brachistochrone.transit_time(dist_return, _selected_ship.get_effective_thrust())
	var total_transit := transit_out + transit_ret

	var current_cargo := _selected_ship.get_cargo_total()
	var fuel_outbound := _selected_ship.calc_fuel_for_distance(dist_outbound, current_cargo)
	var fuel_return := _selected_ship.calc_fuel_for_distance(dist_return, est["cargo_total"])
	var custom_fuel_cost := (fuel_outbound + fuel_return) * Ship.FUEL_COST_PER_UNIT

	var total_time: float = total_transit + est["mining_time"]
	var payroll_cycles: float = total_time / Simulation.PAYROLL_INTERVAL
	var wage_per_tick := 0.0
	for w in est_workers:
		wage_per_tick += w.wage
	var custom_wage_cost := wage_per_tick * payroll_cycles

	return revenue - custom_wage_cost - custom_fuel_cost

## Get ore summary for asteroid
func _get_ore_summary(asteroid: AsteroidData) -> String:
	var parts: Array[String] = []
	for ore_type in asteroid.ore_yields:
		parts.append(ResourceTypes.get_ore_name(ore_type))
	return ", ".join(parts)

## Select an asteroid
func _select_asteroid(asteroid: AsteroidData) -> void:
	_selected_asteroid = asteroid
	asteroid_selected.emit(asteroid)

## Select a colony for trading
func _select_colony_trade(colony: Colony) -> void:
	_selected_colony = colony
	colony_selected.emit(colony)

## Calculate colony profit
func _calculate_colony_profit(colony: Colony) -> int:
	if not _selected_ship:
		return 0
	var colony_pos: Vector2 = colony.get_position_au()
	var dist := _selected_ship.position_au.distance_to(colony_pos)
	var cargo_mass := _selected_ship.get_cargo_total()
	var fuel_outbound := _selected_ship.calc_fuel_for_distance(dist, cargo_mass)
	var fuel_return := _selected_ship.calc_fuel_for_distance(dist, 0.0)
	var fuel_cost := int((fuel_outbound + fuel_return) * Ship.FUEL_COST_PER_UNIT)
	var revenue := 0
	for ore_type in _selected_ship.current_cargo:
		var amount: float = _selected_ship.current_cargo[ore_type]
		var price: float = colony.get_ore_price(ore_type, GameState.market)
		revenue += int(amount * price)
	return revenue - fuel_cost

## Get location text for ship
func _get_location_text(ship: Ship) -> String:
	if ship.is_stationed and ship.station_colony:
		return "%s (stationed)" % ship.station_colony.colony_name
	if ship.is_at_earth:
		return "Earth"
	if ship.docked_at_colony:
		return ship.docked_at_colony.colony_name
	if ship.current_mission:
		match ship.current_mission.status:
			Mission.Status.IDLE_AT_DESTINATION, Mission.Status.MINING:
				return ship.current_mission.asteroid.asteroid_name
	if ship.current_trade_mission:
		match ship.current_trade_mission.status:
			TradeMission.Status.IDLE_AT_COLONY, TradeMission.Status.SELLING:
				return ship.current_trade_mission.colony.colony_name
	return "Deep space (%.2f, %.2f AU)" % [ship.position_au.x, ship.position_au.y]

## Helper functions

func _lbl() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 18)
	return label

func _free_children(container: Control) -> void:
	for child in container.get_children():
		child.queue_free()

func _format_number(value: int) -> String:
	var s := str(abs(value))
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count == 3:
			result = "," + result
			count = 0
		result = s[i] + result
		count += 1
	if value < 0:
		result = "-" + result
	return result
