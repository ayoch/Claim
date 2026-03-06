class_name LocalBackend
extends BackendInterface

## Local single-player backend implementation
## Wraps GameState for now - logic will be migrated here gradually

# ══════════════════════════════════════════════════════════════════════════════
# AUTHENTICATION (Always succeeds for local play)
# ══════════════════════════════════════════════════════════════════════════════

func login(username: String, password: String) -> Dictionary:
	# Local mode doesn't need authentication - auto-success
	return {
		"success": true,
		"player_id": 1,  # Local player is always ID 1
		"token": "",
		"error": ""
	}


func register(username: String, password: String, email: String) -> Dictionary:
	# Local mode doesn't need registration - auto-success
	# Email parameter ignored in local mode
	return {
		"success": true,
		"player_id": 1,
		"error": ""
	}


func logout() -> void:
	# Nothing to do for local mode
	pass


# ══════════════════════════════════════════════════════════════════════════════
# GAME STATE
# ══════════════════════════════════════════════════════════════════════════════

func get_game_state() -> Dictionary:
	# Build state dictionary from GameState
	var ships_data: Array = []
	for s in GameState.ships:
		ships_data.append({
			"id": s.get_instance_id(),
			"ship_name": s.ship_name,
			"ship_class": s.ship_class,
			"cargo_capacity": s.cargo_capacity,
			"fuel": s.fuel,
			"fuel_capacity": s.fuel_capacity,
			"is_stationed": s.is_stationed,
			"is_derelict": s.is_derelict,
		})

	var workers_data: Array = []
	for w in GameState.workers:
		workers_data.append({
			"id": w.get_instance_id(),
			"first_name": w.first_name,
			"last_name": w.last_name,
			"pilot_skill": w.pilot_skill,
			"engineer_skill": w.engineer_skill,
			"mining_skill": w.mining_skill,
			"wage": w.wage,
			"loyalty": w.loyalty,
			"is_available": w.is_available,
		})

	var missions_data: Array = []
	for m in GameState.missions:
		missions_data.append({
			"id": m.get_instance_id(),
			"status": m.status,
			"mission_type": m.mission_type,
			"elapsed_time": m.elapsed_time,
		})

	return {
		"money": GameState.money,
		"ships": ships_data,
		"workers": workers_data,
		"missions": missions_data,
	}


func save_game() -> void:
	GameState.save_game()


func load_game(save_name: String) -> bool:
	# For now, just load the default save
	return GameState.load_game()


func get_save_files() -> Array:
	# List save files in user:// directory
	var saves: Array = []
	var dir := DirAccess.open("user://saves")
	if dir:
		dir.list_dir_begin()
		var file_name := dir.get_next()
		while file_name != "":
			if file_name.ends_with(".save"):
				saves.append(file_name.trim_suffix(".save"))
			file_name = dir.get_next()
		dir.list_dir_end()
	return saves


# ══════════════════════════════════════════════════════════════════════════════
# SHIPS & MISSIONS
# ══════════════════════════════════════════════════════════════════════════════

func dispatch_mission(ship_id: int, asteroid_id: int, mission_type: int, mining_duration: float, return_to_station: bool):
	# Find ship by instance ID
	var ship: Ship = null
	for s in GameState.ships:
		if s.get_instance_id() == ship_id:
			ship = s
			break

	if not ship:
		push_warning("Ship not found: %d" % ship_id)
		return null

	# Find asteroid by ID (using array index for now)
	if asteroid_id < 0 or asteroid_id >= GameState.asteroids.size():
		push_warning("Asteroid not found: %d" % asteroid_id)
		return null

	var asteroid := GameState.asteroids[asteroid_id]

	# Dispatch mission using MissionManager
	var mission := MissionManager.start_mission(ship, asteroid)
	return mission


func buy_ship(ship_class: int, ship_name: String, colony_id: int):
	var ship := GameState.purchase_ship(ship_class)
	if ship:
		ship.ship_name = ship_name
	return ship


func sell_ship(ship_id: int) -> void:
	# Find and remove ship
	for i in range(GameState.ships.size()):
		if GameState.ships[i].get_instance_id() == ship_id:
			GameState.ships.remove_at(i)
			EventBus.ship_sold.emit(ship_id)
			break


# ══════════════════════════════════════════════════════════════════════════════
# WORKERS
# ══════════════════════════════════════════════════════════════════════════════

func hire_worker(colony_id: int):
	# Generate random worker
	var worker := Worker.new()
	worker.first_name = ["Alex", "Sam", "Jordan", "Casey", "Morgan"].pick_random()
	worker.last_name = ["Chen", "Okafor", "Petrov", "Nakamura", "Singh"].pick_random()
	worker.pilot_skill = randf_range(0.0, 1.5)
	worker.engineer_skill = randf_range(0.0, 1.5)
	worker.mining_skill = randf_range(0.0, 1.5)
	worker.wage = int(80 + (worker.pilot_skill + worker.engineer_skill + worker.mining_skill) * 40)
	worker.loyalty = randf_range(45.0, 65.0)
	worker.is_available = true

	WorkerManager.hire_worker(worker)
	return worker


func fire_worker(worker_id: int) -> void:
	for worker in GameState.workers:
		if worker.get_instance_id() == worker_id:
			WorkerManager.fire_worker(worker)
			break


func assign_worker(worker_id: int, ship_id: int) -> void:
	var worker: Worker = null
	var ship: Ship = null

	for w in GameState.workers:
		if w.get_instance_id() == worker_id:
			worker = w
			break

	for s in GameState.ships:
		if s.get_instance_id() == ship_id:
			ship = s
			break

	if worker and ship:
		WorkerManager.assign_worker_to_ship(worker, ship)


func unassign_worker(worker_id: int) -> void:
	var worker: Worker = null
	for w in GameState.workers:
		if w.get_instance_id() == worker_id:
			worker = w
			break

	if worker and worker.assigned_ship:
		WorkerManager.remove_worker_from_ship(worker, worker.assigned_ship)


# ══════════════════════════════════════════════════════════════════════════════
# WORLD DATA
# ══════════════════════════════════════════════════════════════════════════════

func get_colonies() -> Array:
	# Return colony data from GameState
	var colonies_data: Array = []
	for colony in GameState.colonies:
		colonies_data.append({
			"id": colony.get_instance_id(),
			"colony_name": colony.colony_name,
			"planet_id": colony.planet_id,
			"population": colony.population,
		})
	return colonies_data


func get_asteroids() -> Array:
	# Return asteroid data
	var asteroids: Array = []
	for i in range(GameState.asteroids.size()):
		var ast := GameState.asteroids[i]
		asteroids.append({
			"id": i,
			"asteroid_name": ast.name,
			"body_type": ast.body_type,
			"semi_major_axis": ast.semi_major_axis,
			"eccentricity": ast.eccentricity,
			"ore_yields": ast.ore_yields,
		})
	return asteroids


func get_market_prices() -> Dictionary:
	if GameState.market:
		return GameState.market.current_prices.duplicate()
	return {}


# ══════════════════════════════════════════════════════════════════════════════
# POLICIES
# ══════════════════════════════════════════════════════════════════════════════

func update_policies(policies: Dictionary) -> void:
	if policies.has("thrust_policy"):
		GameState.thrust_policy = policies["thrust_policy"]
	if policies.has("supply_policy"):
		GameState.supply_policy = policies["supply_policy"]
	if policies.has("collection_policy"):
		GameState.collection_policy = policies["collection_policy"]
	if policies.has("encounter_policy"):
		GameState.encounter_policy = policies["encounter_policy"]
	if policies.has("repair_policy"):
		GameState.repair_policy = policies["repair_policy"]


# ══════════════════════════════════════════════════════════════════════════════
# REAL-TIME EVENTS
# ══════════════════════════════════════════════════════════════════════════════

func subscribe_events(callback: Callable) -> void:
	# Local mode uses EventBus signals directly - no subscription needed
	# In the future, we could connect EventBus signals to the callback
	pass


func unsubscribe_events() -> void:
	# Nothing to unsubscribe in local mode
	pass


# ══════════════════════════════════════════════════════════════════════════════
# UTILITY
# ══════════════════════════════════════════════════════════════════════════════

func is_backend_ready() -> bool:
	return true  # Local is always "connected"


func get_backend_type() -> String:
	return "local"


# ══════════════════════════════════════════════════════════════════════════════
# BUG REPORTS
# ══════════════════════════════════════════════════════════════════════════════

func submit_bug_report(title: String, description: String, category: String, game_version: String) -> Dictionary:
	"""Save bug report to local JSON file for offline review"""
	var reports_file := "user://bug_reports.json"
	var reports := []

	# Load existing reports
	if FileAccess.file_exists(reports_file):
		var file := FileAccess.open(reports_file, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK:
				reports = json.data if json.data is Array else []
			file.close()

	# Add new report
	reports.append({
		"title": title,
		"description": description,
		"category": category,
		"game_version": game_version,
		"backend_mode": "local",
		"reporter_username": "LocalPlayer",
		"timestamp": Time.get_datetime_string_from_system()
	})

	# Save to file
	var file := FileAccess.open(reports_file, FileAccess.WRITE)
	if not file:
		return {"success": false, "error": "Failed to open bug reports file"}

	file.store_string(JSON.stringify(reports, "\t"))
	file.close()

	return {"success": true, "error": ""}
