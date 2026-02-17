extends MarginContainer

@onready var money_label: Label = %MoneyLabel
@onready var missions_list: VBoxContainer = %MissionsList
@onready var resources_list: VBoxContainer = %ResourcesList
@onready var workers_summary: Label = %WorkersSummary
@onready var events_list: VBoxContainer = %EventsList

const MAX_EVENTS: int = 8
var _event_messages: Array[String] = []

func _ready() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.mission_started.connect(func(_m: Mission) -> void: _refresh_missions())
	EventBus.mission_completed.connect(func(m: Mission) -> void:
		_refresh_missions()
		_add_event("Mission complete: %s returned from %s" % [m.ship.ship_name, m.asteroid.asteroid_name])
	)
	EventBus.mission_phase_changed.connect(func(_m: Mission) -> void: _refresh_missions())
	EventBus.worker_hired.connect(func(_w: Worker) -> void: _refresh_workers())
	EventBus.worker_fired.connect(func(_w: Worker) -> void: _refresh_workers())
	EventBus.survey_update.connect(_on_survey_update)
	EventBus.tick.connect(_on_tick)
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
			var label := Label.new()
			label.text = "%s: %.1f t" % [ResourceTypes.get_ore_name(ore_type), amount]
			resources_list.add_child(label)
	if resources_list.get_child_count() == 0:
		var label := Label.new()
		label.text = "No resources in stockpile"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		resources_list.add_child(label)

func _refresh_missions() -> void:
	for child in missions_list.get_children():
		child.queue_free()
	if GameState.missions.is_empty():
		var label := Label.new()
		label.text = "No active missions"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		missions_list.add_child(label)
		return
	for mission: Mission in GameState.missions:
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

func _refresh_workers() -> void:
	var total := GameState.workers.size()
	var available := GameState.get_available_workers().size()
	workers_summary.text = "%d workers (%d available)" % [total, available]

func _on_survey_update(_asteroid: AsteroidData, message: String) -> void:
	_add_event(message)

func _add_event(message: String) -> void:
	_event_messages.push_front(message)
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
	for msg in _event_messages:
		var label := Label.new()
		label.text = msg
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if msg.contains("richer"):
			label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		elif msg.contains("thinner"):
			label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
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
