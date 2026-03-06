extends VBoxContainer
## SpecialActionsPanel Component
## Handles partnership selection, station jobs, fleet rescue, and supply shop

signal partnership_created(ship1: Ship, ship2: Ship)
signal station_confirmed(ship: Ship, colony: Colony, jobs: Array[String])
signal rescue_confirmed(ferry_ship: Ship, target_ship: Ship, food: float, parts: float)
signal supplies_purchased(ship: Ship, purchases: Dictionary)
signal action_cancelled()

var _game_state: Node = null  # GameState reference
var _selected_ship: Ship = null

# Station jobs state
var _station_job_checks: Dictionary = {}  # job_name -> CheckBox
var _station_job_order: Array[String] = []  # Current ordering

const STATION_JOBS: Array[Dictionary] = [
	{"key": "mining", "label": "Mining", "desc": "Mine nearby asteroids"},
	{"key": "trading", "label": "Trading", "desc": "Sell ore at local market"},
	{"key": "repair", "label": "Repair Assist", "desc": "Repair nearby damaged ships"},
	{"key": "parts_delivery", "label": "Parts Delivery", "desc": "Deliver repair parts to remote ships"},
	{"key": "provisioning", "label": "Provisioning", "desc": "Supply deployed crews with food"},
	{"key": "crew_ferry", "label": "Crew Rotation", "desc": "Rotate fatigued workers"},
	{"key": "patrol", "label": "Patrol", "desc": "Patrol nearby rocks"},
]

@onready var content_container: VBoxContainer = %ContentContainer

func _ready() -> void:
	_game_state = get_node("/root/GameState")

func show_partnership_selection(ship: Ship) -> void:
	_selected_ship = ship

	# Clear previous content
	for child in content_container.get_children():
		child.queue_free()

	var title := _lbl()
	title.text = "Select Partner Ship"
	title.add_theme_font_size_override("font_size", 22)
	content_container.add_child(title)

	var desc := _lbl()
	desc.text = "Choose a ship to partner with %s:" % ship.ship_name
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_container.add_child(desc)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 300)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	content_container.add_child(scroll)

	# List eligible ships
	var found_eligible := false
	for other in _game_state.ships:
		if other == ship:
			continue

		var check: Dictionary = ship.can_partner_with(other)
		if not check["valid"]:
			continue

		found_eligible = true
		var btn := Button.new()
		btn.text = "%s (Cargo: %.0f t, Fuel: %.0f)" % [other.ship_name, other.cargo_capacity, other.fuel]
		btn.add_theme_font_size_override("font_size", 14)
		btn.custom_minimum_size = Vector2(0, 40)
		btn.flat = true
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.pressed.connect(func() -> void:
			_game_state.create_partnership(ship, other)
			partnership_created.emit(ship, other)
		)
		vbox.add_child(btn)

	if not found_eligible:
		var no_ships := _lbl()
		no_ships.text = "No eligible ships nearby"
		no_ships.add_theme_font_size_override("font_size", 14)
		no_ships.add_theme_color_override("font_color", Color(0.8, 0.6, 0.3))
		vbox.add_child(no_ships)

	# Add cancel button
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content_container.add_child(button_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 44)
	cancel_btn.pressed.connect(func() -> void:
		action_cancelled.emit()
	)
	button_row.add_child(cancel_btn)

func show_station_jobs(ship: Ship) -> void:
	_selected_ship = ship

	# Clear previous content
	for child in content_container.get_children():
		child.queue_free()

	var colony: Colony = ship.docked_at_colony if ship.docked_at_colony else ship.station_colony
	var colony_name: String = colony.colony_name if colony else "Unknown"

	var title := _lbl()
	title.text = "STATION AT %s" % colony_name.to_upper()
	title.add_theme_font_size_override("font_size", 26)
	content_container.add_child(title)

	var desc := _lbl()
	desc.text = "Select jobs and priority order. Ship will autonomously perform the highest-priority actionable job."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	content_container.add_child(desc)

	# Initialize job order from existing or defaults
	_station_job_order.clear()
	_station_job_checks.clear()

	# Use existing jobs if editing, otherwise start with mining + trading
	var existing_jobs: Array[String] = ship.station_jobs if ship.is_stationed else []
	var all_job_keys: Array[String] = []
	for job_def in STATION_JOBS:
		all_job_keys.append(job_def["key"])

	# Order: existing enabled jobs first, then remaining in default order
	for job_key in existing_jobs:
		if job_key in all_job_keys:
			_station_job_order.append(job_key)
	for job_key in all_job_keys:
		if job_key not in _station_job_order:
			_station_job_order.append(job_key)

	# Build job list UI
	var jobs_container := VBoxContainer.new()
	jobs_container.name = "JobsContainer"
	jobs_container.add_theme_constant_override("separation", 4)
	content_container.add_child(jobs_container)

	_rebuild_station_job_list(jobs_container, existing_jobs)

	# Buttons
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 8)
	content_container.add_child(button_row)

	var confirm_btn := Button.new()
	confirm_btn.text = "Confirm Station" if not ship.is_stationed else "Update Jobs"
	confirm_btn.custom_minimum_size = Vector2(0, 44)
	confirm_btn.pressed.connect(func() -> void:
		var selected_jobs: Array[String] = []
		for job_key in _station_job_order:
			if _station_job_checks.has(job_key):
				var cb: CheckBox = _station_job_checks[job_key]
				if cb.button_pressed:
					selected_jobs.append(job_key)
		if selected_jobs.is_empty():
			return  # Must select at least one job
		station_confirmed.emit(ship, colony, selected_jobs)
	)
	button_row.add_child(confirm_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 44)
	cancel_btn.pressed.connect(func() -> void:
		action_cancelled.emit()
	)
	button_row.add_child(cancel_btn)

func _rebuild_station_job_list(container: VBoxContainer, enabled_jobs: Array[String]) -> void:
	# Clear previous children
	for child in container.get_children():
		child.queue_free()

	var priority_label := _lbl()
	priority_label.text = "Priority (top = highest):"
	priority_label.add_theme_font_size_override("font_size", 18)
	container.add_child(priority_label)

	for i in range(_station_job_order.size()):
		var job_key: String = _station_job_order[i]
		var job_def: Dictionary = {}
		for jd in STATION_JOBS:
			if jd["key"] == job_key:
				job_def = jd
				break

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		# Priority number
		var num_label := _lbl()
		num_label.text = "%d." % (i + 1)
		num_label.custom_minimum_size = Vector2(24, 0)
		num_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		row.add_child(num_label)

		# Checkbox
		var cb := CheckBox.new()
		cb.text = "%s — %s" % [job_def.get("label", job_key), job_def.get("desc", "")]
		cb.button_pressed = job_key in enabled_jobs or (enabled_jobs.is_empty() and job_key in ["mining", "trading"])
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cb)
		_station_job_checks[job_key] = cb

		# Move up button
		if i > 0:
			var up_btn := Button.new()
			up_btn.text = "^"
			up_btn.custom_minimum_size = Vector2(36, 36)
			var idx: int = i
			up_btn.pressed.connect(func() -> void:
				_station_move_job(idx, -1, container, enabled_jobs)
			)
			row.add_child(up_btn)
		else:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(36, 36)
			row.add_child(spacer)

		# Move down button
		if i < _station_job_order.size() - 1:
			var down_btn := Button.new()
			down_btn.text = "v"
			down_btn.custom_minimum_size = Vector2(36, 36)
			var idx: int = i
			down_btn.pressed.connect(func() -> void:
				_station_move_job(idx, 1, container, enabled_jobs)
			)
			row.add_child(down_btn)
		else:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(36, 36)
			row.add_child(spacer)

		container.add_child(row)

func _station_move_job(idx: int, direction: int, container: VBoxContainer, enabled_jobs: Array[String]) -> void:
	var new_idx: int = idx + direction
	if new_idx < 0 or new_idx >= _station_job_order.size():
		return
	# Capture current check states before rebuild
	var current_enabled: Array[String] = []
	for job_key in _station_job_order:
		if _station_job_checks.has(job_key):
			var cb: CheckBox = _station_job_checks[job_key]
			if cb.button_pressed:
				current_enabled.append(job_key)
	# Swap
	var tmp: String = _station_job_order[idx]
	_station_job_order[idx] = _station_job_order[new_idx]
	_station_job_order[new_idx] = tmp
	_station_job_checks.clear()
	_rebuild_station_job_list(container, current_enabled)

func show_fleet_rescue_dispatch(ferry_ship: Ship, target_ship: Ship) -> void:
	_selected_ship = ferry_ship

	# Clear previous content
	for child in content_container.get_children():
		child.queue_free()

	var title := _lbl()
	title.text = "RESCUE: %s" % target_ship.ship_name
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))
	content_container.add_child(title)

	var dist: float = ferry_ship.position_au.distance_to(target_ship.position_au)
	var transit_t: float = Brachistochrone.transit_time(dist, ferry_ship.get_effective_thrust())
	var fuel_rt: float = ferry_ship.calc_fuel_for_distance(dist) * 2.0

	var info := _lbl()
	var reason_str: String = "out of fuel" if target_ship.derelict_reason == "out_of_fuel" else "breakdown"
	info.text = "Target: %s (%s)\nTransit: %s  |  Fuel round-trip: %.0ft / %.0ft available" % [
		target_ship.ship_name, reason_str,
		TimeScale.format_time(transit_t), fuel_rt, ferry_ship.fuel
	]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	content_container.add_child(info)

	# Supplies to send
	var food_on_ferry: float = ferry_ship.supplies.get("food", 0.0)
	var parts_on_ferry: float = ferry_ship.supplies.get("repair_parts", 0.0)
	var target_crew_est: int = maxi(target_ship.crew.size(), 1)

	var sup_label := _lbl()
	sup_label.text = "Ferry supplies available: Food %.0f kg, Repair Parts %.0f units" % [food_on_ferry, parts_on_ferry]
	sup_label.add_theme_color_override("font_color", Color(0.4, 0.85, 0.55))
	sup_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_container.add_child(sup_label)

	# SpinBoxes for supply amounts to send
	var sup_grid := GridContainer.new()
	sup_grid.columns = 3
	sup_grid.add_theme_constant_override("h_separation", 8)

	var food_lbl := _lbl()
	food_lbl.text = "Food to send:"
	sup_grid.add_child(food_lbl)
	var food_spin := SpinBox.new()
	food_spin.min_value = 0.0
	food_spin.max_value = food_on_ferry
	food_spin.step = 1.0
	food_spin.value = minf(food_on_ferry, target_crew_est * 30 * 2.8)  # ~30 days default (2.8 kg/crew/day)
	food_spin.custom_minimum_size = Vector2(100, 0)
	sup_grid.add_child(food_spin)
	var food_est_lbl := _lbl()
	food_est_lbl.add_theme_font_size_override("font_size", 16)
	food_est_lbl.add_theme_color_override("font_color", Color(0.5, 0.8, 0.5))
	food_spin.value_changed.connect(func(v: float) -> void:
		var days_f: float = v / (target_crew_est * 2.8) if target_crew_est > 0 else 0.0
		food_est_lbl.text = "~%.0fd for %d crew" % [days_f, target_crew_est]
	)
	var init_food_days: float = food_spin.value / (target_crew_est * 2.8) if target_crew_est > 0 else 0.0
	food_est_lbl.text = "~%.0fd for %d crew" % [init_food_days, target_crew_est]
	sup_grid.add_child(food_est_lbl)

	var parts_lbl := _lbl()
	parts_lbl.text = "Parts to send:"
	sup_grid.add_child(parts_lbl)
	var parts_spin := SpinBox.new()
	parts_spin.min_value = 0.0
	parts_spin.max_value = parts_on_ferry
	parts_spin.step = 1.0
	parts_spin.value = minf(parts_on_ferry, 10.0)
	parts_spin.custom_minimum_size = Vector2(100, 0)
	sup_grid.add_child(parts_spin)
	sup_grid.add_child(_lbl())  # spacer

	content_container.add_child(sup_grid)

	var crew_note := _lbl()
	crew_note.text = "The ferry's crew will fly out together. On arrival, as many as possible will stay on %s (loyalty -20) and both ships will return for more crew." % target_ship.ship_name
	crew_note.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
	crew_note.add_theme_font_size_override("font_size", 16)
	crew_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_container.add_child(crew_note)

	var warning_lbl := _lbl()
	warning_lbl.name = "WarningLabel"
	warning_lbl.add_theme_color_override("font_color", Color(0.8, 0.6, 0.3))
	warning_lbl.add_theme_font_size_override("font_size", 16)
	warning_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content_container.add_child(warning_lbl)

	# Buttons
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 8)
	content_container.add_child(button_row)

	var rescue_btn := Button.new()
	rescue_btn.text = "Dispatch Rescue"
	rescue_btn.custom_minimum_size = Vector2(0, 44)
	rescue_btn.add_theme_color_override("font_color", Color(0.9, 0.5, 0.2))
	rescue_btn.pressed.connect(func() -> void:
		var result = MissionManager.start_fleet_rescue(
			ferry_ship, target_ship, [],
			food_spin.value, parts_spin.value
		)
		if result != null:
			rescue_confirmed.emit(ferry_ship, target_ship, food_spin.value, parts_spin.value)
		else:
			warning_lbl.text = "⚠ Need at least 2 crew for a rescue (1 stays on target, 1 flies back)."
			warning_lbl.add_theme_color_override("font_color", Color(0.9, 0.3, 0.2))
	)
	button_row.add_child(rescue_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 44)
	cancel_btn.pressed.connect(func() -> void:
		action_cancelled.emit()
	)
	button_row.add_child(cancel_btn)

func show_supply_shop(ship: Ship) -> void:
	_selected_ship = ship

	# Clear previous content
	for child in content_container.get_children():
		child.queue_free()

	var title := _lbl()
	title.text = "BUY SUPPLIES"
	title.add_theme_font_size_override("font_size", 26)
	content_container.add_child(title)

	var desc := _lbl()
	desc.text = "Purchase supplies for %s. Supplies share cargo capacity with ore." % ship.ship_name
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	content_container.add_child(desc)

	var capacity_label := _lbl()
	var cargo_used: float = ship.get_cargo_total()
	capacity_label.text = "Cargo: %.1f / %.1f tons" % [cargo_used, ship.cargo_capacity]
	capacity_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
	content_container.add_child(capacity_label)

	var money_label := _lbl()
	money_label.text = "Funds: $%s" % _format_number(_game_state.money)
	money_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	content_container.add_child(money_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	content_container.add_child(spacer)

	# Supply spinboxes
	var spinboxes: Dictionary = {}
	for supply_type in SupplyData.SUPPLY_INFO:
		var info: Dictionary = SupplyData.SUPPLY_INFO[supply_type]
		var key: String = info["key"]
		var supply_name: String = info["name"]
		var unit_label: String = info.get("unit_label", "unit")
		var cost: int = info["cost_per_unit"]
		var mass: float = info["mass_per_unit"]
		var current: float = ship.supplies.get(key, 0.0)

		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)

		var header := _lbl()
		header.text = "%s — $%s/%s, %.3ft/%s" % [supply_name, _format_number(cost), unit_label, mass, unit_label]
		header.add_theme_font_size_override("font_size", 18)
		row.add_child(header)

		if current > 0:
			var cur_label := _lbl()
			cur_label.text = "  On board: %.1f %ss" % [current, unit_label]
			cur_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5))
			cur_label.add_theme_font_size_override("font_size", 17)
			row.add_child(cur_label)

		var spin_row := HBoxContainer.new()
		spin_row.add_theme_constant_override("separation", 8)

		var qty_label := _lbl()
		qty_label.text = "Buy:"
		spin_row.add_child(qty_label)

		var spinbox := SpinBox.new()
		spinbox.min_value = 0
		spinbox.max_value = 999
		spinbox.step = 1
		spinbox.value = 0
		spinbox.custom_minimum_size = Vector2(120, 40)
		spin_row.add_child(spinbox)
		spinboxes[key] = spinbox

		var cost_preview := _lbl()
		cost_preview.text = "= $0"
		cost_preview.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		spin_row.add_child(cost_preview)

		spinbox.value_changed.connect(func(val: float) -> void:
			cost_preview.text = "= $%s" % _format_number(int(val * cost))
		)

		row.add_child(spin_row)
		content_container.add_child(row)

	# Buttons
	var button_row := HBoxContainer.new()
	button_row.alignment = BoxContainer.ALIGNMENT_CENTER
	button_row.add_theme_constant_override("separation", 8)
	content_container.add_child(button_row)

	var purchase_btn := Button.new()
	purchase_btn.text = "Purchase"
	purchase_btn.custom_minimum_size = Vector2(0, 44)
	purchase_btn.pressed.connect(func() -> void:
		var purchases: Dictionary = {}
		for key in spinboxes:
			var sb: SpinBox = spinboxes[key]
			var qty: int = int(sb.value)
			if qty > 0:
				purchases[key] = float(qty)
		if not purchases.is_empty():
			supplies_purchased.emit(ship, purchases)
	)
	button_row.add_child(purchase_btn)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel"
	cancel_btn.custom_minimum_size = Vector2(0, 44)
	cancel_btn.pressed.connect(func() -> void:
		action_cancelled.emit()
	)
	button_row.add_child(cancel_btn)

func _format_number(n: int) -> String:
	var s: String = str(abs(n))
	var result := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	if n < 0:
		result = "-" + result
	return result

func _lbl() -> Label:
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 14)
	return label
