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
