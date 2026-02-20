extends MarginContainer

# Combined Fleet + Market tab with ship-centric view

@onready var ships_list: VBoxContainer = %ShipsList
@onready var dispatch_popup: PanelContainer = %DispatchPopup
@onready var dispatch_content: VBoxContainer = %DispatchContent
@onready var dispatch_buttons: HBoxContainer = %DispatchButtons
@onready var buy_ship_popup: PanelContainer = %BuyShipPopup
@onready var buy_ship_content: VBoxContainer = %BuyShipContent
@onready var _ships_scroll: ScrollContainer = %ShipsList.get_parent()
@onready var _tab_title: Label = $VBox/Title

var _selected_ship: Ship = null
var _selected_asteroid: AsteroidData = null
var _selected_workers: Array[Worker] = []
var _selected_transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE
var _selected_mission_type: int = Mission.MissionType.MINING
var _selected_deploy_units: Array[MiningUnit] = []
var _selected_deploy_workers: Array[Worker] = []
var _sell_at_destination_markets: bool = true  # Toggle: return with ore vs sell at nearby markets
var _sort_by: String = "profit"
var _filter_type: int = -1
var _available_slingshot_routes: Array = []  # Array of GravityAssist.SlingshotRoute
var _selected_slingshot_route = null  # GravityAssist.SlingshotRoute or null
var _needs_full_rebuild: bool = true
var _progress_bars: Dictionary = {}
var _status_labels: Dictionary = {}
var _detail_labels: Dictionary = {}
var _location_labels: Dictionary = {}
var _cargo_labels: Dictionary = {}  # Ship -> Label for cargo display
const PROGRESS_LERP_SPEED: float = 8.0  # How fast progress bars catch up
var _dispatch_refresh_timer: float = 0.0
const DISPATCH_REFRESH_INTERVAL: float = 2.0  # Refresh dispatch popup every 2 seconds
var _last_tick_msec: int = 0
const TICK_THROTTLE_MSEC: int = 100  # Only process ticks every 100ms real-time
var _on_selection_screen: bool = false  # Track if we're on the initial destination selection screen
var _on_estimate_screen: bool = false  # Track if we're on the worker selection / estimate screen
var _saved_colonies_scroll: float = 0.0  # Preserve scroll position across refreshes
var _saved_mining_scroll: float = 0.0  # Preserve scroll position across refreshes
# In-place update references for destination lists
var _colony_dest_buttons: Dictionary = {}  # Colony -> Button
var _mining_dest_buttons: Dictionary = {}  # AsteroidData -> Button
var _colony_dest_data: Array = []  # Ordered list of Colony for current view
var _mining_dest_data: Array = []  # Ordered list of AsteroidData for current view
var _mining_scroll: ScrollContainer = null  # Reference for collapsible toggle
var _colonies_scroll: ScrollContainer = null  # Reference for collapsible toggle
var _mining_header_label: Label = null  # Clickable toggle header
var _colonies_header_label: Label = null  # Clickable toggle header
var _mining_controls: HFlowContainer = null  # Filter/sort controls for mining section
var _worker_checkboxes: Dictionary = {}  # Worker -> CheckBox for programmatic toggling
var _colonies_section_expanded: int = -1  # -1 = use default (cargo-based), 0 = collapsed, 1 = expanded
var _mining_section_expanded: int = -1  # -1 = use default (cargo-based), 0 = collapsed, 1 = expanded

static func _free_children(container: Node) -> void:
	for i in range(container.get_child_count() - 1, -1, -1):
		container.get_child(i).queue_free()

func _ready() -> void:
	_cancel_preview()
	_hide_dispatch()
	_hide_buy_ship()
	EventBus.ship_purchased.connect(func(_s: Ship, _c: int) -> void: _mark_dirty())
	EventBus.mission_started.connect(func(_m: Mission) -> void: _mark_dirty())
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _mark_dirty())
	EventBus.mission_phase_changed.connect(func(_m: Mission) -> void: _mark_dirty())
	EventBus.equipment_installed.connect(func(_s: Ship, _e: Equipment) -> void: _mark_dirty())
	EventBus.equipment_broken.connect(func(_s: Ship, _e: Equipment) -> void: _mark_dirty())
	EventBus.equipment_repaired.connect(func(_s: Ship, _e: Equipment) -> void: _mark_dirty())
	EventBus.trade_mission_started.connect(func(_tm: TradeMission) -> void: _mark_dirty())
	EventBus.trade_mission_completed.connect(func(_tm: TradeMission) -> void: _mark_dirty())
	EventBus.trade_mission_phase_changed.connect(func(_tm: TradeMission) -> void: _mark_dirty())
	EventBus.ship_idle_at_destination.connect(func(_s: Ship, _m: Mission) -> void: _mark_dirty())
	EventBus.ship_idle_at_colony.connect(func(_s: Ship, _tm: TradeMission) -> void: _mark_dirty())
	EventBus.ship_breakdown.connect(func(_s: Ship, _r: String) -> void: _mark_dirty())
	EventBus.ship_derelict.connect(func(_s: Ship) -> void: _mark_dirty())
	EventBus.ship_destroyed.connect(func(_s: Ship, _b: String) -> void: _mark_dirty())
	EventBus.rescue_mission_started.connect(func(_s: Ship, _c: int) -> void: _mark_dirty())
	EventBus.rescue_mission_completed.connect(func(_s: Ship) -> void: _mark_dirty())
	EventBus.refuel_mission_started.connect(func(_s: Ship, _c: int, _f: float) -> void: _mark_dirty())
	EventBus.refuel_mission_completed.connect(func(_s: Ship, _f: float) -> void: _mark_dirty())
	EventBus.stranger_rescue_offered.connect(func(_s: Ship, _n: String) -> void: _mark_dirty())
	EventBus.stranger_rescue_completed.connect(func(_s: Ship, _n: String) -> void: _mark_dirty())
	EventBus.stranger_rescue_declined.connect(func(_s: Ship, _n: String) -> void: _mark_dirty())
	EventBus.resource_changed.connect(func(_o: ResourceTypes.OreType, _a: float) -> void: _mark_dirty())
	EventBus.money_changed.connect(func(_m: int) -> void: _mark_dirty())
	EventBus.ship_stationed.connect(func(_s: Ship, _c: Colony) -> void: _mark_dirty())
	EventBus.ship_unstationed.connect(func(_s: Ship) -> void: _mark_dirty())
	EventBus.station_job_started.connect(func(_s: Ship, _j: String, _d: String) -> void: _mark_dirty())
	EventBus.station_job_completed.connect(func(_s: Ship, _j: String, _su: String) -> void: _mark_dirty())
	EventBus.worker_hired.connect(_on_worker_hired)
	EventBus.tick.connect(_on_tick)
	_rebuild_ships()

func _mark_dirty() -> void:
	_needs_full_rebuild = true

func _show_dispatch() -> void:
	dispatch_popup.visible = true
	buy_ship_popup.visible = false
	_ships_scroll.visible = false
	_tab_title.visible = false

func _hide_dispatch() -> void:
	dispatch_popup.visible = false
	_ships_scroll.visible = true
	_tab_title.visible = true
	_clear_dispatch_buttons()

func _set_dispatch_buttons(buttons: Array) -> void:
	_clear_dispatch_buttons()
	for entry in buttons:
		var btn := Button.new()
		btn.text = entry["text"]
		btn.custom_minimum_size = Vector2(0, 44)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if entry.has("color"):
			btn.add_theme_color_override("font_color", entry["color"])
		btn.pressed.connect(entry["callback"])
		dispatch_buttons.add_child(btn)

func _clear_dispatch_buttons() -> void:
	_free_children(dispatch_buttons)

func _show_buy_ship() -> void:
	buy_ship_popup.visible = true
	dispatch_popup.visible = false
	_ships_scroll.visible = false
	_tab_title.visible = false
	_build_buy_ship_ui()

func _hide_buy_ship() -> void:
	buy_ship_popup.visible = false
	_ships_scroll.visible = true
	_tab_title.visible = true

func _process(delta: float) -> void:
	# Smooth LERP for progress bars
	for ship: Ship in _progress_bars:
		var bar: ProgressBar = _progress_bars[ship]
		if is_instance_valid(bar):
			var target_progress := 0.0
			var use_instant_update := false

			if ship in GameState.refuel_missions:
				var refuel_data: Dictionary = GameState.refuel_missions[ship]
				var refuel_progress: float = float(refuel_data["elapsed_ticks"]) / float(refuel_data["transit_time"])
				target_progress = refuel_progress * 100.0
			elif ship.current_mission:
				target_progress = ship.current_mission.get_progress() * 100.0
				# Instant update during mining so it matches ore accumulation
				use_instant_update = (ship.current_mission.status == Mission.Status.MINING)
			elif ship.current_trade_mission:
				target_progress = ship.current_trade_mission.get_progress() * 100.0

			if use_instant_update:
				bar.value = target_progress
			else:
				bar.value = lerp(bar.value, target_progress, PROGRESS_LERP_SPEED * delta)

func _on_worker_hired(_worker: Worker) -> void:
	# Refresh worker selection screen if currently visible
	if dispatch_popup.visible and _on_estimate_screen:
		_show_worker_selection()

func _on_tick(_dt: float) -> void:
	# Throttle tick processing to real-time (not game-time, which explodes at high speed)
	var now := Time.get_ticks_msec()
	if now - _last_tick_msec < TICK_THROTTLE_MSEC:
		return
	_last_tick_msec = now

	# Refresh dispatch popup periodically to update orbital positions and fuel estimates
	if dispatch_popup.visible:
		_dispatch_refresh_timer += 0.1  # Real-time increment (this block fires every 100ms)
		if _dispatch_refresh_timer >= DISPATCH_REFRESH_INTERVAL:
			_dispatch_refresh_timer = 0.0
			if _on_estimate_screen:
				_update_estimate_display()
				return
			elif _on_selection_screen:
				_update_destination_labels()
				return

	if _needs_full_rebuild:
		_needs_full_rebuild = false
		if not dispatch_popup.visible:
			_rebuild_ships()
		return
	# Update labels (not progress - that's done in _process with LERP)
	for ship: Ship in _status_labels:
		var label: Label = _status_labels[ship]
		if is_instance_valid(label):
			if ship.current_mission:
				label.text = ship.current_mission.get_status_text()
			elif ship.current_trade_mission:
				label.text = ship.current_trade_mission.get_status_text()
	for ship: Ship in _detail_labels:
		var label: Label = _detail_labels[ship]
		if is_instance_valid(label):
			label.text = _build_details_text(ship)
	# Update cargo displays to show incremental amounts during mining
	for ship: Ship in _cargo_labels:
		var label: Label = _cargo_labels[ship]
		if is_instance_valid(label) and ship.get_cargo_total() > 0.01:
			var cargo_lines: Array[String] = ["Cargo (%.1ft):" % ship.get_cargo_total()]
			for ore_type in ship.current_cargo:
				var amount: float = ship.current_cargo[ore_type]
				if amount > 0.01:
					cargo_lines.append("  %s: %.1ft" % [ResourceTypes.get_ore_name(ore_type), amount])
			label.text = "\n".join(cargo_lines)
	# Update location displays to show ship positions during transit
	for ship: Ship in _location_labels:
		var label: Label = _location_labels[ship]
		if is_instance_valid(label):
			label.text = _get_location_text(ship)

func _rebuild_ships() -> void:
	_progress_bars.clear()
	_status_labels.clear()
	_detail_labels.clear()
	_cargo_labels.clear()
	_location_labels.clear()
	_free_children(ships_list)

	for ship: Ship in GameState.ships:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 4)

		# === SHIP HEADER ===
		var header := VBoxContainer.new()
		header.add_theme_constant_override("separation", 2)
		var name_label := Label.new()
		name_label.text = "%s (%s)" % [ship.ship_name, ship.get_class_name()]
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		header.add_child(name_label)

		var _derelict_actions: HFlowContainer = null  # Populated below for derelict ships
		if ship.is_derelict:
			var status := Label.new()
			var status_text := "STRANDED (OUT OF FUEL)" if ship.derelict_reason == "out_of_fuel" else "DERELICT (BREAKDOWN)"
			if ship.speed_au_per_tick > 0.0:
				var speed_km_s := ship.speed_au_per_tick * CelestialData.AU_TO_METERS / 1000.0
				status_text += " — Drifting %.1f km/s" % speed_km_s
			status.text = status_text
			status.add_theme_color_override("font_color", Color(0.9, 0.2, 0.2))
			header.add_child(status)

			_derelict_actions = HFlowContainer.new()
			_derelict_actions.add_theme_constant_override("h_separation", 8)

			# Show refuel in progress
			if ship in GameState.refuel_missions:
				var refuel_data: Dictionary = GameState.refuel_missions[ship]
				var elapsed: float = refuel_data["elapsed_ticks"]
				var total: float = refuel_data["transit_time"]
				var progress: float = elapsed / total
				var remaining := total - elapsed
				var source_name: String = refuel_data.get("source_name", "Earth")
				var refuel_label := Label.new()
				refuel_label.text = "Refuel: %d%% — ETA %s from %s" % [int(progress * 100), TimeScale.format_time(remaining), source_name]
				refuel_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9))
				_derelict_actions.add_child(refuel_label)
			# Show rescue in progress
			elif ship in GameState.rescue_missions:
				var rescue_data: Dictionary = GameState.rescue_missions[ship]
				var elapsed: float = rescue_data["elapsed_ticks"]
				var total: float = rescue_data["transit_time"]
				var progress: float = elapsed / total
				var remaining := total - elapsed
				var source_name: String = rescue_data.get("source_name", "Earth")
				var rescue_label := Label.new()
				rescue_label.text = "Rescue: %d%% — ETA %s from %s" % [int(progress * 100), TimeScale.format_time(remaining), source_name]
				rescue_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.2))
				_derelict_actions.add_child(rescue_label)
			else:
				# Stranger offer
				if ship in GameState.stranger_offers:
					var offer: Dictionary = GameState.stranger_offers[ship]
					var stranger_name: String = offer["stranger_name"]
					var tip: int = offer["suggested_tip"]
					var offer_label := Label.new()
					offer_label.text = "A passing vessel (%s) is offering assistance" % stranger_name
					offer_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
					offer_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					offer_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
					_derelict_actions.add_child(offer_label)

					var accept_free_btn := Button.new()
					accept_free_btn.text = "Accept (Free)"
					accept_free_btn.custom_minimum_size = Vector2(0, 44)
					accept_free_btn.pressed.connect(func() -> void:
						GameState.accept_stranger_rescue(ship, false)
						_mark_dirty()
					)
					_derelict_actions.add_child(accept_free_btn)

					var accept_pay_btn := Button.new()
					accept_pay_btn.text = "Accept + Pay $%s" % _format_number(tip)
					accept_pay_btn.custom_minimum_size = Vector2(0, 44)
					accept_pay_btn.disabled = GameState.money < tip
					accept_pay_btn.pressed.connect(func() -> void:
						GameState.accept_stranger_rescue(ship, true)
						_mark_dirty()
					)
					_derelict_actions.add_child(accept_pay_btn)

					var decline_btn := Button.new()
					decline_btn.text = "Decline"
					decline_btn.custom_minimum_size = Vector2(0, 44)
					decline_btn.pressed.connect(func() -> void:
						GameState.decline_stranger_rescue(ship)
						_mark_dirty()
					)
					_derelict_actions.add_child(decline_btn)

				# Refuel option (cheaper, only for fuel depletion)
				if ship.derelict_reason == "out_of_fuel" and ship not in GameState.stranger_offers:
					var refuel_cost := GameState.get_refuel_cost(ship, ship.fuel_capacity)
					var refuel_btn := Button.new()
					refuel_btn.text = "Refuel ($%s)" % _format_number(refuel_cost)
					refuel_btn.custom_minimum_size = Vector2(0, 44)
					refuel_btn.disabled = GameState.money < refuel_cost
					refuel_btn.pressed.connect(func() -> void:
						GameState.start_refuel(ship, ship.fuel_capacity)
						_mark_dirty()
					)
					_derelict_actions.add_child(refuel_btn)

				# Rescue option (expensive, for breakdowns or as alternative)
				if ship not in GameState.stranger_offers:
					var rescue_cost := GameState.get_rescue_cost(ship)
					var rescue_btn := Button.new()
					rescue_btn.text = "Rescue ($%s)" % _format_number(rescue_cost)
					rescue_btn.custom_minimum_size = Vector2(0, 44)
					rescue_btn.disabled = GameState.money < rescue_cost
					rescue_btn.pressed.connect(func() -> void:
						GameState.start_rescue(ship)
						_mark_dirty()
					)
					_derelict_actions.add_child(rescue_btn)
		elif ship.is_stationed:
			var status := Label.new()
			if ship.is_stationed_idle:
				status.text = "STATIONED @ %s (idle)" % ship.station_colony.colony_name
			elif ship.current_mission:
				status.text = "STATIONED @ %s — %s" % [ship.station_colony.colony_name, ship.current_mission.get_status_text()]
			elif ship.current_trade_mission:
				status.text = "STATIONED @ %s — %s" % [ship.station_colony.colony_name, ship.current_trade_mission.get_status_text()]
			else:
				status.text = "STATIONED @ %s" % ship.station_colony.colony_name
			status.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
			header.add_child(status)
			_status_labels[ship] = status
		elif ship.is_docked:
			var status := Label.new()
			if ship.docked_at_colony:
				status.text = "Docked at %s" % ship.docked_at_colony.colony_name
			else:
				status.text = "Docked at Earth"
			status.add_theme_color_override("font_color", Color(0.3, 0.8, 0.3))
			header.add_child(status)
		elif ship.is_idle_remote:
			var status := Label.new()
			if ship.current_mission and ship.current_mission.status == Mission.Status.IDLE_AT_DESTINATION:
				status.text = "Idle at " + ship.current_mission.asteroid.asteroid_name
			elif ship.current_trade_mission and ship.current_trade_mission.status == TradeMission.Status.IDLE_AT_COLONY:
				status.text = "Idle at " + ship.current_trade_mission.colony.colony_name
			else:
				status.text = "Idle (remote)"
			status.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
			header.add_child(status)
			_status_labels[ship] = status
		else:
			var status := Label.new()
			# Check for refuel mission first
			if ship in GameState.refuel_missions:
				var refuel_data: Dictionary = GameState.refuel_missions[ship]
				var progress: float = float(refuel_data["elapsed_ticks"]) / float(refuel_data["transit_time"])
				status.text = "Refueling: %d%%" % int(progress * 100)
				status.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9))
			elif ship.current_mission:
				status.text = ship.current_mission.get_status_text()
				status.add_theme_color_override("font_color", Color(0.8, 0.7, 0.2))
			elif ship.current_trade_mission:
				status.text = ship.current_trade_mission.get_status_text()
				status.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
			header.add_child(status)
			_status_labels[ship] = status

		vbox.add_child(header)
		if _derelict_actions:
			vbox.add_child(_derelict_actions)

		# === LOCATION & DETAILS ===
		var loc_label := Label.new()
		loc_label.text = _get_location_text(ship)
		loc_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		loc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		loc_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(loc_label)
		_location_labels[ship] = loc_label

		var details := Label.new()
		details.text = _build_details_text(ship)
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_child(details)
		_detail_labels[ship] = details

		# === CARGO DISPLAY ===
		if ship.get_cargo_total() > 0.01:
			var cargo_label := Label.new()
			var cargo_lines: Array[String] = ["Cargo (%.1ft):" % ship.get_cargo_total()]
			for ore_type in ship.current_cargo:
				var amount: float = ship.current_cargo[ore_type]
				# Only show ore types with meaningful amounts (skip near-zero from floating point)
				if amount > 0.01:
					cargo_lines.append("  %s: %.1ft" % [ResourceTypes.get_ore_name(ore_type), amount])
			cargo_label.text = "\n".join(cargo_lines)
			cargo_label.add_theme_color_override("font_color", Color(0.7, 0.9, 0.7))
			vbox.add_child(cargo_label)
			_cargo_labels[ship] = cargo_label  # Store reference for updates

		# === ACTION BUTTONS ===

		# Stationed ships: Edit Jobs and Unstation
		if ship.is_stationed:
			# Show active jobs list
			var jobs_label := Label.new()
			var jobs_text := "Jobs: " + ", ".join(ship.station_jobs) if not ship.station_jobs.is_empty() else "Jobs: None"
			jobs_label.text = jobs_text
			jobs_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9))
			jobs_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			vbox.add_child(jobs_label)

			# Show recent station log
			if not ship.station_log.is_empty():
				var log_label := Label.new()
				var recent := ship.station_log[0]
				var elapsed := GameState.total_ticks - float(recent["time"])
				var time_ago := TimeScale.format_time(elapsed) + " ago" if elapsed > 0 else "just now"
				log_label.text = "Last: %s (%s)" % [recent["message"], time_ago]
				log_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
				log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				vbox.add_child(log_label)

			var station_btn_row := HBoxContainer.new()
			station_btn_row.add_theme_constant_override("separation", 8)

			var edit_jobs_btn := Button.new()
			edit_jobs_btn.text = "Edit Jobs"
			edit_jobs_btn.custom_minimum_size = Vector2(0, 44)
			edit_jobs_btn.pressed.connect(_show_station_jobs.bind(ship))
			station_btn_row.add_child(edit_jobs_btn)

			var unstation_btn := Button.new()
			unstation_btn.text = "Unstation"
			unstation_btn.custom_minimum_size = Vector2(0, 44)
			unstation_btn.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
			unstation_btn.pressed.connect(func() -> void:
				GameState.unstation_ship(ship)
				_mark_dirty()
			)
			station_btn_row.add_child(unstation_btn)

			vbox.add_child(station_btn_row)

			# Buy Supplies button (only when docked at station colony)
			if ship.is_stationed_idle and ship.station_colony != null:
				var supply_btn := Button.new()
				supply_btn.text = "Buy Supplies"
				supply_btn.custom_minimum_size = Vector2(0, 44)
				supply_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 0.5))
				supply_btn.pressed.connect(_show_supply_shop.bind(ship))
				vbox.add_child(supply_btn)

				# Show current supplies if any
				if not ship.supplies.is_empty():
					var supply_text := "Supplies: "
					var parts: Array[String] = []
					for key in ship.supplies:
						if ship.supplies[key] > 0:
							parts.append("%s: %.0f" % [key.replace("_", " ").capitalize(), ship.supplies[key]])
					if not parts.is_empty():
						supply_text += ", ".join(parts)
						var supply_label := Label.new()
						supply_label.text = supply_text
						supply_label.add_theme_color_override("font_color", Color(0.4, 0.8, 0.5))
						supply_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
						vbox.add_child(supply_label)

		# Docked ships: Dispatch, Unload, and Station
		if ship.is_docked and not ship.is_stationed:
			var btn_row := HBoxContainer.new()
			btn_row.add_theme_constant_override("separation", 8)

			var dispatch_btn := Button.new()
			dispatch_btn.text = "Dispatch"
			dispatch_btn.custom_minimum_size = Vector2(0, 44)
			dispatch_btn.pressed.connect(_start_dispatch.bind(ship))
			btn_row.add_child(dispatch_btn)

			# Unload cargo button
			if ship.get_cargo_total() > 0:
				var unload_btn := Button.new()
				unload_btn.text = "Unload to Stockpile"
				unload_btn.custom_minimum_size = Vector2(0, 44)
				unload_btn.pressed.connect(func() -> void:
					for ore_type in ship.current_cargo:
						GameState.add_resource(ore_type, ship.current_cargo[ore_type])
					ship.current_cargo.clear()
					_mark_dirty()
				)
				btn_row.add_child(unload_btn)

			# Station Here button (only at colonies, not at Earth)
			if ship.docked_at_colony != null:
				var station_btn := Button.new()
				station_btn.text = "Station Here"
				station_btn.custom_minimum_size = Vector2(0, 44)
				station_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
				station_btn.pressed.connect(_show_station_jobs.bind(ship))
				btn_row.add_child(station_btn)

			vbox.add_child(btn_row)

		# Idle remote ships: Sell at colony, Dispatch, Return
		if ship.is_idle_remote:
			var at_colony: Colony = null
			if ship.current_trade_mission and ship.current_trade_mission.status == TradeMission.Status.IDLE_AT_COLONY:
				at_colony = ship.current_trade_mission.colony

			# Contract fulfillment and cargo selling options
			if at_colony and ship.get_cargo_total() > 0:
				# Check for matching contracts
				var matching_contracts := _get_matching_contracts(ship, at_colony)

				# Show contract options if any match
				if not matching_contracts.is_empty():
					var contract_header := Label.new()
					contract_header.text = "Available Contracts at %s:" % at_colony.colony_name
					contract_header.add_theme_font_size_override("font_size", 14)
					contract_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
					vbox.add_child(contract_header)

					for contract in matching_contracts:
						_add_contract_fulfillment_ui(vbox, ship, contract, at_colony)

					var sep := HSeparator.new()
					vbox.add_child(sep)

				# Spot market sell button
				var sell_btn := Button.new()
				var revenue := 0
				for ore_type in ship.current_cargo:
					var amount: float = ship.current_cargo[ore_type]
					var price: float = at_colony.get_ore_price(ore_type, GameState.market)
					revenue += int(amount * price)
				sell_btn.text = "Sell All on Spot Market ($%s)" % _format_number(revenue)
				sell_btn.custom_minimum_size = Vector2(0, 44)
				sell_btn.pressed.connect(func() -> void:
					var total_revenue := 0
					for ore_type in ship.current_cargo:
						var amount: float = ship.current_cargo[ore_type]
						var price: float = at_colony.get_ore_price(ore_type, GameState.market)
						total_revenue += int(amount * price)
					GameState.money += total_revenue
					ship.current_cargo.clear()
					_mark_dirty()
				)
				vbox.add_child(sell_btn)

			var action_row := HBoxContainer.new()
			action_row.add_theme_constant_override("separation", 8)

			var dispatch_btn := Button.new()
			dispatch_btn.text = "Dispatch"
			dispatch_btn.custom_minimum_size = Vector2(0, 44)
			dispatch_btn.pressed.connect(_start_dispatch.bind(ship))
			action_row.add_child(dispatch_btn)

			var return_btn := Button.new()
			return_btn.text = "Return to Earth"
			return_btn.custom_minimum_size = Vector2(0, 44)
			return_btn.pressed.connect(func() -> void:
				GameState.order_return_to_earth(ship)
				_mark_dirty()
			)
			action_row.add_child(return_btn)

			vbox.add_child(action_row)

		# Engine repair button (docked ships with engine < 100)
		if ship.is_docked and ship.engine_condition < 100.0:
			var repair_cost := ship.get_engine_repair_cost()
			var engine_btn := Button.new()
			engine_btn.text = "Repair Engine ($%s)" % _format_number(repair_cost)
			engine_btn.custom_minimum_size = Vector2(0, 44)
			engine_btn.disabled = GameState.money < repair_cost
			engine_btn.pressed.connect(func() -> void:
				GameState.repair_engine(ship)
				_mark_dirty()
			)
			vbox.add_child(engine_btn)

		# === EQUIPMENT ===
		if not ship.equipment.is_empty():
			for e in ship.equipment:
				var equip_row := HBoxContainer.new()
				equip_row.add_theme_constant_override("separation", 6)

				var equip_label := Label.new()
				var dur_str := "%d%%" % int(e.durability)
				var broken_str := ""
				if e.durability <= 0:
					broken_str = " (BROKEN)"
					equip_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
				elif e.durability < 30:
					equip_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
				else:
					equip_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))

				equip_label.text = "%s (%.2fx) %s%s" % [e.equipment_name, e.mining_bonus, dur_str, broken_str]
				equip_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				equip_label.clip_text = true
				equip_row.add_child(equip_label)

				var dur_bar := ProgressBar.new()
				dur_bar.custom_minimum_size = Vector2(60, 0)
				dur_bar.value = e.durability
				dur_bar.max_value = e.max_durability
				equip_row.add_child(dur_bar)

				vbox.add_child(equip_row)

		# === PROGRESS BAR ===
		if not ship.is_docked and not ship.is_idle_remote and not ship.is_derelict and not ship.is_stationed_idle:
			var progress := ProgressBar.new()
			if ship in GameState.refuel_missions:
				var refuel_data: Dictionary = GameState.refuel_missions[ship]
				var refuel_progress: float = float(refuel_data["elapsed_ticks"]) / float(refuel_data["transit_time"])
				progress.value = refuel_progress * 100.0
			elif ship.current_mission:
				progress.value = ship.current_mission.get_progress() * 100.0
			elif ship.current_trade_mission:
				progress.value = ship.current_trade_mission.get_progress() * 100.0
			vbox.add_child(progress)
			_progress_bars[ship] = progress

			# === QUEUED MISSION INFO & PLAN BUTTON ===
			# Show queued mission info if one is set
			if ship.has_queued_mission():
				var queued_info := Label.new()
				var dest_name := ""
				if ship.queued_destination is AsteroidData:
					dest_name = ship.queued_destination.asteroid_name
				elif ship.queued_destination is Colony:
					dest_name = ship.queued_destination.colony_name
				queued_info.text = "Queued: %s (%d crew)" % [dest_name, ship.queued_workers.size()]
				queued_info.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
				queued_info.add_theme_font_size_override("font_size", 14)
				vbox.add_child(queued_info)

			var plan_row := HBoxContainer.new()
			plan_row.add_theme_constant_override("separation", 8)

			var plan_btn := Button.new()
			plan_btn.text = "Plan Next Mission" if not ship.has_queued_mission() else "Change Queued Mission"
			plan_btn.custom_minimum_size = Vector2(0, 44)
			plan_btn.pressed.connect(_start_dispatch.bind(ship, true))  # true = planning mode
			plan_row.add_child(plan_btn)

			# Clear queue button if mission is queued
			if ship.has_queued_mission():
				var clear_btn := Button.new()
				clear_btn.text = "Clear Queue"
				clear_btn.custom_minimum_size = Vector2(0, 44)
				clear_btn.pressed.connect(func() -> void:
					ship.clear_queued_mission()
					_mark_dirty()
				)
				plan_row.add_child(clear_btn)

			vbox.add_child(plan_row)

		panel.add_child(vbox)
		ships_list.add_child(panel)

	# Add "Buy Ship" button at the end
	var buy_ship_panel := PanelContainer.new()
	buy_ship_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var buy_ship_vbox := VBoxContainer.new()
	buy_ship_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var buy_ship_btn := Button.new()
	buy_ship_btn.text = "Buy New Ship"
	buy_ship_btn.custom_minimum_size = Vector2(0, 56)
	buy_ship_btn.pressed.connect(_show_buy_ship)
	buy_ship_vbox.add_child(buy_ship_btn)

	buy_ship_panel.add_child(buy_ship_vbox)
	ships_list.add_child(buy_ship_panel)

# Include all the helper functions from fleet_tab.gd
func _get_location_text(ship: Ship) -> String:
	if ship.is_stationed and ship.station_colony:
		return "Location: %s (stationed)" % ship.station_colony.colony_name
	if ship.is_at_earth:
		return "Location: Earth"
	if ship.docked_at_colony:
		return "Location: %s" % ship.docked_at_colony.colony_name
	if ship.current_mission:
		match ship.current_mission.status:
			Mission.Status.IDLE_AT_DESTINATION:
				return "Location: At %s" % ship.current_mission.asteroid.asteroid_name
			Mission.Status.MINING:
				return "Location: At %s" % ship.current_mission.asteroid.asteroid_name
			_:
				return "Location: Deep space (%.2f, %.2f AU)" % [ship.position_au.x, ship.position_au.y]
	if ship.current_trade_mission:
		match ship.current_trade_mission.status:
			TradeMission.Status.IDLE_AT_COLONY, TradeMission.Status.SELLING:
				return "Location: At %s" % ship.current_trade_mission.colony.colony_name
			_:
				return "Location: Deep space (%.2f, %.2f AU)" % [ship.position_au.x, ship.position_au.y]
	return "Location: Deep space (%.2f, %.2f AU)" % [ship.position_au.x, ship.position_au.y]

func _cancel_preview() -> void:
	EventBus.mission_preview_cancelled.emit()

var _is_planning_mode: bool = false  # Track if we're planning next mission (vs immediate dispatch)

func _start_dispatch(ship: Ship, planning_mode: bool = false) -> void:
	_selected_ship = ship
	_selected_asteroid = null
	_selected_workers.clear()
	_selected_mission_type = Mission.MissionType.MINING
	_selected_deploy_units.clear()
	_selected_deploy_workers.clear()
	_sort_by = "profit"
	_filter_type = -1
	_is_planning_mode = planning_mode
	_colonies_section_expanded = -1  # Reset to cargo-based default
	_mining_section_expanded = -1

	# Show popup immediately for responsiveness
	dispatch_popup.visible = true

	# Populate content in next frame (feels instant, avoids UI lag)
	await get_tree().process_frame
	_show_asteroid_selection()

func _show_asteroid_selection() -> void:
	_on_selection_screen = true  # We're on the main selection screen
	_on_estimate_screen = false  # Not on estimate screen

	# Save scroll positions before clearing (if they exist)
	for child in dispatch_content.get_children():
		if child is ScrollContainer:
			if child.name == "ColoniesScroll":
				_saved_colonies_scroll = child.scroll_vertical
			elif child.name == "MiningScroll":
				_saved_mining_scroll = child.scroll_vertical

	_clear_dispatch_content()
	_colony_dest_buttons.clear()
	_colony_dest_data.clear()
	_mining_dest_buttons.clear()
	_mining_dest_data.clear()

	var title := Label.new()
	title.text = "Select Destination"
	title.add_theme_font_size_override("font_size", 20)
	dispatch_content.add_child(title)

	# Show ship origin info and cargo
	var origin_label := Label.new()
	var cargo_total := _selected_ship.get_cargo_total()
	if cargo_total > 0:
		origin_label.text = "Dispatching from: %s (%.1ft cargo)" % [_get_location_text(_selected_ship), cargo_total]
	else:
		origin_label.text = "Dispatching from: %s" % _get_location_text(_selected_ship)
	origin_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	origin_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	dispatch_content.add_child(origin_label)

	# Determine layout priority: use persisted toggle state, or default from cargo
	var has_cargo_for_selling := cargo_total > 0
	var colonies_expanded: bool
	var mining_expanded: bool
	if _colonies_section_expanded >= 0:
		colonies_expanded = _colonies_section_expanded == 1
	else:
		colonies_expanded = has_cargo_for_selling
	if _mining_section_expanded >= 0:
		mining_expanded = _mining_section_expanded == 1
	else:
		mining_expanded = not has_cargo_for_selling

	# --- MARKET DESTINATIONS SECTION (always present) ---
	var colonies_header := Label.new()
	_colonies_header_label = colonies_header
	colonies_header.text = "MARKET DESTINATIONS %s" % ("▾" if colonies_expanded else "▸")
	colonies_header.add_theme_font_size_override("font_size", 18)
	colonies_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
	colonies_header.mouse_filter = Control.MOUSE_FILTER_STOP
	colonies_header.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle_colonies_section()
	)
	dispatch_content.add_child(colonies_header)

	var colonies_scroll := ScrollContainer.new()
	_colonies_scroll = colonies_scroll
	colonies_scroll.name = "ColoniesScroll"
	colonies_scroll.size_flags_vertical = Control.SIZE_FILL
	colonies_scroll.custom_minimum_size = Vector2(0, 400 if colonies_expanded else 0)
	colonies_scroll.visible = colonies_expanded
	colonies_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var colonies_vbox := VBoxContainer.new()
	colonies_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	colonies_vbox.add_theme_constant_override("separation", 6)

	# Sort colonies by profit (revenue - fuel cost)
	var sorted_colonies := GameState.colonies.duplicate()
	sorted_colonies.sort_custom(func(a: Colony, b: Colony) -> bool:
		var profit_a := _calculate_colony_profit(a)
		var profit_b := _calculate_colony_profit(b)
		return profit_a > profit_b  # Highest profit first
	)

	# Filter out current location to prevent exploit (within 0.1 AU proximity)
	const PROXIMITY_THRESHOLD := 0.1
	var filtered_colonies: Array[Colony] = []
	for colony in sorted_colonies:
		var dist_to_colony := _selected_ship.position_au.distance_to(colony.get_position_au())
		if dist_to_colony > PROXIMITY_THRESHOLD:
			filtered_colonies.append(colony)

	for colony in filtered_colonies:
		var colony_pos: Vector2 = colony.get_position_au()
		var dist := _selected_ship.position_au.distance_to(colony_pos)
		var transit := Brachistochrone.transit_time(dist, _selected_ship.get_effective_thrust())

		# Calculate WORST-CASE round-trip fuel (loaded outbound, empty return)
		var cargo_mass := _selected_ship.get_cargo_total()
		var fuel_outbound := _selected_ship.calc_fuel_for_distance(dist, cargo_mass)
		var fuel_return := _selected_ship.calc_fuel_for_distance(dist, 0.0)
		var fuel_needed := fuel_outbound + fuel_return

		# Calculate potential revenue from cargo
		var revenue := 0
		var cargo_breakdown := ""
		for ore_type in _selected_ship.current_cargo:
			var amount: float = _selected_ship.current_cargo[ore_type]
			var price: float = colony.get_ore_price(ore_type, GameState.market)
			revenue += int(amount * price)
			if cargo_breakdown != "":
				cargo_breakdown += ", "
			cargo_breakdown += "%s: $%s" % [ResourceTypes.get_ore_name(ore_type), _format_number(int(amount * price))]

		var fuel_status := ""
		# If ship is at a colony, assume it can refuel before departing
		var available_fuel := _selected_ship.get_effective_fuel_capacity() if _selected_ship.is_idle_remote else _selected_ship.fuel
		var has_insufficient_fuel := fuel_needed > available_fuel
		var has_cargo := cargo_mass > 0

		# Calculate fuel route if needed
		var fuel_route: Array[String] = []
		var is_unreachable := false
		if has_insufficient_fuel:
			fuel_route = _calculate_fuel_route(colony)
			if fuel_route.is_empty():
				# Completely unreachable
				is_unreachable = true
				# Skip if setting is disabled
				if not GameState.settings.get("show_unreachable_destinations", false):
					continue
				fuel_status = " [UNREACHABLE - insufficient fuel capacity]"
			else:
				fuel_status = " [NEEDS REFUEL]"
		elif fuel_needed > available_fuel * 0.9:
			fuel_status = " [CRITICAL - %.0f/%.0f fuel]" % [available_fuel, fuel_needed]

		# Create row container for destination + jettison buttons
		var colony_row := VBoxContainer.new()
		colony_row.add_theme_constant_override("separation", 4)

		# Name label
		var name_label := Label.new()
		name_label.text = "%s (MARKET)" % colony.colony_name
		name_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.6))
		colony_row.add_child(name_label)

		# Fixed-width data fields
		var data_row := HBoxContainer.new()
		data_row.add_theme_constant_override("separation", 8)

		var col_dist_label := Label.new()
		col_dist_label.custom_minimum_size = Vector2(120, 0)
		col_dist_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		var col_dv := Brachistochrone.delta_v_km_s(dist, _selected_ship.get_effective_thrust())
		col_dist_label.text = "%.0f km/s Δv" % col_dv
		data_row.add_child(col_dist_label)

		var col_time_label := Label.new()
		col_time_label.custom_minimum_size = Vector2(100, 0)
		col_time_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		col_time_label.text = _format_time(transit)
		data_row.add_child(col_time_label)

		var col_revenue_label := Label.new()
		col_revenue_label.custom_minimum_size = Vector2(120, 0)
		col_revenue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		col_revenue_label.text = "$%s" % _format_number(revenue)
		col_revenue_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		data_row.add_child(col_revenue_label)

		var col_warning_label := Label.new()
		col_warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col_warning_label.add_theme_font_size_override("font_size", 12)
		col_warning_label.text = fuel_status
		if "CRITICAL" in fuel_status or "UNREACHABLE" in fuel_status:
			col_warning_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		elif fuel_status != "":
			col_warning_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		data_row.add_child(col_warning_label)

		colony_row.add_child(data_row)

		# Cargo breakdown row
		if cargo_breakdown != "":
			var cargo_label := Label.new()
			cargo_label.text = cargo_breakdown
			cargo_label.add_theme_font_size_override("font_size", 12)
			cargo_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5))
			cargo_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			colony_row.add_child(cargo_label)

		# Dispatch button
		var btn := Button.new()
		btn.text = "Sell Here"
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btn.custom_minimum_size = Vector2(0, 36)
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = is_unreachable
		btn.pressed.connect(func() -> void:
			_confirm_colony_dispatch(colony)
		)
		colony_row.add_child(btn)

		# Show fuel stop route as clickable buttons
		if not fuel_route.is_empty():
			var route_label := Label.new()
			route_label.text = "  Fuel stops needed:"
			route_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9))
			colony_row.add_child(route_label)

			var stops_hbox := HFlowContainer.new()
			stops_hbox.add_theme_constant_override("h_separation", 8)
			for stop_name in fuel_route:
				# Find the colony by name
				var stop_colony: Colony = null
				for c in GameState.colonies:
					if c.colony_name == stop_name:
						stop_colony = c
						break

				if stop_colony:
					var stop_btn := Button.new()
					stop_btn.text = stop_name
					stop_btn.custom_minimum_size = Vector2(0, 36)
					stop_btn.focus_mode = Control.FOCUS_NONE
					stop_btn.pressed.connect(func() -> void:
						_confirm_colony_dispatch(stop_colony)
					)
					stops_hbox.add_child(stop_btn)

			colony_row.add_child(stops_hbox)

		# ALWAYS show action buttons if ship has cargo
		if has_cargo:
			var jettison_row := HFlowContainer.new()
			jettison_row.add_theme_constant_override("h_separation", 8)

			var jettison_label := Label.new()
			jettison_label.text = "  Jettison cargo:"
			jettison_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
			jettison_row.add_child(jettison_label)

			# Smart jettison button (minimum needed)
			var smart_btn := Button.new()
			smart_btn.text = "Dump to Fit"
			smart_btn.custom_minimum_size = Vector2(0, 36)
			smart_btn.tooltip_text = "Jettison minimum cargo needed to make this trip"
			smart_btn.focus_mode = Control.FOCUS_NONE
			smart_btn.flat = true
			smart_btn.pressed.connect(func() -> void:
				var jettisoned := GameState.jettison_cargo_for_trip(_selected_ship, dist, 0.0)  # Empty on return
				_show_asteroid_selection()  # Refresh the list
				print("Jettisoned %.1f tons to make trip viable" % jettisoned)
			)
			jettison_row.add_child(smart_btn)

			# Dump all button
			var dump_all_btn := Button.new()
			dump_all_btn.text = "Dump All (%.0ft)" % cargo_mass
			dump_all_btn.custom_minimum_size = Vector2(0, 36)
			dump_all_btn.tooltip_text = "Jettison all cargo (lost forever)"
			dump_all_btn.focus_mode = Control.FOCUS_NONE
			dump_all_btn.flat = true
			dump_all_btn.pressed.connect(func() -> void:
				GameState.jettison_all_cargo(_selected_ship)
				_show_asteroid_selection()  # Refresh the list
			)
			jettison_row.add_child(dump_all_btn)

			colony_row.add_child(jettison_row)

		_colony_dest_buttons[colony] = {
			"dist": col_dist_label, "time": col_time_label,
			"revenue": col_revenue_label, "warning": col_warning_label,
			"btn": btn,
		}
		_colony_dest_data.append(colony)
		colonies_vbox.add_child(colony_row)
		colonies_vbox.add_child(HSeparator.new())

	colonies_scroll.add_child(colonies_vbox)
	dispatch_content.add_child(colonies_scroll)

	# Restore scroll position after UI has been laid out
	if _saved_colonies_scroll > 0:
		var saved_pos := _saved_colonies_scroll
		colonies_scroll.call_deferred("set", "scroll_vertical", int(saved_pos))

	var sep0 := HSeparator.new()
	dispatch_content.add_child(sep0)

	# --- MINING DESTINATIONS SECTION (always present, collapsible) ---
	var mining_header := Label.new()
	_mining_header_label = mining_header
	mining_header.text = "MINING DESTINATIONS %s" % ("▾" if mining_expanded else "▸")
	mining_header.add_theme_font_size_override("font_size", 18)
	mining_header.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	mining_header.mouse_filter = Control.MOUSE_FILTER_STOP
	mining_header.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_toggle_mining_section()
	)
	dispatch_content.add_child(mining_header)

	# Fixed filter/sort controls
	var controls := HFlowContainer.new()
	_mining_controls = controls
	controls.visible = mining_expanded
	controls.add_theme_constant_override("h_separation", 8)

	var sort_btn := OptionButton.new()
	sort_btn.add_item("Best Profit")
	sort_btn.add_item("Nearest")
	sort_btn.add_item("Name A-Z")
	sort_btn.custom_minimum_size = Vector2(0, 44)
	sort_btn.focus_mode = Control.FOCUS_NONE
	sort_btn.item_selected.connect(func(idx: int) -> void:
		_sort_by = ["profit", "distance", "name"][idx]
		_show_asteroid_selection()
	)
	match _sort_by:
		"profit": sort_btn.selected = 0
		"distance": sort_btn.selected = 1
		"name": sort_btn.selected = 2
	controls.add_child(sort_btn)

	var filter_btn := OptionButton.new()
	filter_btn.add_item("All Types")
	for bt in AsteroidData.BodyType.values():
		filter_btn.add_item(AsteroidData.BODY_TYPE_NAMES[bt])
	filter_btn.custom_minimum_size = Vector2(0, 44)
	filter_btn.focus_mode = Control.FOCUS_NONE
	filter_btn.selected = 0 if _filter_type == -1 else _filter_type + 1
	filter_btn.item_selected.connect(func(idx: int) -> void:
		_filter_type = idx - 1  # -1 = all
		_show_asteroid_selection()
	)
	controls.add_child(filter_btn)

	# Market strategy toggle
	var market_toggle := Button.new()
	market_toggle.toggle_mode = true
	market_toggle.button_pressed = _sell_at_destination_markets
	market_toggle.text = "Local Market" if _sell_at_destination_markets else "Return w/ Ore"
	market_toggle.custom_minimum_size = Vector2(0, 44)
	market_toggle.tooltip_text = "Toggle: Return with ore vs sell at markets near destination"
	market_toggle.focus_mode = Control.FOCUS_NONE
	market_toggle.toggled.connect(func(pressed: bool) -> void:
		_sell_at_destination_markets = pressed
		market_toggle.text = "Local Market" if pressed else "Return w/ Ore"
		_show_asteroid_selection()
	)
	controls.add_child(market_toggle)

	dispatch_content.add_child(controls)

	# Scrollable list for mining destinations
	var mining_scroll := ScrollContainer.new()
	_mining_scroll = mining_scroll
	mining_scroll.name = "MiningScroll"
	mining_scroll.size_flags_vertical = Control.SIZE_FILL
	mining_scroll.custom_minimum_size = Vector2(0, 400 if mining_expanded else 0)
	mining_scroll.visible = mining_expanded
	mining_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var mining_vbox := VBoxContainer.new()
	mining_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mining_vbox.add_theme_constant_override("separation", 6)

	# Build a dummy worker list for estimation (use available workers)
	var est_workers := GameState.get_available_workers()
	if est_workers.is_empty():
		var placeholder := Worker.new()
		placeholder.mining_skill = 1.0
		placeholder.wage = 100
		est_workers = [placeholder]

	# Get filtered and sorted asteroid list
	var asteroids := _get_sorted_asteroids(est_workers)

	for asteroid in asteroids:
		var asteroid_pos: Vector2 = asteroid.get_position_au()
		var dist_outbound := _selected_ship.position_au.distance_to(asteroid_pos)

		# Get base estimate for mining (using Brachistochrone as default)
		var est := AsteroidData.estimate_mission(
			asteroid, _selected_ship, est_workers, -1.0, Vector2(-999, -999), Mission.TransitMode.BRACHISTOCHRONE
		)

		# Calculate based on market strategy
		var return_pos: Vector2
		var dist_return: float
		var revenue: float
		var strategy_label := ""

		if _sell_at_destination_markets:
			# Find nearest colony to asteroid
			var nearest_colony: Colony = null
			var nearest_dist := 999999.0
			for colony in GameState.colonies:
				var d := asteroid_pos.distance_to(colony.get_position_au())
				if d < nearest_dist:
					nearest_dist = d
					nearest_colony = colony

			if nearest_colony:
				return_pos = nearest_colony.get_position_au()
				dist_return = nearest_dist
				strategy_label = " → %s" % nearest_colony.colony_name

				# Calculate revenue at colony prices (with scarcity multiplier)
				revenue = 0.0
				var cargo_breakdown: Dictionary = est["cargo_breakdown"]
				for ore_type in cargo_breakdown:
					var tons: float = cargo_breakdown[ore_type]
					var colony_price := nearest_colony.get_ore_price(ore_type, GameState.market)
					revenue += tons * colony_price
			else:
				# Fallback: return to current position
				return_pos = _selected_ship.position_au
				dist_return = dist_outbound
				revenue = est["revenue"]
		else:
			# Return with ore to current position
			return_pos = _selected_ship.position_au
			dist_return = dist_outbound
			revenue = est["revenue"]
			strategy_label = " (round trip)"

		# Use profit from estimate if returning to ship position (simple case)
		# Otherwise recalculate for alternate destinations
		var adjusted_profit: float
		var total_time: float
		var total_fuel_needed: float
		var current_cargo := _selected_ship.get_cargo_total()
		var total_transit: float

		if absf(dist_outbound - dist_return) < 0.01 and not _sell_at_destination_markets:
			# Simple round trip - use estimate directly
			adjusted_profit = est["profit"]
			total_time = est["total_time"]
			total_fuel_needed = est.get("fuel_needed", 0.0)
			# Calculate transit for display
			var transit_one_way := Brachistochrone.transit_time(dist_outbound, _selected_ship.get_effective_thrust())
			total_transit = transit_one_way * 2.0
		else:
			# Custom destination - recalculate
			var transit_out := Brachistochrone.transit_time(dist_outbound, _selected_ship.get_effective_thrust())
			var transit_ret := Brachistochrone.transit_time(dist_return, _selected_ship.get_effective_thrust())
			total_transit = transit_out + transit_ret

			# Fuel calculation
			var fuel_outbound := _selected_ship.calc_fuel_for_distance(dist_outbound, current_cargo)
			var fuel_return := _selected_ship.calc_fuel_for_distance(dist_return, est["cargo_total"])
			total_fuel_needed = fuel_outbound + fuel_return
			var custom_fuel_cost := total_fuel_needed * Ship.FUEL_COST_PER_UNIT

			# Wages for total mission time
			total_time = total_transit + est["mining_time"]
			var payroll_cycles: float = total_time / Simulation.PAYROLL_INTERVAL
			var wage_per_tick := 0.0
			for w in est_workers:
				wage_per_tick += w.wage
			var custom_wage_cost := wage_per_tick * payroll_cycles

			# Final profit
			adjusted_profit = revenue - custom_wage_cost - custom_fuel_cost

		var fuel_warning := ""
		# If ship is at a colony, assume it can refuel before departing
		var available_fuel := _selected_ship.get_effective_fuel_capacity() if _selected_ship.is_idle_remote else _selected_ship.fuel
		var has_insufficient_fuel := total_fuel_needed > available_fuel
		var has_cargo := current_cargo > 0

		# Calculate fuel route if needed (for mining destinations)
		var fuel_route: Array[String] = []
		var is_unreachable := false
		if has_insufficient_fuel:
			# Calculate fuel route to asteroid position (reuse asteroid_pos from line 731)
			fuel_route = _calculate_fuel_route_to_position(asteroid_pos, current_cargo)
			if fuel_route.is_empty():
				# Completely unreachable
				is_unreachable = true
				# Skip if setting is disabled
				if not GameState.settings.get("show_unreachable_destinations", false):
					continue
				fuel_warning = " [UNREACHABLE - insufficient fuel capacity]"
			else:
				fuel_warning = " [NEEDS REFUEL]"
		elif total_fuel_needed > available_fuel * 0.9:
			fuel_warning = " [CRITICAL - %.0f/%.0f fuel]" % [available_fuel, total_fuel_needed]

		# Create row container for destination + jettison buttons
		var dest_row := VBoxContainer.new()
		dest_row.add_theme_constant_override("separation", 4)

		# Row 1: Name label
		var name_label := Label.new()
		name_label.text = "%s (%s)" % [asteroid.asteroid_name, asteroid.get_type_name()]
		dest_row.add_child(name_label)

		# Row 2: Fixed-width data fields
		var data_row := HBoxContainer.new()
		data_row.add_theme_constant_override("separation", 8)

		var dist_label := Label.new()
		dist_label.custom_minimum_size = Vector2(220, 0)
		dist_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		data_row.add_child(dist_label)

		var time_label := Label.new()
		time_label.custom_minimum_size = Vector2(100, 0)
		time_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
		data_row.add_child(time_label)

		var profit_label := Label.new()
		profit_label.custom_minimum_size = Vector2(120, 0)
		profit_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		data_row.add_child(profit_label)

		var warning_label := Label.new()
		warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		warning_label.add_theme_font_size_override("font_size", 12)
		data_row.add_child(warning_label)

		dest_row.add_child(data_row)

		# Set initial values
		var thrust := _selected_ship.get_effective_thrust()
		var dv_out := Brachistochrone.delta_v_km_s(dist_outbound, thrust)
		var dv_ret := Brachistochrone.delta_v_km_s(dist_return, thrust)
		dist_label.text = "%.0f out %.0f ret Δv" % [dv_out, dv_ret]
		time_label.text = _format_time(total_transit)
		var profit_str := "$%s" % _format_number(int(adjusted_profit))
		profit_label.text = "%s%s" % ["+" if adjusted_profit > 0 else "", profit_str]
		if adjusted_profit >= 0:
			profit_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		else:
			profit_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		warning_label.text = fuel_warning
		if "CRITICAL" in fuel_warning or "UNREACHABLE" in fuel_warning:
			warning_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		elif fuel_warning != "":
			warning_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))

		# Dispatch button
		var btn := Button.new()
		btn.text = "Dispatch"
		btn.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		btn.custom_minimum_size = Vector2(0, 36)
		btn.focus_mode = Control.FOCUS_NONE
		btn.disabled = is_unreachable
		btn.pressed.connect(func() -> void:
			_confirm_asteroid_dispatch(asteroid)
		)
		dest_row.add_child(btn)
		# Store references for in-place updates: {dist, time, profit, warning}
		_mining_dest_buttons[asteroid] = {
			"dist": dist_label, "time": time_label,
			"profit": profit_label, "warning": warning_label,
			"btn": btn,
		}
		_mining_dest_data.append(asteroid)

		# Show fuel stop route as clickable buttons
		if not fuel_route.is_empty():
			var route_label := Label.new()
			route_label.text = "  Fuel stops needed:"
			route_label.add_theme_color_override("font_color", Color(0.3, 0.8, 0.9))
			dest_row.add_child(route_label)

			var stops_hbox := HFlowContainer.new()
			stops_hbox.add_theme_constant_override("h_separation", 8)
			for stop_name in fuel_route:
				# Find the colony by name
				var stop_colony: Colony = null
				for c in GameState.colonies:
					if c.colony_name == stop_name:
						stop_colony = c
						break

				if stop_colony:
					var stop_btn := Button.new()
					stop_btn.text = stop_name
					stop_btn.custom_minimum_size = Vector2(0, 36)
					stop_btn.focus_mode = Control.FOCUS_NONE
					stop_btn.pressed.connect(func() -> void:
						_confirm_colony_dispatch(stop_colony)
					)
					stops_hbox.add_child(stop_btn)

			dest_row.add_child(stops_hbox)

		# ALWAYS show action buttons if ship has cargo
		if has_cargo:
			var jettison_row := HFlowContainer.new()
			jettison_row.add_theme_constant_override("h_separation", 8)

			var jettison_label := Label.new()
			jettison_label.text = "  Jettison cargo:"
			jettison_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
			jettison_row.add_child(jettison_label)

			# Smart jettison button (minimum needed)
			var smart_btn := Button.new()
			smart_btn.text = "Dump to Fit"
			smart_btn.custom_minimum_size = Vector2(0, 36)
			smart_btn.tooltip_text = "Jettison minimum cargo needed to make this trip"
			smart_btn.focus_mode = Control.FOCUS_NONE
			smart_btn.flat = true
			var capture_dist_out := dist_outbound
			var capture_dist_ret := dist_return
			smart_btn.pressed.connect(func() -> void:
				# Custom jettison for asymmetric trips
				var needed := _calculate_jettison_for_asymmetric_trip(capture_dist_out, capture_dist_ret)
				if needed > 0:
					var current := _selected_ship.get_cargo_total()
					var ratio := needed / current
					for ore_type in _selected_ship.current_cargo.keys():
						var amount: float = _selected_ship.current_cargo[ore_type]
						_selected_ship.current_cargo[ore_type] = amount * (1.0 - ratio)
					EventBus.cargo_jettisoned.emit(_selected_ship, needed)
				_show_asteroid_selection()  # Refresh the list
				print("Jettisoned %.1f tons to make trip viable" % needed)
			)
			jettison_row.add_child(smart_btn)

			# Dump all button
			var dump_all_btn := Button.new()
			dump_all_btn.text = "Dump All (%.0ft)" % current_cargo
			dump_all_btn.custom_minimum_size = Vector2(0, 36)
			dump_all_btn.tooltip_text = "Jettison all cargo (lost forever)"
			dump_all_btn.focus_mode = Control.FOCUS_NONE
			dump_all_btn.flat = true
			dump_all_btn.pressed.connect(func() -> void:
				GameState.jettison_all_cargo(_selected_ship)
				_show_asteroid_selection()  # Refresh the list
			)
			jettison_row.add_child(dump_all_btn)

			dest_row.add_child(jettison_row)

		mining_vbox.add_child(dest_row)
		mining_vbox.add_child(HSeparator.new())

	mining_scroll.add_child(mining_vbox)
	dispatch_content.add_child(mining_scroll)

	# Restore scroll position after UI has been laid out
	if _saved_mining_scroll > 0:
		var saved_pos := _saved_mining_scroll
		mining_scroll.call_deferred("set", "scroll_vertical", int(saved_pos))

	var _cancel_cb := func() -> void:
		_cancel_preview()
		_hide_dispatch()
	_set_dispatch_buttons([{"text": "Cancel", "callback": _cancel_cb}])

	_show_dispatch()

func _toggle_colonies_section() -> void:
	if not is_instance_valid(_colonies_scroll):
		return
	var expanding := not _colonies_scroll.visible
	_colonies_section_expanded = 1 if expanding else 0
	_colonies_scroll.visible = expanding
	_colonies_scroll.custom_minimum_size = Vector2(0, 400 if expanding else 0)
	if is_instance_valid(_colonies_header_label):
		var base_text := _colonies_header_label.text.split(" ▾")[0].split(" ▸")[0]
		_colonies_header_label.text = "%s %s" % [base_text, "▾" if expanding else "▸"]

func _toggle_mining_section() -> void:
	if not is_instance_valid(_mining_scroll):
		return
	var expanding := not _mining_scroll.visible
	_mining_section_expanded = 1 if expanding else 0
	_mining_scroll.visible = expanding
	_mining_scroll.custom_minimum_size = Vector2(0, 400 if expanding else 0)
	if is_instance_valid(_mining_controls):
		_mining_controls.visible = expanding
	if is_instance_valid(_mining_header_label):
		var base_text := _mining_header_label.text.split(" ▾")[0].split(" ▸")[0]
		_mining_header_label.text = "%s %s" % [base_text, "▾" if expanding else "▸"]

func _update_destination_labels() -> void:
	# Update existing destination buttons in place without rebuilding layout
	if not _selected_ship:
		return

	# Update colony destination labels in place
	for colony: Colony in _colony_dest_buttons:
		var refs: Dictionary = _colony_dest_buttons[colony]
		var col_dist_label: Label = refs["dist"]
		var col_time_label: Label = refs["time"]
		var col_revenue_label: Label = refs["revenue"]
		var col_warning_label: Label = refs["warning"]
		if not is_instance_valid(col_dist_label):
			continue
		var colony_pos: Vector2 = colony.get_position_au()
		var dist := _selected_ship.position_au.distance_to(colony_pos)
		var transit := Brachistochrone.transit_time(dist, _selected_ship.get_effective_thrust())
		var cargo_mass := _selected_ship.get_cargo_total()
		var fuel_outbound := _selected_ship.calc_fuel_for_distance(dist, cargo_mass)
		var fuel_return := _selected_ship.calc_fuel_for_distance(dist, 0.0)
		var fuel_needed := fuel_outbound + fuel_return
		var revenue := 0
		for ore_type in _selected_ship.current_cargo:
			var amount: float = _selected_ship.current_cargo[ore_type]
			var price: float = colony.get_ore_price(ore_type, GameState.market)
			revenue += int(amount * price)
		var col_dv := Brachistochrone.delta_v_km_s(dist, _selected_ship.get_effective_thrust())
		col_dist_label.text = "%.0f km/s Δv" % col_dv
		col_time_label.text = _format_time(transit)
		col_revenue_label.text = "$%s" % _format_number(revenue)
		var available_fuel := _selected_ship.get_effective_fuel_capacity() if _selected_ship.is_idle_remote else _selected_ship.fuel
		if fuel_needed > available_fuel:
			col_warning_label.text = " [NEEDS REFUEL]"
			col_warning_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		elif fuel_needed > available_fuel * 0.9:
			col_warning_label.text = " [CRITICAL]"
			col_warning_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		else:
			col_warning_label.text = ""

	# Update mining destination labels in place
	var est_workers := GameState.get_available_workers()
	if est_workers.is_empty():
		var placeholder := Worker.new()
		placeholder.mining_skill = 1.0
		placeholder.wage = 100
		est_workers = [placeholder]

	for asteroid: AsteroidData in _mining_dest_buttons:
		var refs: Dictionary = _mining_dest_buttons[asteroid]
		var dist_label: Label = refs["dist"]
		var time_label: Label = refs["time"]
		var profit_label: Label = refs["profit"]
		var warning_label: Label = refs["warning"]
		if not is_instance_valid(dist_label):
			continue
		var asteroid_pos: Vector2 = asteroid.get_position_au()
		var dist_outbound := _selected_ship.position_au.distance_to(asteroid_pos)
		var est := AsteroidData.estimate_mission(
			asteroid, _selected_ship, est_workers, -1.0, Vector2(-999, -999), Mission.TransitMode.BRACHISTOCHRONE
		)
		var dist_return: float
		var revenue: float
		if _sell_at_destination_markets:
			var nearest_colony: Colony = null
			var nearest_dist := 999999.0
			for colony in GameState.colonies:
				var d := asteroid_pos.distance_to(colony.get_position_au())
				if d < nearest_dist:
					nearest_dist = d
					nearest_colony = colony
			if nearest_colony:
				dist_return = nearest_dist
				revenue = 0.0
				var cargo_breakdown: Dictionary = est["cargo_breakdown"]
				for ore_type in cargo_breakdown:
					var tons: float = cargo_breakdown[ore_type]
					revenue += tons * nearest_colony.get_ore_price(ore_type, GameState.market)
			else:
				dist_return = dist_outbound
				revenue = est["revenue"]
		else:
			dist_return = dist_outbound
			revenue = est["revenue"]
		var total_transit: float
		var adjusted_profit: float
		if absf(dist_outbound - dist_return) < 0.01 and not _sell_at_destination_markets:
			adjusted_profit = est["profit"]
			var transit_one_way := Brachistochrone.transit_time(dist_outbound, _selected_ship.get_effective_thrust())
			total_transit = transit_one_way * 2.0
		else:
			var transit_out := Brachistochrone.transit_time(dist_outbound, _selected_ship.get_effective_thrust())
			var transit_ret := Brachistochrone.transit_time(dist_return, _selected_ship.get_effective_thrust())
			total_transit = transit_out + transit_ret
			var fuel_out := _selected_ship.calc_fuel_for_distance(dist_outbound, _selected_ship.get_cargo_total())
			var fuel_ret := _selected_ship.calc_fuel_for_distance(dist_return, est["cargo_total"])
			var custom_fuel_cost := (fuel_out + fuel_ret) * Ship.FUEL_COST_PER_UNIT
			var total_time: float = total_transit + est["mining_time"]
			var payroll_cycles: float = total_time / Simulation.PAYROLL_INTERVAL
			var wage_per_tick := 0.0
			for w in est_workers:
				wage_per_tick += w.wage
			adjusted_profit = revenue - wage_per_tick * payroll_cycles - custom_fuel_cost
		# Update labels in place
		var thrust := _selected_ship.get_effective_thrust()
		var dv_out := Brachistochrone.delta_v_km_s(dist_outbound, thrust)
		var dv_ret := Brachistochrone.delta_v_km_s(dist_return, thrust)
		dist_label.text = "%.0f out %.0f ret Δv" % [dv_out, dv_ret]
		time_label.text = _format_time(total_transit)
		var profit_str := "$%s" % _format_number(int(adjusted_profit))
		profit_label.text = "%s%s" % ["+" if adjusted_profit > 0 else "", profit_str]
		if adjusted_profit >= 0:
			profit_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
		else:
			profit_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		var available_fuel := _selected_ship.get_effective_fuel_capacity() if _selected_ship.is_idle_remote else _selected_ship.fuel
		var total_fuel := _selected_ship.calc_fuel_for_distance(dist_outbound, _selected_ship.get_cargo_total()) + _selected_ship.calc_fuel_for_distance(dist_return, est["cargo_total"])
		if total_fuel > available_fuel:
			warning_label.text = " [NEEDS REFUEL]"
			warning_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.2))
		elif total_fuel > available_fuel * 0.9:
			warning_label.text = " [CRITICAL]"
			warning_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		else:
			warning_label.text = ""

func _get_sorted_asteroids(est_workers: Array[Worker]) -> Array[AsteroidData]:
	var filtered: Array[AsteroidData] = []
	for a in GameState.asteroids:
		if _filter_type >= 0 and a.body_type != _filter_type:
			continue
		filtered.append(a)

	match _sort_by:
		"profit":
			filtered.sort_custom(func(a: AsteroidData, b: AsteroidData) -> bool:
				var profit_a := _calculate_adjusted_profit(a, est_workers)
				var profit_b := _calculate_adjusted_profit(b, est_workers)
				return profit_a > profit_b
			)
		"distance":
			filtered.sort_custom(func(a: AsteroidData, b: AsteroidData) -> bool:
				var da := _selected_ship.position_au.distance_to(a.get_position_au())
				var db := _selected_ship.position_au.distance_to(b.get_position_au())
				return da < db
			)
		"name":
			filtered.sort_custom(func(a: AsteroidData, b: AsteroidData) -> bool:
				return a.asteroid_name.naturalcasecmp_to(b.asteroid_name) < 0
			)
	return filtered

func _calculate_adjusted_profit(asteroid: AsteroidData, est_workers: Array[Worker]) -> float:
	# Calculate profit based on current market strategy
	var asteroid_pos: Vector2 = asteroid.get_position_au()
	var dist_outbound := _selected_ship.position_au.distance_to(asteroid_pos)

	# Get base estimate for mining (using Brachistochrone as default)
	var est := AsteroidData.estimate_mission(
		asteroid, _selected_ship, est_workers, -1.0, Vector2(-999, -999), Mission.TransitMode.BRACHISTOCHRONE
	)

	# Calculate based on market strategy
	var dist_return: float
	var revenue: float

	if _sell_at_destination_markets:
		# Find nearest colony to asteroid
		var nearest_colony: Colony = null
		var nearest_dist := 999999.0
		for colony in GameState.colonies:
			var d := asteroid_pos.distance_to(colony.get_position_au())
			if d < nearest_dist:
				nearest_dist = d
				nearest_colony = colony

		if nearest_colony:
			dist_return = nearest_dist

			# Calculate revenue at colony prices (with scarcity multiplier)
			revenue = 0.0
			var cargo_breakdown: Dictionary = est["cargo_breakdown"]
			for ore_type in cargo_breakdown:
				var tons: float = cargo_breakdown[ore_type]
				var colony_price := nearest_colony.get_ore_price(ore_type, GameState.market)
				revenue += tons * colony_price
		else:
			# Fallback: return to current position
			dist_return = dist_outbound
			revenue = est["revenue"]
	else:
		# Return with ore to current position
		dist_return = dist_outbound
		revenue = est["revenue"]

	# Use profit from estimate if returning to ship position (simple case)
	if absf(dist_outbound - dist_return) < 0.01 and not _sell_at_destination_markets:
		# Simple round trip - use estimate directly
		return est["profit"]

	# Custom destination - recalculate
	var transit_out := Brachistochrone.transit_time(dist_outbound, _selected_ship.get_effective_thrust())
	var transit_ret := Brachistochrone.transit_time(dist_return, _selected_ship.get_effective_thrust())
	var total_transit := transit_out + transit_ret

	# Fuel calculation
	var current_cargo := _selected_ship.get_cargo_total()
	var fuel_outbound := _selected_ship.calc_fuel_for_distance(dist_outbound, current_cargo)
	var fuel_return := _selected_ship.calc_fuel_for_distance(dist_return, est["cargo_total"])
	var total_fuel_needed := fuel_outbound + fuel_return
	var custom_fuel_cost := total_fuel_needed * Ship.FUEL_COST_PER_UNIT

	# Wages for total mission time
	var total_time: float = total_transit + est["mining_time"]
	var payroll_cycles: float = total_time / Simulation.PAYROLL_INTERVAL
	var wage_per_tick := 0.0
	for w in est_workers:
		wage_per_tick += w.wage
	var custom_wage_cost := wage_per_tick * payroll_cycles

	# Final profit
	return revenue - custom_wage_cost - custom_fuel_cost

func _get_ore_summary(asteroid: AsteroidData) -> String:
	var parts: Array[String] = []
	for ore_type in asteroid.ore_yields:
		parts.append(ResourceTypes.get_ore_name(ore_type))
	return ", ".join(parts)

func _select_asteroid(asteroid: AsteroidData) -> void:
	_selected_asteroid = asteroid
	_show_worker_selection()

func _select_colony_trade(colony: Colony) -> void:
	# Skip worker selection, go straight to trade mission
	var cargo := _selected_ship.current_cargo.duplicate()
	if cargo.is_empty():
		return

	# Auto-refuel from current position
	if GameState.settings.get("auto_refuel", true):
		var colony_pos: Vector2 = colony.get_position_au()
		var dist := _selected_ship.position_au.distance_to(colony_pos)
		var fuel_needed := _selected_ship.calc_fuel_for_distance(dist)
		var fuel_cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)
		if GameState.money < fuel_cost:
			return  # Can't afford fuel
		_selected_ship.fuel = _selected_ship.fuel_capacity
		GameState.money -= fuel_cost

	var assigned: Array[Worker] = []
	if _selected_ship.is_idle_remote:
		GameState.dispatch_idle_ship_trade(_selected_ship, colony, assigned, cargo)
	else:
		GameState.start_trade_mission(_selected_ship, colony, assigned, cargo)
	_cancel_preview()
	_hide_dispatch()
	_mark_dirty()

func _show_worker_selection() -> void:
	_on_selection_screen = false  # Left the main selection screen
	_on_estimate_screen = true  # Now on the estimate screen
	_worker_checkboxes.clear()
	_clear_dispatch_content()

	# AI-calculate optimal thrust based on company policy
	var expected_cargo := _selected_ship.cargo_capacity  # Assume we'll fill the hold
	var ai_thrust := CompanyPolicy.calculate_thrust_setting(
		GameState.thrust_policy,
		_selected_ship,
		_selected_asteroid.get_position_au(),
		expected_cargo
	)
	_selected_ship.thrust_setting = ai_thrust

	# Find beneficial slingshot routes
	_available_slingshot_routes = GravityAssist.find_beneficial_slingshots(
		_selected_ship.position_au,
		_selected_asteroid.get_position_au(),
		_selected_ship,
		expected_cargo
	)

	# AI-select preferred route based on company policy
	_selected_slingshot_route = CompanyPolicy.calculate_preferred_route(
		GameState.thrust_policy,
		_available_slingshot_routes
	)

	# Show trajectory preview on map (with slingshot route if selected)
	EventBus.mission_preview_started.emit(_selected_ship, _selected_asteroid.get_position_au(), _selected_slingshot_route)

	var title := Label.new()
	title.text = "Assign Crew"
	title.add_theme_font_size_override("font_size", 20)
	dispatch_content.add_child(title)

	var dest_label := Label.new()
	dest_label.text = "Destination: %s (%s)" % [
		_selected_asteroid.asteroid_name, _selected_asteroid.get_type_name()
	]
	dispatch_content.add_child(dest_label)

	var ore_label := Label.new()
	ore_label.text = "Resources: %s" % _get_ore_summary(_selected_asteroid)
	dispatch_content.add_child(ore_label)

	# Distance from ship position
	var dist := _selected_ship.position_au.distance_to(_selected_asteroid.get_position_au())
	var dist_label := Label.new()
	var dv := Brachistochrone.delta_v_km_s(dist, _selected_ship.get_effective_thrust())
	dist_label.text = "Δv: %.0f km/s (%.2f AU)" % [dv, dist]
	dist_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	dispatch_content.add_child(dist_label)

	# Mission type selection (only show options when relevant)
	var has_deploy_units := not GameState.mining_unit_inventory.is_empty()
	var has_stockpile := not GameState.get_ore_stockpile(_selected_asteroid.asteroid_name).is_empty()
	if has_deploy_units or has_stockpile:
		var type_sep := HSeparator.new()
		dispatch_content.add_child(type_sep)
		var type_label := Label.new()
		type_label.text = "Mission Type:"
		type_label.add_theme_font_size_override("font_size", 16)
		type_label.add_theme_color_override("font_color", Color(0.9, 0.7, 0.3))
		dispatch_content.add_child(type_label)
		var type_row := HFlowContainer.new()
		type_row.add_theme_constant_override("h_separation", 8)

		var mine_btn := Button.new()
		mine_btn.text = "Mine"
		mine_btn.toggle_mode = true
		mine_btn.button_pressed = (_selected_mission_type == Mission.MissionType.MINING)
		mine_btn.custom_minimum_size = Vector2(0, 36)
		mine_btn.pressed.connect(func() -> void:
			_selected_mission_type = Mission.MissionType.MINING
			_show_worker_selection()
		)
		type_row.add_child(mine_btn)

		if has_deploy_units:
			var slots := _selected_asteroid.get_max_mining_slots()
			var occupied := GameState.get_occupied_slots(_selected_asteroid.asteroid_name)
			var deploy_btn := Button.new()
			deploy_btn.text = "Deploy Units (%d/%d slots)" % [occupied, slots]
			deploy_btn.toggle_mode = true
			deploy_btn.button_pressed = (_selected_mission_type == Mission.MissionType.DEPLOY_UNIT)
			deploy_btn.custom_minimum_size = Vector2(0, 36)
			deploy_btn.disabled = occupied >= slots
			deploy_btn.pressed.connect(func() -> void:
				_selected_mission_type = Mission.MissionType.DEPLOY_UNIT
				_show_worker_selection()
			)
			type_row.add_child(deploy_btn)

		if has_stockpile:
			var pile := GameState.get_ore_stockpile(_selected_asteroid.asteroid_name)
			var total_stockpile := 0.0
			for _ot in pile:
				total_stockpile += pile[_ot]
			var collect_btn := Button.new()
			collect_btn.text = "Collect Ore (%.1ft)" % total_stockpile
			collect_btn.toggle_mode = true
			collect_btn.button_pressed = (_selected_mission_type == Mission.MissionType.COLLECT_ORE)
			collect_btn.custom_minimum_size = Vector2(0, 36)
			collect_btn.pressed.connect(func() -> void:
				_selected_mission_type = Mission.MissionType.COLLECT_ORE
				_show_worker_selection()
			)
			type_row.add_child(collect_btn)

		dispatch_content.add_child(type_row)

	# Deploy unit selection (when Deploy Units is selected)
	if _selected_mission_type == Mission.MissionType.DEPLOY_UNIT:
		var du_sep := HSeparator.new()
		dispatch_content.add_child(du_sep)
		var du_label := Label.new()
		du_label.text = "Select Units to Deploy:"
		du_label.add_theme_font_size_override("font_size", 14)
		du_label.add_theme_color_override("font_color", Color(0.5, 0.8, 1.0))
		dispatch_content.add_child(du_label)

		var slots_avail := _selected_asteroid.get_max_mining_slots() - GameState.get_occupied_slots(_selected_asteroid.asteroid_name)
		var cargo_space := _selected_ship.cargo_capacity - _selected_ship.get_cargo_total()
		var total_unit_mass := 0.0
		for u in _selected_deploy_units:
			total_unit_mass += u.mass

		for unit in GameState.mining_unit_inventory:
			var already_selected := unit in _selected_deploy_units
			var unit_btn := Button.new()
			unit_btn.flat = not already_selected
			unit_btn.custom_minimum_size = Vector2(0, 36)
			unit_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			unit_btn.text = "%s (%.1ft, %d workers, %.1fx)" % [
				unit.unit_name, unit.mass, unit.workers_required, unit.mining_multiplier
			]
			_apply_selection_style(unit_btn, already_selected)
			var can_add := not already_selected and _selected_deploy_units.size() < slots_avail and (total_unit_mass + unit.mass) <= cargo_space
			if not already_selected and not can_add:
				unit_btn.disabled = true
			unit_btn.pressed.connect(func() -> void:
				if unit in _selected_deploy_units:
					_selected_deploy_units.erase(unit)
				else:
					_selected_deploy_units.append(unit)
				_show_worker_selection()
			)
			dispatch_content.add_child(unit_btn)

		# Show workers to assign to units
		if not _selected_deploy_units.is_empty():
			var dw_label := Label.new()
			var total_workers_needed := 0
			for u in _selected_deploy_units:
				total_workers_needed += u.workers_required
			dw_label.text = "Workers to leave at asteroid: %d/%d" % [_selected_deploy_workers.size(), total_workers_needed]
			dw_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
			dispatch_content.add_child(dw_label)

			var available_for_deploy := GameState.get_available_workers()
			# Remove already-selected transit crew
			for w in _selected_workers:
				available_for_deploy.erase(w)
			for w in available_for_deploy:
				var is_deploy_selected := w in _selected_deploy_workers
				var dw_btn := Button.new()
				dw_btn.flat = not is_deploy_selected
				dw_btn.custom_minimum_size = Vector2(0, 36)
				dw_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
				dw_btn.text = "%s  |  %s  |  $%d/pay" % [
					w.worker_name, w.get_specialties_text(), w.wage
				]
				_apply_selection_style(dw_btn, is_deploy_selected)
				if not is_deploy_selected and _selected_deploy_workers.size() >= total_workers_needed:
					dw_btn.disabled = true
				dw_btn.pressed.connect(func() -> void:
					if w in _selected_deploy_workers:
						_selected_deploy_workers.erase(w)
					else:
						_selected_deploy_workers.append(w)
					_show_worker_selection()
				)
				dispatch_content.add_child(dw_btn)

	var sep := HSeparator.new()
	dispatch_content.add_child(sep)

	var crew_label := Label.new()
	crew_label.text = "Minimum crew: %d" % _selected_ship.min_crew
	crew_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	dispatch_content.add_child(crew_label)

	# Determine available crew based on ship location
	var available := GameState.get_available_workers()
	var crew_locked := false  # True when crew can't be changed (ship is remote)
	if _selected_ship.is_idle_remote and _selected_ship.last_crew.size() > 0:
		# Ship is at a remote location — can only use crew that's aboard
		available = _selected_ship.last_crew.duplicate()
		crew_locked = true
	elif _is_planning_mode and _selected_ship.last_crew.size() >= _selected_ship.min_crew:
		# Ship is underway - allow selecting current crew for queued mission
		available = _selected_ship.last_crew.duplicate()
		crew_locked = true

	if available.size() < _selected_ship.min_crew:
		var label := Label.new()
		if _is_planning_mode:
			label.text = "Not enough crew! Need %d, but current mission has %d. Cannot queue mission." % [
				_selected_ship.min_crew, _selected_ship.last_crew.size()
			]
		else:
			label.text = "Not enough crew! Need %d, have %d available. Hire more first." % [
				_selected_ship.min_crew, available.size()
			]
		label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		dispatch_content.add_child(label)
	elif crew_locked:
		# Crew is locked — ship is remote or underway, use whoever is aboard
		_selected_workers = available.duplicate()

		var locked_label := Label.new()
		locked_label.text = "Crew aboard (%d):" % available.size()
		locked_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		dispatch_content.add_child(locked_label)

		for worker in available:
			var wlabel := Label.new()
			wlabel.text = "  %s  |  %s  |  $%d/pay" % [
				worker.worker_name, worker.get_specialties_text(), worker.wage
			]
			wlabel.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
			dispatch_content.add_child(wlabel)

		call_deferred("_update_estimate_display")
	else:
		# Optimize crew buttons row
		var opt_row := HFlowContainer.new()
		opt_row.add_theme_constant_override("h_separation", 8)

		var auto_btn := Button.new()
		auto_btn.text = "Auto"
		auto_btn.flat = true
		auto_btn.focus_mode = Control.FOCUS_NONE
		auto_btn.custom_minimum_size = Vector2(0, 32)
		auto_btn.pressed.connect(func() -> void:
			_optimize_crew(available, "auto")
		)
		opt_row.add_child(auto_btn)

		var miners_btn := Button.new()
		miners_btn.text = "Best Miners"
		miners_btn.flat = true
		miners_btn.focus_mode = Control.FOCUS_NONE
		miners_btn.custom_minimum_size = Vector2(0, 32)
		miners_btn.pressed.connect(func() -> void:
			_optimize_crew(available, "mining")
		)
		opt_row.add_child(miners_btn)

		var pilots_btn := Button.new()
		pilots_btn.text = "Best Pilots"
		pilots_btn.flat = true
		pilots_btn.focus_mode = Control.FOCUS_NONE
		pilots_btn.custom_minimum_size = Vector2(0, 32)
		pilots_btn.pressed.connect(func() -> void:
			_optimize_crew(available, "pilot")
		)
		opt_row.add_child(pilots_btn)

		var engineers_btn := Button.new()
		engineers_btn.text = "Best Engineers"
		engineers_btn.flat = true
		engineers_btn.focus_mode = Control.FOCUS_NONE
		engineers_btn.custom_minimum_size = Vector2(0, 32)
		engineers_btn.pressed.connect(func() -> void:
			_optimize_crew(available, "engineer")
		)
		opt_row.add_child(engineers_btn)

		var clear_btn := Button.new()
		clear_btn.text = "Clear"
		clear_btn.flat = true
		clear_btn.focus_mode = Control.FOCUS_NONE
		clear_btn.custom_minimum_size = Vector2(0, 32)
		clear_btn.pressed.connect(func() -> void:
			_optimize_crew(available, "clear")
		)
		opt_row.add_child(clear_btn)

		dispatch_content.add_child(opt_row)

		# Scrollable crew list
		var crew_scroll := ScrollContainer.new()
		crew_scroll.custom_minimum_size = Vector2(0, 200)
		crew_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		crew_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var crew_vbox := VBoxContainer.new()
		crew_vbox.add_theme_constant_override("separation", 4)
		crew_scroll.add_child(crew_vbox)
		dispatch_content.add_child(crew_scroll)

		# Auto-select: pre-select last crew, or first min_crew workers
		_worker_checkboxes.clear()
		var should_preselect := func(worker: Worker) -> bool:
			if _selected_ship.last_crew.size() > 0:
				return worker in _selected_ship.last_crew
			# No history: select the first min_crew workers
			var idx := available.find(worker)
			return idx >= 0 and idx < _selected_ship.min_crew

		for worker in available:
			var preselect: bool = should_preselect.call(worker)
			if preselect and worker not in _selected_workers:
				_selected_workers.append(worker)

			var crew_btn := Button.new()
			crew_btn.flat = true
			crew_btn.custom_minimum_size = Vector2(0, 40)
			crew_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
			crew_btn.focus_mode = Control.FOCUS_NONE
			crew_btn.text = "%s  |  %s  |  $%d/pay" % [
				worker.worker_name, worker.get_specialties_text(), worker.wage
			]
			_apply_crew_style(crew_btn, preselect)
			crew_btn.pressed.connect(func() -> void:
				if worker in _selected_workers:
					_selected_workers.erase(worker)
					_apply_crew_style(crew_btn, false)
				else:
					_selected_workers.append(worker)
					_apply_crew_style(crew_btn, true)
				_update_estimate_display()
			)
			crew_vbox.add_child(crew_btn)
			_worker_checkboxes[worker] = crew_btn

		# Show initial estimate if workers were pre-selected
		if not _selected_workers.is_empty():
			call_deferred("_update_estimate_display")

	# Estimate display
	var est_panel := PanelContainer.new()
	est_panel.name = "EstimatePanel"
	var est_vbox := VBoxContainer.new()
	est_vbox.add_theme_constant_override("separation", 4)

	var est_title := Label.new()
	est_title.text = "MISSION ESTIMATE"
	est_title.add_theme_font_size_override("font_size", 14)
	est_vbox.add_child(est_title)

	# Transit mode selection buttons
	var mode_hbox := HFlowContainer.new()
	mode_hbox.name = "TransitModeButtons"
	mode_hbox.add_theme_constant_override("h_separation", 8)

	var brach_btn := Button.new()
	brach_btn.name = "BrachButton"
	brach_btn.text = "Fast (Brachistochrone)"
	brach_btn.custom_minimum_size = Vector2(0, 36)
	brach_btn.toggle_mode = true
	brach_btn.button_pressed = true
	brach_btn.pressed.connect(func() -> void:
		_selected_transit_mode = Mission.TransitMode.BRACHISTOCHRONE
		_update_estimate_display()
	)
	mode_hbox.add_child(brach_btn)

	var hohmann_btn := Button.new()
	hohmann_btn.name = "HohmannButton"
	hohmann_btn.text = "Economical (Hohmann)"
	hohmann_btn.custom_minimum_size = Vector2(0, 36)
	hohmann_btn.toggle_mode = true
	hohmann_btn.button_pressed = false
	hohmann_btn.pressed.connect(func() -> void:
		_selected_transit_mode = Mission.TransitMode.HOHMANN
		_update_estimate_display()
	)
	mode_hbox.add_child(hohmann_btn)

	est_vbox.add_child(mode_hbox)

	# Route selection (slingshot vs direct) - only show if beneficial routes exist
	if not _available_slingshot_routes.is_empty():
		var route_label := Label.new()
		route_label.text = "Route Options:"
		route_label.add_theme_font_size_override("font_size", 12)
		route_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		est_vbox.add_child(route_label)

		# AI route info
		var ai_route_info := Label.new()
		if _selected_slingshot_route:
			ai_route_info.text = "AI: %s (%s)" % [_selected_slingshot_route.route_name, CompanyPolicy.THRUST_POLICY_NAMES[GameState.thrust_policy]]
		else:
			ai_route_info.text = "AI: Direct Route (%s)" % CompanyPolicy.THRUST_POLICY_NAMES[GameState.thrust_policy]
		ai_route_info.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
		ai_route_info.add_theme_font_size_override("font_size", 11)
		est_vbox.add_child(ai_route_info)

		# Direct route button (always available)
		var direct_btn := Button.new()
		direct_btn.name = "DirectRouteButton"
		direct_btn.text = "Direct Route (Baseline)"
		direct_btn.custom_minimum_size = Vector2(0, 32)
		direct_btn.toggle_mode = true
		direct_btn.button_pressed = (_selected_slingshot_route == null)  # AI selection
		direct_btn.pressed.connect(func() -> void:
			_selected_slingshot_route = null
			_update_route_button_states()
			_update_estimate_display()
			EventBus.mission_preview_started.emit(_selected_ship, _selected_asteroid.get_position_au(), null)
		)
		est_vbox.add_child(direct_btn)

		# Slingshot route buttons
		for route in _available_slingshot_routes:
			var slingshot_btn := Button.new()
			slingshot_btn.name = "SlingshotButton_%d" % route.planet_index
			var savings_text: String = "Saves %.0f%% fuel" % route.fuel_savings_percent
			var time_text := ""
			if route.time_penalty > 0:
				var hours: float = route.time_penalty / 3600.0  # Convert seconds to hours
				time_text = " (+%.1fh)" % hours
			slingshot_btn.text = "%s - %s%s" % [route.route_name, savings_text, time_text]
			slingshot_btn.custom_minimum_size = Vector2(0, 32)
			slingshot_btn.toggle_mode = true
			slingshot_btn.button_pressed = (_selected_slingshot_route == route)  # AI selection
			slingshot_btn.pressed.connect(func() -> void:
				_selected_slingshot_route = route
				_update_route_button_states()
				_update_estimate_display()
				EventBus.mission_preview_started.emit(_selected_ship, _selected_asteroid.get_position_au(), route)
			)
			slingshot_btn.add_theme_color_override("font_color", Color(0.3, 0.9, 0.9))
			est_vbox.add_child(slingshot_btn)

	# Manual thrust control (hidden by default, AI-controlled)
	var thrust_control_row := HBoxContainer.new()
	thrust_control_row.name = "ThrustControlRow"
	thrust_control_row.add_theme_constant_override("separation", 8)

	var manual_thrust_btn := Button.new()
	manual_thrust_btn.name = "ManualThrustButton"
	manual_thrust_btn.text = "Manual Thrust Control"
	manual_thrust_btn.custom_minimum_size = Vector2(0, 32)
	manual_thrust_btn.toggle_mode = true
	manual_thrust_btn.pressed.connect(func() -> void:
		var slider_row = est_vbox.find_child("ThrustSliderRow", false, false)
		if slider_row:
			slider_row.visible = manual_thrust_btn.button_pressed
	)
	thrust_control_row.add_child(manual_thrust_btn)

	var ai_label := Label.new()
	ai_label.name = "AIThrustLabel"
	ai_label.text = "AI: %.0f%% (%s)" % [_selected_ship.thrust_setting * 100.0, CompanyPolicy.THRUST_POLICY_NAMES[GameState.thrust_policy]]
	ai_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	thrust_control_row.add_child(ai_label)

	est_vbox.add_child(thrust_control_row)

	# Thrust slider (hidden by default)
	var thrust_slider_row := HBoxContainer.new()
	thrust_slider_row.name = "ThrustSliderRow"
	thrust_slider_row.visible = false
	thrust_slider_row.add_theme_constant_override("separation", 8)

	var thrust_label := Label.new()
	thrust_label.text = "Thrust:"
	thrust_label.custom_minimum_size = Vector2(60, 0)
	thrust_slider_row.add_child(thrust_label)

	var thrust_slider := HSlider.new()
	thrust_slider.name = "ThrustSlider"
	thrust_slider.min_value = 0.1
	thrust_slider.max_value = 1.0
	thrust_slider.step = 0.05
	thrust_slider.value = _selected_ship.thrust_setting
	thrust_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	thrust_slider.custom_minimum_size = Vector2(200, 0)
	thrust_slider.value_changed.connect(func(value: float) -> void:
		_selected_ship.thrust_setting = value
		_update_estimate_display()
	)
	thrust_slider_row.add_child(thrust_slider)

	var thrust_pct_label := Label.new()
	thrust_pct_label.name = "ThrustPctLabel"
	thrust_pct_label.text = "%.0f%%" % (_selected_ship.thrust_setting * 100.0)
	thrust_pct_label.custom_minimum_size = Vector2(50, 0)
	thrust_slider_row.add_child(thrust_pct_label)

	est_vbox.add_child(thrust_slider_row)

	var est_details := Label.new()
	est_details.name = "EstimateDetails"
	est_details.text = "Select crew to see estimate"
	est_vbox.add_child(est_details)

	est_panel.add_child(est_vbox)
	dispatch_content.add_child(est_panel)

	var _back_cb := func() -> void:
		_cancel_preview()
		_show_asteroid_selection()
	var _cancel_cb := func() -> void:
		_cancel_preview()
		_hide_dispatch()
	_set_dispatch_buttons([
		{"text": "Back", "callback": _back_cb},
		{"text": "Confirm Dispatch", "callback": _execute_dispatch},
		{"text": "Cancel", "callback": _cancel_cb},
	])

func _update_route_button_states() -> void:
	# Toggle route buttons to reflect selection
	var est_panel := dispatch_content.find_child("EstimatePanel", true, false)
	if not est_panel:
		return

	# Update direct route button
	var direct_btn: Button = est_panel.find_child("DirectRouteButton", true, false)
	if direct_btn:
		direct_btn.button_pressed = (_selected_slingshot_route == null)

	# Update slingshot buttons
	for route in _available_slingshot_routes:
		var slingshot_btn: Button = est_panel.find_child("SlingshotButton_%d" % route.planet_index, true, false)
		if slingshot_btn:
			slingshot_btn.button_pressed = (_selected_slingshot_route == route)

func _optimize_crew(available: Array, mode: String) -> void:
	_selected_workers.clear()
	if mode != "clear":
		var sorted_workers := available.duplicate()
		match mode:
			"mining":
				sorted_workers.sort_custom(func(a: Worker, b: Worker) -> bool:
					return a.mining_skill > b.mining_skill
				)
			"pilot":
				sorted_workers.sort_custom(func(a: Worker, b: Worker) -> bool:
					return a.pilot_skill > b.pilot_skill
				)
			"engineer":
				sorted_workers.sort_custom(func(a: Worker, b: Worker) -> bool:
					return a.engineer_skill > b.engineer_skill
				)
			"auto":
				sorted_workers.sort_custom(func(a: Worker, b: Worker) -> bool:
					var avg_a := (a.pilot_skill + a.engineer_skill + a.mining_skill) / 3.0
					var avg_b := (b.pilot_skill + b.engineer_skill + b.mining_skill) / 3.0
					return avg_a > avg_b
				)
		var count := mini(sorted_workers.size(), _selected_ship.min_crew)
		for i in count:
			_selected_workers.append(sorted_workers[i])

	# Update all crew button styles to match selection
	for worker: Worker in _worker_checkboxes:
		var btn: Button = _worker_checkboxes[worker]
		if is_instance_valid(btn):
			_apply_crew_style(btn, worker in _selected_workers)
	_update_estimate_display()

func _apply_selection_style(btn: Button, selected: bool) -> void:
	if selected:
		btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
		var style := StyleBoxFlat.new()
		style.border_color = Color(0.5, 0.7, 0.9, 0.6)
		style.border_width_left = 1
		style.border_width_right = 1
		style.border_width_top = 1
		style.border_width_bottom = 1
		style.bg_color = Color(0.2, 0.25, 0.35, 0.3)
		style.content_margin_left = 8.0
		style.content_margin_right = 8.0
		style.content_margin_top = 4.0
		style.content_margin_bottom = 4.0
		btn.add_theme_stylebox_override("normal", style)
	else:
		btn.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))

func _apply_crew_style(btn: Button, selected: bool) -> void:
	if selected:
		# Selected = assigned, dim down (they're "in the crew", settled)
		btn.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	else:
		# Unselected = available, bright (they stand out, waiting to be picked)
		btn.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))

func _update_estimate_display() -> void:
	var est_panel := dispatch_content.find_child("EstimatePanel", true, false)
	if not est_panel:
		return
	var est_label: Label = est_panel.find_child("EstimateDetails", true, false)
	if not est_label:
		return

	if _selected_workers.size() < _selected_ship.min_crew:
		est_label.text = "Need at least %d crew (%d selected)" % [
			_selected_ship.min_crew, _selected_workers.size()
		]
		est_label.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
		return

	# Get estimate with current transit mode
	var est := AsteroidData.estimate_mission(
		_selected_asteroid, _selected_ship, _selected_workers, -1.0, Vector2(-999, -999), _selected_transit_mode
	)

	# Override estimates if using slingshot route
	if _selected_slingshot_route:
		est["fuel_needed"] = _selected_slingshot_route.fuel_cost
		est["fuel_cost"] = int(_selected_slingshot_route.fuel_cost * Ship.FUEL_COST_PER_UNIT)
		est["transit_time"] = _selected_slingshot_route.transit_time
		# Profit = revenue - fuel cost
		est["profit"] = est["revenue"] - est["fuel_cost"]

	# If selling at destination markets, recalculate profit with colony prices
	var adjusted_profit: float = est["profit"]
	var nearest_colony: Colony = null
	var colony_revenue: float = est["revenue"]

	if _sell_at_destination_markets:
		# Find nearest colony to asteroid
		var asteroid_pos := _selected_asteroid.get_position_au()
		var nearest_dist := 999999.0
		for colony in GameState.colonies:
			var d := asteroid_pos.distance_to(colony.get_position_au())
			if d < nearest_dist:
				nearest_dist = d
				nearest_colony = colony

		if nearest_colony:
			# Recalculate revenue at colony prices
			colony_revenue = 0.0
			var cargo_breakdown: Dictionary = est["cargo_breakdown"]
			for ore_type in cargo_breakdown:
				var tons: float = cargo_breakdown[ore_type]
				var colony_price := nearest_colony.get_ore_price(ore_type, GameState.market)
				colony_revenue += tons * colony_price

			# Recalculate profit with colony revenue
			adjusted_profit = colony_revenue - est["wage_cost"] - est["fuel_cost"]

	# Update transit mode button states
	var mode_hbox := est_panel.find_child("TransitModeButtons", true, false)
	if mode_hbox:
		var brach_btn: Button = mode_hbox.find_child("BrachButton", false, false)
		var hohmann_btn: Button = mode_hbox.find_child("HohmannButton", false, false)
		if brach_btn and hohmann_btn:
			brach_btn.button_pressed = (_selected_transit_mode == Mission.TransitMode.BRACHISTOCHRONE)
			hohmann_btn.button_pressed = (_selected_transit_mode == Mission.TransitMode.HOHMANN)
			# Disable Hohmann if not viable (insufficient fuel)
			hohmann_btn.disabled = not est.get("hohmann_available", false)
			if hohmann_btn.disabled and _selected_transit_mode == Mission.TransitMode.HOHMANN:
				# Auto-switch to brachistochrone if Hohmann becomes invalid
				_selected_transit_mode = Mission.TransitMode.BRACHISTOCHRONE
				brach_btn.button_pressed = true
				hohmann_btn.button_pressed = false
				# Recalculate
				est = AsteroidData.estimate_mission(
					_selected_asteroid, _selected_ship, _selected_workers, -1.0, Vector2(-999, -999), _selected_transit_mode
				)

	# Update thrust labels
	var thrust_pct_label: Label = est_panel.find_child("ThrustPctLabel", true, false)
	if thrust_pct_label:
		thrust_pct_label.text = "%.0f%%" % (_selected_ship.thrust_setting * 100.0)

	var ai_thrust_label: Label = est_panel.find_child("AIThrustLabel", true, false)
	if ai_thrust_label:
		ai_thrust_label.text = "AI: %.0f%% (%s)" % [_selected_ship.thrust_setting * 100.0, CompanyPolicy.THRUST_POLICY_NAMES[GameState.thrust_policy]]

	var mode_name := "HOHMANN (Fuel-Efficient)" if _selected_transit_mode == Mission.TransitMode.HOHMANN else "BRACHISTOCHRONE (Fast)"

	var lines: Array[String] = []
	lines.append("Mode: %s" % mode_name)
	lines.append("Transit: %s each way" % _format_time(est["transit_time"]))
	lines.append("Mining: %s  |  Total: %s" % [
		_format_time(est["mining_time"]), _format_time(est["total_time"])
	])
	lines.append("Cargo: %.0f / %.0f t" % [est["cargo_total"], _selected_ship.cargo_capacity])

	# Fuel cost
	if GameState.settings.get("auto_refuel", true):
		var fuel_cost: float = est.get("fuel_cost", 0.0)
		lines.append("Fuel cost: $%s" % _format_number(int(fuel_cost)))

	# Fuel warning for one-way insufficiency
	var dist := _selected_ship.position_au.distance_to(_selected_asteroid.get_position_au())
	var fuel_round_trip := _selected_ship.calc_fuel_for_distance(dist)
	if fuel_round_trip > _selected_ship.fuel_capacity:
		lines.append("WARNING: Insufficient fuel capacity for round trip!")

	lines.append("")

	var breakdown: Dictionary = est["cargo_breakdown"]
	for ore_type in breakdown:
		var tons: float = breakdown[ore_type]
		var price: float
		if _sell_at_destination_markets and nearest_colony:
			price = nearest_colony.get_ore_price(ore_type, GameState.market)
		else:
			price = MarketData.get_ore_price(ore_type)
		lines.append("  %s: %.1ft = $%s" % [
			ResourceTypes.get_ore_name(ore_type), tons, _format_number(int(tons * price))
		])

	lines.append("")
	if _sell_at_destination_markets and nearest_colony:
		lines.append("Revenue (at %s): $%s" % [nearest_colony.colony_name, _format_number(int(colony_revenue))])
	else:
		lines.append("Revenue (at Earth): $%s" % _format_number(int(est["revenue"])))
	lines.append("Wages: -$%s" % _format_number(int(est["wage_cost"])))
	if GameState.settings.get("auto_refuel", true):
		# Show fuel cost with source info
		var fuel_info := FuelPricing.get_fuel_price_info(_selected_ship.position_au)
		var fuel_cost_display := "Fuel: -$%s" % _format_number(int(est.get("fuel_cost", 0.0)))
		if fuel_info["source"] != "Earth Depot":
			fuel_cost_display += " (from %s)" % fuel_info["source"]
		else:
			fuel_cost_display += " (from Earth)"
		lines.append(fuel_cost_display)

	var profit_text := "$%s" % _format_number(int(abs(adjusted_profit)))
	if adjusted_profit >= 0:
		lines.append("Profit: +%s" % profit_text)
	else:
		lines.append("LOSS: -%s" % profit_text)

	est_label.text = "\n".join(lines)

	if adjusted_profit < 0:
		est_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
	elif adjusted_profit < 500:
		est_label.add_theme_color_override("font_color", Color(0.9, 0.8, 0.3))
	else:
		est_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))

func _confirm_dispatch() -> void:
	# Auto-assign crew if not enough selected
	if _selected_workers.size() < _selected_ship.min_crew:
		var available := GameState.get_available_workers()
		# Sort by skill descending
		available.sort_custom(func(a: Worker, b: Worker) -> bool:
			return a.skill > b.skill
		)
		# Add highest skilled workers until min_crew reached
		for worker in available:
			if worker not in _selected_workers:
				_selected_workers.append(worker)
			if _selected_workers.size() >= _selected_ship.min_crew:
				break

	# If still not enough crew, abort
	if _selected_workers.size() < _selected_ship.min_crew:
		return

	# Get mission estimate for confirmation
	var est := AsteroidData.estimate_mission(
		_selected_asteroid, _selected_ship, _selected_workers, -1.0, Vector2(-999, -999), _selected_transit_mode
	)

	var dist := _selected_ship.position_au.distance_to(_selected_asteroid.get_position_au())
	var mode_name := "Hohmann" if _selected_transit_mode == Mission.TransitMode.HOHMANN else "Brachistochrone"
	var profit_sign := "+" if est["profit"] >= 0 else ""

	var crew_names := ""
	for i in range(_selected_workers.size()):
		if i > 0:
			crew_names += ", "
		crew_names += _selected_workers[i].worker_name

	var confirm_text := "Dispatch to %s?\n\nMode: %s\nDistance: %.2f AU\nTransit: %s each way\nMining: %s\nCrew: %s\nEstimated Profit: %s$%s" % [
		_selected_asteroid.asteroid_name, mode_name, dist,
		_format_time(est["transit_time"]), _format_time(est["mining_time"]),
		crew_names, profit_sign, _format_number(int(abs(est["profit"])))
	]

	# Show confirmation before executing
	_show_dispatch_confirmation(confirm_text)

func _show_dispatch_confirmation(message: String) -> void:
	# Clear and show confirmation
	_clear_dispatch_content()

	var title := Label.new()
	title.text = "Confirm Mission Dispatch"
	title.add_theme_font_size_override("font_size", 20)
	dispatch_content.add_child(title)

	var msg_label := Label.new()
	msg_label.text = message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dispatch_content.add_child(msg_label)

	var buttons: Array[Dictionary] = []
	if _is_planning_mode:
		var _queue_cb := func() -> void: _queue_mission()
		var _abort_cb := func() -> void: _abort_and_dispatch()
		buttons.append({"text": "Queue for After Current Task", "callback": _queue_cb})
		buttons.append({"text": "Dispatch Now (Abort Current)", "callback": _abort_cb, "color": Color(0.9, 0.3, 0.3)})
	else:
		var _confirm_cb := func() -> void: _execute_dispatch()
		buttons.append({"text": "Confirm Dispatch", "callback": _confirm_cb})
	var _cancel_cb := func() -> void: _show_worker_selection()
	buttons.append({"text": "Cancel", "callback": _cancel_cb})
	_set_dispatch_buttons(buttons)

	_show_dispatch()

func _queue_mission() -> void:
	# Queue the mission to start when current task completes
	var mining_duration := 86400.0  # Default 1 day
	if _selected_asteroid:
		# Calculate mining duration based on workers and ore amount
		var total_mining_rate := 0.0
		for worker in _selected_workers:
			total_mining_rate += worker.mining_rate
		var total_ore: float = _selected_asteroid.get_total_ore()
		var cargo_space: float = _selected_ship.get_cargo_remaining()
		var minable_ore: float = min(total_ore, cargo_space)
		if total_mining_rate > 0:
			mining_duration = minable_ore / total_mining_rate

	_selected_ship.queue_mission(
		_selected_asteroid,
		_selected_workers,
		_selected_transit_mode,
		mining_duration,
		_selected_slingshot_route
	)

	# Remember crew for next dispatch
	_selected_ship.last_crew = _selected_workers.duplicate()

	_cancel_preview()
	_hide_dispatch()
	_mark_dirty()

func _abort_and_dispatch() -> void:
	# Abort current mission and dispatch immediately
	# Clear current mission
	if _selected_ship.current_mission:
		_selected_ship.current_mission = null
	if _selected_ship.current_trade_mission:
		_selected_ship.current_trade_mission = null

	# Now execute normal dispatch
	_execute_dispatch()

func _execute_dispatch() -> void:
	# Actually execute the dispatch after confirmation
	# Check fuel
	if GameState.settings.get("auto_refuel", true):
		var dist := _selected_ship.position_au.distance_to(_selected_asteroid.get_position_au())
		var fuel_needed := _selected_ship.calc_fuel_for_distance(dist)
		var fuel_cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)
		if GameState.money < fuel_cost:
			return  # Can't afford fuel
		# Refuel and charge
		_selected_ship.fuel = _selected_ship.fuel_capacity
		GameState.money -= fuel_cost

	# Remember crew for next dispatch
	_selected_ship.last_crew = _selected_workers.duplicate()

	match _selected_mission_type:
		Mission.MissionType.DEPLOY_UNIT:
			GameState.start_deploy_mission(_selected_ship, _selected_asteroid, _selected_workers, _selected_deploy_units, _selected_deploy_workers, _selected_transit_mode, _selected_slingshot_route)
		Mission.MissionType.COLLECT_ORE:
			GameState.start_collect_mission(_selected_ship, _selected_asteroid, _selected_workers, _selected_transit_mode, _selected_slingshot_route)
		_:
			if _selected_ship.is_idle_remote:
				GameState.dispatch_idle_ship(_selected_ship, _selected_asteroid, _selected_workers, _selected_transit_mode, _selected_slingshot_route)
			else:
				GameState.start_mission(_selected_ship, _selected_asteroid, _selected_workers, _selected_transit_mode, _selected_slingshot_route)
	_cancel_preview()
	_hide_dispatch()
	_mark_dirty()

func _build_details_text(ship: Ship) -> String:
	var engine_str := ""
	if ship.engine_condition < 100.0:
		engine_str = " | Eng: %d%%" % int(ship.engine_condition)
	return "Thrust: %.1fg (%.0f%%) | Cargo: %.0f/%.0ft\nFuel: %.0f/%.0f | Equip: %d/%d (%.2fx)%s" % [
		ship.get_effective_thrust(), ship.thrust_setting * 100.0, ship.get_cargo_total(), ship.get_effective_cargo_capacity(),
		ship.fuel, ship.get_effective_fuel_capacity(),
		ship.equipment.size(), ship.max_equipment_slots, ship.get_mining_multiplier(),
		engine_str,
	]

func _calculate_jettison_for_asymmetric_trip(dist_outbound: float, dist_return: float) -> float:
	# Calculate minimum cargo to jettison for asymmetric trip
	var current_cargo := _selected_ship.get_cargo_total()

	# Binary search for minimum jettison
	var low := 0.0
	var high := current_cargo
	var needed_jettison := current_cargo

	for _i in range(10):
		var mid := (low + high) / 2.0
		var remaining_cargo := current_cargo - mid

		# Fuel needed: outbound with current cargo, return fully loaded
		var fuel_out := _selected_ship.calc_fuel_for_distance(dist_outbound, remaining_cargo)
		var fuel_ret := _selected_ship.calc_fuel_for_distance(dist_return, _selected_ship.cargo_capacity)
		var total_fuel := fuel_out + fuel_ret

		if total_fuel <= _selected_ship.fuel:
			needed_jettison = mid
			high = mid
		else:
			low = mid

	return needed_jettison

func _clear_dispatch_content() -> void:
	_free_children(dispatch_content)

func _format_time(ticks: float) -> String:
	return TimeScale.format_time(ticks)

var _station_job_checks: Dictionary = {}  # job_name -> CheckBox
var _station_job_order: Array[String] = []  # Current ordering

const STATION_JOBS: Array[Dictionary] = [
	{"key": "mining", "label": "Mining", "desc": "Mine nearby asteroids"},
	{"key": "trading", "label": "Trading", "desc": "Sell ore at local market"},
	{"key": "repair", "label": "Repair Assist", "desc": "Repair nearby damaged ships"},
	{"key": "parts_delivery", "label": "Parts Delivery", "desc": "Deliver repair parts to remote ships"},
	{"key": "provisioning", "label": "Provisioning", "desc": "Supply deployed crews with food"},
	{"key": "crew_ferry", "label": "Crew Rotation", "desc": "Rotate fatigued workers"},
	{"key": "patrol", "label": "Patrol", "desc": "Patrol nearby rocks"},
]

func _show_station_jobs(ship: Ship) -> void:
	_selected_ship = ship
	_show_dispatch()
	_clear_dispatch_content()
	_on_selection_screen = false
	_on_estimate_screen = false

	var colony: Colony = ship.docked_at_colony if ship.docked_at_colony else ship.station_colony
	var colony_name := colony.colony_name if colony else "Unknown"

	var title := Label.new()
	title.text = "STATION AT %s" % colony_name.to_upper()
	title.add_theme_font_size_override("font_size", 20)
	dispatch_content.add_child(title)

	var desc := Label.new()
	desc.text = "Select jobs and priority order. Ship will autonomously perform the highest-priority actionable job."
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	dispatch_content.add_child(desc)

	# Initialize job order from existing or defaults
	_station_job_order.clear()
	_station_job_checks.clear()

	# Use existing jobs if editing, otherwise start with mining + trading
	var existing_jobs: Array[String] = ship.station_jobs if ship.is_stationed else []
	var all_job_keys: Array[String] = []
	for job_def in STATION_JOBS:
		all_job_keys.append(job_def["key"])

	# Order: existing enabled jobs first, then remaining in default order
	for job_key in existing_jobs:
		if job_key in all_job_keys:
			_station_job_order.append(job_key)
	for job_key in all_job_keys:
		if job_key not in _station_job_order:
			_station_job_order.append(job_key)

	# Build job list UI
	var jobs_container := VBoxContainer.new()
	jobs_container.name = "JobsContainer"
	jobs_container.add_theme_constant_override("separation", 4)
	dispatch_content.add_child(jobs_container)

	_rebuild_station_job_list(jobs_container, existing_jobs)

	# Buttons
	_set_dispatch_buttons([
		{
			"text": "Confirm Station" if not ship.is_stationed else "Update Jobs",
			"callback": func() -> void:
				var selected_jobs: Array[String] = []
				for job_key in _station_job_order:
					if _station_job_checks.has(job_key):
						var cb: CheckBox = _station_job_checks[job_key]
						if cb.button_pressed:
							selected_jobs.append(job_key)
				if selected_jobs.is_empty():
					return  # Must select at least one job
				if ship.is_stationed:
					GameState.update_station_jobs(ship, selected_jobs)
				else:
					GameState.station_ship(ship, colony, selected_jobs)
				_hide_dispatch()
				_mark_dirty(),
		},
		{
			"text": "Cancel",
			"callback": func() -> void:
				_hide_dispatch()
				_cancel_preview(),
			"color": Color(0.7, 0.7, 0.7),
		},
	])

func _rebuild_station_job_list(container: VBoxContainer, enabled_jobs: Array[String]) -> void:
	_free_children(container)

	var priority_label := Label.new()
	priority_label.text = "Priority (top = highest):"
	priority_label.add_theme_font_size_override("font_size", 14)
	container.add_child(priority_label)

	for i in range(_station_job_order.size()):
		var job_key: String = _station_job_order[i]
		var job_def: Dictionary = {}
		for jd in STATION_JOBS:
			if jd["key"] == job_key:
				job_def = jd
				break

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)

		# Priority number
		var num_label := Label.new()
		num_label.text = "%d." % (i + 1)
		num_label.custom_minimum_size = Vector2(24, 0)
		num_label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		row.add_child(num_label)

		# Checkbox
		var cb := CheckBox.new()
		cb.text = "%s — %s" % [job_def.get("label", job_key), job_def.get("desc", "")]
		cb.button_pressed = job_key in enabled_jobs or (enabled_jobs.is_empty() and job_key in ["mining", "trading"])
		cb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(cb)
		_station_job_checks[job_key] = cb

		# Move up button
		if i > 0:
			var up_btn := Button.new()
			up_btn.text = "^"
			up_btn.custom_minimum_size = Vector2(36, 36)
			var idx := i
			up_btn.pressed.connect(func() -> void:
				_station_move_job(idx, -1, container, enabled_jobs)
			)
			row.add_child(up_btn)
		else:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(36, 36)
			row.add_child(spacer)

		# Move down button
		if i < _station_job_order.size() - 1:
			var down_btn := Button.new()
			down_btn.text = "v"
			down_btn.custom_minimum_size = Vector2(36, 36)
			var idx := i
			down_btn.pressed.connect(func() -> void:
				_station_move_job(idx, 1, container, enabled_jobs)
			)
			row.add_child(down_btn)
		else:
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(36, 36)
			row.add_child(spacer)

		container.add_child(row)

func _station_move_job(idx: int, direction: int, container: VBoxContainer, enabled_jobs: Array[String]) -> void:
	var new_idx := idx + direction
	if new_idx < 0 or new_idx >= _station_job_order.size():
		return
	# Capture current check states before rebuild
	var current_enabled: Array[String] = []
	for job_key in _station_job_order:
		if _station_job_checks.has(job_key):
			var cb: CheckBox = _station_job_checks[job_key]
			if cb.button_pressed:
				current_enabled.append(job_key)
	# Swap
	var tmp: String = _station_job_order[idx]
	_station_job_order[idx] = _station_job_order[new_idx]
	_station_job_order[new_idx] = tmp
	_station_job_checks.clear()
	_rebuild_station_job_list(container, current_enabled)

func _show_supply_shop(ship: Ship) -> void:
	_selected_ship = ship
	_show_dispatch()
	_clear_dispatch_content()
	_on_selection_screen = false
	_on_estimate_screen = false

	var title := Label.new()
	title.text = "BUY SUPPLIES"
	title.add_theme_font_size_override("font_size", 20)
	dispatch_content.add_child(title)

	var desc := Label.new()
	desc.text = "Purchase supplies for %s. Supplies share cargo capacity with ore." % ship.ship_name
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
	dispatch_content.add_child(desc)

	var capacity_label := Label.new()
	var cargo_used := ship.get_cargo_total() + ship.get_supplies_mass()
	capacity_label.text = "Cargo: %.1f / %.1f tons" % [cargo_used, ship.cargo_capacity]
	capacity_label.add_theme_color_override("font_color", Color(0.8, 0.8, 0.5))
	dispatch_content.add_child(capacity_label)

	var money_label := Label.new()
	money_label.text = "Funds: $%s" % _format_number(GameState.money)
	money_label.add_theme_color_override("font_color", Color(0.5, 0.9, 0.5))
	dispatch_content.add_child(money_label)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 8)
	dispatch_content.add_child(spacer)

	# Supply spinboxes
	var spinboxes: Dictionary = {}
	for supply_type in SupplyData.SUPPLY_INFO:
		var info: Dictionary = SupplyData.SUPPLY_INFO[supply_type]
		var key: String = info["key"]
		var supply_name: String = info["name"]
		var cost: int = info["cost_per_unit"]
		var mass: float = info["mass_per_unit"]
		var current: float = ship.supplies.get(key, 0.0)

		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 2)

		var header := Label.new()
		header.text = "%s — $%s/unit, %.2ft/unit" % [supply_name, _format_number(cost), mass]
		header.add_theme_font_size_override("font_size", 14)
		row.add_child(header)

		if current > 0:
			var cur_label := Label.new()
			cur_label.text = "  On board: %.0f units" % current
			cur_label.add_theme_color_override("font_color", Color(0.5, 0.7, 0.5))
			cur_label.add_theme_font_size_override("font_size", 13)
			row.add_child(cur_label)

		var spin_row := HBoxContainer.new()
		spin_row.add_theme_constant_override("separation", 8)

		var qty_label := Label.new()
		qty_label.text = "Buy:"
		spin_row.add_child(qty_label)

		var spinbox := SpinBox.new()
		spinbox.min_value = 0
		spinbox.max_value = 999
		spinbox.step = 1
		spinbox.value = 0
		spinbox.custom_minimum_size = Vector2(120, 40)
		spin_row.add_child(spinbox)
		spinboxes[key] = spinbox

		var cost_preview := Label.new()
		cost_preview.text = "= $0"
		cost_preview.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
		spin_row.add_child(cost_preview)

		spinbox.value_changed.connect(func(val: float) -> void:
			cost_preview.text = "= $%s" % _format_number(int(val * cost))
		)

		row.add_child(spin_row)
		dispatch_content.add_child(row)

	_set_dispatch_buttons([
		{
			"text": "Purchase",
			"callback": func() -> void:
				var any_bought := false
				for key in spinboxes:
					var sb: SpinBox = spinboxes[key]
					var qty := int(sb.value)
					if qty > 0:
						if GameState.buy_supplies(ship, key, float(qty)):
							any_bought = true
						else:
							ship.add_station_log("Failed to buy %s" % key.replace("_", " "), "warning")
				if any_bought:
					ship.add_station_log("Purchased supplies", "system")
				_hide_dispatch()
				_mark_dirty(),
		},
		{
			"text": "Cancel",
			"callback": func() -> void:
				_hide_dispatch()
				_cancel_preview(),
			"color": Color(0.7, 0.7, 0.7),
		},
	])

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

func _calculate_colony_profit(colony: Colony) -> int:
	# Calculate net profit for selling at this colony (revenue - fuel cost)
	if not _selected_ship:
		return 0

	var colony_pos: Vector2 = colony.get_position_au()
	var dist := _selected_ship.position_au.distance_to(colony_pos)

	# Calculate fuel cost for round trip
	var cargo_mass := _selected_ship.get_cargo_total()
	var fuel_outbound := _selected_ship.calc_fuel_for_distance(dist, cargo_mass)
	var fuel_return := _selected_ship.calc_fuel_for_distance(dist, 0.0)
	var fuel_needed := fuel_outbound + fuel_return
	var fuel_cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)

	# Calculate revenue from cargo
	var revenue := 0
	for ore_type in _selected_ship.current_cargo:
		var amount: float = _selected_ship.current_cargo[ore_type]
		var price: float = colony.get_ore_price(ore_type, GameState.market)
		revenue += int(amount * price)

	return revenue - fuel_cost

func _confirm_colony_dispatch(colony: Colony) -> void:
	_on_selection_screen = false  # Left the main selection screen
	_on_estimate_screen = false  # Not on estimate screen
	# Show confirmation dialog before dispatching
	var colony_pos: Vector2 = colony.get_position_au()
	var dist := _selected_ship.position_au.distance_to(colony_pos)
	var transit := Brachistochrone.transit_time(dist, _selected_ship.get_effective_thrust())

	# Calculate revenue
	var revenue := 0
	for ore_type in _selected_ship.current_cargo:
		var amount: float = _selected_ship.current_cargo[ore_type]
		var price: float = colony.get_ore_price(ore_type, GameState.market)
		revenue += int(amount * price)

	var confirm_text := "Dispatch to %s?\n\nDistance: %.2f AU\nTransit: %s\nRevenue: $%s" % [
		colony.colony_name, dist, _format_time(transit), _format_number(revenue)
	]

	# Create confirmation popup
	_show_confirmation_dialog(confirm_text, func() -> void:
		_select_colony_trade(colony)
	)

func _confirm_asteroid_dispatch(asteroid: AsteroidData) -> void:
	_on_selection_screen = false  # Left the main selection screen
	_on_estimate_screen = false  # Not on estimate screen
	# Show confirmation dialog before dispatching to asteroid
	_selected_asteroid = asteroid
	_show_worker_selection()

func _calculate_fuel_route(destination: Colony) -> Array[String]:
	# Calculate route with fuel stops from current position to destination
	# Returns array of colony names to visit, or empty if unreachable
	const PROXIMITY_THRESHOLD := 0.1
	const MAX_HOPS := 3  # Maximum fuel stops allowed

	var cargo_mass := _selected_ship.get_cargo_total()
	var current_pos := _selected_ship.position_au
	var current_fuel := _selected_ship.fuel
	var max_fuel := _selected_ship.get_effective_fuel_capacity()
	var dest_pos: Vector2 = destination.get_position_au()

	# Check if we can reach directly
	var direct_dist := current_pos.distance_to(dest_pos)
	var direct_fuel := _selected_ship.calc_fuel_for_distance(direct_dist, cargo_mass)
	if direct_fuel <= current_fuel:
		return []  # No fuel stops needed

	# Find route with fuel stops (simple greedy algorithm)
	var route: Array[String] = []
	var visited: Array[Colony] = []
	var pos := current_pos
	var fuel := current_fuel

	for hop in range(MAX_HOPS):
		# Find best intermediate colony
		var best_colony: Colony = null
		var best_score := -999999.0

		for colony in GameState.colonies:
			if colony in visited:
				continue
			if colony == destination:
				continue  # Don't stop at destination for fuel

			var colony_pos: Vector2 = colony.get_position_au()

			# Skip if it's current location
			var dist_from_ship := _selected_ship.position_au.distance_to(colony_pos)
			if dist_from_ship < PROXIMITY_THRESHOLD:
				continue

			# Check if reachable from current position
			var dist_to_colony := pos.distance_to(colony_pos)
			var fuel_to_colony := _selected_ship.calc_fuel_for_distance(dist_to_colony, cargo_mass)
			if fuel_to_colony > fuel:
				continue  # Can't reach this colony

			# Check if destination is reachable from this colony (with full fuel)
			# Use current positions with safety margin to account for orbital motion
			var dist_colony_to_dest := colony_pos.distance_to(dest_pos)
			var fuel_colony_to_dest := _selected_ship.calc_fuel_for_distance(dist_colony_to_dest, cargo_mass)
			# Add 20% safety margin for orbital motion during transit
			if fuel_colony_to_dest > max_fuel * 0.8:
				continue  # Can't reach destination from this colony with safety margin

			# Score: prefer colonies closer to destination
			var score := -dist_colony_to_dest
			if score > best_score:
				best_score = score
				best_colony = colony

		if not best_colony:
			return []  # No valid route found

		# Add this colony to route
		route.append(best_colony.colony_name)
		visited.append(best_colony)
		pos = best_colony.get_position_au()
		fuel = max_fuel  # Refuel at colony

		# Check if we can now reach destination (with safety margin)
		var dist_to_dest := pos.distance_to(dest_pos)
		var fuel_to_dest := _selected_ship.calc_fuel_for_distance(dist_to_dest, cargo_mass)
		# Use 80% of fuel capacity as threshold to provide safety margin
		if fuel_to_dest <= fuel * 0.8:
			return route  # Success!

	return []  # Couldn't find route within MAX_HOPS

func _calculate_fuel_route_to_position(dest_pos: Vector2, cargo_mass: float) -> Array[String]:
	# Calculate route with fuel stops to reach a specific position (for asteroids)
	# Similar to _calculate_fuel_route but works with a Vector2 position instead of Colony
	const PROXIMITY_THRESHOLD := 0.1
	const MAX_HOPS := 3

	var current_pos := _selected_ship.position_au
	var current_fuel := _selected_ship.fuel
	var max_fuel := _selected_ship.get_effective_fuel_capacity()

	# Check if we can reach directly
	var direct_dist := current_pos.distance_to(dest_pos)
	var direct_fuel := _selected_ship.calc_fuel_for_distance(direct_dist, cargo_mass)
	if direct_fuel <= current_fuel:
		return []  # No fuel stops needed

	# Find route with fuel stops
	var route: Array[String] = []
	var visited: Array[Colony] = []
	var pos := current_pos
	var fuel := current_fuel

	for hop in range(MAX_HOPS):
		var best_colony: Colony = null
		var best_score := -999999.0

		for colony in GameState.colonies:
			if colony in visited:
				continue

			var colony_pos: Vector2 = colony.get_position_au()

			# Skip if it's current location
			var dist_from_ship := _selected_ship.position_au.distance_to(colony_pos)
			if dist_from_ship < PROXIMITY_THRESHOLD:
				continue

			# Check if reachable from current position
			var dist_to_colony := pos.distance_to(colony_pos)
			var fuel_to_colony := _selected_ship.calc_fuel_for_distance(dist_to_colony, cargo_mass)
			if fuel_to_colony > fuel:
				continue

			# Check if destination position is reachable from this colony
			var dist_colony_to_dest := colony_pos.distance_to(dest_pos)
			var fuel_colony_to_dest := _selected_ship.calc_fuel_for_distance(dist_colony_to_dest, cargo_mass)
			if fuel_colony_to_dest > max_fuel * 0.8:
				continue

			# Prefer colonies closer to destination
			var score := -dist_colony_to_dest
			if score > best_score:
				best_score = score
				best_colony = colony

		if not best_colony:
			return []

		route.append(best_colony.colony_name)
		visited.append(best_colony)
		pos = best_colony.get_position_au()
		fuel = max_fuel

		# Check if we can now reach destination
		var dist_to_dest := pos.distance_to(dest_pos)
		var fuel_to_dest := _selected_ship.calc_fuel_for_distance(dist_to_dest, cargo_mass)
		if fuel_to_dest <= fuel * 0.8:
			return route

	return []

func _show_confirmation_dialog(message: String, on_confirm: Callable) -> void:
	# Clear dispatch content and show confirmation
	_clear_dispatch_content()

	var title := Label.new()
	title.text = "Confirm Dispatch"
	title.add_theme_font_size_override("font_size", 20)
	dispatch_content.add_child(title)

	var msg_label := Label.new()
	msg_label.text = message
	msg_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	dispatch_content.add_child(msg_label)

	var _confirm_cb := func() -> void: on_confirm.call()
	var _cancel_cb := func() -> void: _show_asteroid_selection()
	_set_dispatch_buttons([
		{"text": "Confirm", "callback": _confirm_cb},
		{"text": "Cancel", "callback": _cancel_cb},
	])

	_show_dispatch()

func _get_matching_contracts(ship: Ship, colony: Colony) -> Array[Contract]:
	# Find active contracts that match ship's cargo and can be delivered at this colony
	var matches: Array[Contract] = []
	for contract in GameState.active_contracts:
		# Check if contract can be delivered at this colony
		if contract.delivery_colony and contract.delivery_colony != colony:
			continue  # Wrong delivery location

		# Check if ship has this ore type
		if ship.current_cargo.get(contract.ore_type, 0.0) > 0:
			matches.append(contract)

	return matches

func _add_contract_fulfillment_ui(container: VBoxContainer, ship: Ship, contract: Contract, colony: Colony) -> void:
	var panel := PanelContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 4)

	# Contract info
	var info := Label.new()
	var ore_name := ResourceTypes.get_ore_name(contract.ore_type)
	var ship_has: float = ship.current_cargo.get(contract.ore_type, 0.0)
	var remaining := contract.get_remaining_quantity()
	var can_deliver := minf(ship_has, remaining)
	var contract_price_per_ton := float(contract.reward) / contract.quantity
	var spot_price := colony.get_ore_price(contract.ore_type, GameState.market)

	var price_comparison := ""
	if contract_price_per_ton > spot_price:
		var premium := ((contract_price_per_ton / spot_price) - 1.0) * 100.0
		price_comparison = " (+%.0f%% vs spot)" % premium
	else:
		var discount := (1.0 - (contract_price_per_ton / spot_price)) * 100.0
		price_comparison = " (-%.0f%% vs spot)" % discount

	info.text = "%s: %s %.1ft/%.1ft - $%.0f/t%s - %.0f ticks\nYou have: %.1ft | Can deliver: %.1ft" % [
		contract.issuer_name, ore_name, contract.quantity_delivered, contract.quantity,
		contract_price_per_ton, price_comparison, contract.deadline_ticks,
		ship_has, can_deliver
	]
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(info)

	# Fulfillment buttons
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 8)

	# Full/Partial fulfillment button
	var fulfill_btn := Button.new()
	var payment := contract.get_partial_payment(can_deliver)
	if can_deliver >= remaining:
		fulfill_btn.text = "Fulfill Contract ($%s)" % _format_number(payment)
	else:
		if contract.allows_partial:
			fulfill_btn.text = "Deliver %.1ft ($%s)" % [can_deliver, _format_number(payment)]
		else:
			fulfill_btn.text = "Requires Full Amount"
			fulfill_btn.disabled = true

	fulfill_btn.custom_minimum_size = Vector2(0, 36)
	fulfill_btn.pressed.connect(func() -> void:
		var result := GameState.fulfill_contract_from_ship(contract, ship, can_deliver)
		if result["success"]:
			_mark_dirty()
	)
	btn_row.add_child(fulfill_btn)

	# Spot market comparison
	var spot_value := int(can_deliver * spot_price)
	var spot_label := Label.new()
	spot_label.text = "Spot: $%s" % _format_number(spot_value)
	if payment > spot_value:
		spot_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	else:
		spot_label.add_theme_color_override("font_color", Color(0.9, 0.6, 0.3))
	btn_row.add_child(spot_label)

	vbox.add_child(btn_row)
	panel.add_child(vbox)
	container.add_child(panel)

func _build_buy_ship_ui() -> void:
	# Clear existing content
	_free_children(buy_ship_content)

	# Header with title and close button
	var header := HBoxContainer.new()
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var title := Label.new()
	title.text = "BUY NEW SHIP"
	title.add_theme_font_size_override("font_size", 20)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "Close"
	close_btn.custom_minimum_size = Vector2(0, 40)
	close_btn.pressed.connect(_hide_buy_ship)
	header.add_child(close_btn)

	buy_ship_content.add_child(header)

	var sep := HSeparator.new()
	buy_ship_content.add_child(sep)

	# Show current money
	var money_label := Label.new()
	money_label.text = "Available Funds: $%s" % _format_number(GameState.money)
	money_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
	money_label.add_theme_font_size_override("font_size", 16)
	buy_ship_content.add_child(money_label)

	buy_ship_content.add_child(HSeparator.new())

	# Display each ship class
	var ship_classes := [
		ShipData.ShipClass.COURIER,
		ShipData.ShipClass.PROSPECTOR,
		ShipData.ShipClass.EXPLORER,
		ShipData.ShipClass.HAULER,
	]

	for ship_class in ship_classes:
		var panel := PanelContainer.new()
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

		var vbox := VBoxContainer.new()
		vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vbox.add_theme_constant_override("separation", 6)

		# Ship class name and price
		var class_header := HBoxContainer.new()
		var class_label := Label.new()
		class_label.text = ShipData.CLASS_NAMES[ship_class]
		class_label.add_theme_font_size_override("font_size", 18)
		class_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		class_header.add_child(class_label)

		var price: int = ShipData.CLASS_PRICES[ship_class]
		var price_label := Label.new()
		price_label.text = "$%s" % _format_number(price)
		price_label.add_theme_font_size_override("font_size", 18)
		if GameState.money >= price:
			price_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.5))
		else:
			price_label.add_theme_color_override("font_color", Color(0.9, 0.3, 0.3))
		class_header.add_child(price_label)

		vbox.add_child(class_header)

		# Description
		var desc := Label.new()
		desc.text = ShipData.get_class_description(ship_class)
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
		vbox.add_child(desc)

		# Specs
		var stats: Dictionary = ShipData.CLASS_STATS[ship_class]
		var specs := Label.new()
		var spec_lines: Array[String] = []
		spec_lines.append("Thrust: %.2fg" % stats["thrust_g"])
		spec_lines.append("Cargo: %.0ft" % stats["cargo_capacity"])
		spec_lines.append("Fuel: %.0f units" % stats["fuel_capacity"])
		spec_lines.append("Min Crew: %d" % stats["min_crew"])
		spec_lines.append("Equipment Slots: %d" % stats["max_equipment_slots"])
		specs.text = " • ".join(spec_lines)
		specs.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		specs.add_theme_color_override("font_color", Color(0.6, 0.8, 0.9))
		vbox.add_child(specs)

		# Purchase button
		var purchase_btn := Button.new()
		purchase_btn.text = "Purchase"
		purchase_btn.custom_minimum_size = Vector2(0, 48)
		purchase_btn.disabled = GameState.money < price

		purchase_btn.pressed.connect(func() -> void:
			var new_ship := GameState.purchase_ship(ship_class)
			if new_ship:
				_hide_buy_ship()
				_mark_dirty()
		)

		vbox.add_child(purchase_btn)

		panel.add_child(vbox)
		buy_ship_content.add_child(panel)
