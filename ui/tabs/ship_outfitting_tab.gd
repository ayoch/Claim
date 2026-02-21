extends MarginContainer

static func _free_children(container: Node) -> void:
	for i in range(container.get_child_count() - 1, -1, -1):
		container.get_child(i).queue_free()

@onready var ships_list: VBoxContainer = %ShipsList

var _dirty: bool = false
var _last_refresh_msec: int = 0
const REFRESH_INTERVAL_MSEC: int = 200
var _refresh_queued: bool = false  # Guard against stacked _queue_refresh()

func _ready() -> void:
	EventBus.upgrade_purchased.connect(func(_u: ShipUpgrade) -> void: _dirty = true)
	EventBus.upgrade_installed.connect(func(_s: Ship, _u: ShipUpgrade) -> void: _dirty = true)
	EventBus.mission_started.connect(func(_m: Mission) -> void: _dirty = true)
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _dirty = true)
	EventBus.money_changed.connect(func(_m: int) -> void: _dirty = true)
	EventBus.mining_unit_purchased.connect(func(_u: MiningUnit) -> void: _dirty = true)
	EventBus.mining_unit_deployed.connect(func(_u: MiningUnit, _a: AsteroidData) -> void: _dirty = true)
	EventBus.mining_unit_recalled.connect(func(_u: MiningUnit) -> void: _dirty = true)
	EventBus.tick.connect(_on_tick)
	_refresh_all()

func _on_tick(_dt: float) -> void:
	if not _dirty:
		return
	var now := Time.get_ticks_msec()
	if now - _last_refresh_msec < REFRESH_INTERVAL_MSEC:
		return
	_last_refresh_msec = now
	_dirty = false
	_refresh_all()

func _queue_refresh() -> void:
	if not _refresh_queued:
		_refresh_queued = true
		call_deferred("_refresh_all")

func _refresh_all() -> void:
	_refresh_queued = false
	_free_children(ships_list)

	var title := Label.new()
	title.text = "SHIP OUTFITTING"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	ships_list.add_child(title)

	var sep1 := HSeparator.new()
	ships_list.add_child(sep1)

	# Show upgrade inventory
	if not GameState.upgrade_inventory.is_empty():
		var inv_header := Label.new()
		inv_header.text = "Upgrade Inventory (ready to install):"
		inv_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inv_header.clip_text = true
		inv_header.add_theme_font_size_override("font_size", 18)
		inv_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		ships_list.add_child(inv_header)

		for upgrade in GameState.upgrade_inventory:
			var upgrade_row := HFlowContainer.new()
			upgrade_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			upgrade_row.add_theme_constant_override("h_separation", 8)
			var upgrade_info := Label.new()
			upgrade_info.text = "%s - %s" % [upgrade.upgrade_name, upgrade.description]
			upgrade_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			upgrade_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			upgrade_row.add_child(upgrade_info)

			# Install on ships with service access (Earth or large colonies)
			for ship in GameState.get_docked_ships():
				if not ship.can_access_services():
					continue  # Skip ships at colonies without services
				var install_btn := Button.new()
				install_btn.text = "Install on %s" % ship.ship_name
				install_btn.custom_minimum_size = Vector2(0, 40)
				install_btn.pressed.connect(func() -> void:
					GameState.install_upgrade(ship, upgrade)
					_queue_refresh()
				)
				upgrade_row.add_child(install_btn)

			ships_list.add_child(upgrade_row)

		var sep2 := HSeparator.new()
		ships_list.add_child(sep2)

	# Show each ship's current stats and upgrades
	for ship in GameState.ships:
		var ship_panel := PanelContainer.new()
		ship_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var ship_vbox := VBoxContainer.new()
		ship_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ship_vbox.add_theme_constant_override("separation", 8)

		# Ship header
		var ship_header := Label.new()
		ship_header.text = ship.ship_name
		ship_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ship_header.clip_text = true
		ship_header.add_theme_font_size_override("font_size", 20)
		ship_header.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
		ship_vbox.add_child(ship_header)

		# Status
		var status_text := ""
		if ship.is_docked:
			var location := "Earth"
			if ship.docked_at_colony != null:
				location = ship.docked_at_colony.colony_name
			if ship.can_access_services():
				status_text = "Docked at %s (services available)" % location
			else:
				status_text = "Docked at %s (no services)" % location
		elif ship.is_derelict:
			status_text = "DERELICT"
		else:
			status_text = "In space (dock at Earth or large colony for services)"

		var status_label := Label.new()
		status_label.text = status_text
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_label.clip_text = true
		status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		ship_vbox.add_child(status_label)

		var stats_sep := HSeparator.new()
		ship_vbox.add_child(stats_sep)

		# Base stats
		var base_stats := Label.new()
		base_stats.text = "BASE STATS:"
		base_stats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		base_stats.clip_text = true
		base_stats.add_theme_font_size_override("font_size", 14)
		base_stats.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		ship_vbox.add_child(base_stats)

		var stats_grid := GridContainer.new()
		stats_grid.columns = 2
		stats_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stats_grid.add_theme_constant_override("h_separation", 16)
		stats_grid.add_theme_constant_override("v_separation", 4)

		_add_stat_row(stats_grid, "Thrust:", "%.2fg max" % ship.max_thrust_g, ship.get_effective_thrust())
		_add_stat_row(stats_grid, "Fuel Capacity:", "%.0f" % ship.fuel_capacity, ship.get_effective_fuel_capacity())
		_add_stat_row(stats_grid, "Cargo Capacity:", "%.0ft" % ship.cargo_capacity, ship.get_effective_cargo_capacity())
		_add_stat_row(stats_grid, "Cargo Volume:", "%.0fm³" % ship.cargo_volume, ship.get_effective_cargo_volume())
		_add_stat_row(stats_grid, "Base Mass:", "%.0ft" % (ship.base_mass if ship.base_mass > 0 else ship.cargo_capacity * 2.0), ship.get_base_mass())

		ship_vbox.add_child(stats_grid)

		# Installed upgrades
		var upgrades_sep := HSeparator.new()
		ship_vbox.add_child(upgrades_sep)

		var upgrades_header := Label.new()
		upgrades_header.text = "INSTALLED UPGRADES:"
		upgrades_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		upgrades_header.clip_text = true
		upgrades_header.add_theme_font_size_override("font_size", 14)
		upgrades_header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
		ship_vbox.add_child(upgrades_header)

		if ship.upgrades.is_empty():
			var no_upgrades := Label.new()
			no_upgrades.text = "No upgrades installed"
			no_upgrades.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			no_upgrades.clip_text = true
			no_upgrades.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			ship_vbox.add_child(no_upgrades)
		else:
			for upgrade in ship.upgrades:
				var upgrade_label := Label.new()
				upgrade_label.text = "• %s - %s" % [upgrade.upgrade_name, upgrade.description]
				upgrade_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				upgrade_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				upgrade_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
				ship_vbox.add_child(upgrade_label)

		ship_panel.add_child(ship_vbox)
		ships_list.add_child(ship_panel)

	# Available upgrades to purchase
	var purchase_sep := HSeparator.new()
	ships_list.add_child(purchase_sep)

	var purchase_header := Label.new()
	purchase_header.text = "AVAILABLE UPGRADES TO PURCHASE"
	purchase_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	purchase_header.clip_text = true
	purchase_header.add_theme_font_size_override("font_size", 20)
	purchase_header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	ships_list.add_child(purchase_header)

	for entry in UpgradeCatalog.get_available_upgrades():
		var buy_row := HBoxContainer.new()
		buy_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buy_row.add_theme_constant_override("separation", 8)
		var info := Label.new()
		info.text = "%s - %s ($%s)" % [
			entry["name"], entry["description"], _format_number(entry["cost"])
		]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buy_row.add_child(info)

		var btn := Button.new()
		btn.text = "Buy $%s" % _format_number(entry["cost"])
		btn.custom_minimum_size = Vector2(0, 44)
		btn.disabled = GameState.money < entry["cost"]
		btn.pressed.connect(func() -> void:
			if GameState.purchase_upgrade(entry):
				_queue_refresh()
		)
		buy_row.add_child(btn)
		ships_list.add_child(buy_row)

	# Mining units section
	var mu_sep := HSeparator.new()
	ships_list.add_child(mu_sep)

	var mu_header := Label.new()
	mu_header.text = "MINING UNITS"
	mu_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mu_header.clip_text = true
	mu_header.add_theme_font_size_override("font_size", 20)
	mu_header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	ships_list.add_child(mu_header)

	# Show inventory
	if not GameState.mining_unit_inventory.is_empty():
		var inv_label := Label.new()
		inv_label.text = "In Inventory: %d unit(s)" % GameState.mining_unit_inventory.size()
		inv_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		inv_label.clip_text = true
		inv_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		ships_list.add_child(inv_label)
		for unit in GameState.mining_unit_inventory:
			var unit_row := HBoxContainer.new()
			unit_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			unit_row.add_theme_constant_override("separation", 8)
			var unit_info := Label.new()
			unit_info.text = "  • %s (%.1ft, %.1fx, %.0f/%.0f%% dur)" % [
				unit.unit_name, unit.mass, unit.mining_multiplier, unit.durability, unit.max_durability
			]
			unit_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			unit_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			unit_info.clip_text = true
			unit_row.add_child(unit_info)
			if unit.max_durability < 100.0:
				var rebuild_btn := Button.new()
				rebuild_btn.text = "Rebuild $%s" % _format_number(unit.rebuild_cost())
				rebuild_btn.custom_minimum_size = Vector2(0, 32)
				rebuild_btn.disabled = GameState.money < unit.rebuild_cost()
				rebuild_btn.pressed.connect(func() -> void:
					GameState.rebuild_mining_unit(unit)
					_queue_refresh()
				)
				unit_row.add_child(rebuild_btn)
			ships_list.add_child(unit_row)

	# Show deployed
	if not GameState.deployed_mining_units.is_empty():
		var dep_label := Label.new()
		dep_label.text = "Deployed: %d unit(s)" % GameState.deployed_mining_units.size()
		dep_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dep_label.clip_text = true
		dep_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
		ships_list.add_child(dep_label)
		for unit in GameState.deployed_mining_units:
			var worker_names: Array[String] = []
			for w in unit.assigned_workers:
				worker_names.append(w.worker_name)
			var unit_info := Label.new()
			unit_info.text = "  • %s at %s (%.0f%% durability, crew: %s)" % [
				unit.unit_name, unit.deployed_at_asteroid, unit.durability,
				", ".join(worker_names) if not worker_names.is_empty() else "none"
			]
			unit_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			unit_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			unit_info.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			ships_list.add_child(unit_info)

	# Purchase catalog
	var mu_buy_header := Label.new()
	mu_buy_header.text = "Available to Purchase:"
	mu_buy_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mu_buy_header.clip_text = true
	mu_buy_header.add_theme_font_size_override("font_size", 16)
	mu_buy_header.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	ships_list.add_child(mu_buy_header)

	for mu_entry in MiningUnitCatalog.get_available_units():
		var mu_row := HBoxContainer.new()
		mu_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mu_row.add_theme_constant_override("separation", 8)
		var mu_info := Label.new()
		mu_info.text = "%s - %s ($%s, %.1ft, %d workers)" % [
			mu_entry["name"], mu_entry["description"],
			_format_number(mu_entry["cost"]), mu_entry["mass"], mu_entry["workers_required"]
		]
		mu_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mu_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		mu_row.add_child(mu_info)

		var mu_btn := Button.new()
		mu_btn.text = "Buy $%s" % _format_number(mu_entry["cost"])
		mu_btn.custom_minimum_size = Vector2(0, 44)
		mu_btn.disabled = GameState.money < mu_entry["cost"]
		mu_btn.pressed.connect(func() -> void:
			if GameState.purchase_mining_unit(mu_entry):
				_queue_refresh()
		)
		mu_row.add_child(mu_btn)
		ships_list.add_child(mu_row)

func _add_stat_row(grid: GridContainer, label_text: String, base_value: String, effective_value: float) -> void:
	var label := Label.new()
	label.text = label_text
	label.clip_text = true
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	grid.add_child(label)

	var value := Label.new()
	# Show effective value if different from base
	if str(effective_value) != base_value:
		value.text = "%s → %.1f" % [base_value, effective_value]
		value.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	else:
		value.text = base_value
	value.clip_text = true
	value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(value)

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
