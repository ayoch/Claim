class_name FuelPricing
extends RefCounted

# Base fuel production costs ($/unit)
const EARTH_BASE_COST: float = 5.0      # Cheapest production (unlimited ocean water, lunar He-3)
const COLONY_BASE_COST: float = 6.5     # More expensive (smaller scale, frontier operations)

# Shipping cost per AU ($/unit per AU)
const SHIPPING_COST_PER_AU: float = 1.2

## Calculate fuel cost at a given location, accounting for shipping from nearest source
static func get_fuel_price_at_location(location_au: Vector2) -> float:
	# Find cheapest fuel source considering base cost + shipping
	var earth_pos := CelestialData.get_earth_position_au()
	var earth_dist := location_au.distance_to(earth_pos)
	var earth_delivered_cost := EARTH_BASE_COST + (earth_dist * SHIPPING_COST_PER_AU)

	# Check all colonies for better prices
	var best_price := earth_delivered_cost
	var best_source := "Earth"

	for colony in GameState.colonies:
		var colony_pos := colony.get_position_au()
		var colony_dist := location_au.distance_to(colony_pos)

		# Colonies have local production, no shipping if you're AT the colony
		var colony_delivered_cost := COLONY_BASE_COST
		if colony_dist > 0.1:  # Not at the colony, add shipping
			colony_delivered_cost += colony_dist * SHIPPING_COST_PER_AU

		if colony_delivered_cost < best_price:
			best_price = colony_delivered_cost
			best_source = colony.colony_name

	return best_price

## Get detailed fuel pricing info for UI display
static func get_fuel_price_info(location_au: Vector2) -> Dictionary:
	var earth_pos := CelestialData.get_earth_position_au()
	var earth_dist := location_au.distance_to(earth_pos)
	var earth_delivered_cost := EARTH_BASE_COST + (earth_dist * SHIPPING_COST_PER_AU)

	var best_price := earth_delivered_cost
	var best_source := "Earth Depot"
	var best_distance := earth_dist

	for colony in GameState.colonies:
		var colony_pos := colony.get_position_au()
		var colony_dist := location_au.distance_to(colony_pos)

		var colony_delivered_cost := COLONY_BASE_COST
		if colony_dist > 0.1:
			colony_delivered_cost += colony_dist * SHIPPING_COST_PER_AU

		if colony_delivered_cost < best_price:
			best_price = colony_delivered_cost
			best_source = colony.colony_name
			best_distance = colony_dist

	return {
		"price": best_price,
		"source": best_source,
		"distance": best_distance,
		"earth_price": earth_delivered_cost,
		"earth_distance": earth_dist,
	}

## Calculate refuel cost for a ship at its current location
static func calculate_refuel_cost(ship: Ship, fuel_amount: float) -> int:
	var price_per_unit := get_fuel_price_at_location(ship.position_au)
	return int(fuel_amount * price_per_unit)

## Get nearest fuel source location and price
static func get_nearest_fuel_source(from_pos: Vector2) -> Dictionary:
	var earth_pos := CelestialData.get_earth_position_au()
	var earth_dist := from_pos.distance_to(earth_pos)
	var earth_price := EARTH_BASE_COST + (earth_dist * SHIPPING_COST_PER_AU)

	var nearest_dist := earth_dist
	var nearest_price := earth_price
	var nearest_name := "Earth"
	var nearest_pos := earth_pos

	for colony in GameState.colonies:
		var colony_pos := colony.get_position_au()
		var colony_dist := from_pos.distance_to(colony_pos)
		var colony_price := COLONY_BASE_COST
		if colony_dist > 0.1:
			colony_price += colony_dist * SHIPPING_COST_PER_AU

		if colony_price < nearest_price:
			nearest_dist = colony_dist
			nearest_price = colony_price
			nearest_name = colony.colony_name
			nearest_pos = colony_pos

	return {
		"name": nearest_name,
		"position": nearest_pos,
		"distance": nearest_dist,
		"price": nearest_price,
	}
