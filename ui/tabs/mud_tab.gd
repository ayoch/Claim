extends MarginContainer

@onready var content: VBoxContainer = %Content
@onready var scroll: ScrollContainer = %ScrollContainer

var _dirty: bool = false
var _last_refresh_msec: int = 0
const REFRESH_INTERVAL_MSEC: int = 200

func _ready() -> void:
	# Connect to relevant signals
	EventBus.mining_unit_purchased.connect(func(_u: MiningUnit) -> void: _dirty = true)
	EventBus.mining_unit_deployed.connect(func(_u: MiningUnit, _a: AsteroidData) -> void: _dirty = true)
	EventBus.mining_unit_recalled.connect(func(_u: MiningUnit) -> void: _dirty = true)
	EventBus.mining_unit_broken.connect(func(_u: MiningUnit) -> void: _dirty = true)
	EventBus.worker_assigned.connect(func(_w: Worker, _s) -> void: _dirty = true)
	EventBus.worker_unassigned.connect(func(_w: Worker) -> void: _dirty = true)
	EventBus.mission_completed.connect(func(_m) -> void: _dirty = true)

	_dirty = true

func _on_become_visible() -> void:
	_dirty = true

func _on_tick(_dt: float) -> void:
	if not is_visible_in_tree():
		return
	if not _dirty:
		return

	var now := Time.get_ticks_msec()
	if now - _last_refresh_msec < REFRESH_INTERVAL_MSEC:
		return

	_last_refresh_msec = now
	_dirty = false
	_refresh()

func _refresh() -> void:
	# Clear existing content
	for child in content.get_children():
		child.queue_free()

	# Title
	var title := Label.new()
	title.text = "MUD Operations"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
	content.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "Mining Units, Deployable"
	subtitle.add_theme_font_size_override("font_size", 14)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	content.add_child(subtitle)

	content.add_child(HSeparator.new())

	# Inventory section
	_create_inventory_section()

	content.add_child(HSeparator.new())

	# Deployed units section
	_create_deployed_section()

	content.add_child(HSeparator.new())

	# Purchase section
	_create_purchase_section()

func _create_inventory_section() -> void:
	var header := Label.new()
	header.text = "Inventory (%d units)" % GameState.mining_unit_inventory.size()
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
	content.add_child(header)

	if GameState.mining_unit_inventory.is_empty():
		var empty := Label.new()
		empty.text = "No units in inventory. Purchase units below to begin mining operations."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(empty)
		return

	for unit in GameState.mining_unit_inventory:
		var panel := PanelContainer.new()
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)

		# Unit name and type
		var name_label := Label.new()
		name_label.text = "%s (%s)" % [unit.unit_name, unit.get_type_name()]
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
		vbox.add_child(name_label)

		# Stats
		var stats := Label.new()
		stats.text = "Workers: %d  |  Mining: %.1fx  |  Durability: %.0f/%.0f" % [
			unit.workers_required,
			unit.mining_multiplier,
			unit.durability,
			unit.max_durability
		]
		stats.add_theme_font_size_override("font_size", 12)
		stats.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		vbox.add_child(stats)

		# Action buttons
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 8)

		# Repair button (if damaged)
		if unit.durability < unit.max_durability:
			var repair_cost := unit.repair_cost()
			var repair_btn := Button.new()
			repair_btn.text = "Repair ($%s)" % _format_money(repair_cost)
			repair_btn.custom_minimum_size = Vector2(0, 32)
			repair_btn.disabled = GameState.money < repair_cost
			repair_btn.pressed.connect(func() -> void:
				var success := await GameState.repair_mining_unit_any_mode(unit)
				if success:
					_dirty = true
			)
			btn_row.add_child(repair_btn)

		# Rebuild button (if max durability low)
		if unit.needs_rebuild():
			var rebuild_cost := unit.rebuild_cost()
			var rebuild_btn := Button.new()
			rebuild_btn.text = "Rebuild ($%s)" % _format_money(rebuild_cost)
			rebuild_btn.custom_minimum_size = Vector2(0, 32)
			rebuild_btn.disabled = GameState.money < rebuild_cost
			rebuild_btn.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
			rebuild_btn.pressed.connect(func() -> void:
				var success := await GameState.rebuild_mining_unit_any_mode(unit)
				if success:
					_dirty = true
			)
			btn_row.add_child(rebuild_btn)

		if btn_row.get_child_count() > 0:
			vbox.add_child(btn_row)

		panel.add_child(vbox)
		content.add_child(panel)

func _create_deployed_section() -> void:
	var header := Label.new()
	header.text = "Deployed Units (%d)" % GameState.deployed_mining_units.size()
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color(0.7, 0.9, 0.9))
	content.add_child(header)

	if GameState.deployed_mining_units.is_empty():
		var empty := Label.new()
		empty.text = "No units deployed. Dispatch a ship with units to begin mining."
		empty.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(empty)
		return

	# Group units by asteroid
	var units_by_asteroid: Dictionary = {}
	for unit in GameState.deployed_mining_units:
		var ast_name := unit.deployed_at_asteroid
		if not units_by_asteroid.has(ast_name):
			units_by_asteroid[ast_name] = []
		units_by_asteroid[ast_name].append(unit)

	# Display each asteroid group
	var asteroid_names := units_by_asteroid.keys()
	asteroid_names.sort()

	for ast_name in asteroid_names:
		var units: Array = units_by_asteroid[ast_name]

		# Asteroid header
		var ast_header := Label.new()
		ast_header.text = "📍 %s (%d units)" % [ast_name, units.size()]
		ast_header.add_theme_font_size_override("font_size", 18)
		ast_header.add_theme_color_override("font_color", Color(0.9, 0.8, 0.5))
		content.add_child(ast_header)

		# Stockpile info
		var stockpile := GameState.ore_stockpiles.get(ast_name, {})
		if not stockpile.is_empty():
			var stockpile_text := "Stockpile: "
			var ore_parts: Array[String] = []
			for ore_type in stockpile:
				var amount: float = stockpile[ore_type]
				if amount > 0.01:
					ore_parts.append("%s: %.1f t" % [ResourceTypes.get_ore_name(ore_type), amount])

			if not ore_parts.is_empty():
				var stockpile_label := Label.new()
				stockpile_label.text = stockpile_text + ", ".join(ore_parts)
				stockpile_label.add_theme_font_size_override("font_size", 12)
				stockpile_label.add_theme_color_override("font_color", Color(0.5, 0.8, 0.9))
				stockpile_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				content.add_child(stockpile_label)

				# Collection mission button
				var total_mass := 0.0
				for amount in stockpile.values():
					total_mass += amount

				if total_mass > 1.0:
					var collect_btn := Button.new()
					collect_btn.text = "Dispatch Collection Mission"
					collect_btn.custom_minimum_size = Vector2(0, 32)
					collect_btn.pressed.connect(func() -> void:
						_show_collection_dispatch(ast_name, stockpile)
					)
					content.add_child(collect_btn)

		# Units at this asteroid
		for unit in units:
			var unit_panel := PanelContainer.new()
			var unit_vbox := VBoxContainer.new()
			unit_vbox.add_theme_constant_override("separation", 4)

			# Unit name and status
			var unit_header := Label.new()
			var status_icon := "✅" if unit.is_functional() else "❌"
			unit_header.text = "%s %s" % [status_icon, unit.unit_name]
			unit_header.add_theme_font_size_override("font_size", 14)
			var header_color := Color(0.7, 0.9, 0.7) if unit.is_functional() else Color(0.9, 0.4, 0.4)
			unit_header.add_theme_color_override("font_color", header_color)
			unit_vbox.add_child(unit_header)

			# Durability
			var dur_label := Label.new()
			dur_label.text = "Durability: %.0f/%.0f (%.0f%%)" % [
				unit.durability,
				unit.max_durability,
				(unit.durability / unit.max_durability * 100.0) if unit.max_durability > 0 else 0.0
			]
			dur_label.add_theme_font_size_override("font_size", 11)
			var dur_color := Color.GREEN
			if unit.durability < unit.max_durability * 0.3:
				dur_color = Color.RED
			elif unit.durability < unit.max_durability * 0.6:
				dur_color = Color.YELLOW
			dur_label.add_theme_color_override("font_color", dur_color)
			unit_vbox.add_child(dur_label)

			# Workers
			if unit.assigned_workers.is_empty():
				var no_crew := Label.new()
				no_crew.text = "⚠️ No workers assigned - not producing"
				no_crew.add_theme_font_size_override("font_size", 11)
				no_crew.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
				unit_vbox.add_child(no_crew)
			else:
				var workers_text := "Workers: "
				var worker_names: Array[String] = []
				for w in unit.assigned_workers:
					worker_names.append(w.worker_name)
				workers_text += ", ".join(worker_names)

				var workers_label := Label.new()
				workers_label.text = workers_text
				workers_label.add_theme_font_size_override("font_size", 11)
				workers_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
				workers_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				unit_vbox.add_child(workers_label)

			# Action buttons
			var action_row := HBoxContainer.new()
			action_row.add_theme_constant_override("separation", 8)

			var recall_btn := Button.new()
			recall_btn.text = "Recall Unit"
			recall_btn.custom_minimum_size = Vector2(0, 28)
			recall_btn.pressed.connect(func() -> void:
				var success := await GameState.recall_mining_unit_any_mode(unit)
				if success:
					_dirty = true
			)
			action_row.add_child(recall_btn)

			unit_vbox.add_child(action_row)

			unit_panel.add_child(unit_vbox)
			content.add_child(unit_panel)

		content.add_child(VSeparator.new())

func _create_purchase_section() -> void:
	var header := Label.new()
	header.text = "Purchase Units"
	header.add_theme_font_size_override("font_size", 22)
	header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.5))
	content.add_child(header)

	var catalog := MiningUnitCatalog.get_available_units()

	for entry in catalog:
		var panel := PanelContainer.new()
		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 4)

		# Name
		var name_label := Label.new()
		name_label.text = entry["name"]
		name_label.add_theme_font_size_override("font_size", 16)
		name_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.7))
		vbox.add_child(name_label)

		# Description
		var desc := Label.new()
		desc.text = entry["description"]
		desc.add_theme_font_size_override("font_size", 12)
		desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(desc)

		# Stats
		var stats := Label.new()
		stats.text = "Mining: %.1fx  |  Workers: %d  |  Mass: %.1f t  |  Wear: %.1f/day" % [
			entry["mining_multiplier"],
			entry["workers_required"],
			entry["mass"],
			entry["wear_per_day"]
		]
		stats.add_theme_font_size_override("font_size", 11)
		stats.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
		vbox.add_child(stats)

		# Purchase button
		var cost: int = entry["cost"]
		var buy_btn := Button.new()
		buy_btn.text = "Purchase - $%s" % _format_money(cost)
		buy_btn.custom_minimum_size = Vector2(0, 36)
		buy_btn.disabled = GameState.money < cost
		buy_btn.pressed.connect(func() -> void:
			var success := await GameState.purchase_mining_unit_any_mode(entry)
			if success:
				_dirty = true
		)
		vbox.add_child(buy_btn)

		panel.add_child(vbox)
		content.add_child(panel)

func _show_collection_dispatch(asteroid_name: String, stockpile: Dictionary) -> void:
	# TODO: Show ship selection dialog for collection mission
	# For now, just show a placeholder message
	var dialog := AcceptDialog.new()
	dialog.title = "Collection Mission"
	dialog.dialog_text = "Collection missions coming soon!\n\nStockpile at %s:\n%s" % [
		asteroid_name,
		_format_stockpile(stockpile)
	]
	dialog.min_size = Vector2i(400, 200)
	add_child(dialog)
	dialog.popup_centered()
	dialog.confirmed.connect(func() -> void:
		dialog.queue_free()
	)

func _format_stockpile(stockpile: Dictionary) -> String:
	var parts: Array[String] = []
	for ore_type in stockpile:
		var amount: float = stockpile[ore_type]
		if amount > 0.01:
			parts.append("%s: %.1f t" % [ResourceTypes.get_ore_name(ore_type), amount])
	return "\n".join(parts)

func _format_money(amount: int) -> String:
	if amount >= 1000000:
		return "%.1fM" % (amount / 1000000.0)
	elif amount >= 1000:
		return "%.0fK" % (amount / 1000.0)
	else:
		return str(amount)
