class_name GravityAssist
extends RefCounted

# Planet masses in Earth masses (for gravity assist calculations)
const PLANET_MASSES: Array = [
	0.055,    # Mercury
	0.815,    # Venus
	1.000,    # Earth
	0.107,    # Mars
	317.8,    # Jupiter
	95.2,     # Saturn
	14.5,     # Uranus
	17.1,     # Neptune
]

# Standard gravitational parameter μ = GM (in AU³/tick²)
# For game units: AU for distance, ticks for time
const GRAVITATIONAL_CONSTANT: float = 0.0001  # Calibrated for game scale

# Minimum fuel savings percentage to recommend a slingshot
const MIN_FUEL_SAVINGS_PERCENT: float = 15.0

# Maximum detour factor (slingshot route / direct route)
const MAX_DETOUR_FACTOR: float = 1.6

# Typical flyby periapsis distance (in AU) - represents safe closest approach
const FLYBY_PERIAPSIS_AU: float = 0.01  # ~1.5 million km

## Find all beneficial slingshot routes from start to end for the given ship
## Returns Array[SlingshotRoute]
static func find_beneficial_slingshots(start_pos: Vector2, end_pos: Vector2, ship: Ship, expected_cargo_mass: float = 0.0) -> Array:
	var routes: Array = []

	# Calculate direct route as baseline
	var direct_dist := start_pos.distance_to(end_pos)
	var direct_fuel := ship.calc_fuel_for_distance(direct_dist, expected_cargo_mass)
	var direct_time := Brachistochrone.transit_time(direct_dist, ship.get_effective_thrust())

	# Check each planet as a potential waypoint
	for i in range(CelestialData.PLANETS.size()):
		var planet_pos := CelestialData.get_planet_position_au(i)
		var planet_name: String = CelestialData.PLANETS[i]["name"]

		# Calculate slingshot route via this planet
		var route = _calculate_slingshot_route(
			start_pos, planet_pos, end_pos,
			ship, expected_cargo_mass,
			i, planet_name,
			direct_dist, direct_fuel, direct_time
		)

		# Only include if it meets benefit criteria
		if route and route.fuel_savings_percent >= MIN_FUEL_SAVINGS_PERCENT:
			# Check detour isn't too extreme
			var detour_factor: float = route.total_distance / direct_dist
			if detour_factor <= MAX_DETOUR_FACTOR:
				routes.append(route)

	# Sort by fuel savings (best first)
	routes.sort_custom(func(a, b) -> bool:
		return a.fuel_savings > b.fuel_savings
	)

	return routes

## Calculate a specific slingshot route via a planet waypoint
## Returns SlingshotRoute or null
static func _calculate_slingshot_route(
	start_pos: Vector2, waypoint_pos: Vector2, end_pos: Vector2,
	ship: Ship, cargo_mass: float,
	planet_index: int, planet_name: String,
	direct_dist: float, direct_fuel: float, direct_time: float
):
	# Calculate leg distances
	var leg1_dist := start_pos.distance_to(waypoint_pos)
	var leg2_dist := waypoint_pos.distance_to(end_pos)
	var total_dist := leg1_dist + leg2_dist

	# Check if this waypoint is actually on a reasonable path
	# (Avoid routes that backtrack egregiously)
	if total_dist > direct_dist * MAX_DETOUR_FACTOR:
		return null  # Too much detour

	# Calculate gravity assist benefit
	var delta_v := _calculate_gravity_assist_delta_v(planet_index, ship)

	# Estimate fuel savings from gravity assist
	# The assist provides "free" delta-v, reducing fuel needed for leg 2
	var leg1_fuel := ship.calc_fuel_for_distance(leg1_dist, cargo_mass)
	var leg2_fuel_without_assist := ship.calc_fuel_for_distance(leg2_dist, cargo_mass)

	# Gravity assist reduces fuel needed for leg 2
	# Simplified model: fuel reduction proportional to delta_v
	var fuel_reduction_factor := _calculate_fuel_reduction(delta_v, leg2_dist, ship)
	var leg2_fuel_with_assist := leg2_fuel_without_assist * (1.0 - fuel_reduction_factor)

	var total_fuel := leg1_fuel + leg2_fuel_with_assist
	var fuel_savings := direct_fuel - total_fuel
	var fuel_savings_percent := (fuel_savings / direct_fuel) * 100.0 if direct_fuel > 0 else 0.0

	# Calculate transit times
	var leg1_time := Brachistochrone.transit_time(leg1_dist, ship.get_effective_thrust())
	var leg2_time := Brachistochrone.transit_time(leg2_dist, ship.get_effective_thrust())
	var total_time := leg1_time + leg2_time
	var time_penalty := total_time - direct_time

	# Create route structure
	var route := SlingshotRoute.new()
	route.route_name = "Via %s" % planet_name
	route.planet_index = planet_index
	route.planet_name = planet_name
	route.waypoint_pos = waypoint_pos
	route.total_distance = total_dist
	route.fuel_cost = total_fuel
	route.transit_time = total_time
	route.fuel_savings = fuel_savings
	route.fuel_savings_percent = fuel_savings_percent
	route.time_penalty = time_penalty
	route.leg1_distance = leg1_dist
	route.leg2_distance = leg2_dist
	route.leg1_time = leg1_time
	route.leg2_time = leg2_time
	route.delta_v_bonus = delta_v

	return route

## Calculate delta-v gained from gravity assist around a planet
static func _calculate_gravity_assist_delta_v(planet_index: int, ship: Ship) -> float:
	if planet_index < 0 or planet_index >= PLANET_MASSES.size():
		return 0.0

	var planet_mass: float = PLANET_MASSES[planet_index]
	var planet_orbit_au: float = CelestialData.PLANETS[planet_index]["orbit_au"]

	# Standard gravitational parameter μ = GM
	var mu: float = GRAVITATIONAL_CONSTANT * planet_mass

	# Escape velocity at periapsis: v_esc = sqrt(2*μ/r)
	var v_escape := sqrt(2.0 * mu / FLYBY_PERIAPSIS_AU)

	# For optimal gravity assist, deflection angle ~90 degrees
	# Delta-v ≈ 2 * v_esc * sin(θ/2) ≈ 1.4 * v_esc for θ=90°
	var delta_v := 1.4 * v_escape

	# Scale by ship's velocity relative to planet (higher velocity = less benefit)
	# Simplified: assume ship velocity ~ sqrt(thrust * distance)
	var ship_velocity_scale := sqrt(ship.get_effective_thrust())
	delta_v = delta_v / (1.0 + ship_velocity_scale * 0.5)

	return delta_v

## Calculate fuel reduction factor from gravity assist
static func _calculate_fuel_reduction(delta_v: float, leg2_distance: float, ship: Ship) -> float:
	# The gravity assist provides "free" velocity change
	# This reduces the fuel needed for the next leg

	# Fuel is proportional to: distance * thrust * mass
	# With free delta-v, effective thrust needed is reduced

	# Simplified model: each unit of delta_v saves ~20% of leg2 fuel
	# (This is calibrated for game balance, not strict physics)
	var reduction := delta_v * 0.2

	# Cap at 50% reduction (can't save more than half the fuel)
	return clampf(reduction, 0.0, 0.5)
