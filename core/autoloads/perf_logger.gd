extends Node

# Performance baseline logger
# Press 9 to dump current stats to res://perf_baseline.txt

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_9:
		log_baseline()

func log_baseline() -> void:
	var log := FileAccess.open("res://perf_baseline.txt", FileAccess.WRITE)
	if not log:
		print("Failed to open perf_baseline.txt")
		return

	log.store_line("=== PERFORMANCE BASELINE ===")
	log.store_line("Timestamp: %s" % Time.get_datetime_string_from_system())
	log.store_line("Game time: %.1f days" % (GameState.total_ticks / 86400.0))
	log.store_line("")

	# === Game Objects ===
	log.store_line("--- Game Objects ---")
	log.store_line("Ships: %d" % GameState.ships.size())
	log.store_line("Workers: %d" % GameState.workers.size())
	log.store_line("Missions: %d" % GameState.missions.size())
	log.store_line("Trade Missions: %d" % GameState.trade_missions.size())
	log.store_line("Deployed Mining Units: %d" % GameState.deployed_mining_units.size())
	log.store_line("Asteroids: %d" % GameState.asteroids.size())
	log.store_line("Colonies: %d" % GameState.colonies.size())
	log.store_line("Contracts (available): %d" % GameState.available_contracts.size())
	log.store_line("Contracts (active): %d" % GameState.active_contracts.size())
	log.store_line("Market Events: %d" % GameState.active_market_events.size())
	log.store_line("")

	# === Rival Corps ===
	var total_rival_ships := 0
	for corp in GameState.rival_corps:
		total_rival_ships += corp.ships.size()
	log.store_line("Rival Corps: %d" % GameState.rival_corps.size())
	log.store_line("Rival Ships: %d" % total_rival_ships)
	log.store_line("")

	# === Ships Breakdown ===
	var ships_on_mission := 0
	var ships_on_trade := 0
	var ships_idle := 0
	var ships_derelict := 0
	var total_crew := 0
	for ship in GameState.ships:
		if ship.is_derelict:
			ships_derelict += 1
		elif ship.current_mission:
			ships_on_mission += 1
		elif ship.current_trade_mission:
			ships_on_trade += 1
		else:
			ships_idle += 1
		total_crew += ship.crew.size()

	log.store_line("--- Ships Detail ---")
	log.store_line("On mining mission: %d" % ships_on_mission)
	log.store_line("On trade mission: %d" % ships_on_trade)
	log.store_line("Idle: %d" % ships_idle)
	log.store_line("Derelict: %d" % ships_derelict)
	log.store_line("Total crew assigned: %d" % total_crew)
	log.store_line("")

	# === Scene Tree ===
	var root := get_tree().root
	var node_count := _count_nodes(root)
	log.store_line("--- Scene Tree ---")
	log.store_line("Total nodes: %d" % node_count)
	log.store_line("")

	# === Performance Metrics ===
	log.store_line("--- Performance ---")
	log.store_line("FPS: %d" % Engine.get_frames_per_second())
	log.store_line("Process time: %.2f ms" % (Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0))
	log.store_line("Physics time: %.2f ms" % (Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0))
	log.store_line("Current speed: %.0fx" % TimeScale.speed_multiplier)
	log.store_line("")

	# === Memory ===
	log.store_line("--- Memory ---")
	log.store_line("Static: %.2f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC) / 1024.0 / 1024.0))
	log.store_line("Dynamic: %.2f MB" % (Performance.get_monitor(Performance.MEMORY_STATIC_MAX) / 1024.0 / 1024.0))
	log.store_line("Objects: %d" % Performance.get_monitor(Performance.OBJECT_COUNT))
	log.store_line("Resources: %d" % Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))
	log.store_line("Nodes: %d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	log.store_line("")

	log.close()
	print("Performance baseline written to res://perf_baseline.txt")

func _count_nodes(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += _count_nodes(child)
	return count
