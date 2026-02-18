extends MarginContainer

@onready var money_label: Label = %MoneyLabel
@onready var missions_list: VBoxContainer = %MissionsList
@onready var resources_list: VBoxContainer = %ResourcesList
@onready var workers_summary: Label = %WorkersSummary
@onready var events_list: VBoxContainer = %EventsList

const MAX_EVENTS: int = 8
const PROGRESS_LERP_SPEED: float = 8.0  # How fast progress bars catchup
var _event_messages: Array[Dictionary] = []  # { "text": String, "color": Color }
var _progress_bars: Dictionary = {}  # mission/trade_mission -> ProgressBar

func _ready() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.resource_changed.connect(_on_resource_changed)
	EventBus.mission_started.connect(func(_m: Mission) -> void: _refresh_missions())
	EventBus.mission_completed.connect(func(m: Mission) -> void:
		_refresh_missions()
		var location := m.asteroid.asteroid_name if m.asteroid else "remote location"
		_add_event("Mission complete: %s returned from %s" % [m.ship.ship_name, location], Color(0.3, 0.9, 0.4))
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

	# Breakdown & rescue events
	EventBus.ship_breakdown.connect(func(ship: Ship, reason: String) -> void:
		_add_event("ALERT: %s — %s" % [ship.ship_name, reason], Color(0.9, 0.2, 0.2))
		_send_system_notification("Ship Breakdown", "%s — %s" % [ship.ship_name, reason])
	)
	EventBus.rescue_mission_started.connect(func(ship: Ship, cost: int) -> void:
		_refresh_missions()
		_add_event("Rescue dispatched for %s ($%s)" % [ship.ship_name, _format_number(cost)], Color(0.9, 0.6, 0.2))
	)
	EventBus.rescue_mission_completed.connect(func(ship: Ship) -> void:
		_refresh_missions()
		_add_event("%s rescued and returned safely" % ship.ship_name, Color(0.3, 0.9, 0.4))
	)
	EventBus.refuel_mission_started.connect(func(ship: Ship, cost: int, _fuel: float) -> void:
		_add_event("Refuel tanker sent to %s ($%s)" % [ship.ship_name, _format_number(cost)], Color(0.3, 0.8, 0.9))
	)
	EventBus.refuel_mission_completed.connect(func(ship: Ship, _fuel: float) -> void:
		_add_event("%s refueled" % ship.ship_name, Color(0.3, 0.8, 0.9))
	)

	# Stranger rescue events
	EventBus.stranger_rescue_offered.connect(func(ship: Ship, stranger_name: String) -> void:
		_add_event("A passing vessel (%s) is offering to help %s!" % [stranger_name, ship.ship_name], Color(1.0, 0.9, 0.3))
		_send_system_notification("Stranger Offering Help", "%s wants to help %s" % [stranger_name, ship.ship_name])
	)
	EventBus.stranger_rescue_completed.connect(func(ship: Ship, stranger_name: String) -> void:
		_add_event("%s rescued by %s" % [ship.ship_name, stranger_name], Color(0.3, 0.9, 0.4))
	)

	# Reputation
	EventBus.reputation_changed.connect(func(_score: float, _tier: int) -> void:
		_refresh_reputation()
	)

	_refresh_all()
	_setup_policies_ui()
	_setup_reputation_display()

func _setup_policies_ui() -> void:
	# Find the main VBox in the dashboard
	var scroll := get_node("ScrollContainer")
	var vbox := scroll.get_node("VBox")

	# Add policies card
	var policies_card := PanelContainer.new()
	var policies_vbox := VBoxContainer.new()
	policies_vbox.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "COMPANY POLICIES"
	title.add_theme_font_size_override("font_size", 14)
	policies_vbox.add_child(title)

	# Thrust policy selector
	var thrust_row := HBoxContainer.new()
	thrust_row.add_theme_constant_override("separation", 8)

	var thrust_label := Label.new()
	thrust_label.text = "Thrust Strategy:"
	thrust_label.custom_minimum_size = Vector2(120, 0)
	thrust_row.add_child(thrust_label)

	var thrust_option := OptionButton.new()
	thrust_option.custom_minimum_size = Vector2(0, 36)
	for policy in CompanyPolicy.ThrustPolicy.values():
		thrust_option.add_item(CompanyPolicy.THRUST_POLICY_NAMES[policy])
	thrust_option.selected = GameState.thrust_policy
	thrust_option.item_selected.connect(func(idx: int) -> void:
		GameState.thrust_policy = idx
	)
	thrust_row.add_child(thrust_option)

	policies_vbox.add_child(thrust_row)

	# Policy description
	var desc_label := Label.new()
	desc_label.text = CompanyPolicy.THRUST_POLICY_DESCRIPTIONS[GameState.thrust_policy]
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	desc_label.custom_minimum_size = Vector2(0, 40)
	policies_vbox.add_child(desc_label)

	# Update description when policy changes
	thrust_option.item_selected.connect(func(idx: int) -> void:
		desc_label.text = CompanyPolicy.THRUST_POLICY_DESCRIPTIONS[idx]
	)

	policies_card.add_child(policies_vbox)
	vbox.add_child(policies_card)

func _process(delta: float) -> void:
	# Smooth progress bar updates with LERP
	for mission_or_trade in _progress_bars:
		var progress_bar: ProgressBar = _progress_bars[mission_or_trade]
		if not is_instance_valid(progress_bar):
			continue

		var target_progress: float = 0.0
		var use_instant_update := false

		if mission_or_trade is Mission:
			target_progress = mission_or_trade.get_progress() * 100.0
			# Instant update during mining so it matches ore accumulation
			use_instant_update = (mission_or_trade.status == Mission.Status.MINING)
		elif mission_or_trade is TradeMission:
			target_progress = mission_or_trade.get_progress() * 100.0

		# Instant update during mining, smooth lerp otherwise
		if use_instant_update:
			progress_bar.value = target_progress
		else:
			progress_bar.value = lerp(progress_bar.value, target_progress, PROGRESS_LERP_SPEED * delta)

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
	# Clean up old progress bar references for completed missions
	var to_remove: Array = []
	for mission_or_trade in _progress_bars:
		var still_active := false
		if mission_or_trade is Mission and mission_or_trade in GameState.missions:
			still_active = true
		elif mission_or_trade is TradeMission and mission_or_trade in GameState.trade_missions:
			still_active = true
		if not still_active:
			to_remove.append(mission_or_trade)
	for key in to_remove:
		_progress_bars.erase(key)

	for child in missions_list.get_children():
		child.queue_free()

	var has_any := false

	# Mining missions
	for mission: Mission in GameState.missions:
		has_any = true
		var hbox := HBoxContainer.new()
		var status_label := Label.new()
		status_label.text = mission.get_status_text()
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(status_label)
		var progress := ProgressBar.new()
		progress.custom_minimum_size = Vector2(100, 0)
		progress.value = mission.get_progress() * 100.0
		_progress_bars[mission] = progress  # Store reference for lerping
		hbox.add_child(progress)
		missions_list.add_child(hbox)

	# Trade missions
	for tm: TradeMission in GameState.trade_missions:
		has_any = true
		var hbox := HBoxContainer.new()
		var status_label := Label.new()
		status_label.text = tm.get_status_text()
		status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(status_label)
		var progress := ProgressBar.new()
		progress.custom_minimum_size = Vector2(100, 0)
		progress.value = tm.get_progress() * 100.0
		_progress_bars[tm] = progress  # Store reference for lerping
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

func _send_system_notification(p_title: String, p_body: String) -> void:
	# Desktop: flash the taskbar/window
	if OS.get_name() in ["Windows", "macOS", "Linux"]:
		DisplayServer.window_request_attention()
	# Android: TODO — use JavaClassWrapper → NotificationManager
	# iOS: TODO — requires native plugin

func _setup_reputation_display() -> void:
	var scroll := get_node("ScrollContainer")
	var vbox := scroll.get_node("VBox")

	var rep_card := PanelContainer.new()
	rep_card.name = "ReputationCard"
	var rep_vbox := VBoxContainer.new()
	rep_vbox.add_theme_constant_override("separation", 4)

	var rep_title := Label.new()
	rep_title.text = "REPUTATION"
	rep_title.add_theme_font_size_override("font_size", 14)
	rep_vbox.add_child(rep_title)

	var rep_label := Label.new()
	rep_label.name = "ReputationLabel"
	rep_label.text = "%s (%+.0f)" % [Reputation.get_tier_name(), Reputation.score]
	_color_reputation_label(rep_label)
	rep_vbox.add_child(rep_label)

	rep_card.add_child(rep_vbox)
	vbox.add_child(rep_card)

func _refresh_reputation() -> void:
	var rep_card := get_node_or_null("ScrollContainer/VBox/ReputationCard")
	if not rep_card:
		return
	var rep_label: Label = rep_card.find_child("ReputationLabel", true, false)
	if rep_label:
		rep_label.text = "%s (%+.0f)" % [Reputation.get_tier_name(), Reputation.score]
		_color_reputation_label(rep_label)

func _color_reputation_label(label: Label) -> void:
	var tier := Reputation.get_tier()
	if tier == Reputation.Tier.NOTORIOUS or tier == Reputation.Tier.SHADY:
		label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	elif tier == Reputation.Tier.RESPECTED or tier == Reputation.Tier.RENOWNED:
		label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	else:
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

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
