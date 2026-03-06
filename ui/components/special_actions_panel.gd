extends VBoxContainer
class_name SpecialActionsPanel

## Special Actions Panel Component
## Partnership, station jobs, fleet rescue, supply shop
## Extracted from fleet_market_tab.gd

signal partnership_created(ship1: Ship, ship2: Ship)
signal station_job_changed(ship: Ship, jobs: Array)
signal rescue_dispatched(rescuer: Ship, target: Ship)
signal supplies_purchased(ship: Ship, supplies: Dictionary)


func show_partnership_selection(ship: Ship) -> void:
	# TODO: Extract from fleet_market_tab.gd
	pass


func show_station_jobs(ship: Ship) -> void:
	# TODO: Extract from fleet_market_tab.gd
	pass


func show_fleet_rescue_dispatch(target_ship: Ship) -> void:
	# TODO: Extract from fleet_market_tab.gd
	pass


func show_supply_shop(ship: Ship) -> void:
	# TODO: Extract from fleet_market_tab.gd
	pass


func _format_number(n: int) -> String:
	# TODO: Extract from fleet_market_tab.gd
	return str(n)
