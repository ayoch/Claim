class_name Brachistochrone
extends RefCounted

const G_ACCEL: float = 9.81  # m/s^2

# Time compression: makes interplanetary travel take minutes not months
# Higher value = faster gameplay
const TIME_COMPRESSION: float = 50000.0

## Calculate transit time in game ticks (seconds at 1x speed)
## d_au: distance in AU, accel_g: ship acceleration in g-forces
static func transit_time(d_au: float, accel_g: float) -> float:
	var d_meters: float = d_au * CelestialData.AU_TO_METERS
	var a: float = accel_g * G_ACCEL
	# Brachistochrone: t = 2 * sqrt(d / a) for flip-and-burn
	var real_seconds: float = 2.0 * sqrt(d_meters / a)
	return real_seconds / TIME_COMPRESSION

## Get the distance from Earth to an asteroid
static func distance_to(asteroid: AsteroidData) -> float:
	return absf(asteroid.orbit_au - CelestialData.EARTH_ORBIT_AU)
