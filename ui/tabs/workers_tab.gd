extends MarginContainer

@onready var workers_list: VBoxContainer = %WorkersList
@onready var hire_button: Button = %HireButton
@onready var hire_popup: PanelContainer = %HirePopup
@onready var candidates_list: VBoxContainer = %CandidatesList

var _candidates: Array[Worker] = []

func _ready() -> void:
	hire_button.pressed.connect(_on_hire_pressed)
	EventBus.worker_hired.connect(func(_w: Worker) -> void: _refresh_list())
	EventBus.worker_fired.connect(func(_w: Worker) -> void: _refresh_list())
	EventBus.mission_started.connect(func(_m: Mission) -> void: _refresh_list())
	EventBus.mission_completed.connect(func(_m: Mission) -> void: _refresh_list())
	hire_popup.visible = false
	_refresh_list()

func _refresh_list() -> void:
	for child in workers_list.get_children():
		child.queue_free()

	if GameState.workers.is_empty():
		var label := Label.new()
		label.text = "No workers hired yet"
		label.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
		workers_list.add_child(label)
		return

	for worker: Worker in GameState.workers:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)

		var info := Label.new()
		var status_text := "Available" if worker.is_available else "On Mission"
		info.text = "%s  |  Skill: %.2f  |  $%d/pay  |  %s" % [
			worker.worker_name, worker.skill, worker.wage, status_text
		]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info)

		if worker.is_available:
			var fire_btn := Button.new()
			fire_btn.text = "Fire"
			fire_btn.pressed.connect(func() -> void: GameState.fire_worker(worker))
			hbox.add_child(fire_btn)

		workers_list.add_child(hbox)

func _on_hire_pressed() -> void:
	_candidates.clear()
	for i in range(3):
		_candidates.append(Worker.generate_random())

	for child in candidates_list.get_children():
		child.queue_free()

	for candidate in _candidates:
		var hbox := HBoxContainer.new()
		hbox.add_theme_constant_override("separation", 12)

		var info := Label.new()
		info.text = "%s  |  Skill: %.2f  |  $%d/pay" % [
			candidate.worker_name, candidate.skill, candidate.wage
		]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(info)

		var btn := Button.new()
		btn.text = "Hire"
		btn.pressed.connect(_hire_candidate.bind(candidate))
		hbox.add_child(btn)

		candidates_list.add_child(hbox)

	hire_popup.visible = true

func _hire_candidate(worker: Worker) -> void:
	GameState.hire_worker(worker)
	hire_popup.visible = false
