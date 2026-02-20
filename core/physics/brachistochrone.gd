class_name Brachistochrone
extends RefCounted

const G_ACCEL: float = 9.81  # m/s^2

## Calculate transit time in game ticks (seconds at 1x speed)
## At 1.0x speed: 1 real second = 1 game second (true real-time)
## d_au: distance in AU, accel_g: ship acceleration in g-forces
static func transit_time(d_au: float, accel_g: float) -> float:
	var d_meters: float = d_au * CelestialData.AU_TO_METERS
	var a: float = accel_g * G_ACCEL
	# Brachistochrone: t = 2 * sqrt(d / a) for flip-and-burn
	var real_seconds: float = 2.0 * sqrt(d_meters / a)

	# Return real seconds directly - no compression
	# TimeScale.speed_multiplier controls how fast time passes (2x, 5x, etc.)
	return real_seconds

## Calculate delta-V for a Brachistochrone transfer in km/s
## d_au: distance in AU, accel_g: ship acceleration in g-forces
static func delta_v_km_s(d_au: float, accel_g: float) -> float:
	var d_meters: float = d_au * CelestialData.AU_TO_METERS
	var a: float = accel_g * G_ACCEL
	# Brachistochrone delta-V: dv = 2 * sqrt(d * a) for flip-and-burn
	var dv_m_s: float = 2.0 * sqrt(d_meters * a)
	return dv_m_s / 1000.0

## Get the 2D distance from Earth to an asteroid using orbital positions
static func distance_to(asteroid: AsteroidData) -> float:
	var earth_pos := CelestialData.get_earth_position_au()
	var asteroid_pos := asteroid.get_position_au()
	return earth_pos.distance_to(asteroid_pos)

## Get 2D distance between two positions in AU
static func distance_between_au(from_pos: Vector2, to_pos: Vector2) -> float:
	return from_pos.distance_to(to_pos)

## Calculate Hohmann transfer time (fuel-efficient orbit)
## Uses elliptical transfer orbit - much slower but uses ~25% fuel
## Time is independent of ship thrust (orbital mechanics, not thrust-based)
static func hohmann_time(d_au: float) -> float:
	# Simple consistent formula: Hohmann takes 3x as long as baseline brachistochrone
	# Using 0.3g baseline for reference (typical ship)
	var d_meters: float = d_au * CelestialData.AU_TO_METERS
	var baseline_accel: float = 0.3 * G_ACCEL
	var baseline_brach: float = 2.0 * sqrt(d_meters / baseline_accel)
	var hohmann_real_seconds: float = baseline_brach * 3.0
	return hohmann_real_seconds  # Real-time, no compression

## Calculate fuel multiplier for Hohmann transfer
## Returns fraction of brachistochrone fuel (typically 0.25 = 25%)
static func hohmann_fuel_multiplier() -> float:
	return 0.25

## Estimate if Hohmann is viable given current fuel
## Returns true if brachistochrone would fail but Hohmann would work
static func should_use_hohmann(ship: Ship, distance: float, cargo_mass_return: float) -> bool:
	var current_cargo := ship.get_cargo_total()

	# Calculate brachistochrone fuel (worst case)
	var fuel_out_brach := ship.calc_fuel_for_distance(distance, current_cargo)
	var fuel_ret_brach := ship.calc_fuel_for_distance(distance, cargo_mass_return)
	var total_brach := fuel_out_brach + fuel_ret_brach

	# If brachistochrone fits in fuel tank, it's available
	if total_brach <= ship.fuel:
		return false  # Brachistochrone is fine, no need for Hohmann

	# Calculate Hohmann fuel
	var total_hohmann := total_brach * hohmann_fuel_multiplier()

	# Use Hohmann if it fits but brachistochrone doesn't
	return total_hohmann <= ship.fuel

## Calculate rescue intercept for a drifting derelict
## Returns: { "time": float (seconds), "fuel": float, "distance": float, "feasible": bool, "reason": String }
static func calculate_rescue_intercept(
	rescue_pos: Vector2,       # Rescue ship starting position (AU)
	rescue_accel_g: float,     # Rescue ship acceleration (g)
	rescue_fuel_capacity: float, # Rescue ship fuel capacity
	derelict_pos: Vector2,     # Derelict current position (AU)
	derelict_vel: Vector2      # Derelict velocity (AU/tick = AU/second at 1x)
) -> Dictionary:

	# Convert velocity to AU/s for calculation
	var v_drift := derelict_vel.length()  # AU/s

	# If derelict is stationary or very slow, simple intercept
	if v_drift < 0.0001:  # Effectively stationary
		var dist := rescue_pos.distance_to(derelict_pos)
		var t := transit_time(dist, rescue_accel_g)
		# Fuel calculation: rescue ship needs to accelerate there and back
		# Simplified: distance * accel * mass_estimate
		# Using rough estimate: 500t rescue ship mass
		var fuel_needed := dist * rescue_accel_g * 500.0 * 0.35 * 2.0  # Round trip
		return {
			"time": t,
			"fuel": fuel_needed,
			"distance": dist,
			"feasible": fuel_needed <= rescue_fuel_capacity,
			"reason": "Derelict stationary" if fuel_needed <= rescue_fuel_capacity else "Insufficient fuel for intercept"
		}

	# For moving derelicts: pursuit intercept
	# Simplified approach: calculate where derelict will be after pursuit time
	# This is an iterative problem, but we can approximate

	var initial_separation := rescue_pos.distance_to(derelict_pos)
	var drift_direction := derelict_vel.normalized()

	# Estimate intercept time (iterative approximation)
	var intercept_time := 0.0
	var iterations := 5
	for i in range(iterations):
		# Where will derelict be after intercept_time?
		var future_derelict_pos := derelict_pos + derelict_vel * intercept_time
		var pursuit_distance := rescue_pos.distance_to(future_derelict_pos)
		# How long to cover that distance?
		intercept_time = transit_time(pursuit_distance, rescue_accel_g)

	# Final intercept position
	var intercept_pos := derelict_pos + derelict_vel * intercept_time
	var pursuit_distance := rescue_pos.distance_to(intercept_pos)

	# Velocity matching cost (delta-v to match derelict's drift velocity)
	var velocity_match_dv_km_s := v_drift * CelestialData.AU_TO_METERS / 1000.0

	# Total delta-v: pursuit + velocity match + return
	var pursuit_dv := delta_v_km_s(pursuit_distance, rescue_accel_g)
	var return_dv := delta_v_km_s(pursuit_distance, rescue_accel_g)  # Decelerate back
	var total_dv_km_s := pursuit_dv + velocity_match_dv_km_s + return_dv

	# Fuel estimate (simplified): dv * mass / exhaust_velocity
	# Using rough approximation: 1 km/s dv ≈ 100 fuel units for 500t ship
	var fuel_needed := total_dv_km_s * 100.0

	# Check feasibility
	var feasible := fuel_needed <= rescue_fuel_capacity
	var reason := ""
	if not feasible:
		if velocity_match_dv_km_s > 1000.0:  # >1000 km/s = impossible
			reason = "Derelict velocity too high (>1000 km/s)"
		else:
			reason = "Insufficient fuel for intercept (need %.0f, have %.0f)" % [fuel_needed, rescue_fuel_capacity]
	else:
		reason = "Intercept feasible"

	return {
		"time": intercept_time,
		"fuel": fuel_needed,
		"distance": pursuit_distance,
		"intercept_dv_km_s": total_dv_km_s,
		"velocity_match_km_s": velocity_match_dv_km_s,
		"feasible": feasible,
		"reason": reason
	}

## Calculate course change for a ship already in motion
## Returns: { "fuel_cost": float, "new_transit_time": float, "feasible": bool, "reason": String }
static func calculate_course_change(
	ship_pos: Vector2,          # Current position (AU)
	ship_vel: Vector2,          # Current velocity (AU/tick)
	ship_accel_g: float,        # Ship acceleration
	ship_fuel_remaining: float, # Fuel left in tank
	new_destination: Vector2    # New target position (AU)
) -> Dictionary:

	# Vector from current position to new destination
	var to_dest := new_destination - ship_pos
	var dist_to_dest := to_dest.length()

	if dist_to_dest < 0.001:  # Already at destination
		return {
			"fuel_cost": 0.0,
			"new_transit_time": 0.0,
			"feasible": true,
			"reason": "Already at destination"
		}

	# Current velocity magnitude and direction
	var current_speed := ship_vel.length()
	var vel_direction := ship_vel.normalized() if current_speed > 0.0001 else Vector2.ZERO
	var dest_direction := to_dest.normalized()

	# Angle between current velocity and destination
	var dot := vel_direction.dot(dest_direction) if current_speed > 0.0001 else 0.0

	# Delta-v needed to redirect
	# If moving toward destination (dot > 0), cheaper redirect
	# If moving away (dot < 0), expensive redirect
	var alignment_factor := (1.0 - dot) / 2.0  # 0.0 = perfect alignment, 1.0 = opposite direction

	# Simplified: Calculate as if doing a brachistochrone from current position
	# but add penalty for velocity mismatch
	var base_dv := delta_v_km_s(dist_to_dest, ship_accel_g)
	var current_speed_km_s := current_speed * CelestialData.AU_TO_METERS / 1000.0

	# Redirect penalty: need to cancel current velocity component perpendicular to new path
	var redirect_penalty_dv := current_speed_km_s * alignment_factor * 2.0
	var total_dv_km_s := base_dv + redirect_penalty_dv

	# Estimate fuel (same formula as rescue: ~100 fuel per km/s dv for typical ship)
	var fuel_needed := total_dv_km_s * 100.0

	# Calculate new transit time from current position
	var new_transit_time := transit_time(dist_to_dest, ship_accel_g)

	# Feasibility check
	var feasible := fuel_needed <= ship_fuel_remaining
	var reason := "Course change feasible" if feasible else "Insufficient fuel (need %.0f, have %.0f)" % [fuel_needed, ship_fuel_remaining]

	return {
		"fuel_cost": fuel_needed,
		"new_transit_time": new_transit_time,
		"alignment": 1.0 - alignment_factor,  # 1.0 = perfect, 0.0 = opposite
		"total_dv_km_s": total_dv_km_s,
		"feasible": feasible,
		"reason": reason
	}
