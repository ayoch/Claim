extends Node

## Test harness for Worker Skill Progression system
## Automatically creates test scenario if new game
## Logs to res://xp_test_log.txt

var log_file: FileAccess
var test_workers: Array[Worker] = []
var initial_skills: Dictionary = {}  # worker_name -> {pilot, engineer, mining}
var initial_wages: Dictionary = {}  # worker_name -> wage
var level_up_count: int = 0
var test_start_ticks: float = 0.0
var test_duration_ticks: float = 432000.0  # 5 game-days (shorter test)

func _ready() -> void:
	# Open log file
	log_file = FileAccess.open("res://xp_test_log.txt", FileAccess.WRITE)
	if not log_file:
		push_error("Failed to open xp_test_log.txt")
		return

	_log("=== Worker XP System Test Started ===")
	_log("Game time: %.1f days" % (GameState.total_ticks / 86400.0))
	
	# If new game with no workers, set up a test scenario
	if GameState.workers.is_empty():
		_log("\nNew game detected - creating test scenario...")
		_setup_test_scenario()
	
	_log("Test duration: %.0f ticks (%.1f game-days)" % [test_duration_ticks, test_duration_ticks / 86400.0])

	# Connect signals
	EventBus.worker_skill_leveled.connect(_on_skill_leveled)
	EventBus.tick.connect(_on_tick)

	# Record initial state
	test_start_ticks = GameState.total_ticks
	_log("\nInitial Worker Stats:")
	for worker in GameState.workers:
		test_workers.append(worker)
		initial_skills[worker.worker_name] = {
			"pilot": worker.pilot_skill,
			"engineer": worker.engineer_skill,
			"mining": worker.mining_skill,
		}
		initial_wages[worker.worker_name] = worker.wage
		_log("  %s: P=%.2f E=%.2f M=%.2f wage=$%d" % [
			worker.worker_name,
			worker.pilot_skill,
			worker.engineer_skill,
			worker.mining_skill,
			worker.wage
		])
		_log("    XP: P=%.0f E=%.0f M=%.0f" % [worker.pilot_xp, worker.engineer_xp, worker.mining_xp])

	# Record active missions
	_log("\nActive Missions: %d" % GameState.missions.size())
	for mission in GameState.missions:
		_log("  %s -> %s (status: %d, crew: %d)" % [
			mission.ship.ship_name,
			mission.asteroid.asteroid_name if mission.asteroid else "?",
			mission.status,
			mission.ship.crew.size()
		])

	# Record deployed mining units
	_log("\nDeployed Mining Units: %d" % GameState.deployed_mining_units.size())
	for unit in GameState.deployed_mining_units:
		_log("  %s at %s (workers: %d)" % [
			unit.unit_name,
			unit.deployed_at_asteroid,
			unit.assigned_workers.size()
		])

	_log("\n--- Test Running at high speed (use keyboard shortcuts to set 200000x) ---")

func _setup_test_scenario() -> void:
	# Hire 3 workers with varied skills
	_log("  Hiring 3 test workers...")
	for i in range(3):
		var worker := Worker.generate_random()
		GameState.hire_worker(worker)
		_log("    Hired %s (P=%.2f E=%.2f M=%.2f)" % [
			worker.worker_name,
			worker.pilot_skill,
			worker.engineer_skill,
			worker.mining_skill
		])
	
	# Get starting ship
	var ship: Ship = GameState.ships[0] if not GameState.ships.is_empty() else null
	if not ship:
		_log("  ERROR: No ship available for test")
		return
	
	# Assign 2 workers to ship
	var assigned := 0
	for worker in GameState.workers:
		if assigned < 2:
			GameState.assign_worker_to_ship(worker, ship)
			assigned += 1
	
	_log("  Assigned %d workers to %s" % [assigned, ship.ship_name])
	
	# Find a close asteroid for quick test
	var closest_asteroid: AsteroidData = null
	var closest_dist := 999999.0
	for asteroid in GameState.asteroids:
		var dist := ship.position_au.distance_to(asteroid.get_position_au())
		if dist < closest_dist and dist > 0.1:  # Not too close
			closest_dist = dist
			closest_asteroid = asteroid
	
	if closest_asteroid:
		_log("  Dispatching mission to %s (%.2f AU away)" % [closest_asteroid.asteroid_name, closest_dist])
		GameState.dispatch_mission(ship, closest_asteroid, Mission.MissionType.MINING, 86400.0, true)
	else:
		_log("  WARNING: No suitable asteroid found for mission")

func _on_skill_leveled(worker: Worker, skill_type: int, new_value: float) -> void:
	level_up_count += 1
	var skill_name := ""
	match skill_type:
		0: skill_name = "Pilot"
		1: skill_name = "Engineer"
		2: skill_name = "Mining"

	var elapsed_days := (GameState.total_ticks - test_start_ticks) / 86400.0
	_log("[Day %.1f] LEVEL UP: %s's %s skill -> %.2f (wage now $%d)" % [
		elapsed_days,
		worker.worker_name,
		skill_name,
		new_value,
		worker.wage
	])

func _on_tick(dt: float) -> void:
	var elapsed := GameState.total_ticks - test_start_ticks
	if elapsed >= test_duration_ticks:
		_finish_test()

func _finish_test() -> void:
	_log("\n=== Test Complete ===")
	var elapsed_days := (GameState.total_ticks - test_start_ticks) / 86400.0
	_log("Elapsed: %.1f game-days" % elapsed_days)
	_log("Total level-ups recorded: %d" % level_up_count)

	_log("\nFinal Worker Stats:")
	for worker in test_workers:
		if worker not in GameState.workers:
			_log("  %s: FIRED/REMOVED" % worker.worker_name)
			continue

		var init_skills: Dictionary = initial_skills.get(worker.worker_name, {})
		var init_wage: int = initial_wages.get(worker.worker_name, 0)

		var pilot_gain: float = worker.pilot_skill - float(init_skills.get("pilot", 0.0))
		var eng_gain: float = worker.engineer_skill - float(init_skills.get("engineer", 0.0))
		var mine_gain: float = worker.mining_skill - float(init_skills.get("mining", 0.0))
		var wage_gain: int = worker.wage - init_wage

		_log("  %s:" % worker.worker_name)
		_log("    Pilot:    %.2f -> %.2f (+%.2f)" % [init_skills.get("pilot", 0.0), worker.pilot_skill, pilot_gain])
		_log("    Engineer: %.2f -> %.2f (+%.2f)" % [init_skills.get("engineer", 0.0), worker.engineer_skill, eng_gain])
		_log("    Mining:   %.2f -> %.2f (+%.2f)" % [init_skills.get("mining", 0.0), worker.mining_skill, mine_gain])
		_log("    Wage:     $%d -> $%d (+$%d)" % [init_wage, worker.wage, wage_gain])
		_log("    XP remaining: P=%.0f E=%.0f M=%.0f" % [worker.pilot_xp, worker.engineer_xp, worker.mining_xp])

	# Check for issues
	_log("\n=== Validation ===")
	var issues := 0

	# Check that at least some XP was gained
	var total_gains: float = 0.0
	for worker in test_workers:
		if worker not in GameState.workers:
			continue
		var init_skills: Dictionary = initial_skills.get(worker.worker_name, {})
		total_gains += (worker.pilot_skill - float(init_skills.get("pilot", 0.0)))
		total_gains += (worker.engineer_skill - float(init_skills.get("engineer", 0.0)))
		total_gains += (worker.mining_skill - float(init_skills.get("mining", 0.0)))

	if total_gains < 0.01:
		_log("WARNING: No skill gains detected! XP system may not be working.")
		issues += 1
	else:
		_log("✓ Total skill gains: %.2f" % total_gains)

	if level_up_count == 0 and elapsed_days > 1.0:
		_log("WARNING: No level-ups detected after %.1f days" % elapsed_days)
		issues += 1
	else:
		_log("✓ Level-ups detected: %d" % level_up_count)

	if issues == 0:
		_log("\n✓✓✓ All checks passed! XP system is working correctly. ✓✓✓")
	else:
		_log("\n⚠ %d issues detected. Review log for details." % issues)

	_log("\n=== End of Test ===")
	log_file.close()

	# Remove self from tree
	queue_free()

func _log(message: String) -> void:
	print(message)
	if log_file:
		log_file.store_line(message)
		log_file.flush()
