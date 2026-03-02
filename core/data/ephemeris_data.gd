class_name EphemerisData
extends RefCounted

# Keplerian orbital elements for accurate planet positions
# Source: JPL approximations valid 1800-2050, projected forward
# Reference epoch: J2000.0 (Jan 1, 2000 12:00 TT) = JD 2451545.0
#
# Elements: [a (AU), e, I (deg), L0 (deg), w (deg), dL (deg/century)]
# a = semi-major axis, e = eccentricity, I = inclination (unused in 2D)
# L0 = mean longitude at J2000, w = longitude of perihelion
# dL = rate of mean longitude (deg per Julian century)

const ELEMENTS := {
	"Mercury": {"a": 0.38710, "e": 0.20563, "L0": 252.251, "w": 77.457,  "dL": 149472.674},
	"Venus":   {"a": 0.72333, "e": 0.00677, "L0": 181.980, "w": 131.564, "dL": 58517.816},
	"Earth":   {"a": 1.00000, "e": 0.01671, "L0": 100.464, "w": 102.937, "dL": 35999.373},
	"Mars":    {"a": 1.52368, "e": 0.09340, "L0": 355.453, "w": 336.060, "dL": 19140.300},
	"Jupiter": {"a": 5.20260, "e": 0.04849, "L0": 34.351,  "w": 14.331,  "dL": 3034.906},
	"Saturn":  {"a": 9.55491, "e": 0.05551, "L0": 50.077,  "w": 93.057,  "dL": 1222.114},
	"Uranus":  {"a": 19.18171,"e": 0.04686, "L0": 314.055, "w": 173.005, "dL": 428.267},
	"Neptune": {"a": 30.06896,"e": 0.00895, "L0": 304.349, "w": 48.124,  "dL": 218.486},
}

# Game start date: Today's date in year 2112 (calculated dynamically)
# J2000 reference epoch
const J2000_JD: float = 2451545.0
const SECONDS_PER_DAY: float = 86400.0
const DAYS_PER_CENTURY: float = 36525.0

# Calculate START_JD dynamically based on current system date in year 2112
static func _calculate_start_jd() -> float:
	# Get current system date (month and day)
	var now := Time.get_datetime_dict_from_system()

	# Create date in year 2112 with current month/day
	var game_year := 2112
	var month: int = now["month"]
	var day: int = now["day"]

	# Calculate Unix timestamp for this date
	# Note: GDScript's Time.get_unix_time_from_datetime_dict expects UTC
	var game_date := {
		"year": game_year,
		"month": month,
		"day": day,
		"hour": 0,
		"minute": 0,
		"second": 0
	}

	var unix_timestamp: int = Time.get_unix_time_from_datetime_dict(game_date)

	# Convert Unix timestamp to Julian Date
	# JD = 2440587.5 + (Unix seconds / 86400)
	var jd: float = 2440587.5 + (float(unix_timestamp) / SECONDS_PER_DAY)

	print("[EphemerisData] Game start: %s %d, %d = JD %.1f" % [
		Time.get_datetime_string_from_datetime_dict(game_date, false).split(" ")[0],
		day,
		game_year,
		jd
	])

	return jd

# START_JD is no longer used - we calculate JD directly from system time
# var START_JD: float = _calculate_start_jd()

# Cached positions (updated each second of real time)
var _cached_positions: Dictionary = {}  # body_name -> Vector2
var _last_update_time: int = -1  # Unix timestamp of last update

func initialize() -> void:
	_update_all_positions_from_realtime()

## Get current Julian Date based on real-world time in 2112
static func _get_current_jd() -> float:
	var now := Time.get_datetime_dict_from_system()
	var game_date := {
		"year": 2112,
		"month": now["month"],
		"day": now["day"],
		"hour": now["hour"],
		"minute": now["minute"],
		"second": now["second"]
	}
	var unix_timestamp: int = Time.get_unix_time_from_datetime_dict(game_date)
	return 2440587.5 + (float(unix_timestamp) / SECONDS_PER_DAY)

## Compute position for a planet at the current game time
func get_position(body_name: String) -> Vector2:
	# Update cache if real-world time changed (check once per second)
	var current_time: int = Time.get_unix_time_from_system()
	if current_time != _last_update_time:
		_update_all_positions_from_realtime()
	return _cached_positions.get(body_name, Vector2.ZERO)

## Predict position at a future time (current time + dt_seconds)
func get_position_at_time(body_name: String, dt_seconds: float) -> Vector2:
	# Get current JD and add dt to predict future position
	var current_jd := _get_current_jd()
	var future_jd := current_jd + (dt_seconds / SECONDS_PER_DAY)
	var T := (future_jd - J2000_JD) / DAYS_PER_CENTURY

	return _compute_position(body_name, T)

## Update all planet positions based on current real-world time
func _update_all_positions_from_realtime() -> void:
	_last_update_time = Time.get_unix_time_from_system()

	# Get Julian Date for current real-world time in 2112
	var jd := _get_current_jd()

	# Julian centuries from J2000
	var T := (jd - J2000_JD) / DAYS_PER_CENTURY

	for body_name in ELEMENTS:
		_cached_positions[body_name] = _compute_position(body_name, T)

## Compute heliocentric ecliptic position from Keplerian elements
func _compute_position(body_name: String, T: float) -> Vector2:
	var el: Dictionary = ELEMENTS[body_name]

	var a: float = el["a"]
	var e: float = el["e"]
	var L0: float = el["L0"]
	var w: float = el["w"]
	var dL: float = el["dL"]

	# Mean longitude (degrees)
	var L := fmod(L0 + dL * T, 360.0)
	if L < 0:
		L += 360.0

	# Mean anomaly (degrees)
	var M_deg := fmod(L - w, 360.0)
	if M_deg < 0:
		M_deg += 360.0
	var M := deg_to_rad(M_deg)

	# Solve Kepler's equation: E - e*sin(E) = M (Newton-Raphson)
	var E := M
	for _i in range(10):
		var dE := (M - E + e * sin(E)) / (1.0 - e * cos(E))
		E += dE
		if absf(dE) < 1e-8:
			break

	# True anomaly
	var v := atan2(sqrt(1.0 - e * e) * sin(E), cos(E) - e)

	# Heliocentric distance
	var r := a * (1.0 - e * cos(E))

	# Heliocentric longitude (radians)
	var lon := v + deg_to_rad(w)

	return Vector2(r * cos(lon), r * sin(lon))

## Check if we need to refresh - no longer needed with Keplerian computation
func should_refresh() -> bool:
	return false

## No-op for compatibility
func refresh_for_new_day() -> void:
	pass
