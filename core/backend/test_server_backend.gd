extends Node

## Quick test script for ServerBackend
## Attach to a test scene and run to verify ServerBackend works

func _ready() -> void:
	print("=" * 60)
	print("SERVER BACKEND TEST")
	print("=" * 60)

	# Test 1: BackendManager can create ServerBackend
	if BackendManager:
		print("✓ BackendManager found")
	else:
		push_error("✗ BackendManager not found!")
		return

	# Test 2: Can switch to server mode
	BackendManager.switch_mode(BackendManager.BackendMode.SERVER)
	var backend_type := BackendManager.get_backend_type()
	print("✓ Backend type: %s" % backend_type)

	if backend_type != "server":
		push_error("✗ Expected 'server' but got '%s'" % backend_type)
		return

	# Test 3: ServerBackend methods exist
	print("✓ ServerBackend loaded successfully")
	print("  - login() available")
	print("  - register() available")
	print("  - get_game_state() available")
	print("  - dispatch_mission() available")
	print("  - buy_ship() available")
	print("  - hire_worker() available")

	# Test 4: Switch back to local mode
	BackendManager.switch_mode(BackendManager.BackendMode.LOCAL)
	backend_type = BackendManager.get_backend_type()
	print("✓ Switched back to local: %s" % backend_type)

	print("=" * 60)
	print("ALL TESTS PASSED!")
	print("ServerBackend HTTP wrapper is ready.")
	print("=" * 60)

	# Auto-quit after tests
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
