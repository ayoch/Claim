extends Node

## Test script for partnership system
## Run this from the Godot editor to validate partnership functionality

func _ready() -> void:
	print("=== Partnership System Test ===")

	# Wait for game to initialize
	await get_tree().create_timer(0.5).timeout

	if GameState.ships.size() < 2:
		print("ERROR: Need at least 2 ships to test partnerships")
		return

	var ship1 := GameState.ships[0]
	var ship2 := GameState.ships[1]

	print("\n1. Testing partnership creation...")
	print("  Ship 1: %s at %s" % [ship1.ship_name, ship1.position_au])
	print("  Ship 2: %s at %s" % [ship2.ship_name, ship2.position_au])

	# Move ships close together
	ship2.position_au = ship1.position_au
	ship2.docked_at_earth = true
	ship1.docked_at_earth = true

	var check := ship1.can_partner_with(ship2)
	print("  Can partner: %s" % check["valid"])
	if not check["valid"]:
		print("  Reason: %s" % check["reason"])
		return

	var success := GameState.create_partnership(ship1, ship2)
	print("  Partnership created: %s" % success)

	if not ship1.is_partnered():
		print("ERROR: ship1 not partnered after creation")
		return

	print("  ✓ Ship 1 partnered with: %s (leader: %s)" % [ship1.partner_ship_name, ship1.is_partnership_leader])
	print("  ✓ Ship 2 partnered with: %s (leader: %s)" % [ship2.partner_ship_name, ship2.is_partnership_leader])

	print("\n2. Testing partnership roles...")
	print("  Ship 1 role: %s" % ship1.get_partnership_role())
	print("  Ship 2 role: %s" % ship2.get_partnership_role())

	if not ship1.is_partnership_leader:
		print("ERROR: Ship 1 should be leader")
		return
	if ship2.is_partnership_leader:
		print("ERROR: Ship 2 should be follower")
		return

	print("  ✓ Roles assigned correctly")

	print("\n3. Testing mission dispatch...")
	if GameState.asteroids.is_empty():
		print("ERROR: No asteroids to dispatch to")
		return

	var target := GameState.asteroids[0]
	print("  Dispatching to: %s" % target.asteroid_name)

	# Add crew to ship1
	if ship1.crew.size() < ship1.min_crew:
		for i in range(ship1.min_crew):
			var w := Worker.new()
			w.worker_name = "Test Crew %d" % i
			w.mining_skill = 0.5
			w.pilot_skill = 0.5
			w.engineer_skill = 0.5
			GameState.workers.append(w)
			GameState.assign_worker_to_ship(w, ship1)

	var mission := GameState.start_mission(ship1, target)
	if mission == null:
		print("ERROR: Failed to start mission")
		return

	print("  ✓ Leader mission created: %s" % mission.status)

	if ship2.current_mission == null:
		print("ERROR: Follower should have shadow mission")
		return

	print("  ✓ Follower shadow mission created: %s" % ship2.current_mission.status)
	print("  ✓ Shadow mission flag: %s" % ship2.current_mission.is_partnership_shadow)

	print("\n4. Testing save/load...")
	GameState.save_game("partnership_test")

	# Clear partnership references
	var saved_name1 := ship1.partner_ship_name
	var saved_name2 := ship2.partner_ship_name
	ship1.partner_ship = null
	ship2.partner_ship = null

	if GameState.load_game("partnership_test.json"):
		print("  ✓ Game loaded")

		# Check if partnerships restored
		var loaded_ship1 := GameState.ships[0]
		var loaded_ship2 := GameState.ships[1]

		if loaded_ship1.partner_ship == null:
			print("ERROR: Partnership not restored for ship1")
			return

		print("  ✓ Ship 1 partner restored: %s" % loaded_ship1.partner_ship_name)
		print("  ✓ Ship 2 partner restored: %s" % loaded_ship2.partner_ship_name)
		print("  ✓ Ship 1 partner reference: %s" % (loaded_ship1.partner_ship != null))
		print("  ✓ Ship 2 partner reference: %s" % (loaded_ship2.partner_ship != null))
	else:
		print("ERROR: Failed to load game")
		return

	print("\n5. Testing partnership breaking...")
	GameState.break_partnership(ship1, ship2, "Test termination")

	if ship1.is_partnered():
		print("ERROR: Ship 1 still partnered after break")
		return
	if ship2.is_partnered():
		print("ERROR: Ship 2 still partnered after break")
		return

	print("  ✓ Partnership broken successfully")
	print("  ✓ Ship 1 partner: %s" % ship1.partner_ship)
	print("  ✓ Ship 2 partner: %s" % ship2.partner_ship)

	print("\n=== ALL TESTS PASSED ===")
