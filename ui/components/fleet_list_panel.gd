extends VBoxContainer

## Fleet List Panel Component
## Displays all ships with their status, equipment, cargo, and action buttons
## Extracted from fleet_market_tab.gd _rebuild_ships() (885 lines)

signal ship_selected(ship: Ship)
signal dispatch_requested(ship: Ship, planning_mode: bool, redirect_mode: bool)
signal partnership_requested(ship: Ship)
signal station_jobs_requested(ship: Ship)
signal supply_shop_requested(ship: Ship)
signal needs_rebuild()

# Ship panel container
@onready var ships_list: VBoxContainer = %ShipsList

# Cached UI elements (Ship -> Control)
var _progress_bars: Dictionary = {}  # Ship -> ProgressBar
var _status_labels: Dictionary = {}  # Ship -> Label
var _detail_labels: Dictionary = {}  # Ship -> Label
var _cargo_labels: Dictionary = {}  # Ship -> Label
var _location_labels: Dictionary = {}  # Ship -> Label
var _signal_labels: Dictionary = {}  # Ship -> Label (for pending orders)

# Expansion state (Ship -> bool)
var _ship_stats_expanded: Dictionary = {}  # Stats section
var _policy_overrides_expanded: Dictionary = {}  # Policy overrides section
var _crew_expanded: Dictionary = {}  # Crew section

# Animation state
var _target_progress: Dictionary = {}  # Ship -> float (0-1)
var _lerp_progress: Dictionary = {}  # Ship -> float (0-1)

func _ready() -> void:
	EventBus.tick.connect(_on_tick)

func _process(delta: float) -> void:
	# Smooth LERP for progress bar animations
	for ship: Ship in _progress_bars:
		if _target_progress.has(ship) and _lerp_progress.has(ship):
			var target: float = _target_progress[ship]
			var current: float = _lerp_progress[ship]
			var new_val := lerpf(current, target, delta * 2.0)
			_lerp_progress[ship] = new_val
			if _progress_bars.has(ship):
				_progress_bars[ship].value = new_val * 100.0

func _on_tick() -> void:
	# Update dynamic labels and cargo without full rebuild
	for ship: Ship in _status_labels:
		if ship.is_stationed and not ship.is_stationed_idle:
			if ship.current_mission:
				_status_labels[ship].text = "STATIONED @ %s — %s" % [ship.station_colony.colony_name, ship.current_mission.get_status_text()]
			elif ship.current_trade_mission:
				_status_labels[ship].text = "STATIONED @ %s — %s" % [ship.station_colony.colony_name, ship.current_trade_mission.get_status_text()]
		elif not ship.is_docked and not ship.is_idle_remote and not ship.is_derelict:
			if ship in GameState.refuel_missions:
				var refuel_data: Dictionary = GameState.refuel_missions[ship]
				var progress: float = float(refuel_data["elapsed_ticks"]) / float(refuel_data["transit_time"])
				_status_labels[ship].text = "Refueling: %d%%" % int(progress * 100)
			elif ship.current_mission:
				_status_labels[ship].text = ship.current_mission.get_status_text()
			elif ship.current_trade_mission:
				_status_labels[ship].text = ship.current_trade_mission.get_status_text()

	# Update location labels
	for ship: Ship in _location_labels:
		_location_labels[ship].text = _get_location_text(ship)

	# Update detail labels
	for ship: Ship in _detail_labels:
		_detail_labels[ship].text = _build_details_text(ship)

	# Update cargo labels (ore totals can change during mining)
	for ship: Ship in _cargo_labels:
		var _ore_total := 0.0
		for _amt in ship.current_cargo.values():
			_ore_total += _amt
		if _ore_total > 0.01:
			var cargo_lines: Array[String] = ["Ore (%.1ft):" % _ore_total]
			for ore_type in ship.current_cargo:
				var amount: float = ship.current_cargo[ore_type]
				if amount > 0.01:
					cargo_lines.append("  %s: %.1ft" % [ResourceTypes.get_ore_name(ore_type), amount])
			_cargo_labels[ship].text = "\n".join(cargo_lines)

	# Update pending order countdowns (lightspeed signal delays)
	for ship: Ship in _signal_labels:
		var pending_order := GameState.get_pending_order(ship)
		if not pending_order.is_empty():
			var remaining_secs: float = pending_order["fires_at"] - GameState.total_ticks
			var mins := int(remaining_secs / 60.0)
			var secs := int(fmod(remaining_secs, 60.0))
			var delay_str := "%dm %02ds" % [mins, secs] if mins > 0 else "%ds" % secs
			_signal_labels[ship].text = "📡 Signal in transit: %s (%s remaining)" % [pending_order["label"], delay_str]

	# Update mission progress bars (smooth LERP targets)
	for ship: Ship in _progress_bars:
		if ship in GameState.refuel_missions:
			var refuel_data: Dictionary = GameState.refuel_missions[ship]
			_target_progress[ship] = float(refuel_data["elapsed_ticks"]) / float(refuel_data["transit_time"])
		elif ship.current_mission:
			_target_progress[ship] = ship.current_mission.get_progress()
		elif ship.current_trade_mission:
			_target_progress[ship] = ship.current_trade_mission.get_progress()
		else:
			_target_progress[ship] = 0.0

		if not _lerp_progress.has(ship):
			_lerp_progress[ship] = _target_progress[ship]

## Rebuild entire ship list from scratch
func rebuild_ships() -> void:
	_progress_bars.clear()
	_status_labels.clear()
	_detail_labels.clear()
	_cargo_labels.clear()
	_location_labels.clear()
	_signal_labels.clear()
	_free_children(ships_list)

	for ship: Ship in GameState.ships:
		_build_ship_panel(ship)

## Build a single ship's display panel
func _build_ship_panel(ship: Ship) -> void:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 4)

	# === SHIP HEADER ===
	var header := VBoxContainer.new()
	header.add_theme_constant_override("separation", 2)
	var name_row := HBoxContainer.new()
	var name_label := _lbl()
	name_label.text = "%s (%s)" % [ship.ship_name, ship.get_class_name()]
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_row.add_child(name_label)
	var wrench_tex := _get_wrench_texture(ship)
	if wrench_tex:
		var icon_wrapper := Control.new()
		icon_wrapper.custom_minimum_size = Vector2(20, 20)
		icon_wrapper.size_flags_horizontal = Control.SIZE_SHRINK_END
		icon_wrapper.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		var icon := TextureRect.new()
		icon.texture = wrench_tex
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		icon.pivot_offset = Vector2(10, 10)
		icon.rotation_degrees = 35.0
		icon_wrapper.add_child(icon)
		name_row.add_child(icon_wrapper)
	header.add_child(name_row)

	var _derelict_actions: HFlowContainer = null
	if ship.is_derelict:
		var status := _lbl()
		var status_text := "STRANDED (OUT OF FUEL)" if ship.derelict_reason == "out_of_fuel" else "DERELICT (BREAKDOWN)"
		if ship.speed_au_per_tick > 0.0:
			var speed_km_s := ship.speed_au_per_tick * CelestialData.AU_TO_METERS / 1000.0
			status_text += " — Drifting %.1f km/s" % speed_km_s
		status.text = status_text
		status.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
		header.add_child(status)

		_derelict_actions = HFlowContainer.new()
		_derelict_actions.add_theme_constant_override("h_separation", 8)

		# Show refuel in progress
		if ship in GameState.refuel_missions:
			var refuel_data: Dictionary = GameState.refuel_missions[ship]
			var elapsed: float = refuel_data["elapsed_ticks"]
			var total: float = refuel_data["transit_time"]
			var progress: float = elapsed / total
			var remaining := total - elapsed
			var source_name: String = refuel_data.get("source_name", "Earth")
			var refuel_label := _lbl()
			refuel_label.text = "Refuel: %d%% — ETA %s from %s" % [int(progress * 100), TimeScale.format_time(remaining), source_name]
			refuel_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9))
			_derelict_actions.add_child(refuel_label)
		# Show fleet rescue in progress
		elif GameState.find_fleet_rescue_ferry(ship) != null:
			var ferry_ship := GameState.find_fleet_rescue_ferry(ship)
			var ferry_mission := ferry_ship.current_mission
			var elapsed: float = ferry_mission.elapsed_ticks
			var total: float = ferry_mission.transit_time
			var progress: float = clampf(elapsed / total if total > 0 else 0.0, 0.0, 1.0)
			var remaining: float = maxf(0.0, total - elapsed)
			var rescue_label := _lbl()
			rescue_label.text = "Fleet Rescue: %s en route (%d%% — ETA %s)" % [
				ferry_ship.ship_name, int(progress * 100), TimeScale.format_time(remaining)
			]
			rescue_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
			_derelict_actions.add_child(rescue_label)
			var cancel_rescue_btn := Button.new()
			cancel_rescue_btn.text = "Cancel Rescue"
			cancel_rescue_btn.custom_minimum_size = Vector2(0, 36)
			cancel_rescue_btn.pressed.connect(func() -> void:
				GameState.cancel_fleet_rescue(ship)
				needs_rebuild.emit()
			)
			_derelict_actions.add_child(cancel_rescue_btn)
		# Show hired rescue in progress
		elif ship in GameState.rescue_missions:
			var rescue_data: Dictionary = GameState.rescue_missions[ship]
			var elapsed: float = rescue_data["elapsed_ticks"]
			var total: float = rescue_data["transit_time"]
			var progress: float = elapsed / total
			var remaining := total - elapsed
			var source_name: String = rescue_data.get("source_name", "Earth")
			var rescue_label := _lbl()
			rescue_label.text = "Rescue: %d%% — ETA %s from %s" % [int(progress * 100), TimeScale.format_time(remaining), source_name]
			rescue_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
			_derelict_actions.add_child(rescue_label)
		else:
			# Stranger offer
			if ship in GameState.stranger_offers:
				var offer: Dictionary = GameState.stranger_offers[ship]
				var stranger_name: String = offer["stranger_name"]
				var tip: int = offer["suggested_tip"]
				var offer_label := _lbl()
				offer_label.text = "A passing vessel (%s) is offering assistance" % stranger_name
				offer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
				offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				offer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				_derelict_actions.add_child(offer_label)

				var accept_free_btn := Button.new()
				accept_free_btn.text = "Accept (Free)"
				accept_free_btn.custom_minimum_size = Vector2(0, 44)
				accept_free_btn.pressed.connect(func() -> void:
					GameState.accept_stranger_rescue(ship, false)
					needs_rebuild.emit()
				)
				_derelict_actions.add_child(accept_free_btn)

				var accept_pay_btn := Button.new()
				accept_pay_btn.text = "Accept + Pay $%s" % _format_number(tip)
				accept_pay_btn.custom_minimum_size = Vector2(0, 44)
				accept_pay_btn.disabled = GameState.money < tip
				accept_pay_btn.pressed.connect(func() -> void:
					GameState.accept_stranger_rescue(ship, true)
					needs_rebuild.emit()
				)
				_derelict_actions.add_child(accept_pay_btn)

				var decline_btn := Button.new()
				decline_btn.text = "Decline"
				decline_btn.custom_minimum_size = Vector2(0, 44)
				decline_btn.pressed.connect(func() -> void:
					GameState.decline_stranger_rescue(ship)
					needs_rebuild.emit()
				)
				_derelict_actions.add_child(decline_btn)

			# Refuel option (cheaper, only for fuel depletion)
			if ship.derelict_reason == "out_of_fuel" and ship not in GameState.stranger_offers:
				var refuel_cost := GameState.get_refuel_cost(ship, ship.fuel_capacity)
				var refuel_btn := Button.new()
				refuel_btn.text = "Refuel ($%s)" % _format_number(refuel_cost)
				refuel_btn.custom_minimum_size = Vector2(0, 44)
				refuel_btn.disabled = GameState.money < refuel_cost
				refuel_btn.pressed.connect(func() -> void:
					GameState.start_refuel(ship, ship.fuel_capacity)
					needs_rebuild.emit()
				)
				_derelict_actions.add_child(refuel_btn)

			# Rescue option (expensive, for breakdowns or as alternative)
			if ship not in GameState.stranger_offers:
				var rescue_cost := GameState.get_rescue_cost(ship)
				var rescue_btn := Button.new()
				rescue_btn.text = "Rescue ($%s)" % _format_number(rescue_cost)
				rescue_btn.custom_minimum_size = Vector2(0, 44)
				rescue_btn.disabled = GameState.money < rescue_cost
				rescue_btn.pressed.connect(func() -> void:
					GameState.start_rescue(ship)
					needs_rebuild.emit()
				)
				_derelict_actions.add_child(rescue_btn)
	elif ship.is_stationed:
		var status := _lbl()
		if ship.is_stationed_idle:
			status.text = "STATIONED @ %s (idle)" % ship.station_colony.colony_name
		elif ship.current_mission:
			status.text = "STATIONED @ %s — %s" % [ship.station_colony.colony_name, ship.current_mission.get_status_text()]
		elif ship.current_trade_mission:
			status.text = "STATIONED @ %s — %s" % [ship.station_colony.colony_name, ship.current_trade_mission.get_status_text()]
		else:
			status.text = "STATIONED @ %s" % ship.station_colony.colony_name
		status.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
		header.add_child(status)
		_status_labels[ship] = status
	elif ship.is_docked:
		var status := _lbl()
		if ship.docked_at_colony:
			status.text = "Docked at %s" % ship.docked_at_colony.colony_name
		else:
			status.text = "Docked at Earth"
		status.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
		header.add_child(status)
	elif ship.is_idle_remote:
		var status := _lbl()
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
		var status := _lbl()
		if ship in GameState.refuel_missions:
			var refuel_data: Dictionary = GameState.refuel_missions[ship]
			var progress: float = float(refuel_data["elapsed_ticks"]) / float(refuel_data["transit_time"])
			status.text = "Refueling: %d%%" % int(progress * 100)
			status.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9))
		elif ship.current_mission:
			status.text = ship.current_mission.get_status_text()
			status.add_theme_color_override("font_color", Color(0.8, 0.7, 0.2))
		elif ship.current_trade_mission:
			status.text = ship.current_trade_mission.get_status_text()
			status.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
		header.add_child(status)
		_status_labels[ship] = status

	vbox.add_child(header)
	if _derelict_actions:
		vbox.add_child(_derelict_actions)

	# === PARTNERSHIP STATUS ===
	if ship.is_partnered():
		var partnership_row := HBoxContainer.new()
		partnership_row.add_theme_constant_override("separation", 8)

		var partner_icon := _lbl()
		partner_icon.text = "🤝"
		partner_icon.add_theme_font_size_override("font_size", 18)
		partnership_row.add_child(partner_icon)

		var partner_label := _lbl()
		var role := "Leader" if ship.is_partnership_leader else "Follower"
		partner_label.text = "%s: Partnered with %s" % [role, ship.partner_ship_name]
		partner_label.add_theme_color_override("font_color", Color(0.4, 0.8, 1.0))
		partner_label.add_theme_font_size_override("font_size", 14)
		partnership_row.add_child(partner_label)

		var break_btn := Button.new()
		break_btn.text = "Break Partnership"
		break_btn.add_theme_font_size_override("font_size", 13)
		break_btn.custom_minimum_size = Vector2(0, 24)
		break_btn.pressed.connect(func() -> void:
			GameState.break_partnership(ship, ship.partner_ship, "User terminated partnership")
			needs_rebuild.emit()
		)
		partnership_row.add_child(break_btn)

		vbox.add_child(partnership_row)

	# Partnership creation button (for idle docked ships)
	if ship.is_docked and not ship.is_partnered() and ship.current_mission == null:
		var partner_btn := Button.new()
		partner_btn.text = "Create Partnership"
		partner_btn.add_theme_font_size_override("font_size", 14)
		partner_btn.custom_minimum_size = Vector2(0, 28)
		partner_btn.pressed.connect(func() -> void:
			partnership_requested.emit(ship)
		)
		vbox.add_child(partner_btn)

	# === SHIP STATS (Collapsible) ===
	_build_ship_stats_section(vbox, ship)

	# === LOCATION & DETAILS ===
	var loc_label := _lbl()
	loc_label.text = _get_location_text(ship)
	loc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	loc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	loc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(loc_label)
	_location_labels[ship] = loc_label

	var details := _lbl()
	details.text = _build_details_text(ship)
	details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(details)
	_detail_labels[ship] = details

	# === CARGO DISPLAY ===
	var _ore_total := 0.0
	for _amt in ship.current_cargo.values():
		_ore_total += _amt
	if _ore_total > 0.01:
		var cargo_label := _lbl()
		var cargo_lines: Array[String] = ["Ore (%.1ft):" % _ore_total]
		for ore_type in ship.current_cargo:
			var amount: float = ship.current_cargo[ore_type]
			if amount > 0.01:
				cargo_lines.append("  %s: %.1ft" % [ResourceTypes.get_ore_name(ore_type), amount])
		cargo_label.text = "\n".join(cargo_lines)
		cargo_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
		vbox.add_child(cargo_label)
		_cargo_labels[ship] = cargo_label

	# === SUPPLIES DISPLAY ===
	var _sup_mass := ship.get_supplies_mass()
	if _sup_mass > 0.01:
		var sup_label := _lbl()
		var sup_lines: Array[String] = ["Supplies (%.1ft):" % _sup_mass]
		var crew_count: int = maxi(ship.crew.size(), 1)
		var _food_kg: float = ship.supplies.get("food", 0.0)
		if _food_kg > 0.01:
			var food_days := _food_kg / (crew_count * 2.8)
			sup_lines.append("  Food: %.1f kg (~%.1fd for %d crew)" % [_food_kg, food_days, crew_count])
		var _water_units: float = ship.supplies.get("water", 0.0)
		if _water_units > 0.01:
			var water_days := _water_units * 80.0 / crew_count
			sup_lines.append("  Water: %.1f tanks (~%.1fd for %d crew)" % [_water_units, water_days, crew_count])
		var _o2_units: float = ship.supplies.get("oxygen", 0.0)
		if _o2_units > 0.01:
			var o2_days := _o2_units * 40.0 / crew_count
			sup_lines.append("  O2: %.1f canisters (~%.1fd for %d crew)" % [_o2_units, o2_days, crew_count])
		var _parts_units: float = ship.supplies.get("repair_parts", 0.0)
		if _parts_units > 0.01:
			sup_lines.append("  Repair Parts: %.0f kits" % _parts_units)
		sup_label.text = "\n".join(sup_lines)
		sup_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.55))
		vbox.add_child(sup_label)

	# === ACTION BUTTONS ===
	_build_action_buttons(vbox, ship)

	# === EQUIPMENT ===
	_build_equipment_section(vbox, ship)

	# === PROGRESS BAR ===
	if not ship.is_docked and not ship.is_idle_remote and not ship.is_derelict and not ship.is_stationed_idle:
		var progress := ProgressBar.new()
		if ship in GameState.refuel_missions:
			var refuel_data: Dictionary = GameState.refuel_missions[ship]
			var refuel_progress: float = float(refuel_data["elapsed_ticks"]) / float(refuel_data["transit_time"])
			progress.value = refuel_progress * 100.0
			_target_progress[ship] = refuel_progress
			_lerp_progress[ship] = refuel_progress
		elif ship.current_mission:
			progress.value = ship.current_mission.get_progress() * 100.0
			_target_progress[ship] = ship.current_mission.get_progress()
			_lerp_progress[ship] = ship.current_mission.get_progress()
		elif ship.current_trade_mission:
			progress.value = ship.current_trade_mission.get_progress() * 100.0
			_target_progress[ship] = ship.current_trade_mission.get_progress()
			_lerp_progress[ship] = ship.current_trade_mission.get_progress()
		vbox.add_child(progress)
		_progress_bars[ship] = progress

		# === QUEUED MISSION INFO & PLAN BUTTON ===
		if ship.has_queued_mission():
			var queued_info := _lbl()
			var dest_name := ""
			if ship.queued_destination is AsteroidData:
				dest_name = ship.queued_destination.asteroid_name
			elif ship.queued_destination is Colony:
				dest_name = ship.queued_destination.colony_name
			queued_info.text = "Queued: %s (%d crew)" % [dest_name, ship.crew.size()]
			queued_info.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
			queued_info.add_theme_font_size_override("font_size", 18)
			vbox.add_child(queued_info)

		# Show pending order (lightspeed signal in transit)
		var transit_pending := GameState.get_pending_order(ship)
		if not transit_pending.is_empty():
			var rem_secs: float = transit_pending["fires_at"] - GameState.total_ticks
			var r_mins := int(rem_secs / 60.0)
			var r_secs := int(fmod(rem_secs, 60.0))
			var transit_delay_str := "%dm %02ds" % [r_mins, r_secs] if r_mins > 0 else "%ds" % r_secs
			var pending_lbl := _lbl()
			pending_lbl.text = "📡 Signal in transit: %s (%s remaining)" % [transit_pending["label"], transit_delay_str]
			pending_lbl.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
			pending_lbl.add_theme_font_size_override("font_size", 17)
			pending_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(pending_lbl)

		var plan_row := HBoxContainer.new()
		plan_row.add_theme_constant_override("separation", 8)

		var redirect_btn := Button.new()
		redirect_btn.text = "Redirect"
		redirect_btn.custom_minimum_size = Vector2(0, 44)
		redirect_btn.pressed.connect(func() -> void:
			dispatch_requested.emit(ship, false, true)  # planning_mode=false, redirect_mode=true
		)
		plan_row.add_child(redirect_btn)

		var plan_btn := Button.new()
		plan_btn.text = "Plan Next Mission" if not ship.has_queued_mission() else "Change Queued Mission"
		plan_btn.custom_minimum_size = Vector2(0, 44)
		plan_btn.pressed.connect(func() -> void:
			dispatch_requested.emit(ship, true, false)  # planning_mode=true, redirect_mode=false
		)
		plan_row.add_child(plan_btn)

		# Clear queue button if mission is queued
		if ship.has_queued_mission():
			var clear_btn := Button.new()
			clear_btn.text = "Clear Queue"
			clear_btn.custom_minimum_size = Vector2(0, 44)
			clear_btn.pressed.connect(func() -> void:
				ship.clear_queued_mission()
				needs_rebuild.emit()
			)
			plan_row.add_child(clear_btn)

		vbox.add_child(plan_row)

	# === POLICY OVERRIDES ===
	if not ship.is_derelict:
		_build_policy_overrides_section(vbox, ship)

	# === CREW TOGGLE ===
	_build_crew_section(vbox, ship)

	panel.add_child(vbox)
	ships_list.add_child(panel)

## Build ship stats section (collapsible)
func _build_ship_stats_section(vbox: VBoxContainer, ship: Ship) -> void:
	var stats_expanded: bool = _ship_stats_expanded.get(ship, false)

	var stats_header_btn := Button.new()
	stats_header_btn.text = "[Stats] ▶" if not stats_expanded else "[Stats] ▼"
	stats_header_btn.flat = true
	stats_header_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	stats_header_btn.add_theme_color_override("font_color", Color(0.5, 0.7, 0.9))
	stats_header_btn.add_theme_font_size_override("font_size", 17)
	stats_header_btn.custom_minimum_size = Vector2(0, 28)
	vbox.add_child(stats_header_btn)

	var stats_container := VBoxContainer.new()
	stats_container.visible = stats_expanded
	stats_container.add_theme_constant_override("separation", 4)

	var stats_grid := GridContainer.new()
	stats_grid.columns = 2
	stats_grid.add_theme_constant_override("h_separation", 16)
	stats_grid.add_theme_constant_override("v_separation", 4)

	var current_thrust := 0.0 if (ship.is_docked or ship.is_stationed or ship.is_idle_remote) else ship.get_effective_thrust()
	_add_fleet_stat_row(stats_grid, "Thrust:", "%.2fg", ship.max_thrust_g, current_thrust)
	_add_fleet_stat_row(stats_grid, "Fuel:", "%.0ft", ship.fuel_capacity, ship.get_effective_fuel_capacity())

	var dv_base := ship.get_delta_v(ship.fuel_capacity)
	var dv_eff := ship.get_delta_v(ship.get_effective_fuel_capacity())
	var dv_label := _lbl()
	dv_label.text = "Δv (full):"
	dv_label.clip_text = true
	dv_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	dv_label.add_theme_font_size_override("font_size", 16)
	stats_grid.add_child(dv_label)

	var dv_value := _lbl()
	if abs(dv_eff - dv_base) > 0.05:
		dv_value.text = "%.1f km/s → %.1f km/s" % [dv_base, dv_eff]
		dv_value.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	else:
		dv_value.text = "%.1f km/s" % dv_base
		dv_value.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	dv_value.clip_text = true
	dv_value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dv_value.add_theme_font_size_override("font_size", 16)
	stats_grid.add_child(dv_value)

	_add_fleet_stat_row(stats_grid, "Cargo:", "%.0ft", ship.cargo_capacity, ship.get_effective_cargo_capacity())
	_add_fleet_stat_row(stats_grid, "Volume:", "%.0fm³", ship.cargo_volume, ship.get_effective_cargo_volume())
	_add_fleet_stat_row(stats_grid, "Min Crew:", "%d", float(ship.min_crew), float(ship.min_crew))

	stats_container.add_child(stats_grid)
	vbox.add_child(stats_container)

	stats_header_btn.pressed.connect(func() -> void:
		_ship_stats_expanded[ship] = not _ship_stats_expanded.get(ship, false)
		needs_rebuild.emit()
	)

## Build action buttons section (huge!)
func _build_action_buttons(vbox: VBoxContainer, ship: Ship) -> void:
	# Stationed ships: Edit Jobs and Unstation
	if ship.is_stationed:
		var jobs_label := _lbl()
		var jobs_text := "Jobs: " + ", ".join(ship.station_jobs) if not ship.station_jobs.is_empty() else "Jobs: None"
		jobs_label.text = jobs_text
		jobs_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9))
		jobs_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(jobs_label)

		if not ship.station_log.is_empty():
			var log_label := _lbl()
			var recent := ship.station_log[0]
			var elapsed := GameState.total_ticks - float(recent["time"])
			var time_ago := TimeScale.format_time(elapsed) + " ago" if elapsed > 0 else "just now"
			log_label.text = "Last: %s (%s)" % [recent["message"], time_ago]
			log_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
			log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(log_label)

		var station_btn_row := HBoxContainer.new()
		station_btn_row.add_theme_constant_override("separation", 8)

		var edit_jobs_btn := Button.new()
		edit_jobs_btn.text = "Edit Jobs"
		edit_jobs_btn.custom_minimum_size = Vector2(0, 44)
		edit_jobs_btn.pressed.connect(func() -> void:
			station_jobs_requested.emit(ship)
		)
		station_btn_row.add_child(edit_jobs_btn)

		var unstation_btn := Button.new()
		unstation_btn.text = "Unstation"
		unstation_btn.custom_minimum_size = Vector2(0, 44)
		unstation_btn.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
		unstation_btn.pressed.connect(func() -> void:
			GameState.unstation_ship(ship)
			needs_rebuild.emit()
		)
		station_btn_row.add_child(unstation_btn)

		vbox.add_child(station_btn_row)

		if ship.is_stationed_idle and ship.station_colony != null:
			var supply_btn := Button.new()
			supply_btn.text = "Manage Supplies"
			supply_btn.custom_minimum_size = Vector2(0, 44)
			supply_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
			supply_btn.pressed.connect(func() -> void:
				supply_shop_requested.emit(ship)
			)
			vbox.add_child(supply_btn)

	# Docked ships: Dispatch, Unload, and Station
	if ship.is_docked and not ship.is_stationed:
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 8)

		var dispatch_btn := Button.new()
		dispatch_btn.text = "Dispatch"
		dispatch_btn.custom_minimum_size = Vector2(0, 44)
		dispatch_btn.pressed.connect(func() -> void:
			dispatch_requested.emit(ship, false, false)
		)
		btn_row.add_child(dispatch_btn)

		var manage_sup_btn := Button.new()
		manage_sup_btn.text = "Supplies"
		manage_sup_btn.custom_minimum_size = Vector2(0, 44)
		manage_sup_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
		manage_sup_btn.pressed.connect(func() -> void:
			supply_shop_requested.emit(ship)
		)
		btn_row.add_child(manage_sup_btn)

		# Unload ore button
		var _dock_ore_total := 0.0
		for _v in ship.current_cargo.values():
			_dock_ore_total += _v
		if _dock_ore_total > 0.01:
			var unload_btn := Button.new()
			unload_btn.text = "Unload Ore to Stockpile"
			unload_btn.custom_minimum_size = Vector2(0, 44)
			unload_btn.pressed.connect(func() -> void:
				for ore_type in ship.current_cargo:
					GameState.add_resource(ore_type, ship.current_cargo[ore_type])
				ship.current_cargo.clear()
				needs_rebuild.emit()
			)
			btn_row.add_child(unload_btn)

		# Station Here button (only at colonies)
		if ship.docked_at_colony != null:
			var station_btn := Button.new()
			station_btn.text = "Station Here"
			station_btn.custom_minimum_size = Vector2(0, 44)
			station_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
			station_btn.pressed.connect(func() -> void:
				station_jobs_requested.emit(ship)
			)
			btn_row.add_child(station_btn)

		vbox.add_child(btn_row)

	# Idle remote ships: Sell, Dispatch, Return
	if ship.is_idle_remote:
		var at_colony: Colony = null
		if ship.current_trade_mission and ship.current_trade_mission.status == TradeMission.Status.IDLE_AT_COLONY:
			at_colony = ship.current_trade_mission.colony

		if at_colony and ship.get_ore_total() > 0:
			# Check for matching contracts
			var matching_contracts := _get_matching_contracts(ship, at_colony)

			if not matching_contracts.is_empty():
				var contract_header := _lbl()
				contract_header.text = "Available Contracts at %s:" % at_colony.colony_name
				contract_header.add_theme_font_size_override("font_size", 18)
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
				if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
					if ship.server_id > 0:
						await BackendManager.sell_cargo(ship.server_id)
					return
				var total_revenue := 0
				for ore_type in ship.current_cargo:
					var amount: float = ship.current_cargo[ore_type]
					var price: float = at_colony.get_ore_price(ore_type, GameState.market)
					total_revenue += int(amount * price)
				GameState.money += total_revenue
				ship.current_cargo.clear()
				needs_rebuild.emit()
			)
			vbox.add_child(sell_btn)

		# Show pending order status
		var pending_order := GameState.get_pending_order(ship)
		if not pending_order.is_empty():
			var remaining_secs: float = pending_order["fires_at"] - GameState.total_ticks
			var mins := int(remaining_secs / 60.0)
			var secs := int(fmod(remaining_secs, 60.0))
			var delay_str := "%dm %02ds" % [mins, secs] if mins > 0 else "%ds" % secs
			var signal_lbl := _lbl()
			signal_lbl.text = "📡 Signal in transit: %s (%s remaining)" % [pending_order["label"], delay_str]
			signal_lbl.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
			signal_lbl.add_theme_font_size_override("font_size", 17)
			signal_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(signal_lbl)
			_signal_labels[ship] = signal_lbl

		var action_row := HBoxContainer.new()
		action_row.add_theme_constant_override("separation", 8)

		var dispatch_btn := Button.new()
		dispatch_btn.text = "Dispatch"
		dispatch_btn.custom_minimum_size = Vector2(0, 44)
		dispatch_btn.disabled = not pending_order.is_empty()
		dispatch_btn.pressed.connect(func() -> void:
			dispatch_requested.emit(ship, false, false)
		)
		action_row.add_child(dispatch_btn)

		var return_btn := Button.new()
		return_btn.text = "Return to Earth"
		return_btn.custom_minimum_size = Vector2(0, 44)
		return_btn.disabled = not pending_order.is_empty()
		return_btn.pressed.connect(func() -> void:
			GameState.order_return_to_earth(ship)
			needs_rebuild.emit()
		)
		action_row.add_child(return_btn)

		vbox.add_child(action_row)

	# Engine repair button
	if ship.is_docked and ship.engine_condition < 100.0:
		var repair_cost := ship.get_engine_repair_cost()
		var engine_btn := Button.new()
		engine_btn.text = "Repair Engine ($%s)" % _format_number(repair_cost)
		engine_btn.custom_minimum_size = Vector2(0, 44)
		engine_btn.disabled = GameState.money < repair_cost
		engine_btn.pressed.connect(func() -> void:
			GameState.repair_engine(ship)
			needs_rebuild.emit()
		)
		vbox.add_child(engine_btn)

	# Torpedo restocking button
	if ship.is_docked:
		var restock_cost := GameState.get_torpedo_restock_cost(ship)
		if restock_cost > 0:
			var location_name := "Earth"
			if ship.docked_at_colony != null:
				location_name = ship.docked_at_colony.colony_name
			var quality: int = MunitionsData.get_quality_at_location(location_name)
			var quality_name := MunitionsData.get_quality_name(quality)
			var quality_color := MunitionsData.get_quality_color(quality)

			var restock_btn := Button.new()
			restock_btn.text = "Restock Torpedoes ($%s) — %s" % [_format_number(restock_cost), quality_name]
			restock_btn.custom_minimum_size = Vector2(0, 44)
			restock_btn.disabled = GameState.money < restock_cost
			restock_btn.add_theme_color_override("font_color", quality_color)
			restock_btn.pressed.connect(func() -> void:
				GameState.restock_torpedoes(ship)
				needs_rebuild.emit()
			)
			vbox.add_child(restock_btn)

## Build equipment section
func _build_equipment_section(vbox: VBoxContainer, ship: Ship) -> void:
	if not ship.equipment.is_empty():
		for e in ship.equipment:
			var equip_row := HBoxContainer.new()
			equip_row.add_theme_constant_override("separation", 6)

			var equip_label := _lbl()
			var dur_str := "%d%%" % int(e.durability)
			var broken_str := ""
			if e.durability <= 0:
				broken_str = " (BROKEN)"
				equip_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
			elif e.durability < 30:
				equip_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
			else:
				equip_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))

			var equip_text := ""
			if e.is_weapon():
				var ammo_str := ""
				if e.has_ammo():
					var quality_name := MunitionsData.get_quality_name(e.ammo_quality)
					ammo_str = " [%d/%d %s]" % [e.current_ammo, e.ammo_capacity, quality_name]
				equip_text = "%s%s %s%s" % [e.equipment_name, ammo_str, dur_str, broken_str]
			else:
				equip_text = "%s (%.2fx) %s%s" % [e.equipment_name, e.mining_bonus, dur_str, broken_str]

			equip_label.text = equip_text
			equip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			equip_label.clip_text = true
			equip_row.add_child(equip_label)

			var dur_bar := ProgressBar.new()
			dur_bar.custom_minimum_size = Vector2(60, 0)
			dur_bar.value = e.durability
			dur_bar.max_value = e.max_durability
			equip_row.add_child(dur_bar)

			vbox.add_child(equip_row)

## Build policy overrides section
func _build_policy_overrides_section(vbox: VBoxContainer, ship: Ship) -> void:
	var policy_expanded: bool = _policy_overrides_expanded.get(ship, false)
	var policy_header := _lbl()
	policy_header.text = ("▾ " if policy_expanded else "▸ ") + "Policy Overrides"
	policy_header.add_theme_font_size_override("font_size", 14)
	policy_header.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	policy_header.mouse_filter = Control.MOUSE_FILTER_STOP
	vbox.add_child(policy_header)

	var policy_grid := GridContainer.new()
	policy_grid.columns = 2
	policy_grid.add_theme_constant_override("h_separation", 8)
	policy_grid.add_theme_constant_override("v_separation", 4)
	policy_grid.visible = policy_expanded
	policy_header.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			policy_grid.visible = not policy_grid.visible
			_policy_overrides_expanded[ship] = policy_grid.visible
			policy_header.text = ("▾ " if policy_grid.visible else "▸ ") + "Policy Overrides"
	)

	var policy_defs := [
		{
			"label": "Thrust",
			"names": CompanyPolicy.THRUST_POLICY_NAMES,
			"get": func() -> int: return ship.thrust_policy_override,
			"set": func(v: int) -> void: ship.thrust_policy_override = v,
		},
		{
			"label": "Supply",
			"names": CompanyPolicy.SUPPLY_POLICY_NAMES,
			"get": func() -> int: return ship.supply_policy_override,
			"set": func(v: int) -> void: ship.supply_policy_override = v,
		},
		{
			"label": "Pickup Threshold",
			"names": CompanyPolicy.COLLECTION_POLICY_NAMES,
			"get": func() -> int: return ship.collection_policy_override,
			"set": func(v: int) -> void: ship.collection_policy_override = v,
		},
		{
			"label": "Encounter",
			"names": CompanyPolicy.ENCOUNTER_POLICY_NAMES,
			"get": func() -> int: return ship.encounter_policy_override,
			"set": func(v: int) -> void: ship.encounter_policy_override = v,
		},
		{
			"label": "Repair",
			"names": CompanyPolicy.REPAIR_POLICY_NAMES,
			"get": func() -> int: return ship.repair_policy_override,
			"set": func(v: int) -> void: ship.repair_policy_override = v,
		},
		{
			"label": "Mining Threshold",
			"names": CompanyPolicy.CARGO_POLICY_NAMES,
			"get": func() -> int: return ship.cargo_policy_override,
			"set": func(v: int) -> void: ship.cargo_policy_override = v,
		},
		{
			"label": "Equipment Maintenance",
			"names": CompanyPolicy.MAINTENANCE_POLICY_NAMES,
			"get": func() -> int: return ship.maintenance_policy_override,
			"set": func(v: int) -> void: ship.maintenance_policy_override = v,
		},
		{
			"label": "Trading",
			"names": CompanyPolicy.TRADING_POLICY_NAMES,
			"get": func() -> int: return ship.trading_policy_override,
			"set": func(v: int) -> void: ship.trading_policy_override = v,
		},
		{
			"label": "Crew Morale",
			"names": CompanyPolicy.MORALE_POLICY_NAMES,
			"get": func() -> int: return ship.morale_policy_override,
			"set": func(v: int) -> void: ship.morale_policy_override = v,
		},
		{
			"label": "Automation",
			"names": CompanyPolicy.AUTOMATION_POLICY_NAMES,
			"get": func() -> int: return ship.automation_policy_override,
			"set": func(v: int) -> void: ship.automation_policy_override = v,
		},
	]

	for pd in policy_defs:
		var lbl := _lbl()
		lbl.text = pd["label"] + ":"
		lbl.add_theme_font_size_override("font_size", 14)
		lbl.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		policy_grid.add_child(lbl)

		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(0, 32)
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		opt.add_theme_font_size_override("font_size", 14)
		opt.add_item("Company Default")
		opt.set_item_metadata(0, -1)
		var enum_names: Dictionary = pd["names"]
		for i in enum_names.size():
			opt.add_item(enum_names[i])
			opt.set_item_metadata(i + 1, i)
		var current_override: int = pd["get"].call()
		opt.selected = 0 if current_override < 0 else current_override + 1
		var set_fn: Callable = pd["set"]
		opt.item_selected.connect(func(idx: int) -> void:
			set_fn.call(opt.get_item_metadata(idx))
		)
		policy_grid.add_child(opt)

	vbox.add_child(policy_grid)

## Build crew section (collapsible)
func _build_crew_section(vbox: VBoxContainer, ship: Ship) -> void:
	var ship_crew: Array[Worker] = ship.crew.duplicate()

	var crew_panel := VBoxContainer.new()
	crew_panel.add_theme_constant_override("separation", 3)
	crew_panel.visible = _crew_expanded.get(ship, false)

	for w in ship_crew:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)

		var name_lbl := _lbl()
		name_lbl.text = w.worker_name
		name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_lbl.clip_text = true
		name_lbl.add_theme_font_size_override("font_size", 16)
		row.add_child(name_lbl)

		var skills_lbl := _lbl()
		var parts: Array[String] = []
		if w.pilot_skill >= 0.05:
			parts.append("P%.2f" % w.pilot_skill)
		if w.engineer_skill >= 0.05:
			parts.append("E%.2f" % w.engineer_skill)
		if w.mining_skill >= 0.05:
			parts.append("M%.2f" % w.mining_skill)
		skills_lbl.text = " ".join(parts) if parts.size() > 0 else "—"
		skills_lbl.add_theme_font_size_override("font_size", 16)
		skills_lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 1.0))
		row.add_child(skills_lbl)

		var fatigue_lbl := _lbl()
		fatigue_lbl.text = "Fatigue %d%%" % int(w.fatigue)
		fatigue_lbl.add_theme_font_size_override("font_size", 14)
		if w.fatigue >= 80.0:
			fatigue_lbl.add_theme_color_override("font_color", Color(0.9, 0.4, 0.2))
		else:
			fatigue_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		row.add_child(fatigue_lbl)

		crew_panel.add_child(row)

	if ship_crew.is_empty():
		var empty_lbl := _lbl()
		empty_lbl.text = "No crew assigned"
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		empty_lbl.add_theme_font_size_override("font_size", 16)
		crew_panel.add_child(empty_lbl)

	var crew_btn := Button.new()
	crew_btn.text = "Crew (%d)" % ship_crew.size()
	crew_btn.custom_minimum_size = Vector2(0, 36)
	crew_btn.pressed.connect(func() -> void:
		crew_panel.visible = not crew_panel.visible
		_crew_expanded[ship] = crew_panel.visible
	)
	vbox.add_child(crew_btn)
	vbox.add_child(crew_panel)

## Helper functions

func _get_wrench_texture(ship: Ship) -> Texture2D:
	if ship.engine_condition >= 90.0:
		return null
	if ship.engine_condition >= 50.0:
		return load("res://assets/icons/wrench_yellow.png")
	else:
		return load("res://assets/icons/wrench_red.png")

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

func _build_details_text(ship: Ship) -> String:
	var engine_str := ""
	if ship.engine_condition < 100.0:
		engine_str = " | Eng: %d%%" % int(ship.engine_condition)
	return "Thrust: %.1fg (%.0f%%) | Cargo: %.0f/%.0ft\nFuel: %.0f/%.0f | Equip: %d/%d (%.2fx)%s" % [
		ship.get_effective_thrust(), ship.thrust_setting * 100.0, ship.get_cargo_total(), ship.get_effective_cargo_capacity(),
		ship.fuel, ship.get_effective_fuel_capacity(),
		ship.equipment.size(), ship.max_equipment_slots, ship.get_mining_multiplier(),
		engine_str,
	]

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

func _get_matching_contracts(ship: Ship, colony: Colony) -> Array[Contract]:
	var matches: Array[Contract] = []
	for contract in GameState.active_contracts:
		if contract.delivery_colony and contract.delivery_colony != colony:
			continue
		if ship.current_cargo.get(contract.ore_type, 0.0) > 0:
			matches.append(contract)
	return matches

func _add_contract_fulfillment_ui(container: VBoxContainer, ship: Ship, contract: Contract, colony: Colony) -> void:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

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
		contract_price_per_ton, price_comparison, TimeScale.format_time(contract.deadline_ticks),
		ship_has, can_deliver
	]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)

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

	fulfill_btn.custom_minimum_size = Vector2(0, 44)
	fulfill_btn.pressed.connect(func() -> void:
		GameState.fulfill_contract_partial(contract, ship, can_deliver)
		needs_rebuild.emit()
	)
	btn_row.add_child(fulfill_btn)

	vbox.add_child(btn_row)
	panel.add_child(vbox)
	container.add_child(panel)

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
