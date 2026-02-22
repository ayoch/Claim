extends MarginContainer

@onready var money_label: Label = %MoneyLabel
@onready var missions_list: VBoxContainer = %MissionsList
@onready var resources_list: VBoxContainer = %ResourcesList
@onready var workers_summary: Label = %WorkersSummary
@onready var alerts_list: VBoxContainer = %AlertsList
@onready var alerts_scroll: ScrollContainer = %AlertsScroll
@onready var activity_list: VBoxContainer = %ActivityList
@onready var activity_scroll: ScrollContainer = %ActivityScroll
@onready var contracts_list: VBoxContainer = %ContractsList
@onready var contracts_scroll: ScrollContainer = %ContractsScroll
@onready var transactions_list: VBoxContainer = %TransactionsList
@onready var transactions_scroll: ScrollContainer = %TransactionsScroll

const MAX_ALERTS: int = 50
const MAX_ACTIVITY: int = 100
const MAX_CONTRACT_LOG: int = 30
var _contract_messages: Array[Dictionary] = []  # { "text": String, "color": Color }
const PROGRESS_LERP_SPEED: float = 8.0  # How fast progress bars catchup
var _alert_messages: Array[Dictionary] = []  # { "text": String, "color": Color }
var _activity_messages: Array[Dictionary] = []  # { "text": String, "color": Color }
var _progress_bars: Dictionary = {}  # mission/trade_mission -> ProgressBar
var _last_refresh_msec: int = 0
const REFRESH_INTERVAL_MSEC: int = 100  # Only refresh UI every 100ms real-time

# Dirty flags — signals set these, _on_tick does the actual rebuild
var _dirty_missions: bool = false
var _dirty_stationed: bool = false
var _dirty_discipline: bool = false
var _dirty_alerts: bool = false
var _dirty_activity: bool = false
var _dirty_contracts: bool = false
var _dirty_resources: bool = false
var _dirty_workers: bool = false
var _dirty_balance_history: bool = false

# Section collapse state: key -> true means collapsed
var _section_collapsed: Dictionary = {}
var _section_content: Dictionary = {}  # key -> Node
var _section_titles: Dictionary = {}  # key -> Label

static func _free_children(container: Node) -> void:
	for i in range(container.get_child_count() - 1, -1, -1):
		container.get_child(i).free()

func _ready() -> void:
	EventBus.money_changed.connect(_on_money_changed)
	EventBus.resource_changed.connect(func(_o, _a) -> void: _dirty_resources = true)
	EventBus.mission_started.connect(func(_m: Mission) -> void: _dirty_missions = true)
	EventBus.mission_completed.connect(func(m: Mission) -> void:
		_dirty_missions = true
		var location := m.asteroid.asteroid_name if m.asteroid else "remote location"
		_queue_activity("Mission complete: %s returned from %s" % [m.ship.ship_name, location], Color(0.3, 0.9, 0.4))
	)
	EventBus.mission_phase_changed.connect(func(_m: Mission) -> void: _dirty_missions = true)
	EventBus.worker_hired.connect(func(_w: Worker) -> void: _dirty_workers = true)
	EventBus.worker_fired.connect(func(_w: Worker) -> void: _dirty_workers = true)
	EventBus.worker_skill_leveled.connect(_on_worker_skill_leveled)
	EventBus.worker_wage_increased.connect(func(w: Worker, amount: int) -> void:
		_queue_activity("[Greedy] %s negotiated a $%d/day raise (now $%d/day)" % [w.worker_name, amount, w.wage], Color(1.0, 0.8, 0.2))
	)
	EventBus.survey_update.connect(func(_a: AsteroidData, msg: String) -> void:
		var color := Color(0.3, 0.9, 0.4) if msg.contains("richer") else Color(0.9, 0.6, 0.3)
		_queue_activity(msg, color)
	)
	EventBus.tick.connect(_on_tick)

	# Market events → activity
	EventBus.market_event.connect(func(_ore: ResourceTypes.OreType, _old: float, _new: float, msg: String) -> void:
		var color := Color(0.3, 0.9, 0.4) if _new > _old else Color(0.9, 0.4, 0.3)
		_queue_activity(msg, color)
	)

	# Equipment events
	EventBus.equipment_broken.connect(func(ship: Ship, equip: Equipment) -> void:
		_queue_alert("%s on %s has broken!" % [equip.equipment_name, ship.ship_name], Color(0.9, 0.3, 0.3))
	)
	EventBus.equipment_repaired.connect(func(ship: Ship, equip: Equipment) -> void:
		_queue_activity("%s on %s repaired" % [equip.equipment_name, ship.ship_name], Color(0.3, 0.9, 0.4))
	)
	EventBus.equipment_fabricated.connect(func(equip: Equipment) -> void:
		_queue_activity("%s fabrication complete!" % equip.equipment_name, Color(0.3, 0.8, 1.0))
	)

	# Contract events → dedicated contracts ticker
	EventBus.contract_offered.connect(func(c: Contract) -> void:
		_queue_contract_log("NEW: %s wants %.1f t %s — $%s" % [c.issuer_name, c.quantity, ResourceTypes.get_ore_name(c.ore_type), _format_number(c.reward)], Color(0.3, 0.8, 1.0))
	)
	EventBus.contract_accepted.connect(func(_c: Contract) -> void: _dirty_contracts = true)
	EventBus.contract_completed.connect(func(c: Contract) -> void:
		_queue_contract_log("FULFILLED: %s +$%s" % [c.issuer_name, _format_number(c.reward)], Color(0.3, 0.9, 0.4))
	)
	EventBus.contract_failed.connect(func(c: Contract) -> void:
		_queue_contract_log("FAILED: %s — %.1f t %s not delivered" % [c.issuer_name, c.quantity, ResourceTypes.get_ore_name(c.ore_type)], Color(0.9, 0.3, 0.3))
	)

	# Trade mission events → activity
	EventBus.trade_mission_started.connect(func(tm: TradeMission) -> void:
		_dirty_missions = true
		_queue_activity("Trade mission: %s heading to %s" % [tm.ship.ship_name, tm.colony.colony_name], Color(0.3, 0.9, 0.9))
	)
	EventBus.trade_mission_completed.connect(func(tm: TradeMission) -> void:
		_dirty_missions = true
		_queue_activity("Trade complete: %s returned from %s (+$%d)" % [tm.ship.ship_name, tm.colony.colony_name, tm.revenue], Color(0.3, 0.9, 0.4))
	)
	EventBus.trade_mission_phase_changed.connect(func(_tm: TradeMission) -> void: _dirty_missions = true)

	# Breakdown & rescue events → alerts
	EventBus.ship_breakdown.connect(func(ship: Ship, reason: String) -> void:
		_queue_alert("BREAKDOWN: %s — %s" % [ship.ship_name, reason], Color(0.9, 0.2, 0.2))
		_send_system_notification("Ship Breakdown", "%s — %s" % [ship.ship_name, reason])
	)
	EventBus.ship_destroyed.connect(func(ship: Ship, body_name: String) -> void:
		_dirty_missions = true
		var msg := ""
		if body_name == "Life support failure":
			msg = "DESTROYED: %s — life support failure, all hands lost" % ship.ship_name
		else:
			msg = "DESTROYED: %s crashed into %s — all hands lost" % [ship.ship_name, body_name]
		_queue_alert(msg, Color(1.0, 0.1, 0.1))
		_send_system_notification("Ship Destroyed", "%s: %s" % [ship.ship_name, body_name])
	)
	EventBus.life_support_warning.connect(func(ship: Ship, pct: float) -> void:
		var pct_int := int(pct * 100)
		_queue_alert("LIFE SUPPORT: %s at %d%% — send rescue!" % [ship.ship_name, pct_int], Color(1.0, 0.6, 0.1))
		_send_system_notification("Life Support Critical", "%s at %d%%" % [ship.ship_name, pct_int])
	)
	EventBus.rescue_mission_started.connect(func(ship: Ship, cost: int) -> void:
		_dirty_missions = true
		_queue_alert("Rescue dispatched for %s ($%s)" % [ship.ship_name, _format_number(cost)], Color(0.9, 0.6, 0.2))
	)
	EventBus.rescue_mission_completed.connect(func(ship: Ship) -> void:
		_dirty_missions = true
		_queue_alert("RESCUED: %s recovered and returned safely" % ship.ship_name, Color(0.3, 0.9, 0.4))
		_queue_activity("%s rescued and returned safely" % ship.ship_name, Color(0.3, 0.9, 0.4))
	)
	EventBus.refuel_mission_started.connect(func(ship: Ship, cost: int, _fuel: float) -> void:
		_queue_activity("Refuel tanker sent to %s ($%s)" % [ship.ship_name, _format_number(cost)], Color(0.3, 0.8, 0.9))
	)
	EventBus.refuel_mission_completed.connect(func(ship: Ship, _fuel: float) -> void:
		_queue_activity("%s refueled" % ship.ship_name, Color(0.3, 0.8, 0.9))
	)

	# Stranger rescue events → alerts (requires action)
	EventBus.stranger_rescue_offered.connect(func(ship: Ship, stranger_name: String) -> void:
		_queue_alert("A passing vessel (%s) is offering to help %s!" % [stranger_name, ship.ship_name], Color(1.0, 0.9, 0.3))
		_send_system_notification("Stranger Offering Help", "%s wants to help %s" % [stranger_name, ship.ship_name])
	)
	EventBus.stranger_rescue_completed.connect(func(ship: Ship, stranger_name: String) -> void:
		_queue_activity("%s rescued by %s" % [ship.ship_name, stranger_name], Color(0.3, 0.9, 0.4))
	)

	# Mining units
	EventBus.mining_unit_deployed.connect(func(unit: MiningUnit, asteroid: AsteroidData) -> void:
		_queue_activity("Deployed %s at %s" % [unit.unit_name, asteroid.asteroid_name], Color(0.3, 0.9, 0.4))
		_dirty_resources = true
	)
	EventBus.worker_injured.connect(func(w: Worker) -> void:
		if w.assigned_mining_unit:
			_queue_alert("ACCIDENT: %s injured at %s mining unit" % [w.worker_name, w.assigned_mining_unit.deployed_at_asteroid], Color(0.9, 0.4, 0.2))
	)
	EventBus.mining_unit_broken.connect(func(unit: MiningUnit) -> void:
		_queue_alert("UNIT BROKEN: %s at %s needs repair" % [unit.unit_name, unit.deployed_at_asteroid], Color(0.9, 0.3, 0.3))
		_dirty_resources = true
	)
	EventBus.stockpile_collected.connect(func(asteroid: AsteroidData, tons: float) -> void:
		_queue_activity("Collected %.1ft from %s stockpile" % [tons, asteroid.asteroid_name], Color(0.3, 0.9, 0.4))
		_dirty_resources = true
	)
	EventBus.asteroid_supplies_low.connect(func(asteroid_name: String, supply_key: String, days_remaining: float) -> void:
		var supply_label := "food" if supply_key == "food" else "repair parts"
		_queue_alert("LOW SUPPLIES: %.1f days of %s remaining at %s" % [days_remaining, supply_label, asteroid_name], Color(1.0, 0.7, 0.2))
	)

	# Reputation
	EventBus.reputation_changed.connect(func(_score: float, _tier: int) -> void:
		_refresh_reputation()
	)

	# Station events
	EventBus.ship_stationed.connect(func(_s: Ship, _c: Colony) -> void: _dirty_stationed = true)
	EventBus.ship_unstationed.connect(func(_s: Ship) -> void: _dirty_stationed = true)
	EventBus.station_job_started.connect(func(_s: Ship, _j: String, _d: String) -> void: _dirty_stationed = true)
	EventBus.station_job_completed.connect(func(s: Ship, j: String, summary: String) -> void:
		_dirty_stationed = true
		_queue_activity("Station [%s]: %s — %s" % [s.ship_name, j, summary], Color(0.3, 0.9, 0.9))
	)

	# Hitchhike & tardiness events
	EventBus.worker_waiting_for_ride.connect(func(w: Worker, loc: String) -> void:
		_queue_activity("%s waiting for a ride home at %s" % [w.worker_name, loc], Color(0.7, 0.7, 0.3))
	)
	EventBus.worker_hitched_ride.connect(func(w: Worker, s: Ship) -> void:
		_queue_activity("%s hitched a ride on %s heading toward %s" % [w.worker_name, s.ship_name, w.home_colony], Color(0.3, 0.9, 0.4))
	)
	EventBus.worker_tardy.connect(func(w: Worker, reason: String) -> void:
		_queue_alert("TARDY: %s — %s" % [w.worker_name, reason], Color(1.0, 0.6, 0.1))
		_send_system_notification("Worker Tardy", "%s is late returning" % w.worker_name)
		_dirty_discipline = true
	)
	EventBus.worker_tardiness_resolved.connect(func(w: Worker, action: String) -> void:
		_queue_activity("%s tardiness resolved: %s" % [w.worker_name, action], Color(0.3, 0.8, 0.9))
		_dirty_discipline = true
	)
	EventBus.order_queued.connect(func(ship: Ship, label: String, delay_secs: float) -> void:
		var mins := int(delay_secs / 60.0)
		var secs := int(fmod(delay_secs, 60.0))
		var delay_str := "%dm %02ds" % [mins, secs] if mins > 0 else "%ds" % secs
		_queue_activity("📡 %s: '%s' — arrives in %s" % [ship.ship_name, label, delay_str], Color(0.9, 0.8, 0.3))
	)
	EventBus.order_executed.connect(func(ship: Ship, label: String) -> void:
		_queue_activity("✓ %s received order: %s" % [ship.ship_name, label], Color(0.4, 0.9, 0.5))
	)
	EventBus.rival_corp_dispatched.connect(func(corp_name: String, asteroid_name: String) -> void:
		_queue_activity("[Rival] %s heading to %s" % [corp_name, asteroid_name], Color(0.9, 0.6, 0.2))
	)
	EventBus.rival_corp_arrived.connect(func(corp_name: String, asteroid_name: String) -> void:
		_queue_activity("[Rival] %s arrived at %s" % [corp_name, asteroid_name], Color(0.9, 0.5, 0.1))
	)
	EventBus.rival_corp_departed.connect(func(corp_name: String, asteroid_name: String, tons: float) -> void:
		_queue_activity("[Rival] %s left %s with %.1ft cargo" % [corp_name, asteroid_name, tons], Color(0.7, 0.5, 0.2))
	)
	EventBus.rival_corps_contested.connect(func(corp_name: String, asteroid_name: String) -> void:
		_queue_alert("[RIVAL] %s is now competing with you at %s!" % [corp_name, asteroid_name], Color(1.0, 0.4, 0.1))
	)

	_refresh_all()
	_setup_policies_ui()
	_setup_stationed_ships_panel()
	_setup_reputation_display()
	_setup_balance_history()
	_setup_discipline_panel()
	_setup_collapsible_sections()

func _setup_stationed_ships_panel() -> void:
	var scroll := get_node("ScrollContainer")
	var vbox := scroll.get_node("VBox")

	var card := PanelContainer.new()
	card.name = "StationedShipsCard"
	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "STATIONED SHIPS"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
	card_vbox.add_child(title)

	var ships_list := VBoxContainer.new()
	ships_list.name = "StationedShipsList"
	ships_list.add_theme_constant_override("separation", 12)
	card_vbox.add_child(ships_list)

	card.add_child(card_vbox)

	# Insert before AlertsCard (after MissionsCard)
	var missions_card := vbox.get_node_or_null("MissionsCard")
	if missions_card:
		var idx := missions_card.get_index() + 1
		vbox.add_child(card)
		vbox.move_child(card, idx)
	else:
		vbox.add_child(card)

	_refresh_stationed_ships()

func _refresh_stationed_ships() -> void:
	var card := get_node_or_null("ScrollContainer/VBox/StationedShipsCard")
	if not card:
		return

	var ships_list_node := card.find_child("StationedShipsList", true, false)
	if not ships_list_node:
		return

	_free_children(ships_list_node)

	var has_stationed := false
	for ship in GameState.ships:
		if not ship.is_stationed:
			continue
		has_stationed = true

		var ship_vbox := VBoxContainer.new()
		ship_vbox.add_theme_constant_override("separation", 2)
		ship_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var header := Label.new()
		header.text = "%s @ %s" % [ship.ship_name, ship.station_colony.colony_name if ship.station_colony else "Unknown"]
		header.add_theme_font_size_override("font_size", 16)
		header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.clip_text = true
		ship_vbox.add_child(header)

		# Current status
		var status_label := Label.new()
		status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		status_label.clip_text = true
		if ship.is_stationed_idle:
			status_label.text = "Status: Idle (awaiting next job)"
			status_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.2))
		elif ship.current_mission:
			var mission_text := ship.current_mission.get_status_text()
			var progress := int(ship.current_mission.get_progress() * 100.0)
			status_label.text = "Status: %s (%d%%)" % [mission_text, progress]
			status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		elif ship.current_trade_mission:
			var tm_text := ship.current_trade_mission.get_status_text()
			var progress := int(ship.current_trade_mission.get_progress() * 100.0)
			status_label.text = "Status: %s (%d%%)" % [tm_text, progress]
			status_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
		else:
			status_label.text = "Status: Standby"
			status_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		ship_vbox.add_child(status_label)

		# Cargo
		if ship.get_cargo_total() > 0.1:
			var cargo_label := Label.new()
			cargo_label.text = "Cargo: %.0ft / %.0ft" % [ship.get_cargo_total(), ship.get_effective_cargo_capacity()]
			cargo_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
			cargo_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			cargo_label.clip_text = true
			ship_vbox.add_child(cargo_label)

		# Last log entry
		if not ship.station_log.is_empty():
			var log_entry: Dictionary = ship.station_log[0]
			var elapsed := GameState.total_ticks - float(log_entry["time"])
			var time_str := TimeScale.format_time(elapsed) + " ago" if elapsed > 0 else "just now"
			var log_label := Label.new()
			log_label.text = "Last: %s (%s)" % [log_entry["message"], time_str]
			log_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
			log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			log_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ship_vbox.add_child(log_label)

		ships_list_node.add_child(ship_vbox)

	# Hide the entire card if no ships are stationed
	card.visible = has_stationed

func _setup_discipline_panel() -> void:
	var scroll := get_node("ScrollContainer")
	var vbox := scroll.get_node("VBox")

	var card := PanelContainer.new()
	card.name = "DisciplineCard"
	var card_vbox := VBoxContainer.new()
	card_vbox.add_theme_constant_override("separation", 8)

	var title := Label.new()
	title.text = "CREW DISCIPLINE"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
	card_vbox.add_child(title)

	var entries_list := VBoxContainer.new()
	entries_list.name = "DisciplineEntries"
	entries_list.add_theme_constant_override("separation", 12)
	card_vbox.add_child(entries_list)

	card.add_child(card_vbox)

	# Insert near top (after MissionsCard, before StationedShipsCard)
	var missions_card := vbox.get_node_or_null("MissionsCard")
	if missions_card:
		var idx := missions_card.get_index() + 1
		vbox.add_child(card)
		vbox.move_child(card, idx)
	else:
		vbox.add_child(card)

	_refresh_discipline()

func _refresh_discipline() -> void:
	var card := get_node_or_null("ScrollContainer/VBox/DisciplineCard")
	if not card:
		return

	var entries_list_node := card.find_child("DisciplineEntries", true, false)
	if not entries_list_node:
		return

	_free_children(entries_list_node)

	if GameState.tardy_workers.is_empty():
		card.visible = false
		return

	card.visible = true

	for entry in GameState.tardy_workers:
		var worker: Worker = entry["worker"]
		var reason: String = entry["reason"]
		var tardy_since: float = entry["tardy_since"]

		var entry_vbox := VBoxContainer.new()
		entry_vbox.add_theme_constant_override("separation", 4)
		entry_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		# Name
		var name_label := Label.new()
		name_label.text = worker.worker_name
		name_label.add_theme_font_size_override("font_size", 20)
		name_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		name_label.clip_text = true
		entry_vbox.add_child(name_label)

		# Skills / wage / tenure / loyalty
		var info_label := Label.new()
		var tenure_days := int(worker.days_at_company)
		info_label.text = "%s  |  $%d/day  |  %d days at company  |  Loyalty: %d" % [
			worker.get_specialties_text(), worker.wage, tenure_days, int(worker.loyalty)
		]
		info_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry_vbox.add_child(info_label)

		# Home colony
		var home_label := Label.new()
		home_label.text = "Home: %s" % worker.home_colony
		home_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		home_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		home_label.clip_text = true
		entry_vbox.add_child(home_label)

		# Reason
		var reason_label := Label.new()
		reason_label.text = "Reason: %s" % reason
		reason_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
		reason_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		reason_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		entry_vbox.add_child(reason_label)

		# Late by
		var late_days := (GameState.total_ticks - tardy_since) / 86400.0
		var late_label := Label.new()
		late_label.text = "Late by: %.1f days" % late_days
		late_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.3))
		late_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		late_label.clip_text = true
		entry_vbox.add_child(late_label)

		# Action buttons
		var btn_row := HBoxContainer.new()
		btn_row.add_theme_constant_override("separation", 12)

		var forgive_btn := Button.new()
		forgive_btn.text = "Forgive"
		forgive_btn.custom_minimum_size = Vector2(0, 44)
		forgive_btn.pressed.connect(GameState.forgive_tardy_worker.bind(worker))
		btn_row.add_child(forgive_btn)

		var dock_btn := Button.new()
		var dock_amount := worker.wage * 3
		dock_btn.text = "Dock Pay -$%d" % dock_amount
		dock_btn.custom_minimum_size = Vector2(0, 44)
		dock_btn.pressed.connect(GameState.dock_pay_tardy_worker.bind(worker))
		btn_row.add_child(dock_btn)

		var fire_btn := Button.new()
		fire_btn.text = "Fire"
		fire_btn.custom_minimum_size = Vector2(0, 44)
		fire_btn.pressed.connect(GameState.fire_tardy_worker.bind(worker))
		btn_row.add_child(fire_btn)

		entry_vbox.add_child(btn_row)
		entries_list_node.add_child(entry_vbox)

func _setup_policies_ui() -> void:
	# Find the main VBox in the dashboard
	var scroll := get_node("ScrollContainer")
	var vbox := scroll.get_node("VBox")

	# Add policies card
	var policies_card := PanelContainer.new()
	var policies_vbox := VBoxContainer.new()
	policies_vbox.add_theme_constant_override("separation", 8)

	var title_row := HBoxContainer.new()
	var title := Label.new()
	title.text = "COMPANY POLICIES"
	title.add_theme_font_size_override("font_size", 14)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(title)

	var autoplay_btn := Button.new()
	autoplay_btn.toggle_mode = true
	autoplay_btn.button_pressed = GameState.settings.get("autoplay", false)
	autoplay_btn.text = "AUTOPLAY: ON" if autoplay_btn.button_pressed else "AUTOPLAY: OFF"
	autoplay_btn.custom_minimum_size = Vector2(130, 0)
	autoplay_btn.toggled.connect(func(on: bool) -> void:
		GameState.settings["autoplay"] = on
		autoplay_btn.text = "AUTOPLAY: ON" if on else "AUTOPLAY: OFF"
	)
	title_row.add_child(autoplay_btn)
	policies_vbox.add_child(title_row)

	var policies_content := VBoxContainer.new()
	policies_content.add_theme_constant_override("separation", 10)

	# Helper: build one policy row with label, dropdown, and description
	var _add_policy_row := func(
		label_text: String,
		names: Dictionary,
		descriptions: Dictionary,
		get_fn: Callable,
		set_fn: Callable
	) -> void:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		var lbl := Label.new()
		lbl.text = label_text
		lbl.custom_minimum_size = Vector2(130, 0)
		lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
		row.add_child(lbl)
		var opt := OptionButton.new()
		opt.custom_minimum_size = Vector2(0, 36)
		opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for key in names.keys():
			opt.add_item(names[key])
		opt.selected = get_fn.call()
		var desc := Label.new()
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		desc.add_theme_font_size_override("font_size", 11)
		desc.text = descriptions.get(get_fn.call(), "")
		opt.item_selected.connect(func(idx: int) -> void:
			set_fn.call(idx)
			desc.text = descriptions.get(idx, "")
		)
		row.add_child(opt)
		policies_content.add_child(row)
		policies_content.add_child(desc)

	_add_policy_row.call(
		"Thrust:",
		CompanyPolicy.THRUST_POLICY_NAMES,
		CompanyPolicy.THRUST_POLICY_DESCRIPTIONS,
		func() -> int: return GameState.thrust_policy,
		func(idx: int) -> void: GameState.thrust_policy = idx
	)
	_add_policy_row.call(
		"Resupply:",
		CompanyPolicy.SUPPLY_POLICY_NAMES,
		CompanyPolicy.SUPPLY_POLICY_DESCRIPTIONS,
		func() -> int: return GameState.supply_policy,
		func(idx: int) -> void: GameState.supply_policy = idx
	)
	_add_policy_row.call(
		"Ore Collection:",
		CompanyPolicy.COLLECTION_POLICY_NAMES,
		CompanyPolicy.COLLECTION_POLICY_DESCRIPTIONS,
		func() -> int: return GameState.collection_policy,
		func(idx: int) -> void: GameState.collection_policy = idx
	)
	_add_policy_row.call(
		"Encounter:",
		CompanyPolicy.ENCOUNTER_POLICY_NAMES,
		CompanyPolicy.ENCOUNTER_POLICY_DESCRIPTIONS,
		func() -> int: return GameState.encounter_policy,
		func(idx: int) -> void: GameState.encounter_policy = idx
	)

	policies_vbox.add_child(policies_content)
	policies_card.add_child(policies_vbox)
	vbox.add_child(policies_card)

	_make_collapsible("policies", title, policies_content, true)

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
	_refresh_contracts()

func _on_money_changed(amount: int) -> void:
	money_label.text = "$%s" % _format_number(amount)
	_dirty_balance_history = true

func _on_tick(_dt: float) -> void:
	# Throttle UI rebuilds to real-time interval (not game-time)
	var now := Time.get_ticks_msec()
	if now - _last_refresh_msec < REFRESH_INTERVAL_MSEC:
		return
	_last_refresh_msec = now

	# Only rebuild containers that are actually dirty
	if _dirty_missions:
		_dirty_missions = false
		_refresh_missions()
	if _dirty_stationed:
		_dirty_stationed = false
		_refresh_stationed_ships()
	if _dirty_discipline:
		_dirty_discipline = false
		_refresh_discipline()
	if _dirty_contracts:
		_dirty_contracts = false
		_refresh_contracts()
	if _dirty_alerts:
		_dirty_alerts = false
		_refresh_alerts()
	if _dirty_activity:
		_dirty_activity = false
		_refresh_activity()
	if _dirty_resources:
		_dirty_resources = false
		_refresh_resources()
	if _dirty_workers:
		_dirty_workers = false
		_refresh_workers()
	if _dirty_balance_history:
		_dirty_balance_history = false
		_refresh_balance_history()

func _refresh_resources() -> void:
	_free_children(resources_list)
	for ore_type in ResourceTypes.OreType.values():
		var amount: float = GameState.resources.get(ore_type, 0.0)
		if amount > 0.01:
			var price: float = MarketData.get_ore_price(ore_type)
			var label := Label.new()
			label.text = "%s: %.1f t ($%.0f/t)" % [ResourceTypes.get_ore_name(ore_type), amount, price]
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			label.clip_text = true
			resources_list.add_child(label)
	if resources_list.get_child_count() == 0:
		var label := Label.new()
		label.text = "No resources in stockpile"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		resources_list.add_child(label)

	# Mining Claims summary
	if not GameState.deployed_mining_units.is_empty() or not GameState.ore_stockpiles.is_empty():
		var claims_sep := HSeparator.new()
		resources_list.add_child(claims_sep)
		var claims_header := Label.new()
		claims_header.text = "MINING CLAIMS"
		claims_header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		claims_header.add_theme_font_size_override("font_size", 16)
		claims_header.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
		resources_list.add_child(claims_header)

		# Collect asteroid names with deployed units or stockpiles
		var claim_asteroids: Dictionary = {}
		for unit in GameState.deployed_mining_units:
			if not claim_asteroids.has(unit.deployed_at_asteroid):
				claim_asteroids[unit.deployed_at_asteroid] = true
		for asteroid_name in GameState.ore_stockpiles:
			if not claim_asteroids.has(asteroid_name):
				claim_asteroids[asteroid_name] = true

		for asteroid_name in claim_asteroids:
			var units := GameState.get_mining_units_at(asteroid_name)
			var pile := GameState.get_ore_stockpile(asteroid_name)

			# Find asteroid data for max slots
			var max_slots := 0
			for a in GameState.asteroids:
				if a.asteroid_name == asteroid_name:
					max_slots = a.get_max_mining_slots()
					break

			var header_label := Label.new()
			header_label.text = "%s  [%d/%d slots]" % [asteroid_name, units.size(), max_slots]
			header_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			header_label.clip_text = true
			header_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
			resources_list.add_child(header_label)

			# Show unit status
			for unit in units:
				var dur_color := Color(0.3, 0.9, 0.4)
				if unit.durability < 30.0:
					dur_color = Color(0.9, 0.3, 0.3)
				elif unit.durability < 60.0:
					dur_color = Color(0.9, 0.6, 0.2)
				var unit_row := HBoxContainer.new()
				unit_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				unit_row.add_theme_constant_override("separation", 8)
				var unit_label := Label.new()
				var rebuild_warn := " [RECALL FOR REBUILD]" if unit.needs_rebuild() else ""
				unit_label.text = "  %s: %.0f/%.0f%% dur, %.1fx mult%s" % [
					unit.unit_name, unit.durability, unit.max_durability, unit.get_effective_multiplier(), rebuild_warn
				]
				unit_label.add_theme_color_override("font_color", dur_color)
				unit_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				unit_label.clip_text = true
				unit_row.add_child(unit_label)
				var repair_cost := unit.repair_cost()
				if repair_cost > 0:
					var repair_btn := Button.new()
					repair_btn.text = "Repair $%s" % _format_number(repair_cost)
					repair_btn.custom_minimum_size = Vector2(0, 32)
					repair_btn.disabled = GameState.money < repair_cost
					repair_btn.pressed.connect(func() -> void:
						GameState.repair_mining_unit(unit)
						_dirty_resources = true
					)
					unit_row.add_child(repair_btn)
				resources_list.add_child(unit_row)

			# Show stockpile
			if not pile.is_empty():
				var total_tons := 0.0
				var total_value := 0.0
				for ore_type in pile:
					var tons: float = pile[ore_type]
					total_tons += tons
					total_value += tons * MarketData.get_ore_price(ore_type)
				var stockpile_label := Label.new()
				stockpile_label.text = "  Stockpile: %.1ft ($%s)" % [total_tons, _format_number(int(total_value))]
				stockpile_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				stockpile_label.clip_text = true
				stockpile_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
				resources_list.add_child(stockpile_label)

			# Show supplies
			var supplies := GameState.get_asteroid_supplies(asteroid_name)
			var food_days := GameState.get_asteroid_supply_days(asteroid_name, "food")
			var parts_days := GameState.get_asteroid_supply_days(asteroid_name, "repair_parts")
			var food_val: float = supplies.get("food", 0.0)
			var parts_val: float = supplies.get("repair_parts", 0.0)
			if food_val > 0.0 or parts_val > 0.0:
				var sup_label := Label.new()
				var food_str := "%.1fd" % food_days if food_days < INF else "—"
				var parts_str := "%.1fd" % parts_days if parts_days < INF else "—"
				sup_label.text = "  Food: %.2f u (%s)  Parts: %.2f u (%s)" % [food_val, food_str, parts_val, parts_str]
				sup_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				sup_label.clip_text = true
				var sup_color := Color(0.7, 0.7, 0.7)
				if (food_days < 5.0 and food_days > 0.0) or (parts_days < 5.0 and parts_days > 0.0):
					sup_color = Color(1.0, 0.6, 0.2)
				sup_label.add_theme_color_override("font_color", sup_color)
				resources_list.add_child(sup_label)

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

	_free_children(missions_list)

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
	workers_summary.text = "%d crew (%d available)" % [total, available]


func _queue_alert(message: String, color: Color = Color.WHITE) -> void:
	_alert_messages.push_front({"text": message, "color": color})
	if _alert_messages.size() > MAX_ALERTS:
		_alert_messages.resize(MAX_ALERTS)
	_dirty_alerts = true

func _queue_activity(message: String, color: Color = Color.WHITE) -> void:
	_activity_messages.push_front({"text": message, "color": color})
	if _activity_messages.size() > MAX_ACTIVITY:
		_activity_messages.resize(MAX_ACTIVITY)
	_dirty_activity = true

func _refresh_alerts() -> void:
	_free_children(alerts_list)
	if _alert_messages.is_empty():
		var label := Label.new()
		label.text = "No alerts"
		label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		alerts_list.add_child(label)
		return
	for entry in _alert_messages:
		var label := Label.new()
		label.text = entry["text"]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if entry["color"] != Color.WHITE:
			label.add_theme_color_override("font_color", entry["color"])
		alerts_list.add_child(label)

func _refresh_activity() -> void:
	_free_children(activity_list)
	if _activity_messages.is_empty():
		var label := Label.new()
		label.text = "No recent activity"
		label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		activity_list.add_child(label)
		return
	for entry in _activity_messages:
		var label := Label.new()
		label.text = entry["text"]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if entry["color"] != Color.WHITE:
			label.add_theme_color_override("font_color", entry["color"])
		activity_list.add_child(label)

func _queue_contract_log(message: String, color: Color = Color.WHITE) -> void:
	_contract_messages.push_front({"text": message, "color": color})
	if _contract_messages.size() > MAX_CONTRACT_LOG:
		_contract_messages.resize(MAX_CONTRACT_LOG)
	_dirty_contracts = true

func _refresh_contracts() -> void:
	_free_children(contracts_list)

	# Active contracts first
	var has_any := false
	for c in GameState.active_contracts:
		has_any = true
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var info := Label.new()
		var ore_name := ResourceTypes.get_ore_name(c.ore_type)
		var deadline_days: float = c.deadline_ticks / 86400.0
		info.text = "%s: %.1ft %s → %s — $%s (%.1fd left)" % [
			c.issuer_name, c.quantity, ore_name,
			c.get_delivery_location_text(), _format_number(c.reward), deadline_days
		]
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if deadline_days < 1.0:
			info.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		elif deadline_days < 3.0:
			info.add_theme_color_override("font_color", Color(1.0, 0.6, 0.1))
		else:
			info.add_theme_color_override("font_color", Color(0.3, 0.8, 1.0))
		hbox.add_child(info)

		if c.quantity > 0:
			var progress := ProgressBar.new()
			progress.custom_minimum_size = Vector2(80, 0)
			progress.value = c.get_progress() * 100.0
			hbox.add_child(progress)

		contracts_list.add_child(hbox)

	# Available contracts
	for c in GameState.available_contracts:
		has_any = true
		var label := Label.new()
		var ore_name := ResourceTypes.get_ore_name(c.ore_type)
		label.text = "[Available] %s: %.1ft %s → %s — $%s" % [
			c.issuer_name, c.quantity, ore_name,
			c.get_delivery_location_text(), _format_number(c.reward)
		]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.8))
		contracts_list.add_child(label)

	# Separator before log if we have both active contracts and log entries
	if has_any and not _contract_messages.is_empty():
		var sep := HSeparator.new()
		sep.add_theme_constant_override("separation", 8)
		contracts_list.add_child(sep)

	# Recent contract log
	for entry in _contract_messages:
		var label := Label.new()
		label.text = entry["text"]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if entry["color"] != Color.WHITE:
			label.add_theme_color_override("font_color", entry["color"])
		contracts_list.add_child(label)

	if not has_any and _contract_messages.is_empty():
		var label := Label.new()
		label.text = "No contracts"
		label.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		contracts_list.add_child(label)

func _send_system_notification(p_title: String, p_body: String) -> void:
	# Desktop: flash the taskbar/window
	if OS.get_name() in ["Windows", "macOS", "Linux"]:
		DisplayServer.window_request_attention()
	# Android: TODO — use JavaClassWrapper → NotificationManager
	# iOS: TODO — requires native plugin

func _setup_reputation_display() -> void:
	# Reputation is added inside NumbersContent (set up in _setup_balance_history)
	pass

func _refresh_reputation() -> void:
	var rep_label: Label = get_node_or_null(
		"ScrollContainer/VBox/BalanceCard/VBox/NumbersContent/ReputationLabel")
	if rep_label:
		rep_label.text = "Reputation: %s (%+.0f)" % [Reputation.get_tier_name(), Reputation.score]
		_color_reputation_label(rep_label)

func _color_reputation_label(label: Label) -> void:
	var tier := Reputation.get_tier()
	if tier == Reputation.Tier.NOTORIOUS or tier == Reputation.Tier.SHADY:
		label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	elif tier == Reputation.Tier.RESPECTED or tier == Reputation.Tier.RENOWNED:
		label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
	else:
		label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))

func _setup_balance_history() -> void:
	var balance_vbox := get_node_or_null("ScrollContainer/VBox/BalanceCard/VBox")
	if not balance_vbox:
		return
	var title: Label = balance_vbox.get_node("Title")

	# Content wrapper: balance + reputation only
	var content := VBoxContainer.new()
	content.name = "NumbersContent"
	content.add_theme_constant_override("separation", 6)
	balance_vbox.add_child(content)

	# Reparent MoneyLabel into content so it collapses with the section
	var money_lbl: Label = balance_vbox.get_node("MoneyLabel")
	money_lbl.reparent(content)

	# Reputation line
	var rep_label := Label.new()
	rep_label.name = "ReputationLabel"
	rep_label.text = "Reputation: %s (%+.0f)" % [Reputation.get_tier_name(), Reputation.score]
	_color_reputation_label(rep_label)
	content.add_child(rep_label)

	_make_collapsible("numbers", title, content, true)

func _refresh_balance_history() -> void:
	_free_children(transactions_list)
	var history := GameState.financial_history
	if history.is_empty():
		var empty := Label.new()
		empty.text = "No transactions yet"
		empty.add_theme_font_size_override("font_size", 12)
		empty.add_theme_color_override("font_color", Color(0.4, 0.4, 0.4))
		transactions_list.add_child(empty)
		return
	const MAX_DISPLAY := 40
	var start := maxi(0, history.size() - MAX_DISPLAY)
	for i in range(history.size() - 1, start - 1, -1):
		var entry: Dictionary = history[i]
		var change: int = int(entry["change"])
		var balance: int = int(entry["balance"])
		var ticks: float = float(entry["timestamp"])
		var day := int(ticks / 86400.0) + 1
		var hour := int(fmod(ticks, 86400.0) / 3600.0)
		var sign_str := "+" if change >= 0 else ""
		var desc: String = entry.get("desc", "")
		var ship: String = entry.get("ship", "")
		var ship_str := "  [%s]" % ship if ship != "" else ""
		var row := Label.new()
		row.text = "Day %d %02d:00  %s$%s  →  $%s  %s%s" % [
			day, hour, sign_str, _format_number(change), _format_number(balance),
			desc, ship_str
		]
		row.add_theme_font_size_override("font_size", 11)
		row.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if change >= 0:
			row.add_theme_color_override("font_color", Color(0.3, 0.85, 0.4))
		else:
			row.add_theme_color_override("font_color", Color(0.85, 0.4, 0.4))
		transactions_list.add_child(row)

func _setup_collapsible_sections() -> void:
	var base := "ScrollContainer/VBox"
	_make_collapsible("resources",    get_node(base + "/ResourcesCard/VBox/Title"),    resources_list,    true)
	_make_collapsible("missions",     get_node(base + "/MissionsCard/VBox/Title"),     missions_list,     true)
	_make_collapsible("workers",      get_node(base + "/WorkersCard/VBox/Title"),      workers_summary,   true)
	_make_collapsible("alerts",       get_node(base + "/AlertsCard/VBox/Title"),       alerts_scroll,     false)
	_make_collapsible("activity",     get_node(base + "/ActivityCard/VBox/Title"),     activity_scroll,   true)
	_make_collapsible("contracts",    get_node(base + "/ContractsCard/VBox/Title"),    contracts_scroll,  true)
	_make_collapsible("transactions", get_node(base + "/TransactionsCard/VBox/Title"), transactions_scroll, true)
	# Dynamically-created cards are handled when built (stationed ships, reputation, discipline, policies)

func _make_collapsible(key: String, title_label: Label, content: Node, start_collapsed: bool = false) -> void:
	_section_collapsed[key] = start_collapsed
	_section_content[key] = content
	_section_titles[key] = title_label
	content.visible = not start_collapsed
	title_label.mouse_filter = Control.MOUSE_FILTER_STOP
	title_label.text = title_label.text + (" ▸" if start_collapsed else " ▾")
	title_label.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle_section(key, title_label)
	)

func _toggle_section(key: String, title_label: Label) -> void:
	var collapsed: bool = not _section_collapsed.get(key, false)
	_section_collapsed[key] = collapsed
	var content: Node = _section_content.get(key)
	if content:
		content.visible = not collapsed
	# Update arrow indicator
	var base_text := title_label.text.trim_suffix(" ▾").trim_suffix(" ▸")
	title_label.text = base_text + (" ▸" if collapsed else " ▾")

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

func _on_worker_skill_leveled(worker: Worker, skill_type: int, new_value: float) -> void:
	var skill_name := ""
	match skill_type:
		0: skill_name = "Pilot"
		1: skill_name = "Engineer"
		2: skill_name = "Mining"
	var message := "[Worker] %s's %s skill increased to %.2f!" % [worker.worker_name, skill_name, new_value]
	_queue_activity(message, Color(0.3, 0.9, 0.9))
