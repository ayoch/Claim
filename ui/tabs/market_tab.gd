extends MarginContainer

@onready var sell_list: VBoxContainer = %SellList
@onready var equip_list: VBoxContainer = %EquipList
@onready var contracts_list: VBoxContainer = %ContractsList
@onready var colony_list: VBoxContainer = %ColonyList

func _ready() -> void:
	EventBus.resource_changed.connect(func(_o: ResourceTypes.OreType, _a: float) -> void: _refresh_sell())
	EventBus.money_changed.connect(func(_m: int) -> void: _refresh_equip())
	EventBus.equipment_installed.connect(func(_s: Ship, _e: Equipment) -> void: _refresh_equip())
	EventBus.equipment_repaired.connect(func(_s: Ship, _e: Equipment) -> void: _refresh_equip())
	EventBus.equipment_fabricated.connect(func(_e: Equipment) -> void: _refresh_equip())
	EventBus.mission_started.connect(func(_m: Mission) -> void: _refresh_equip(); _refresh_colony())
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _refresh_equip(); _refresh_colony())
	EventBus.market_event.connect(func(_o: ResourceTypes.OreType, _op: float, _np: float, _msg: String) -> void: _refresh_sell())
	EventBus.market_event_started.connect(func(_e: MarketEvent) -> void: _refresh_sell())
	EventBus.market_event_ended.connect(func(_e: MarketEvent) -> void: _refresh_sell())
	EventBus.contract_offered.connect(func(_c: Contract) -> void: _refresh_contracts())
	EventBus.contract_accepted.connect(func(_c: Contract) -> void: _refresh_contracts())
	EventBus.contract_completed.connect(func(_c: Contract) -> void: _refresh_contracts())
	EventBus.contract_expired.connect(func(_c: Contract) -> void: _refresh_contracts())
	EventBus.contract_failed.connect(func(_c: Contract) -> void: _refresh_contracts())
	EventBus.contract_progress.connect(func(_c: Contract, _a: float) -> void: _refresh_contracts())
	EventBus.trade_mission_started.connect(func(_tm: TradeMission) -> void: _refresh_colony())
	EventBus.trade_mission_completed.connect(func(_tm: TradeMission) -> void: _refresh_colony())
	_refresh_sell()
	_refresh_equip()
	_refresh_contracts()
	_refresh_colony()

# ═══════════════════════════════════════════════════
#  SELL ORE SECTION
# ═══════════════════════════════════════════════════

func _refresh_sell() -> void:
	for child in sell_list.get_children():
		child.queue_free()

	# Active Market Events
	if not GameState.active_market_events.is_empty():
		var events_header := Label.new()
		events_header.text = "ACTIVE MARKET EVENTS"
		events_header.add_theme_font_size_override("font_size", 16)
		events_header.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
		sell_list.add_child(events_header)

		for event in GameState.active_market_events:
			var event_panel := PanelContainer.new()
			var event_vbox := VBoxContainer.new()
			event_vbox.add_theme_constant_override("separation", 4)

			var event_title := Label.new()
			event_title.text = event.get_display_text()
			event_title.add_theme_font_size_override("font_size", 14)
			if event.price_multiplier > 1.0:
				event_title.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
			else:
				event_title.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))
			event_vbox.add_child(event_title)

			var event_desc := Label.new()
			event_desc.text = event.event_description
			event_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			event_desc.add_theme_color_override("font_color", Color(0.8, 0.8, 0.9))
			event_vbox.add_child(event_desc)

			event_panel.add_child(event_vbox)
			sell_list.add_child(event_panel)

		var events_sep := HSeparator.new()
		sell_list.add_child(events_sep)

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

	# Per-ore rows with price trend arrows
	for ore_type in ResourceTypes.OreType.values():
		var amount: float = GameState.resources.get(ore_type, 0.0)
		var price: float = MarketData.get_ore_price(ore_type)
		var base_price: float = MarketData.get_base_price(ore_type)

		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		# Price trend arrow
		var trend := ""
		var trend_color := Color.WHITE
		if GameState.market:
			var t := GameState.market.get_price_trend(ore_type)
			if t > 0:
				trend = " ^"
				trend_color = Color(0.3, 0.9, 0.4)
			elif t < 0:
				trend = " v"
				trend_color = Color(0.9, 0.4, 0.3)

		var info := Label.new()
		info.text = "%s: %.1f t  @  $%.0f/t (base $%.0f)%s" % [
			ResourceTypes.get_ore_name(ore_type), amount, price, base_price, trend
		]
		if trend_color != Color.WHITE:
			info.add_theme_color_override("font_color", trend_color)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info)

		var btn := Button.new()
		btn.text = "Sell"
		btn.custom_minimum_size = Vector2(0, 44)
		btn.disabled = amount < 0.01
		btn.pressed.connect(_sell_ore.bind(ore_type))
		hbox.add_child(btn)

		sell_list.add_child(hbox)

# ═══════════════════════════════════════════════════
#  EQUIPMENT SECTION
# ═══════════════════════════════════════════════════

func _refresh_equip() -> void:
	for child in equip_list.get_children():
		child.queue_free()

	# Show fabrication queue
	if not GameState.fabrication_queue.is_empty():
		var fab_header := Label.new()
		fab_header.text = "FABRICATION QUEUE"
		fab_header.add_theme_font_size_override("font_size", 16)
		fab_header.add_theme_color_override("font_color", Color(0.8, 0.7, 0.2))
		equip_list.add_child(fab_header)

		for equip in GameState.fabrication_queue:
			var fab_panel := PanelContainer.new()
			var fab_hbox := HBoxContainer.new()
			fab_hbox.add_theme_constant_override("separation", 8)

			var fab_info := Label.new()
			fab_info.text = "%s (%.2fx)" % [equip.equipment_name, equip.mining_bonus]
			fab_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			fab_hbox.add_child(fab_info)

			var time_label := Label.new()
			var time_str := _format_time(equip.fabrication_ticks)
			time_label.text = "Ready in: %s" % time_str
			time_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
			fab_hbox.add_child(time_label)

			var progress_bar := ProgressBar.new()
			progress_bar.custom_minimum_size = Vector2(100, 0)
			var catalog_entry := _find_catalog_entry(equip.equipment_name)
			if catalog_entry:
				var total_time: float = catalog_entry.get("fabrication_ticks", 1.0)
				var elapsed := total_time - equip.fabrication_ticks
				progress_bar.value = (elapsed / total_time) * 100.0
			fab_hbox.add_child(progress_bar)

			fab_panel.add_child(fab_hbox)
			equip_list.add_child(fab_panel)

		var fab_sep := HSeparator.new()
		equip_list.add_child(fab_sep)

	# Show ready-to-install items in inventory
	var ready_items: Array[Equipment] = []
	for equip in GameState.equipment_inventory:
		if not equip.is_fabricating():
			ready_items.append(equip)

	if not ready_items.is_empty():
		var inv_header := Label.new()
		inv_header.text = "Inventory (ready to install):"
		inv_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		equip_list.add_child(inv_header)
		for equip in ready_items:
			var inv_row := HBoxContainer.new()
			inv_row.add_theme_constant_override("separation", 8)
			var inv_info := Label.new()
			inv_info.text = "%s (%.2fx mining)" % [equip.equipment_name, equip.mining_bonus]
			inv_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			inv_row.add_child(inv_info)

			# Install buttons for each docked ship with open slots
			for ship in GameState.ships:
				if ship.is_docked and ship.equipment.size() < ship.max_equipment_slots:
					var install_btn := Button.new()
					install_btn.text = "Install on %s" % ship.ship_name
					install_btn.custom_minimum_size = Vector2(0, 40)
					install_btn.pressed.connect(func() -> void:
						GameState.install_equipment(ship, equip)
						_refresh_equip()
					)
					inv_row.add_child(install_btn)

			equip_list.add_child(inv_row)

		var inv_sep := HSeparator.new()
		equip_list.add_child(inv_sep)

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

		# Show installed equipment with durability and repair buttons
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
				var status_str := ""
				if equip.durability <= 0:
					status_str = " (BROKEN)"
					eq_info.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
				elif equip.durability < 30:
					eq_info.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))

				eq_info.text = "%s (%.2fx) - %d%% dur%s" % [
					equip.equipment_name, equip.mining_bonus,
					int(equip.durability), status_str
				]
				eq_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				eq_row.add_child(eq_info)

				# Durability bar
				var dur_bar := ProgressBar.new()
				dur_bar.custom_minimum_size = Vector2(80, 0)
				dur_bar.value = equip.durability
				dur_bar.max_value = equip.max_durability
				eq_row.add_child(dur_bar)

				# Repair button (only when docked and damaged)
				if ship.is_docked and equip.durability < equip.max_durability:
					var repair_btn := Button.new()
					var rcost := equip.repair_cost()
					repair_btn.text = "Repair $%s" % _format_number(rcost)
					repair_btn.custom_minimum_size = Vector2(0, 40)
					repair_btn.disabled = GameState.money < rcost or rcost <= 0
					repair_btn.pressed.connect(func() -> void:
						GameState.repair_equipment(ship, equip)
						_refresh_equip()
					)
					eq_row.add_child(repair_btn)

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
			buy_label.text = "Buy Equipment (goes to inventory for fabrication):"
			buy_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			ship_vbox.add_child(buy_label)

			for entry in MarketData.EQUIPMENT_CATALOG:
				var buy_row := HBoxContainer.new()
				buy_row.add_theme_constant_override("separation", 8)
				var fab_time: float = entry.get("fabrication_ticks", 0.0)
				var info := Label.new()
				info.text = "%s  %.2fx  $%s  (fab: %.0f ticks)" % [
					entry["name"], entry["mining_bonus"],
					_format_number(entry["cost"]), fab_time
				]
				info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				buy_row.add_child(info)

				var btn := Button.new()
				btn.text = "Buy"
				btn.custom_minimum_size = Vector2(0, 40)
				btn.disabled = GameState.money < entry["cost"]
				btn.pressed.connect(_buy_equipment.bind(entry))
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

	# ═══════════════════════════════════════════════════
	#  SHIP UPGRADES SECTION
	# ═══════════════════════════════════════════════════

	var upgrades_sep := HSeparator.new()
	equip_list.add_child(upgrades_sep)

	var upgrades_header := Label.new()
	upgrades_header.text = "SHIP UPGRADES"
	upgrades_header.add_theme_font_size_override("font_size", 20)
	upgrades_header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	equip_list.add_child(upgrades_header)

	# Show upgrade inventory
	if not GameState.upgrade_inventory.is_empty():
		for upgrade in GameState.upgrade_inventory:
			var upgrade_row := HBoxContainer.new()
			upgrade_row.add_theme_constant_override("separation", 8)
			var upgrade_info := Label.new()
			upgrade_info.text = "%s - %s" % [upgrade.upgrade_name, upgrade.description]
			upgrade_info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			upgrade_row.add_child(upgrade_info)

			# Install on docked ships
			for docked_ship in GameState.get_docked_ships():
				var install_btn := Button.new()
				install_btn.text = "Install on %s" % docked_ship.ship_name
				install_btn.custom_minimum_size = Vector2(0, 40)
				install_btn.pressed.connect(func() -> void:
					GameState.install_upgrade(docked_ship, upgrade)
					_refresh_equip()
				)
				upgrade_row.add_child(install_btn)

			equip_list.add_child(upgrade_row)

		var upgrade_sep2 := HSeparator.new()
		equip_list.add_child(upgrade_sep2)

	# Buy upgrades
	var buy_upgrades_label := Label.new()
	buy_upgrades_label.text = "Available Upgrades:"
	buy_upgrades_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	equip_list.add_child(buy_upgrades_label)

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
		btn.text = "Buy"
		btn.custom_minimum_size = Vector2(0, 44)
		btn.disabled = GameState.money < entry["cost"]
		btn.pressed.connect(func() -> void:
			if GameState.purchase_upgrade(entry):
				_refresh_equip()
		)
		buy_row.add_child(btn)
		equip_list.add_child(buy_row)

# ═══════════════════════════════════════════════════
#  CONTRACTS SECTION
# ═══════════════════════════════════════════════════

func _refresh_contracts() -> void:
	if not contracts_list:
		return
	for child in contracts_list.get_children():
		child.queue_free()

	# Active contracts
	if not GameState.active_contracts.is_empty():
		var active_header := Label.new()
		active_header.text = "Active Contracts:"
		active_header.add_theme_font_size_override("font_size", 18)
		active_header.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		contracts_list.add_child(active_header)

		for contract in GameState.active_contracts:
			var panel := PanelContainer.new()
			var vbox := VBoxContainer.new()
			vbox.add_theme_constant_override("separation", 4)

			var info := Label.new()
			var ore_name := ResourceTypes.get_ore_name(contract.ore_type)
			var have: float = GameState.resources.get(contract.ore_type, 0.0)
			var delivery_loc := contract.get_delivery_location_text()
			var progress_pct := contract.get_progress() * 100.0

			info.text = "%s: %s %.1f/%.1f t (%.0f%%) - Deliver to: %s\n$%s reward - Deadline: %.0f ticks - Earth stockpile: %.1f t" % [
				contract.issuer_name, ore_name, contract.quantity_delivered, contract.quantity, progress_pct,
				delivery_loc, _format_number(contract.reward), contract.deadline_ticks, have
			]
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(info)

			# Progress bar
			if contract.quantity_delivered > 0:
				var progress_bar := ProgressBar.new()
				progress_bar.value = progress_pct
				progress_bar.max_value = 100.0
				vbox.add_child(progress_bar)

			var hbox := HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 8)

			var fulfill_btn := Button.new()
			var remaining := contract.get_remaining_quantity()
			fulfill_btn.text = "Fulfill from Stockpile"
			fulfill_btn.custom_minimum_size = Vector2(0, 44)
			fulfill_btn.disabled = have < remaining
			fulfill_btn.pressed.connect(func() -> void:
				GameState.fulfill_contract(contract)
				_refresh_contracts()
				_refresh_sell()
			)
			hbox.add_child(fulfill_btn)

			var note := Label.new()
			note.text = "(Or deliver from ship at colony)"
			note.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
			hbox.add_child(note)

			vbox.add_child(hbox)
			panel.add_child(vbox)
			contracts_list.add_child(panel)

		var sep := HSeparator.new()
		contracts_list.add_child(sep)

	# Available contracts
	var avail_header := Label.new()
	avail_header.text = "Available Contracts:"
	avail_header.add_theme_font_size_override("font_size", 18)
	contracts_list.add_child(avail_header)

	if GameState.available_contracts.is_empty():
		var empty := Label.new()
		empty.text = "No contracts available - check back later"
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		contracts_list.add_child(empty)
	else:
		for contract in GameState.available_contracts:
			var panel := PanelContainer.new()
			var hbox := HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 8)

			var info := Label.new()
			var ore_name := ResourceTypes.get_ore_name(contract.ore_type)
			var delivery_loc := contract.get_delivery_location_text()
			var partial_text := " (partial OK)" if contract.allows_partial else " (all or nothing)"
			info.text = "%s: %s %.1f t to %s%s\n$%s reward (+%.0f%% vs spot) - %.0f ticks" % [
				contract.issuer_name, ore_name, contract.quantity, delivery_loc, partial_text,
				_format_number(contract.reward), contract.get_premium_percent(),
				contract.deadline_ticks
			]
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			hbox.add_child(info)

			var accept_btn := Button.new()
			accept_btn.text = "Accept"
			accept_btn.custom_minimum_size = Vector2(0, 44)
			accept_btn.pressed.connect(func() -> void:
				GameState.accept_contract(contract)
				_refresh_contracts()
			)
			hbox.add_child(accept_btn)
			panel.add_child(hbox)
			contracts_list.add_child(panel)

# ═══════════════════════════════════════════════════
#  COLONY TRADE SECTION
# ═══════════════════════════════════════════════════

func _refresh_colony() -> void:
	if not colony_list:
		return
	for child in colony_list.get_children():
		child.queue_free()

	# Check if player has any ore to trade (stockpile)
	var has_ore := false
	for ore_type in ResourceTypes.OreType.values():
		if GameState.resources.get(ore_type, 0.0) > 0.01:
			has_ore = true
			break

	# Check for idle remote ships with cargo
	var idle_remote_with_cargo: Array[Ship] = []
	for s in GameState.ships:
		if s.is_idle_remote and s.get_cargo_total() > 0.01:
			idle_remote_with_cargo.append(s)

	for colony: Colony in GameState.colonies:
		var panel := PanelContainer.new()
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)

		# Colony name and distance from Earth
		var earth_pos := CelestialData.get_earth_position_au()
		var colony_pos := colony.get_position_au()
		var dist_from_earth := earth_pos.distance_to(colony_pos)

		var header := Label.new()
		header.text = "%s (%.2f AU from Earth)" % [colony.colony_name, dist_from_earth]
		header.add_theme_font_size_override("font_size", 18)
		header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
		vbox.add_child(header)

		# Show what they pay for each ore type
		var prices_text := ""
		for ore_type in ResourceTypes.OreType.values():
			var colony_price: float = colony.get_ore_price(ore_type, GameState.market)
			var earth_price: float = MarketData.get_ore_price(ore_type)
			var mult: float = colony.price_multipliers.get(ore_type, 1.0)
			var diff_str := ""
			if mult > 1.05:
				diff_str = " (+%.0f%%)" % ((mult - 1.0) * 100)
			elif mult < 0.95:
				diff_str = " (%.0f%%)" % ((mult - 1.0) * 100)
			var have: float = GameState.resources.get(ore_type, 0.0)
			if have > 0.01 or mult > 1.05:
				prices_text += "  %s: $%.0f/t%s" % [ResourceTypes.get_ore_name(ore_type), colony_price, diff_str]
				if have > 0.01:
					prices_text += " (have %.1ft = $%s)" % [have, _format_number(int(have * colony_price))]
				prices_text += "\n"

		if prices_text != "":
			var prices_label := Label.new()
			prices_label.text = prices_text.strip_edges()
			prices_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(prices_label)

		# Send trade ship button (docked ships with stockpile ore)
		var docked := GameState.get_docked_ships()
		if has_ore and not docked.is_empty():
			var trade_btn := Button.new()
			trade_btn.text = "Send Trade Ship"
			trade_btn.custom_minimum_size = Vector2(0, 44)
			trade_btn.pressed.connect(_start_trade.bind(colony))
			vbox.add_child(trade_btn)

		# Remote idle ships with cargo can trade too
		for remote_ship in idle_remote_with_cargo:
			var ship_dist := remote_ship.position_au.distance_to(colony_pos)
			var trade_btn := Button.new()
			trade_btn.text = "Send %s (%.2f AU away)" % [remote_ship.ship_name, ship_dist]
			trade_btn.custom_minimum_size = Vector2(0, 44)
			trade_btn.pressed.connect(_start_remote_trade.bind(colony, remote_ship))
			vbox.add_child(trade_btn)

		panel.add_child(vbox)
		colony_list.add_child(panel)

# ═══════════════════════════════════════════════════
#  ACTIONS
# ═══════════════════════════════════════════════════

func _sell_all_ores() -> void:
	var total_revenue := 0
	for ore_type in ResourceTypes.OreType.values():
		var amount: float = GameState.resources.get(ore_type, 0.0)
		if amount > 0.01:
			var price: float = MarketData.get_ore_price(ore_type)
			total_revenue += int(amount * price)
			GameState.remove_resource(ore_type, amount)
	if total_revenue > 0:
		GameState.money += total_revenue

func _sell_ore(ore_type: ResourceTypes.OreType) -> void:
	var amount: float = GameState.resources.get(ore_type, 0.0)
	if amount < 0.01:
		return
	var price: float = MarketData.get_ore_price(ore_type)
	var revenue: int = int(amount * price)
	GameState.remove_resource(ore_type, amount)
	GameState.money += revenue

func _buy_equipment(entry: Dictionary) -> void:
	if GameState.purchase_equipment(entry):
		_refresh_equip()

func _remove_equipment(ship: Ship, equip: Equipment) -> void:
	ship.equipment.erase(equip)
	GameState.equipment_inventory.append(equip)
	_refresh_equip()

func _start_trade(colony: Colony) -> void:
	var docked := GameState.get_docked_ships()
	if docked.is_empty():
		return
	var ship: Ship = docked[0]

	# Load all available ore from stockpile
	var cargo: Dictionary = {}
	var total_loaded := 0.0
	for ore_type in ResourceTypes.OreType.values():
		var available: float = GameState.resources.get(ore_type, 0.0)
		if available > 0.01:
			var can_load := minf(available, ship.cargo_capacity - total_loaded)
			if can_load > 0.01:
				cargo[ore_type] = can_load
				total_loaded += can_load
		if total_loaded >= ship.cargo_capacity:
			break

	if cargo.is_empty():
		return

	# Auto-refuel - distance from ship's current position
	if GameState.settings.get("auto_refuel", true):
		var colony_pos := colony.get_position_au()
		var dist := ship.position_au.distance_to(colony_pos)
		var fuel_needed := ship.calc_fuel_for_distance(dist)
		var fuel_cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)
		if GameState.money < fuel_cost:
			return
		ship.fuel = ship.fuel_capacity
		GameState.money -= fuel_cost

	var workers := GameState.get_available_workers()
	var assigned: Array[Worker] = []
	for i in range(mini(ship.min_crew, workers.size())):
		assigned.append(workers[i])

	GameState.start_trade_mission(ship, colony, assigned, cargo)
	_refresh_colony()
	_refresh_sell()

func _start_remote_trade(colony: Colony, ship: Ship) -> void:
	# Remote idle ship trades its on-board cargo
	if not ship.is_idle_remote:
		return

	var cargo: Dictionary = ship.current_cargo.duplicate()
	if cargo.is_empty():
		return

	# Auto-refuel from current position
	if GameState.settings.get("auto_refuel", true):
		var colony_pos := colony.get_position_au()
		var dist := ship.position_au.distance_to(colony_pos)
		var fuel_needed := ship.calc_fuel_for_distance(dist)
		var fuel_cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)
		if GameState.money < fuel_cost:
			return
		ship.fuel = ship.fuel_capacity
		GameState.money -= fuel_cost

	var assigned: Array[Worker] = []
	GameState.dispatch_idle_ship_trade(ship, colony, assigned, cargo)
	_refresh_colony()
	_refresh_sell()

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

func _find_catalog_entry(equipment_name: String) -> Dictionary:
	for entry in MarketData.EQUIPMENT_CATALOG:
		if entry.get("name", "") == equipment_name:
			return entry
	return {}

func _format_time(ticks: float) -> String:
	var total_seconds := int(ticks)
	var hours := total_seconds / 3600
	var minutes := (total_seconds % 3600) / 60
	var seconds := total_seconds % 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	elif minutes > 0:
		return "%dm %ds" % [minutes, seconds]
	return "%ds" % seconds
