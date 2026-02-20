extends MarginContainer

@onready var workers_list: VBoxContainer = %WorkersList
@onready var candidates_list: VBoxContainer = %CandidatesList
@onready var crew_count: Label = %CrewCount
@onready var refresh_btn: Button = %RefreshBtn

static func _free_children(container: Node) -> void:
	for i in range(container.get_child_count() - 1, -1, -1):
		container.get_child(i).free()

var _candidates: Array[Worker] = []
var _dirty_crew: bool = false
var _dirty_all: bool = false
var _last_refresh_msec: int = 0
const REFRESH_INTERVAL_MSEC: int = 200

func _ready() -> void:
	refresh_btn.pressed.connect(_generate_candidates)
	EventBus.worker_hired.connect(func(_w: Worker) -> void: _dirty_all = true)
	EventBus.worker_fired.connect(func(_w: Worker) -> void: _dirty_all = true)
	EventBus.mission_started.connect(func(_m: Mission) -> void: _dirty_crew = true)
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _dirty_crew = true)
	EventBus.tick.connect(_on_tick)
	_generate_candidates()
	_refresh_crew()

func _on_tick(_dt: float) -> void:
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
		var label := Label.new()
		label.text = "No crew hired yet"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		workers_list.add_child(label)
		return

	for worker: Worker in GameState.workers:
		var panel := PanelContainer.new()
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var info_vbox := VBoxContainer.new()
		info_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info_vbox.add_theme_constant_override("separation", 2)

		var name_label := Label.new()
		name_label.text = worker.worker_name
		name_label.add_theme_font_size_override("font_size", 18)
		info_vbox.add_child(name_label)

		var details := Label.new()
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

		hbox.add_child(info_vbox)

		if worker.is_available:
			var fire_btn := Button.new()
			fire_btn.text = "Fire"
			fire_btn.custom_minimum_size = Vector2(0, 44)
			fire_btn.pressed.connect(func() -> void: GameState.fire_worker(worker))
			hbox.add_child(fire_btn)

		panel.add_child(hbox)
		workers_list.add_child(panel)

func _generate_candidates() -> void:
	_candidates.clear()
	for i in range(3):
		_candidates.append(Worker.generate_random())
	_refresh_candidates()

func _refresh_candidates() -> void:
	_free_children(candidates_list)

	for candidate in _candidates:
		# Skip candidates that were already hired
		if candidate in GameState.workers:
			continue

		var panel := PanelContainer.new()
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 8)

		var info := Label.new()
		info.text = "%s  |  %s  |  $%d/pay" % [
			candidate.worker_name, candidate.get_specialties_text(), candidate.wage
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

	if candidates_list.get_child_count() == 0:
		var label := Label.new()
		label.text = "All candidates hired. Press New Candidates for more."
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		candidates_list.add_child(label)

func _hire_candidate(worker: Worker) -> void:
	GameState.hire_worker(worker)
