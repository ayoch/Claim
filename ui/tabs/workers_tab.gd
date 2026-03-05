extends MarginContainer

@onready var workers_list: VBoxContainer = %WorkersList
@onready var candidates_list: VBoxContainer = %CandidatesList
@onready var crew_count: Label = %CrewCount
@onready var refresh_btn: Button = %RefreshBtn

static func _free_children(container: Node) -> void:
	for i in range(container.get_child_count() - 1, -1, -1):
		container.get_child(i).free()

static func _lbl() -> Label:
	var l := Label.new()
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

var _candidates: Array[Worker] = []
var _dirty_crew: bool = false
var _dirty_all: bool = false
var _last_refresh_msec: int = 0
const REFRESH_INTERVAL_MSEC: int = 200

# Server candidate auto-refresh
var _candidate_poll_timer: float = 0.0
const CANDIDATE_POLL_INTERVAL: float = 5.0

func _ready() -> void:
	refresh_btn.pressed.connect(_generate_candidates)
	EventBus.server_state_synced.connect(func() -> void: _dirty_all = true)
	EventBus.worker_hired.connect(func(w: Worker) -> void:
		# In SERVER mode, refetch candidates from server
		# In LOCAL mode, generate a new random candidate to maintain pool
		if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
			_generate_candidates()  # Refetch from server
		else:
			_candidates.erase(w)
			_candidates.append(Worker.generate_random())
		_dirty_all = true
	)
	EventBus.worker_fired.connect(func(_w: Worker) -> void: _dirty_all = true)
	EventBus.worker_skill_leveled.connect(func(_w: Worker, _st: int, _nv: float) -> void: _dirty_crew = true)
	EventBus.crew_casualty_combat.connect(func(_s: Ship, _w: Worker) -> void: _dirty_crew = true)
	EventBus.ship_food_depleted.connect(func(_s: Ship, _count: int) -> void: _dirty_crew = true)
	EventBus.mission_started.connect(func(_m: Mission) -> void: _dirty_crew = true)
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _dirty_crew = true)
	EventBus.tick.connect(_on_tick)
	_generate_candidates()
	_refresh_crew()

func _process(delta: float) -> void:
	if BackendManager.current_mode != BackendManager.BackendMode.SERVER:
		return
	if not is_visible_in_tree():
		return
	_candidate_poll_timer += delta
	if _candidate_poll_timer >= CANDIDATE_POLL_INTERVAL:
		_candidate_poll_timer = 0.0
		_generate_candidates()

func _on_tick(_dt: float) -> void:
	# Skip all updates when tab is not visible (massive performance win)
	if not is_visible_in_tree():
		return

	if not _dirty_crew and not _dirty_all:
		return
	var now := Time.get_ticks_msec()
	if now - _last_refresh_msec < REFRESH_INTERVAL_MSEC:
		return
	_last_refresh_msec = now
	if _dirty_all:
		_dirty_all = false
		_dirty_crew = false
		_refresh_all()
	elif _dirty_crew:
		_dirty_crew = false
		_refresh_crew()

func _refresh_all() -> void:
	_refresh_crew()
	_refresh_candidates()

func _refresh_crew() -> void:
	_free_children(workers_list)

	var total := GameState.workers.size()
	var available := GameState.get_available_workers().size()
	crew_count.text = "%d crew (%d available)" % [total, available]

	if GameState.workers.is_empty():
		var label := _lbl()
		label.text = "No crew hired yet"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		workers_list.add_child(label)
		return

	# Group workers by location and ships by docked location
	var workers_by_location: Dictionary = {}  # location_name -> Array[Worker]
	var ships_by_location: Dictionary = {}    # location_name -> Array[Ship]

	# Group workers by their current location
	for worker: Worker in GameState.workers:
		var location: String = worker.home_colony if worker.home_colony != "" else "Earth"
		if not workers_by_location.has(location):
			workers_by_location[location] = []
		workers_by_location[location].append(worker)

	# Group docked ships by their station location
	for ship: Ship in GameState.ships:
		if ship.is_docked:
			var location: String = "Earth"  # Default
			if ship.station_colony:
				location = ship.station_colony.colony_name
			if not ships_by_location.has(location):
				ships_by_location[location] = []
			ships_by_location[location].append(ship)

	# Get all unique locations (union of worker locations and ship locations)
	var all_locations: Array[String] = []
	for loc in workers_by_location.keys():
		if loc not in all_locations:
			all_locations.append(loc)
	for loc in ships_by_location.keys():
		if loc not in all_locations:
			all_locations.append(loc)

	all_locations.sort()

	# Create section for each location
	for location in all_locations:
		_create_location_section(location, workers_by_location.get(location, []), ships_by_location.get(location, []))

func _create_location_section(location: String, workers: Array, ships: Array) -> void:
	# Location header
	var header := Label.new()
	header.text = "━━━ %s (%d workers, %d ships docked) ━━━" % [location, workers.size(), ships.size()]
	header.add_theme_font_size_override("font_size", 16)
	header.add_theme_color_override("font_color", Color(0.7, 0.8, 1.0))
	workers_list.add_child(header)

	# Show workers at this location
	for worker: Worker in workers:
		var panel := PanelContainer.new()
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_theme_constant_override("separation", 2)

		var name_label := _lbl()
		name_label.text = worker.worker_name
		name_label.add_theme_font_size_override("font_size", 23)
		info_vbox.add_child(name_label)

		var details := _lbl()
		var status_text: String
		var status_color: Color
		match worker.leave_status:
			1:
				status_text = "On Leave (home: %s)" % worker.home_colony
				status_color = Color(0.5, 0.5, 0.8)
			2:
				status_text = "Waiting for Ride (%s)" % worker.home_colony
				status_color = Color(0.7, 0.7, 0.3)
			3:
				status_text = "TARDY"
				status_color = Color(0.9, 0.3, 0.3)
			_:
				if worker.is_available:
					status_text = "Available"
					status_color = Color(0.3, 0.8, 0.3)
				elif worker.assigned_mission:
					var dest_name := ""
					if worker.assigned_mission.asteroid:
						dest_name = worker.assigned_mission.asteroid.asteroid_name
					else:
						dest_name = "remote location"
					status_text = "On mission to %s" % dest_name
					status_color = Color(0.8, 0.7, 0.2)
				else:
					status_text = "On Mission"
					status_color = Color(0.8, 0.7, 0.2)
		details.text = "%s  |  $%d/pay  |  Loyalty: %d  |  Home: %s  |  %s" % [
			worker.get_specialties_text(), worker.wage, int(worker.loyalty), worker.home_colony, status_text
		]
		details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		details.add_theme_color_override("font_color", status_color)
		info_vbox.add_child(details)

		# Personality trait
		var personality_label := _lbl()
		personality_label.text = "%s — %s" % [worker.get_personality_name(), worker.get_personality_description()]
		personality_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		personality_label.add_theme_color_override("font_color", Color(0.75, 0.65, 0.9))
		personality_label.add_theme_font_size_override("font_size", 17)
		info_vbox.add_child(personality_label)

		# XP Progress Bars
		var xp_container := HBoxContainer.new()
		xp_container.add_theme_constant_override("separation", 12)

		# Pilot XP bar
		if worker.pilot_skill >= 0.1 or worker.pilot_xp > 0.0:
			var pilot_vbox := VBoxContainer.new()
			pilot_vbox.add_theme_constant_override("separation", 2)
			var pilot_label := _lbl()
			pilot_label.text = "Pilot %.2f" % worker.pilot_skill
			pilot_label.add_theme_color_override("font_color", Color(0.4, 0.7, 1.0))
			pilot_vbox.add_child(pilot_label)
			var pilot_bar := ProgressBar.new()
			pilot_bar.custom_minimum_size = Vector2(80, 16)
			pilot_bar.value = worker.get_xp_progress(0) * 100.0
			pilot_bar.show_percentage = false
			pilot_vbox.add_child(pilot_bar)
			xp_container.add_child(pilot_vbox)

		# Engineer XP bar
		if worker.engineer_skill >= 0.1 or worker.engineer_xp > 0.0:
			var eng_vbox := VBoxContainer.new()
			eng_vbox.add_theme_constant_override("separation", 2)
			var eng_label := _lbl()
			eng_label.text = "Eng %.2f" % worker.engineer_skill
			eng_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
			eng_vbox.add_child(eng_label)
			var eng_bar := ProgressBar.new()
			eng_bar.custom_minimum_size = Vector2(80, 16)
			eng_bar.value = worker.get_xp_progress(1) * 100.0
			eng_bar.show_percentage = false
			eng_vbox.add_child(eng_bar)
			xp_container.add_child(eng_vbox)

		# Mining XP bar
		if worker.mining_skill >= 0.1 or worker.mining_xp > 0.0:
			var mine_vbox := VBoxContainer.new()
			mine_vbox.add_theme_constant_override("separation", 2)
			var mine_label := _lbl()
			mine_label.text = "Mining %.2f" % worker.mining_skill
			mine_label.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4))
			mine_vbox.add_child(mine_label)
			var mine_bar := ProgressBar.new()
			mine_bar.custom_minimum_size = Vector2(80, 16)
			mine_bar.value = worker.get_xp_progress(2) * 100.0
			mine_bar.show_percentage = false
			mine_vbox.add_child(mine_bar)
			xp_container.add_child(mine_vbox)

		if xp_container.get_child_count() > 0:
			info_vbox.add_child(xp_container)

		hbox.add_child(info_vbox)

		if worker.is_available:
			var fire_btn := Button.new()
			fire_btn.text = "Fire"
			fire_btn.custom_minimum_size = Vector2(0, 44)
			fire_btn.pressed.connect(func() -> void: GameState.fire_worker(worker))
			hbox.add_child(fire_btn)

		panel.add_child(hbox)
		workers_list.add_child(panel)

	# Add spacing between location sections
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	workers_list.add_child(spacer)

func _generate_candidates() -> void:
	_candidates.clear()

	# Check if we're in SERVER mode
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		# SERVER mode: fetch candidates from server
		_fetch_server_candidates()
	else:
		# LOCAL mode: generate candidates locally
		for i in range(3):
			_candidates.append(Worker.generate_random())
		_refresh_candidates()

func _fetch_server_candidates() -> void:
	var log_file := FileAccess.open("res://candidate_fetch.log", FileAccess.WRITE)

	var server_backend = BackendManager._active_backend
	if not server_backend:
		if log_file:
			log_file.store_line("ERROR: No server backend available")
			log_file.close()
		push_error("No server backend available")
		_refresh_candidates()
		return

	if log_file:
		log_file.store_line("Fetching available workers from server...")
		log_file.close()

	var available_workers = await server_backend.get_available_workers()

	log_file = FileAccess.open("res://candidate_fetch.log", FileAccess.READ_WRITE)
	if log_file:
		log_file.seek_end()
		log_file.store_line("Received %d workers from server" % available_workers.size())
		log_file.store_line("Workers data: %s" % str(available_workers))
		log_file.close()

	# Convert server worker data to Worker objects
	for worker_data in available_workers:
		var w := Worker.new()
		w.server_id = worker_data.get("id", 0)
		w.worker_name = worker_data.get("first_name", "") + " " + worker_data.get("last_name", "")
		w.pilot_skill = float(worker_data.get("pilot_skill", 0.5))
		w.engineer_skill = float(worker_data.get("engineer_skill", 0.5))
		w.mining_skill = float(worker_data.get("mining_skill", 0.5))
		w.wage = int(worker_data.get("wage", 100))
		w.personality = int(worker_data.get("personality", 2))

		# Map location_colony_id to colony name
		var colony_id: int = worker_data.get("location_colony_id", 1)
		w.home_colony = ColonyData.get_colony_name(colony_id)

		_candidates.append(w)

	log_file = FileAccess.open("res://candidate_fetch.log", FileAccess.READ_WRITE)
	if log_file:
		log_file.seek_end()
		log_file.store_line("Created %d candidate Worker objects" % _candidates.size())
		log_file.close()

	_refresh_candidates()

func _refresh_candidates() -> void:
	_free_children(candidates_list)

	# Get locations where player has docked ships
	var docked_locations: Array[String] = []
	for ship: Ship in GameState.ships:
		if ship.is_docked:
			var location: String = "Earth"
			if ship.station_colony:
				location = ship.station_colony.colony_name
			if location not in docked_locations:
				docked_locations.append(location)

	docked_locations.sort()

	# Group candidates by location
	var candidates_by_location: Dictionary = {}  # location_name -> Array[Worker]
	for candidate in _candidates:
		# Skip candidates that were already hired
		if candidate in GameState.workers:
			continue

		var location: String = candidate.home_colony if candidate.home_colony != "" else "Earth"

		# Only show candidates at locations where player has docked ships
		if location not in docked_locations:
			continue

		if not candidates_by_location.has(location):
			candidates_by_location[location] = []
		candidates_by_location[location].append(candidate)

	# Display candidates grouped by location
	var total_shown := 0
	for location in docked_locations:
		var candidates_here: Array = candidates_by_location.get(location, [])
		if candidates_here.is_empty():
			continue

		# Location header
		var header := Label.new()
		header.text = "━━━ Available at %s (%d) ━━━" % [location, candidates_here.size()]
		header.add_theme_font_size_override("font_size", 14)
		header.add_theme_color_override("font_color", Color(0.6, 0.9, 0.6))
		candidates_list.add_child(header)

		# Show candidates at this location
		for candidate in candidates_here:
			var panel := PanelContainer.new()
			var hbox := HBoxContainer.new()
			hbox.add_theme_constant_override("separation", 8)

			var info := _lbl()
			info.text = "%s  |  %s  |  $%d/pay  |  %s" % [
				candidate.worker_name, candidate.get_specialties_text(), candidate.wage, candidate.get_personality_name()
			]
			info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hbox.add_child(info)

			var btn := Button.new()
			btn.text = "Hire"
			btn.custom_minimum_size = Vector2(0, 44)
			btn.pressed.connect(_hire_candidate.bind(candidate))
			hbox.add_child(btn)

			panel.add_child(hbox)
			candidates_list.add_child(panel)
			total_shown += 1

		# Add spacing between locations
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(0, 12)
		candidates_list.add_child(spacer)

	if total_shown == 0:
		var label := _lbl()
		if docked_locations.is_empty():
			label.text = "No ships docked. Dock at a colony to hire workers there."
		else:
			label.text = "No candidates available at docked locations. Click 'New Candidates' to refresh."
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		candidates_list.add_child(label)

func _hire_candidate(worker: Worker) -> void:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		if worker.server_id <= 0:
			push_error("Cannot hire worker in SERVER mode: worker has no server_id")
			return

		# Optimistic update: show in crew immediately
		_candidates.erase(worker)
		GameState.workers.append(worker)
		GameState._invalidate_worker_cache()
		_refresh_all()

		# Confirm with server — revert if rejected
		var result = await BackendManager.hire_worker(worker.server_id)
		if result == null:
			GameState.workers.erase(worker)
			GameState._invalidate_worker_cache()
			_candidates.append(worker)
			_refresh_all()
	else:
		GameState.hire_worker(worker)
