extends MarginContainer

@onready var ships_list: VBoxContainer = %ShipsList

func _ready() -> void:
	EventBus.upgrade_purchased.connect(func(_u: ShipUpgrade) -> void: _refresh_all())
	EventBus.upgrade_installed.connect(func(_s: Ship, _u: ShipUpgrade) -> void: _refresh_all())
	EventBus.mission_started.connect(func(_m: Mission) -> void: _refresh_all())
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _refresh_all())
	EventBus.money_changed.connect(func(_m: int) -> void: _refresh_all())
	_refresh_all()

func _refresh_all() -> void:
	for child in ships_list.get_children():
		child.queue_free()

	var title := Label.new()
	title.text = "SHIP OUTFITTING"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	ships_list.add_child(title)

	var sep1 := HSeparator.new()
	ships_list.add_child(sep1)

	# Show upgrade inventory
	if not GameState.upgrade_inventory.is_empty():
		var inv_header := Label.new()
		inv_header.text = "Upgrade Inventory (ready to install):"
		inv_header.add_theme_font_size_override("font_size", 18)
		inv_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		ships_list.add_child(inv_header)

		for upgrade in GameState.upgrade_inventory:
			var upgrade_row := HBoxContainer.new()
			upgrade_row.add_theme_constant_override("separation", 8)
			var upgrade_info := Label.new()
			upgrade_info.text = "%s - %s" % [upgrade.upgrade_name, upgrade.description]
			upgrade_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			upgrade_row.add_child(upgrade_info)

			# Install on docked ships
			for ship in GameState.get_docked_ships():
				var install_btn := Button.new()
				install_btn.text = "Install on %s" % ship.ship_name
				install_btn.custom_minimum_size = Vector2(0, 40)
				install_btn.pressed.connect(func() -> void:
					GameState.install_upgrade(ship, upgrade)
					_refresh_all()
				)
				upgrade_row.add_child(install_btn)

			ships_list.add_child(upgrade_row)

		var sep2 := HSeparator.new()
		ships_list.add_child(sep2)

	# Show each ship's current stats and upgrades
	for ship in GameState.ships:
		var ship_panel := PanelContainer.new()
		var ship_vbox := VBoxContainer.new()
		ship_vbox.add_theme_constant_override("separation", 8)

		# Ship header
		var ship_header := Label.new()
		ship_header.text = ship.ship_name
		ship_header.add_theme_font_size_override("font_size", 20)
		ship_header.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
		ship_vbox.add_child(ship_header)

		# Status
		var status_text := ""
		if ship.is_docked:
			status_text = "Docked at Earth (can install upgrades)"
		elif ship.is_derelict:
			status_text = "DERELICT"
		else:
			status_text = "In space (dock to install upgrades)"

		var status_label := Label.new()
		status_label.text = status_text
		status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		ship_vbox.add_child(status_label)

		var stats_sep := HSeparator.new()
		ship_vbox.add_child(stats_sep)

		# Base stats
		var base_stats := Label.new()
		base_stats.text = "BASE STATS:"
		base_stats.add_theme_font_size_override("font_size", 14)
		base_stats.add_theme_color_override("font_color", Color(0.6, 0.8, 1.0))
		ship_vbox.add_child(base_stats)

		var stats_grid := GridContainer.new()
		stats_grid.columns = 2
		stats_grid.add_theme_constant_override("h_separation", 16)
		stats_grid.add_theme_constant_override("v_separation", 4)

		_add_stat_row(stats_grid, "Thrust:", "%.2fg" % ship.thrust_g, ship.get_effective_thrust())
		_add_stat_row(stats_grid, "Fuel Capacity:", "%.0f" % ship.fuel_capacity, ship.get_effective_fuel_capacity())
		_add_stat_row(stats_grid, "Cargo Capacity:", "%.0ft" % ship.cargo_capacity, ship.get_effective_cargo_capacity())
		_add_stat_row(stats_grid, "Base Mass:", "%.0ft" % (ship.base_mass if ship.base_mass > 0 else ship.cargo_capacity * 2.0), ship.get_base_mass())

		ship_vbox.add_child(stats_grid)

		# Installed upgrades
		var upgrades_sep := HSeparator.new()
		ship_vbox.add_child(upgrades_sep)

		var upgrades_header := Label.new()
		upgrades_header.text = "INSTALLED UPGRADES:"
		upgrades_header.add_theme_font_size_override("font_size", 14)
		upgrades_header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
		ship_vbox.add_child(upgrades_header)

		if ship.upgrades.is_empty():
			var no_upgrades := Label.new()
			no_upgrades.text = "No upgrades installed"
			no_upgrades.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			ship_vbox.add_child(no_upgrades)
		else:
			for upgrade in ship.upgrades:
				var upgrade_label := Label.new()
				upgrade_label.text = "• %s - %s" % [upgrade.upgrade_name, upgrade.description]
				upgrade_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
				ship_vbox.add_child(upgrade_label)

		ship_panel.add_child(ship_vbox)
		ships_list.add_child(ship_panel)

	# Available upgrades to purchase
	var purchase_sep := HSeparator.new()
	ships_list.add_child(purchase_sep)

	var purchase_header := Label.new()
	purchase_header.text = "AVAILABLE UPGRADES TO PURCHASE"
	purchase_header.add_theme_font_size_override("font_size", 20)
	purchase_header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	ships_list.add_child(purchase_header)

	for entry in UpgradeCatalog.get_available_upgrades():
		var buy_row := HBoxContainer.new()
		buy_row.add_theme_constant_override("separation", 8)
		var info := Label.new()
		info.text = "%s - %s ($%s)" % [
			entry["name"], entry["description"], _format_number(entry["cost"])
		]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buy_row.add_child(info)

		var btn := Button.new()
		btn.text = "Buy $%s" % _format_number(entry["cost"])
		btn.custom_minimum_size = Vector2(0, 44)
		btn.disabled = GameState.money < entry["cost"]
		btn.pressed.connect(func() -> void:
			if GameState.purchase_upgrade(entry):
				_refresh_all()
		)
		buy_row.add_child(btn)
		ships_list.add_child(buy_row)

func _add_stat_row(grid: GridContainer, label_text: String, base_value: String, effective_value: float) -> void:
	var label := Label.new()
	label.text = label_text
	label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	grid.add_child(label)

	var value := Label.new()
	# Show effective value if different from base
	if str(effective_value) != base_value:
		value.text = "%s → %.1f" % [base_value, effective_value]
		value.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	else:
		value.text = base_value
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
