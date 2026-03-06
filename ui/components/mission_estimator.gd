extends VBoxContainer
class_name MissionEstimator

## Mission Estimator Component
## Calculate and display journey estimates (time, fuel, profit)
## Extracted from fleet_market_tab.gd

signal estimate_updated(data: Dictionary)
signal transit_mode_changed(mode: int)

var _selected_transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE
var _available_slingshot_routes: Array = []
var _selected_slingshot_route = null
var _sell_at_destination_markets: bool = true


func update_estimate(ship: Ship, destination: Variant, workers: Array[Worker]) -> void:
	# TODO: Extract _update_estimate_display() from fleet_market_tab.gd
	var estimate_data := _calculate_estimate(ship, destination, workers)
	estimate_updated.emit(estimate_data)


func _calculate_estimate(ship: Ship, destination: Variant, workers: Array[Worker]) -> Dictionary:
	# TODO: Calculate time, fuel, profit, risk
	return {
		"journey_time": 0.0,
		"fuel_used": 0.0,
		"estimated_profit": 0,
		"risk_level": "low"
	}


func _update_route_button_states() -> void:
	# TODO: Extract from fleet_market_tab.gd
	pass


func _calculate_jettison_for_asymmetric_trip(dist_outbound: float, dist_return: float) -> float:
	# TODO: Extract from fleet_market_tab.gd
	return 0.0
