extends PanelContainer
## MissionEstimator Component
## Displays mission estimate panel with transit modes, routes, thrust controls, and cost/profit breakdown

signal estimate_updated(data: Dictionary)
signal transit_mode_changed(mode: Mission.TransitMode)
signal route_changed(route)
signal thrust_changed(thrust_percent: float)

var _game_state: Node = null  # GameState reference
var _selected_ship: Ship = null
var _selected_asteroid = null  # CelestialBody
var _selected_colony: Colony = null
var _selected_workers: Array[Worker] = []
var _selected_transit_mode: Mission.TransitMode = Mission.TransitMode.BRACHISTOCHRONE
var _available_slingshot_routes: Array = []
var _selected_slingshot_route = null
var _sell_at_destination_markets: bool = true

# UI references
var _est_vbox: VBoxContainer = null
var _est_details_label: Label = null

@onready var content_container: VBoxContainer = %ContentContainer

func _ready() -> void:
	_game_state = get_node("/root/GameState")

func show_estimate(
	ship: Ship,
	destination,  # CelestialBody or Colony
	workers: Array[Worker],
	is_colony: bool,
	transit_mode: Mission.TransitMode = Mission.TransitMode.BRACHISTOCHRONE,
	slingshot_routes: Array = [],
	selected_route = null
) -> void:
	_selected_ship = ship
	_selected_workers = workers
	_selected_transit_mode = transit_mode
	_available_slingshot_routes = slingshot_routes
	_selected_slingshot_route = selected_route

	if is_colony:
		_selected_colony = destination
		_selected_asteroid = null
	else:
		_selected_asteroid = destination
		_selected_colony = null

	_build_estimate_panel()
	update_estimate_display()

func update_estimate_display() -> void:
	if not _est_details_label:
		return
	if not _selected_ship or (_selected_asteroid == null and _selected_colony == null):
		_est_details_label.text = "No destination selected"
		return

	if _selected_workers.size() < _selected_ship.min_crew:
		_est_details_label.text = "Need at least %d crew (%d selected)" % [
			_selected_ship.min_crew, _selected_workers.size()
		]
		_est_details_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
		return

	# Get estimate with current transit mode
	var est: Dictionary = AsteroidData.estimate_mission(
		_selected_asteroid, _selected_ship, _selected_workers, -1.0, Vector2(-999, -999), _selected_transit_mode
	)

	# Override estimates if using slingshot route
	if _selected_slingshot_route:
		est["fuel_needed"] = _selected_slingshot_route.fuel_cost
		est["fuel_cost"] = int(_selected_slingshot_route.fuel_cost * Ship.FUEL_COST_PER_UNIT)
		est["transit_time"] = _selected_slingshot_route.transit_time
		# Profit = revenue - fuel cost
		est["profit"] = est["revenue"] - est["fuel_cost"]

	# If selling at destination markets, recalculate profit with colony prices
	var adjusted_profit: float = est["profit"]
	var nearest_colony: Colony = null
	var colony_revenue: float = est["revenue"]

	if _sell_at_destination_markets and _selected_asteroid:
		# Find nearest colony to asteroid
		var asteroid_pos: Vector2 = _selected_asteroid.get_position_au()
		var nearest_dist := 999999.0
		for colony in _game_state.colonies:
			var d: float = asteroid_pos.distance_to(colony.get_position_au())
			if d < nearest_dist:
				nearest_dist = d
				nearest_colony = colony

		if nearest_colony:
			# Recalculate revenue at colony prices
			colony_revenue = 0.0
			var cargo_breakdown: Dictionary = est["cargo_breakdown"]
			for ore_type in cargo_breakdown:
				var tons: float = cargo_breakdown[ore_type]
				var colony_price: float = nearest_colony.get_ore_price(ore_type, _game_state.market)
				colony_revenue += tons * colony_price

			# Recalculate profit with colony revenue
			adjusted_profit = colony_revenue - est["wage_cost"] - est["fuel_cost"]

	# Update transit mode button states
	_update_transit_mode_buttons()

	# Update thrust labels
	_update_thrust_labels()

	# Build estimate text
	var mode_name: String = "HOHMANN (Fuel-Efficient)" if _selected_transit_mode == Mission.TransitMode.HOHMANN else "BRACHISTOCHRONE (Fast)"

	var lines: Array[String] = []
	lines.append("Mode: %s" % mode_name)
	lines.append("Transit: %s each way" % _format_time(est["transit_time"]))
	lines.append("Mining: %s  |  Total: %s" % [
		_format_time(est["mining_time"]), _format_time(est["total_time"])
	])
	lines.append("Cargo: %.0f / %.0f t" % [est["cargo_total"], _selected_ship.cargo_capacity])

	# Fuel cost
	if _game_state.settings.get("auto_refuel", true):
		var fuel_cost: float = est.get("fuel_cost", 0.0)
		lines.append("Fuel cost: $%s" % _format_number(int(fuel_cost)))

	# Fuel warning for one-way insufficiency
	var dist: float = _selected_ship.position_au.distance_to(_selected_asteroid.get_position_au())
	var fuel_round_trip: float = _selected_ship.calc_fuel_for_distance(dist)
	if fuel_round_trip > _selected_ship.fuel_capacity:
		lines.append("WARNING: Insufficient fuel capacity for round trip!")

	lines.append("")

	var breakdown: Dictionary = est["cargo_breakdown"]
	for ore_type in breakdown:
		var tons: float = breakdown[ore_type]
		var price: float
		if _sell_at_destination_markets and nearest_colony:
			price = nearest_colony.get_ore_price(ore_type, _game_state.market)
		else:
			price = MarketData.get_ore_price(ore_type)
		lines.append("  %s: %.1ft = $%s" % [
			ResourceTypes.get_ore_name(ore_type), tons, _format_number(int(tons * price))
		])

	lines.append("")
	if _sell_at_destination_markets and nearest_colony:
		lines.append("Revenue (at %s): $%s" % [nearest_colony.colony_name, _format_number(int(colony_revenue))])
	else:
		lines.append("Revenue (at Earth): $%s" % _format_number(int(est["revenue"])))
	lines.append("Wages: -$%s" % _format_number(int(est["wage_cost"])))
	if _game_state.settings.get("auto_refuel", true):
		# Show fuel cost with source info
		var fuel_info: Dictionary = FuelPricing.get_fuel_price_info(_selected_ship.position_au)
		var fuel_cost_display: String = "Fuel: -$%s" % _format_number(int(est.get("fuel_cost", 0.0)))
		if fuel_info["source"] != "Earth Depot":
			fuel_cost_display += " (from %s)" % fuel_info["source"]
		else:
			fuel_cost_display += " (from Earth)"
		lines.append(fuel_cost_display)

	var profit_text: String = "$%s" % _format_number(int(abs(adjusted_profit)))
	if adjusted_profit >= 0:
		lines.append("Profit: +%s" % profit_text)
	else:
		lines.append("LOSS: -%s" % profit_text)

	_est_details_label.text = "\n".join(lines)

	if adjusted_profit < 0:
		_est_details_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	elif adjusted_profit < 500:
		_est_details_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	else:
		_est_details_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))

	# Emit updated estimate
	estimate_updated.emit(est)

func _build_estimate_panel() -> void:
	# Clear previous content
	for child in content_container.get_children():
		child.queue_free()

	_est_vbox = VBoxContainer.new()
	_est_vbox.add_theme_constant_override("separation", 4)
	content_container.add_child(_est_vbox)

	var est_title := _lbl()
	est_title.text = "MISSION ESTIMATE"
	est_title.add_theme_font_size_override("font_size", 18)
	_est_vbox.add_child(est_title)

	# Transit mode selection buttons
	_build_transit_mode_buttons()

	# Route selection (slingshot vs direct) - only show if beneficial routes exist
	if not _available_slingshot_routes.is_empty():
		_build_route_selection()

	# Manual thrust control (hidden by default, AI-controlled)
	_build_thrust_controls()

	# Estimate details label
	_est_details_label = _lbl()
	_est_details_label.name = "EstimateDetails"
	_est_details_label.text = "Select crew to see estimate"
	_est_vbox.add_child(_est_details_label)

func _build_transit_mode_buttons() -> void:
	var mode_hbox := HFlowContainer.new()
	mode_hbox.name = "TransitModeButtons"
	mode_hbox.add_theme_constant_override("h_separation", 8)

	var brach_btn := Button.new()
	brach_btn.name = "BrachButton"
	brach_btn.text = "Fast (Brachistochrone)"
	brach_btn.custom_minimum_size = Vector2(0, 36)
	brach_btn.toggle_mode = true
	brach_btn.button_pressed = (_selected_transit_mode == Mission.TransitMode.BRACHISTOCHRONE)
	brach_btn.pressed.connect(func() -> void:
		_selected_transit_mode = Mission.TransitMode.BRACHISTOCHRONE
		transit_mode_changed.emit(_selected_transit_mode)
		update_estimate_display()
	)
	mode_hbox.add_child(brach_btn)

	var hohmann_btn := Button.new()
	hohmann_btn.name = "HohmannButton"
	hohmann_btn.text = "Economical (Hohmann)"
	hohmann_btn.custom_minimum_size = Vector2(0, 36)
	hohmann_btn.toggle_mode = true
	hohmann_btn.button_pressed = (_selected_transit_mode == Mission.TransitMode.HOHMANN)
	hohmann_btn.pressed.connect(func() -> void:
		_selected_transit_mode = Mission.TransitMode.HOHMANN
		transit_mode_changed.emit(_selected_transit_mode)
		update_estimate_display()
	)
	mode_hbox.add_child(hohmann_btn)

	_est_vbox.add_child(mode_hbox)

func _build_route_selection() -> void:
	var route_label := _lbl()
	route_label.text = "Route Options:"
	route_label.add_theme_font_size_override("font_size", 16)
	route_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_est_vbox.add_child(route_label)

	# AI route info
	var ai_route_info := _lbl()
	if _selected_slingshot_route:
		ai_route_info.text = "AI: %s (%s)" % [_selected_slingshot_route.route_name, CompanyPolicy.THRUST_POLICY_NAMES[_game_state.thrust_policy]]
	else:
		ai_route_info.text = "AI: Direct Route (%s)" % CompanyPolicy.THRUST_POLICY_NAMES[_game_state.thrust_policy]
	ai_route_info.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	ai_route_info.add_theme_font_size_override("font_size", 14)
	_est_vbox.add_child(ai_route_info)

	# Direct route button (always available)
	var direct_btn := Button.new()
	direct_btn.name = "DirectRouteButton"
	direct_btn.text = "Direct Route (Baseline)"
	direct_btn.custom_minimum_size = Vector2(0, 32)
	direct_btn.toggle_mode = true
	direct_btn.button_pressed = (_selected_slingshot_route == null)  # AI selection
	direct_btn.pressed.connect(func() -> void:
		_selected_slingshot_route = null
		_update_route_button_states()
		update_estimate_display()
		route_changed.emit(null)
		EventBus.mission_preview_started.emit(_selected_ship, _selected_asteroid.get_position_au(), null)
	)
	_est_vbox.add_child(direct_btn)

	# Slingshot route buttons
	for route in _available_slingshot_routes:
		var slingshot_btn := Button.new()
		slingshot_btn.name = "SlingshotButton_%d" % route.planet_index
		var savings_text: String = "Saves %.0f%% fuel" % route.fuel_savings_percent
		var time_text := ""
		if route.time_penalty > 0:
			var hours: float = route.time_penalty / 3600.0  # Convert seconds to hours
			time_text = " (+%.1fh)" % hours
		slingshot_btn.text = "%s - %s%s" % [route.route_name, savings_text, time_text]
		slingshot_btn.custom_minimum_size = Vector2(0, 32)
		slingshot_btn.toggle_mode = true
		slingshot_btn.button_pressed = (_selected_slingshot_route == route)  # AI selection
		slingshot_btn.pressed.connect(func() -> void:
			_selected_slingshot_route = route
			_update_route_button_states()
			update_estimate_display()
			route_changed.emit(route)
			EventBus.mission_preview_started.emit(_selected_ship, _selected_asteroid.get_position_au(), route)
		)
		slingshot_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
		_est_vbox.add_child(slingshot_btn)

func _build_thrust_controls() -> void:
	# Manual thrust control row
	var thrust_control_row := HBoxContainer.new()
	thrust_control_row.name = "ThrustControlRow"
	thrust_control_row.add_theme_constant_override("separation", 8)

	var manual_thrust_btn := Button.new()
	manual_thrust_btn.name = "ManualThrustButton"
	manual_thrust_btn.text = "Manual Thrust Control"
	manual_thrust_btn.custom_minimum_size = Vector2(0, 32)
	manual_thrust_btn.toggle_mode = true
	manual_thrust_btn.pressed.connect(func() -> void:
		var slider_row: HBoxContainer = _est_vbox.find_child("ThrustSliderRow", false, false)
		if slider_row:
			slider_row.visible = manual_thrust_btn.button_pressed
	)
	thrust_control_row.add_child(manual_thrust_btn)

	var ai_label := _lbl()
	ai_label.name = "AIThrustLabel"
	ai_label.text = "AI: %.0f%% (%s)" % [_selected_ship.thrust_setting * 100.0, CompanyPolicy.THRUST_POLICY_NAMES[_game_state.thrust_policy]]
	ai_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	thrust_control_row.add_child(ai_label)

	_est_vbox.add_child(thrust_control_row)

	# Thrust slider (hidden by default)
	var thrust_slider_row := HBoxContainer.new()
	thrust_slider_row.name = "ThrustSliderRow"
	thrust_slider_row.visible = false
	thrust_slider_row.add_theme_constant_override("separation", 8)

	var thrust_label := _lbl()
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
		thrust_changed.emit(value)
		update_estimate_display()
	)
	thrust_slider_row.add_child(thrust_slider)

	var thrust_pct_label := _lbl()
	thrust_pct_label.name = "ThrustPctLabel"
	thrust_pct_label.text = "%.0f%%" % (_selected_ship.thrust_setting * 100.0)
	thrust_pct_label.custom_minimum_size = Vector2(50, 0)
	thrust_slider_row.add_child(thrust_pct_label)

	_est_vbox.add_child(thrust_slider_row)

func _update_transit_mode_buttons() -> void:
	# Get estimate to check Hohmann availability
	if not _selected_asteroid or _selected_workers.size() < _selected_ship.min_crew:
		return

	var est: Dictionary = AsteroidData.estimate_mission(
		_selected_asteroid, _selected_ship, _selected_workers, -1.0, Vector2(-999, -999), _selected_transit_mode
	)

	var mode_hbox: HFlowContainer = _est_vbox.find_child("TransitModeButtons", false, false)
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
				transit_mode_changed.emit(_selected_transit_mode)

func _update_thrust_labels() -> void:
	var thrust_pct_label: Label = _est_vbox.find_child("ThrustPctLabel", true, false)
	if thrust_pct_label:
		thrust_pct_label.text = "%.0f%%" % (_selected_ship.thrust_setting * 100.0)

	var ai_thrust_label: Label = _est_vbox.find_child("AIThrustLabel", true, false)
	if ai_thrust_label:
		ai_thrust_label.text = "AI: %.0f%% (%s)" % [_selected_ship.thrust_setting * 100.0, CompanyPolicy.THRUST_POLICY_NAMES[_game_state.thrust_policy]]

func _update_route_button_states() -> void:
	# Toggle route buttons to reflect selection
	if not _est_vbox:
		return

	# Update direct route button
	var direct_btn: Button = _est_vbox.find_child("DirectRouteButton", true, false)
	if direct_btn:
		direct_btn.button_pressed = (_selected_slingshot_route == null)

	# Update slingshot buttons
	for route in _available_slingshot_routes:
		var slingshot_btn: Button = _est_vbox.find_child("SlingshotButton_%d" % route.planet_index, true, false)
		if slingshot_btn:
			slingshot_btn.button_pressed = (_selected_slingshot_route == route)

func calculate_jettison_for_asymmetric_trip(dist_outbound: float, dist_return: float) -> float:
	# Calculate minimum cargo to jettison for asymmetric trip
	if not _selected_ship:
		return 0.0

	var current_cargo: float = _selected_ship.get_cargo_total()

	# Binary search for minimum jettison
	var low := 0.0
	var high := current_cargo
	var needed_jettison := current_cargo

	for _i in range(10):
		var mid: float = (low + high) / 2.0
		var remaining_cargo: float = current_cargo - mid

		# Fuel needed: outbound with current cargo, return fully loaded
		var fuel_out: float = _selected_ship.calc_fuel_for_distance(dist_outbound, remaining_cargo)
		var fuel_ret: float = _selected_ship.calc_fuel_for_distance(dist_return, _selected_ship.cargo_capacity)
		var total_fuel: float = fuel_out + fuel_ret

		if total_fuel <= _selected_ship.fuel:
			needed_jettison = mid
			high = mid
		else:
			low = mid

	return needed_jettison

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
