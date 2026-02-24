extends Node

## Quick test script for backend abstraction layer
## Attach to a test scene and run to verify Phase 1 works

func _ready() -> void:
	print("============================================================")
	print("BACKEND ABSTRACTION LAYER TEST")
	print("============================================================")

	# Test 1: BackendManager exists
	if BackendManager:
		print("✓ BackendManager autoload found")
	else:
		push_error("✗ BackendManager not found!")
		return

	# Test 2: Check backend type
	var backend_type := BackendManager.get_backend_type()
	print("✓ Backend type: %s" % backend_type)

	if backend_type != "local":
		push_error("✗ Expected 'local' but got '%s'" % backend_type)
		return

	# Test 3: Check connection
	if BackendManager.is_backend_ready():
		print("✓ Backend is ready")
	else:
		push_error("✗ Backend not ready!")
		return

	# Test 4: Test game state access
	var state := BackendManager.get_game_state()
	print("✓ Got game state: %d ships, %d workers" % [state["ships"].size(), state["workers"].size()])

	# Test 5: Test colonies access
	var colonies := BackendManager.get_colonies()
	print("✓ Got %d colonies" % colonies.size())

	# Test 6: Test asteroids access
	var asteroids := BackendManager.get_asteroids()
	print("✓ Got %d asteroids" % asteroids.size())

	# Test 7: Test market prices
	var prices := BackendManager.get_market_prices()
	print("✓ Got market prices: %d ore types" % prices.size())

	print("============================================================")
	print("ALL TESTS PASSED!")
	print("Phase 1 backend abstraction is working correctly.")
	print("============================================================")

	# Auto-quit after tests (remove this to keep running)
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
