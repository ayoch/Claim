extends MarginContainer

@onready var sell_list: VBoxContainer = %SellList
@onready var equip_list: VBoxContainer = %EquipList

func _ready() -> void:
	EventBus.resource_changed.connect(func(_o: ResourceTypes.OreType, _a: float) -> void: _refresh_sell())
	EventBus.money_changed.connect(func(_m: int) -> void: _refresh_equip())
	EventBus.equipment_purchased.connect(func(_e: Equipment) -> void: _refresh_equip())
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
	for entry in MarketData.EQUIPMENT_CATALOG:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var info := Label.new()
		info.text = "%s  |  %.2fx mining  |  $%s" % [
			entry["name"], entry["mining_bonus"], entry["cost"]
		]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info)

		var btn := Button.new()
		btn.text = "Buy"
		btn.custom_minimum_size = Vector2(0, 44)
		btn.disabled = GameState.money < entry["cost"]
		btn.pressed.connect(_buy_equipment.bind(entry))
		hbox.add_child(btn)

		equip_list.add_child(hbox)

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

func _buy_equipment(entry: Dictionary) -> void:
	GameState.purchase_equipment(entry)
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
