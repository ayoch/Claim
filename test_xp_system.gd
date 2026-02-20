extends Node

## Quick test script for worker skill progression
## Attach to a Node in the scene tree and run to verify XP system works

func _ready() -> void:
	print("=== Testing Worker Skill Progression ===")

	# Test 1: Create worker and verify initial state
	var worker := Worker.new()
	worker.worker_name = "Test Worker"
	worker.pilot_skill = 0.5
	worker.engineer_skill = 0.3
	worker.mining_skill = 0.8
	worker.wage = int(80 + (0.5 + 0.3 + 0.8) * 40)

	print("\n1. Initial state:")
	print("  Pilot: %.2f, XP: %.0f" % [worker.pilot_skill, worker.pilot_xp])
	print("  Engineer: %.2f, XP: %.0f" % [worker.engineer_skill, worker.engineer_xp])
	print("  Mining: %.2f, XP: %.0f" % [worker.mining_skill, worker.mining_xp])
	print("  Wage: $%d" % worker.wage)

	# Test 2: Calculate XP needed
	var pilot_xp_needed := worker.get_xp_for_next_level(0)
	var eng_xp_needed := worker.get_xp_for_next_level(1)
	var mining_xp_needed := worker.get_xp_for_next_level(2)

	print("\n2. XP needed for next level:")
	print("  Pilot: %.0f (%.1f game-days)" % [pilot_xp_needed, pilot_xp_needed / 86400.0])
	print("  Engineer: %.0f (%.1f game-days)" % [eng_xp_needed, eng_xp_needed / 86400.0])
	print("  Mining: %.0f (%.1f game-days)" % [mining_xp_needed, mining_xp_needed / 86400.0])

	# Test 3: Add XP and check progress
	worker.add_xp(2, 43200.0)  # Half day of mining XP

	print("\n3. After adding 0.5 game-days of mining XP:")
	print("  Mining: %.2f, XP: %.0f, Progress: %.1f%%" % [
		worker.mining_skill,
		worker.mining_xp,
		worker.get_xp_progress(2) * 100.0
	])

	# Test 4: Level up
	var initial_wage := worker.wage
	worker.add_xp(2, mining_xp_needed)  # Add enough to level up

	print("\n4. After leveling up:")
	print("  Mining: %.2f, XP: %.0f" % [worker.mining_skill, worker.mining_xp])
	print("  Wage: $%d (was $%d, +$%d)" % [worker.wage, initial_wage, worker.wage - initial_wage])

	# Test 5: Max skill cap
	var test_worker := Worker.new()
	test_worker.mining_skill = 2.0  # At cap
	test_worker.add_xp(2, 100000.0)  # Try to add lots of XP

	print("\n5. Skill cap test:")
	print("  Mining at cap (2.0): %.2f" % test_worker.mining_skill)
	print("  XP needed: %.0f (should be 0)" % test_worker.get_xp_for_next_level(2))

	# Test 6: Multiple level-ups
	var rapid_worker := Worker.new()
	rapid_worker.pilot_skill = 0.0
	rapid_worker.pilot_xp = 0.0
	rapid_worker.add_xp(0, 500000.0)  # ~5.8 game-days worth

	print("\n6. Multiple level-ups from 0.0 skill:")
	print("  Added 500k XP (~5.8 days)")
	print("  Final pilot skill: %.2f" % rapid_worker.pilot_skill)
	print("  Remaining XP: %.0f" % rapid_worker.pilot_xp)

	print("\n=== All tests complete! ===")
