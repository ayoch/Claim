extends Node

## Leak Detector — press F11 to toggle overlay.
## Shows node/object counts and child counts of every major container.
## Tracks deltas to pinpoint which container is growing.

var enabled: bool = false
var _canvas_layer: CanvasLayer = null
var overlay_label: Label = null
var _timer: float = 0.0
const UPDATE_INTERVAL: float = 1.0  # Update every second

# Snapshot for delta tracking
var _prev_nodes: int = 0
var _prev_objects: int = 0
var _prev_orphans: int = 0
var _prev_children: Dictionary = {}  # path_string -> count

# Containers to monitor — filled on first scan
var _monitored: Array[Dictionary] = []  # [{node, path}]
var _scanned: bool = false

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_overlay()

func _create_overlay() -> void:
	_canvas_layer = CanvasLayer.new()
	_canvas_layer.layer = 128  # Above everything
	add_child(_canvas_layer)

	overlay_label = Label.new()
	overlay_label.name = "LeakDetectorOverlay"
	overlay_label.anchor_left = 0.0
	overlay_label.anchor_top = 0.0
	overlay_label.anchor_right = 1.0
	overlay_label.offset_left = 4.0
	overlay_label.offset_top = 4.0
	overlay_label.add_theme_font_size_override("font_size", 16)
	overlay_label.add_theme_color_override("font_color", Color.WHITE)
	overlay_label.visible = false
	overlay_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Dark background for readability
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.85)
	bg.content_margin_left = 4
	bg.content_margin_right = 4
	bg.content_margin_top = 4
	bg.content_margin_bottom = 4
	overlay_label.add_theme_stylebox_override("normal", bg)
	_canvas_layer.add_child(overlay_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_6:
		enabled = !enabled
		overlay_label.visible = enabled
		if enabled:
			_scanned = false  # Re-scan containers
			print("LEAK DETECTOR: ON")
		else:
			print("LEAK DETECTOR: OFF")
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not enabled:
		return
	_timer += delta
	if _timer < UPDATE_INTERVAL:
		return
	_timer = 0.0

	if not _scanned:
		_scan_containers()
		_scanned = true

	_update_overlay()

func _scan_containers() -> void:
	_monitored.clear()
	var root := get_tree().root
	_walk(root, 0)

func _walk(node: Node, depth: int) -> void:
	if depth > 15:
		return
	# Skip our own overlay
	if node == _canvas_layer or node == overlay_label:
		return

	var lower_name := node.name.to_lower()

	var is_interesting := (
		"list" in lower_name
		or "markers" in lower_name
		or "selector" in lower_name
		or "content" in lower_name
		or "ships" in lower_name
		or "workers" in lower_name
		or "candidates" in lower_name
		or "contracts" in lower_name
		or "missions" in lower_name
		or "discipline" in lower_name
		or "colony" in lower_name
		or "sell" in lower_name
		or "equip" in lower_name
	)

	if is_interesting:
		_monitored.append({"node": node, "path": str(node.get_path())})

	for child in node.get_children():
		_walk(child, depth + 1)

func _update_overlay() -> void:
	var nodes := Performance.get_monitor(Performance.OBJECT_NODE_COUNT)
	var objects := Performance.get_monitor(Performance.OBJECT_COUNT)
	var orphans := Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)

	var d_nodes := int(nodes) - _prev_nodes
	var d_objects := int(objects) - _prev_objects
	var d_orphans := int(orphans) - _prev_orphans

	var lines: Array[String] = []
	lines.append("=== LEAK DETECTOR (1s intervals) ===")
	lines.append("Nodes: %d (%+d) | Objects: %d (%+d) | Orphans: %d (%+d)" % [
		int(nodes), d_nodes, int(objects), d_objects, int(orphans), d_orphans
	])
	lines.append("")

	# --- GameState array sizes (key leak sources) ---
	if is_instance_valid(GameState):
		var gs := GameState
		if gs:
			var gs_lines: Array[String] = []
			gs_lines.append("GameState arrays:")
			gs_lines.append("  workers=%d  ships=%d  missions=%d  trade_missions=%d" % [
				gs.workers.size(), gs.ships.size(), gs.missions.size(), gs.trade_missions.size()
			])
			gs_lines.append("  hitchhike_pool=%d  tardy_workers=%d  security_zones=%d" % [
				gs.hitchhike_pool.size(), gs.tardy_workers.size(), gs.security_zones.size()
			])
			gs_lines.append("  financial_history=%d  available_contracts=%d  active_contracts=%d" % [
				gs.financial_history.size(), gs.available_contracts.size(), gs.active_contracts.size()
			])
			gs_lines.append("  active_market_events=%d  equipment_inventory=%d  fabrication_queue=%d" % [
				gs.active_market_events.size(), gs.equipment_inventory.size(), gs.fabrication_queue.size()
			])
			gs_lines.append("  mining_unit_inventory=%d  deployed_mining_units=%d" % [
				gs.mining_unit_inventory.size(), gs.deployed_mining_units.size()
			])
			for l in gs_lines:
				lines.append(l)
			lines.append("")

	var entries: Array[Dictionary] = []
	for m in _monitored:
		var node: Node = m["node"]
		if not is_instance_valid(node):
			continue
		var path: String = m["path"]
		var count := _count_descendants(node)
		var prev: int = _prev_children.get(path, 0)
		var delta_c := count - prev
		_prev_children[path] = count
		entries.append({"path": path, "count": count, "delta": delta_c})

	# Sort: growing containers first, then by size
	entries.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if a["delta"] != b["delta"]:
			return a["delta"] > b["delta"]
		return a["count"] > b["count"]
	)

	var shown := 0
	for e in entries:
		if shown >= 25:
			break
		var short_path: String = e["path"]
		if short_path.length() > 55:
			short_path = "..." + short_path.right(52)
		if e["delta"] != 0:
			lines.append("%4d (%+4d)  %s" % [e["count"], e["delta"], short_path])
			shown += 1

	_prev_nodes = int(nodes)
	_prev_objects = int(objects)
	_prev_orphans = int(orphans)

	overlay_label.text = "\n".join(lines)

	# Log to file for analysis
	var log_path := "res://leak_log.txt"
	var f := FileAccess.open(log_path, FileAccess.READ_WRITE if FileAccess.file_exists(log_path) else FileAccess.WRITE)
	if f:
		f.seek_end()
		f.store_line("--- %.1fs ---" % (Time.get_ticks_msec() / 1000.0))
		for line in lines:
			f.store_line(line)
		f.store_line("")

func _count_descendants(node: Node) -> int:
	var count := node.get_child_count()
	for child in node.get_children():
		count += _count_descendants(child)
	return count
