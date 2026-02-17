extends MarginContainer

@onready var money_label: Label = %MoneyLabel
@onready var missions_list: VBoxContainer = %MissionsList
@onready var resources_list: VBoxContainer = %ResourcesList
@onready var workers_summary: Label = %WorkersSummary
@onready var events_list: VBoxContainer = %EventsList

const MAX_EVENTS: int = 8
var _event_messages: Array[Dictionary] = []  # { "text": String, "color": Color }

func _ready() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.mission_started.connect(func(_m: Mission) -> void: _refresh_missions())
	EventBus.mission_completed.connect(func(m: Mission) -> void:
		_refresh_missions()
		_add_event("Mission complete: %s returned from %s" % [m.ship.ship_name, m.asteroid.asteroid_name], Color(0.3, 0.9, 0.4))
	)
	EventBus.mission_phase_changed.connect(func(_m: Mission) -> void: _refresh_missions())
	EventBus.worker_hired.connect(func(_w: Worker) -> void: _refresh_workers())
	EventBus.worker_fired.connect(func(_w: Worker) -> void: _refresh_workers())
	EventBus.survey_update.connect(_on_survey_update)
	EventBus.tick.connect(_on_tick)

	# Market events
	EventBus.market_event.connect(func(_ore: ResourceTypes.OreType, _old: float, _new: float, msg: String) -> void:
		var color := Color(0.3, 0.9, 0.4) if _new > _old else Color(0.9, 0.4, 0.3)
		_add_event(msg, color)
	)

	# Equipment events
	EventBus.equipment_broken.connect(func(ship: Ship, equip: Equipment) -> void:
		_add_event("%s on %s has broken!" % [equip.equipment_name, ship.ship_name], Color(0.9, 0.3, 0.3))
	)
	EventBus.equipment_repaired.connect(func(ship: Ship, equip: Equipment) -> void:
		_add_event("%s on %s repaired" % [equip.equipment_name, ship.ship_name], Color(0.3, 0.9, 0.4))
	)
	EventBus.equipment_fabricated.connect(func(equip: Equipment) -> void:
		_add_event("%s fabrication complete!" % equip.equipment_name, Color(0.3, 0.8, 1.0))
	)

	# Contract events
	EventBus.contract_offered.connect(func(c: Contract) -> void:
		_add_event("New contract: %s wants %.1f t %s" % [c.issuer_name, c.quantity, ResourceTypes.get_ore_name(c.ore_type)], Color(0.3, 0.8, 1.0))
	)
	EventBus.contract_completed.connect(func(c: Contract) -> void:
		_add_event("Contract fulfilled! +$%d from %s" % [c.reward, c.issuer_name], Color(0.3, 0.9, 0.4))
	)
	EventBus.contract_failed.connect(func(c: Contract) -> void:
		_add_event("Contract failed: %s deadline expired" % c.issuer_name, Color(0.9, 0.3, 0.3))
	)

	# Trade mission events
	EventBus.trade_mission_started.connect(func(tm: TradeMission) -> void:
		_refresh_missions()
		_add_event("Trade mission: %s heading to %s" % [tm.ship.ship_name, tm.colony.colony_name], Color(0.3, 0.9, 0.9))
	)
	EventBus.trade_mission_completed.connect(func(tm: TradeMission) -> void:
		_refresh_missions()
		_add_event("Trade complete: %s returned from %s (+$%d)" % [tm.ship.ship_name, tm.colony.colony_name, tm.revenue], Color(0.3, 0.9, 0.4))
	)
	EventBus.trade_mission_phase_changed.connect(func(_tm: TradeMission) -> void: _refresh_missions())

	_refresh_all()

func _refresh_all() -> void:
	_on_money_changed(GameState.money)
	_refresh_resources()
	_refresh_missions()
	_refresh_workers()

func _on_money_changed(amount: int) -> void:
	money_label.text = "$%s" % _format_number(amount)

func _on_resource_changed(_ore_type: ResourceTypes.OreType, _amount: float) -> void:
	_refresh_resources()

func _on_tick(_dt: float) -> void:
	_refresh_missions()

func _refresh_resources() -> void:
	for child in resources_list.get_children():
		child.queue_free()
	for ore_type in ResourceTypes.OreType.values():
		var amount: float = GameState.resources.get(ore_type, 0.0)
		if amount > 0.01:
			var price: float = MarketData.get_ore_price(ore_type)
			var label := Label.new()
			label.text = "%s: %.1f t ($%.0f/t)" % [ResourceTypes.get_ore_name(ore_type), amount, price]
			resources_list.add_child(label)
	if resources_list.get_child_count() == 0:
		var label := Label.new()
		label.text = "No resources in stockpile"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		resources_list.add_child(label)

func _refresh_missions() -> void:
	for child in missions_list.get_children():
		child.queue_free()

	var has_any := false

	# Mining missions
	for mission: Mission in GameState.missions:
		has_any = true
		var hbox := HBoxContainer.new()
		var status_label := Label.new()
		status_label.text = mission.get_status_text()
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(status_label)
		var progress := ProgressBar.new()
		progress.custom_minimum_size = Vector2(100, 0)
		progress.value = mission.get_progress() * 100.0
		hbox.add_child(progress)
		missions_list.add_child(hbox)

	# Trade missions
	for tm: TradeMission in GameState.trade_missions:
		has_any = true
		var hbox := HBoxContainer.new()
		var status_label := Label.new()
		status_label.text = tm.get_status_text()
		status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(status_label)
		var progress := ProgressBar.new()
		progress.custom_minimum_size = Vector2(100, 0)
		progress.value = tm.get_progress() * 100.0
		hbox.add_child(progress)
		missions_list.add_child(hbox)

	if not has_any:
		var label := Label.new()
		label.text = "No active missions"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		missions_list.add_child(label)

func _refresh_workers() -> void:
	var total := GameState.workers.size()
	var available := GameState.get_available_workers().size()
	workers_summary.text = "%d workers (%d available)" % [total, available]

func _on_survey_update(_asteroid: AsteroidData, message: String) -> void:
	var color := Color(0.3, 0.9, 0.4) if message.contains("richer") else Color(0.9, 0.6, 0.3)
	_add_event(message, color)

func _add_event(message: String, color: Color = Color.WHITE) -> void:
	_event_messages.push_front({"text": message, "color": color})
	if _event_messages.size() > MAX_EVENTS:
		_event_messages.resize(MAX_EVENTS)
	_refresh_events()

func _refresh_events() -> void:
	for child in events_list.get_children():
		child.queue_free()
	if _event_messages.is_empty():
		var label := Label.new()
		label.text = "No recent events"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		events_list.add_child(label)
		return
	for entry in _event_messages:
		var label := Label.new()
		label.text = entry["text"]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if entry["color"] != Color.WHITE:
			label.add_theme_color_override("font_color", entry["color"])
		events_list.add_child(label)

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
