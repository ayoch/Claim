extends VBoxContainer
class_name DispatchConfirmation

## Dispatch Confirmation Component
## Final confirmation and mission execution
## Extracted from fleet_market_tab.gd

signal mission_dispatched(ship: Ship, mission: Variant)
signal dispatch_cancelled()

var _selected_mission_type: int = Mission.MissionType.MINING
var _selected_deploy_units: Array[MiningUnit] = []


func show_confirmation(ship: Ship, destination: Variant, workers: Array[Worker], estimate: Dictionary) -> void:
	# TODO: Display confirmation dialog with summary
	pass


func _confirm_dispatch() -> void:
	# TODO: Extract from fleet_market_tab.gd
	pass


func _queue_mission() -> void:
	# TODO: Extract from fleet_market_tab.gd
	pass


func _abort_and_dispatch() -> void:
	# TODO: Extract from fleet_market_tab.gd
	pass


func _execute_dispatch() -> void:
	# TODO: Extract from fleet_market_tab.gd
	# Emit mission_dispatched when complete
	pass
