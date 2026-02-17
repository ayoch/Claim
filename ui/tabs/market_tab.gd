extends MarginContainer

@onready var sell_list: VBoxContainer = %SellList
@onready var equip_list: VBoxContainer = %EquipList

func _ready() -> void:
	EventBus.resource_changed.connect(func(_o: ResourceTypes.OreType, _a: float) -> void: _refresh_sell())
	EventBus.money_changed.connect(func(_m: int) -> void: _refresh_equip())
	EventBus.equipment_installed.connect(func(_s: Ship, _e: Equipment) -> void: _refresh_equip())
	EventBus.mission_started.connect(func(_m: Mission) -> void: _refresh_equip())
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _refresh_equip())
	_refresh_sell()
	_refresh_equip()

func _refresh_sell() -> void:
	for child in sell_list.get_children():
		child.queue_free()

	# "Sell All Ores" button at top
	var has_any := false
	var total_value := 0
	for ore_type in ResourceTypes.OreType.values():
		var amount: float = GameState.resources.get(ore_type, 0.0)
		if amount > 0.01:
			has_any = true
			total_value += int(amount * MarketData.get_ore_price(ore_type))

	var sell_all_btn := Button.new()
	sell_all_btn.text = "Sell All Ores ($%s)" % _format_number(total_value)
	sell_all_btn.custom_minimum_size = Vector2(0, 48)
	sell_all_btn.disabled = not has_any
	sell_all_btn.pressed.connect(_sell_all_ores)
	sell_list.add_child(sell_all_btn)

	var sep := HSeparator.new()
	sell_list.add_child(sep)

	# Per-ore rows
	for ore_type in ResourceTypes.OreType.values():
		var amount: float = GameState.resources.get(ore_type, 0.0)
		var price: int = MarketData.get_ore_price(ore_type)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var info := Label.new()
		info.text = "%s: %.1f t  @  $%d/t" % [ResourceTypes.get_ore_name(ore_type), amount, price]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info)

		var btn := Button.new()
		btn.text = "Sell"
		btn.custom_minimum_size = Vector2(0, 44)
		btn.disabled = amount < 0.01
		btn.pressed.connect(_sell_ore.bind(ore_type))
		hbox.add_child(btn)

		sell_list.add_child(hbox)

func _refresh_equip() -> void:
	for child in equip_list.get_children():
		child.queue_free()

	# Show each ship's equipment and available slots
	for ship in GameState.ships:
		var ship_panel := PanelContainer.new()
		var ship_vbox := VBoxContainer.new()
		ship_vbox.add_theme_constant_override("separation", 4)

		var ship_header := Label.new()
		ship_header.text = "%s  [%d/%d slots]" % [
			ship.ship_name, ship.equipment.size(), ship.max_equipment_slots
		]
		ship_header.add_theme_font_size_override("font_size", 18)
		ship_vbox.add_child(ship_header)

		# Show installed equipment with remove buttons
		if ship.equipment.is_empty():
			var empty_label := Label.new()
			empty_label.text = "No equipment installed"
			empty_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
			ship_vbox.add_child(empty_label)
		else:
			for equip in ship.equipment:
				var eq_row := HBoxContainer.new()
				eq_row.add_theme_constant_override("separation", 8)
				var eq_info := Label.new()
				eq_info.text = "%s (%.2fx mining)" % [equip.equipment_name, equip.mining_bonus]
				eq_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				eq_row.add_child(eq_info)

				if ship.is_docked:
					var remove_btn := Button.new()
					remove_btn.text = "Remove"
					remove_btn.custom_minimum_size = Vector2(0, 40)
					remove_btn.pressed.connect(_remove_equipment.bind(ship, equip))
					eq_row.add_child(remove_btn)

				ship_vbox.add_child(eq_row)

		# Buy buttons for available equipment (only if ship has open slots and is docked)
		var has_open_slot: bool = ship.equipment.size() < ship.max_equipment_slots
		if has_open_slot and ship.is_docked:
			var buy_label := Label.new()
			buy_label.text = "Buy & Install:"
			buy_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			ship_vbox.add_child(buy_label)

			for entry in MarketData.EQUIPMENT_CATALOG:
				var buy_row := HBoxContainer.new()
				buy_row.add_theme_constant_override("separation", 8)
				var info := Label.new()
				info.text = "%s  %.2fx  $%s" % [
					entry["name"], entry["mining_bonus"], _format_number(entry["cost"])
				]
				info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				buy_row.add_child(info)

				var btn := Button.new()
				btn.text = "Buy"
				btn.custom_minimum_size = Vector2(0, 40)
				btn.disabled = GameState.money < entry["cost"]
				btn.pressed.connect(_buy_and_install.bind(ship, entry))
				buy_row.add_child(btn)
				ship_vbox.add_child(buy_row)
		elif not has_open_slot:
			var full_label := Label.new()
			full_label.text = "All slots full - remove equipment to make room"
			full_label.add_theme_color_override("font_color", Color(0.8, 0.6, 0.2))
			full_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			ship_vbox.add_child(full_label)

		ship_panel.add_child(ship_vbox)
		equip_list.add_child(ship_panel)

func _sell_all_ores() -> void:
	var total_revenue := 0
	for ore_type in ResourceTypes.OreType.values():
		var amount: float = GameState.resources.get(ore_type, 0.0)
		if amount > 0.01:
			var price: int = MarketData.get_ore_price(ore_type)
			total_revenue += int(amount * price)
			GameState.remove_resource(ore_type, amount)
	if total_revenue > 0:
		GameState.money += total_revenue

func _sell_ore(ore_type: ResourceTypes.OreType) -> void:
	var amount: float = GameState.resources.get(ore_type, 0.0)
	if amount < 0.01:
		return
	var price: int = MarketData.get_ore_price(ore_type)
	var revenue: int = int(amount * price)
	GameState.remove_resource(ore_type, amount)
	GameState.money += revenue

func _buy_and_install(ship: Ship, entry: Dictionary) -> void:
	if GameState.money < entry.get("cost", 0):
		return
	if ship.equipment.size() >= ship.max_equipment_slots:
		return
	var equip := Equipment.from_catalog(entry)
	GameState.money -= equip.cost
	ship.equipment.append(equip)
	EventBus.equipment_installed.emit(ship, equip)
	_refresh_equip()

func _remove_equipment(ship: Ship, equip: Equipment) -> void:
	ship.equipment.erase(equip)
	_refresh_equip()

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
