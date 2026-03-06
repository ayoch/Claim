extends VBoxContainer
class_name WorkerSelector

## Worker Selector Component
## Select crew members for mission
## Extracted from fleet_market_tab.gd

signal workers_selected(workers: Array[Worker])
signal selection_cancelled()

var _selected_workers: Array[Worker] = []
var _worker_checkboxes: Dictionary = {}  # Worker -> CheckBox


func show_worker_selection(ship: Ship, available_workers: Array[Worker]) -> void:
	# TODO: Extract from fleet_market_tab.gd
	pass


func _optimize_crew(available: Array, mode: String) -> void:
	# TODO: Extract from fleet_market_tab.gd (mode: "mining", "piloting", "engineering")
	pass


func _toggle_worker(worker: Worker, selected: bool) -> void:
	if selected and worker not in _selected_workers:
		_selected_workers.append(worker)
	elif not selected:
		_selected_workers.erase(worker)
	_update_worker_summary()


func _update_worker_summary() -> void:
	# TODO: Show selected count, total skills, etc.
	pass


func _confirm_selection() -> void:
	workers_selected.emit(_selected_workers)
