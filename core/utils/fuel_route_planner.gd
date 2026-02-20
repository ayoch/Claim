class_name FuelRoutePlanner
extends RefCounted

## Plans multi-leg routes with fuel stop waypoints
## Uses greedy nearest-colony approach to find intermediate refueling stops

## Plan a route from ship's current position to destination
## Returns route with waypoints, colonies, fuel amounts, costs, and feasibility
static func plan_route_to_position(
	ship: Ship,
	dest_pos: Vector2,
	cargo_mass: float,
	max_stops: int = 3
) -> Dictionary:
	var current_pos := ship.position_au
	var current_fuel := ship.fuel
	var waypoints: Array[Vector2] = []
	var colonies: Array[Colony] = []
	var fuel_amounts: Array[float] = []
	var fuel_costs: Array[int] = []
	var leg_times: Array[float] = []
	var total_cost := 0

	# Check if direct route is possible
	var direct_dist := current_pos.distance_to(dest_pos)
	var direct_fuel := ship.calc_fuel_for_distance(direct_dist, cargo_mass)

	if direct_fuel <= current_fuel:
		# Direct route works, no fuel stops needed
		return {
			"waypoints": [],
			"colonies": [],
			"fuel_amounts": [],
			"fuel_costs": [],
			"leg_times": [],
			"total_cost": 0,
			"feasible": true,
			"reason": "Direct route possible"
		}

	# Need fuel stops - start planning
	var stops := 0
	var simulated_fuel := current_fuel
	var simulated_pos := current_pos

	while stops < max_stops:
		# Find all colonies reachable with current fuel
		var reachable := _find_reachable_colonies(simulated_pos, simulated_fuel, cargo_mass, ship)

		if reachable.is_empty():
			# No colonies reachable - route impossible
			return {
				"waypoints": [],
				"colonies": [],
				"fuel_amounts": [],
				"fuel_costs": [],
				"leg_times": [],
				"total_cost": 0,
				"feasible": false,
				"reason": "No reachable fuel stops from position (%.2f, %.2f)" % [simulated_pos.x, simulated_pos.y]
			}

		# Score colonies by distance to destination (prefer closer to goal)
		var best_colony: Colony = null
		var best_score := INF

		for colony in reachable:
			var colony_pos := colony.get_position_au()
			var dist_to_dest := colony_pos.distance_to(dest_pos)

			# Score: distance to destination (lower is better)
			# Could add other factors: fuel price, distance from current pos, etc.
			var score := dist_to_dest

			if score < best_score:
				best_score = score
				best_colony = colony

		if best_colony == null:
			return {
				"waypoints": [],
				"colonies": [],
				"fuel_amounts": [],
				"fuel_costs": [],
				"leg_times": [],
				"total_cost": 0,
				"feasible": false,
				"reason": "Could not find suitable fuel stop"
			}

		# Add this colony as a waypoint
		var colony_pos := best_colony.get_position_au()
		var leg_dist := simulated_pos.distance_to(colony_pos)
		var leg_fuel := ship.calc_fuel_for_distance(leg_dist, cargo_mass)
		var leg_time := Brachistochrone.transit_time(leg_dist, ship.get_effective_thrust())

		# Calculate how much fuel to purchase at this stop
		# Fill to capacity to maximize range for next leg
		var fuel_to_buy := ship.get_effective_fuel_capacity() - (simulated_fuel - leg_fuel)
		fuel_to_buy = maxf(0.0, fuel_to_buy)

		# Calculate fuel cost at this colony
		var fuel_price := FuelPricing.get_fuel_price_at_location(colony_pos)
		var fuel_cost := int(fuel_to_buy * fuel_price)

		waypoints.append(colony_pos)
		colonies.append(best_colony)
		fuel_amounts.append(fuel_to_buy)
		fuel_costs.append(fuel_cost)
		leg_times.append(leg_time)
		total_cost += fuel_cost

		# Simulate refueling
		simulated_fuel -= leg_fuel  # Consumed during transit
		simulated_fuel += fuel_to_buy  # Refueled at colony
		simulated_fuel = minf(simulated_fuel, ship.get_effective_fuel_capacity())
		simulated_pos = colony_pos
		stops += 1

		# Check if we can now reach destination
		var final_dist := simulated_pos.distance_to(dest_pos)
		var final_fuel := ship.calc_fuel_for_distance(final_dist, cargo_mass)

		if final_fuel <= simulated_fuel:
			# Success! Add final leg time
			var final_leg_time := Brachistochrone.transit_time(final_dist, ship.get_effective_thrust())
			leg_times.append(final_leg_time)

			return {
				"waypoints": waypoints,
				"colonies": colonies,
				"fuel_amounts": fuel_amounts,
				"fuel_costs": fuel_costs,
				"leg_times": leg_times,
				"total_cost": total_cost,
				"feasible": true,
				"reason": "Route found with %d fuel stop(s)" % stops
			}

	# Exceeded max stops
	return {
		"waypoints": [],
		"colonies": [],
		"fuel_amounts": [],
		"fuel_costs": [],
		"leg_times": [],
		"total_cost": 0,
		"feasible": false,
		"reason": "Destination unreachable within %d fuel stops" % max_stops
	}

## Find all colonies reachable from current position with available fuel
static func _find_reachable_colonies(
	from_pos: Vector2,
	available_fuel: float,
	cargo_mass: float,
	ship: Ship
) -> Array[Colony]:
	var reachable: Array[Colony] = []

	for colony in GameState.colonies:
		var colony_pos := colony.get_position_au()
		var dist := from_pos.distance_to(colony_pos)
		var fuel_needed := ship.calc_fuel_for_distance(dist, cargo_mass)

		# Need some margin for safety (95% of available fuel)
		if fuel_needed <= available_fuel * 0.95:
			reachable.append(colony)

	return reachable

## Get detailed route info for UI display
static func get_route_preview(
	ship: Ship,
	dest_pos: Vector2,
	cargo_mass: float,
	max_stops: int = 3
) -> String:
	var route := plan_route_to_position(ship, dest_pos, cargo_mass, max_stops)

	if not route["feasible"]:
		return "ROUTE INFEASIBLE: " + route["reason"]

	if route["waypoints"].is_empty():
		return "Direct route (no fuel stops needed)"

	var text := "Route requires %d fuel stop(s) - Total cost: $%d\n" % [
		route["colonies"].size(),
		route["total_cost"]
	]

	for i in range(route["colonies"].size()):
		var colony: Colony = route["colonies"][i]
		var fuel_amt: float = route["fuel_amounts"][i]
		var cost: int = route["fuel_costs"][i]
		text += "  Stop %d: %s (%.0f units, $%d)\n" % [i + 1, colony.colony_name, fuel_amt, cost]

	return text
