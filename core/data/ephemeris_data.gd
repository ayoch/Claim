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

# Game epoch: Unix timestamp for 2112-01-01 00:00:00 UTC
const GAME_EPOCH_UNIX: float = 4481654400.0

# Cached positions driven by sim time (not wall clock)
var _cached_positions: Dictionary = {}  # body_name -> Vector2
var _sim_elapsed: float = -1.0          # Game-seconds elapsed since game epoch
var _dirty: bool = true                 # Recompute positions on next get_position()
var _sim_correction: float = 0.0       # Unused — kept for compatibility

# Server Hz calibration.
# Server TICK_INTERVAL=1.0 running at ~60Hz asyncio means total_ticks advances
# at 60*speed per real-second. Dividing by _server_hz converts to game-seconds.
# Between polls, advance() uses delta*speed — same rate. Snaps collapse to ~0.
var _server_hz: float = 60.0         # Server tick rate at 1x (ticks/real-second)
var _last_server_ticks: float = -1.0 # total_ticks from previous server poll
var _last_poll_ms: int = -1          # real time (msec) of previous poll
var _hz_anchored: bool = false       # True after first snap; advance(dt) runs freely after

func initialize() -> void:
	# Seed from GameState.total_ticks so saves and MP polls start at the right date
	_sim_elapsed = GameState.total_ticks
	_recompute_positions()

## Advance sim time by dt sim-seconds (called from CelestialData.advance_planets).
func advance(dt: float) -> void:
	_sim_elapsed += dt
	_dirty = true

## Sync to an authoritative tick count (save load, MP server poll).
## LOCAL mode: ticks are game-seconds — snap directly.
## SERVER mode: snap _sim_elapsed ONCE on initial connection to anchor server time,
##   then let advance(dt) run freely. Re-anchors after speed changes.
##   Avoids repeated backward corrections from Hz calibration convergence.
## Returns the snap delta for asteroid/colony orbit angle advancement.
func sync_to_ticks(ticks: float) -> float:
	if BackendManager.current_mode != BackendManager.BackendMode.SERVER:
		# LOCAL mode: total_ticks is already in game-seconds
		var delta := ticks - _sim_elapsed
		_sim_elapsed = ticks
		_dirty = true
		return delta

	# SERVER mode: measure Hz from consecutive polls (for accurate initial anchor)
	var now_ms := Time.get_ticks_msec()
	var hz_measured := false
	if _last_server_ticks >= 0.0 and _last_poll_ms >= 0:
		var real_s := float(now_ms - _last_poll_ms) / 1000.0
		if real_s > 0.1:
			var speed := TimeScale.speed_multiplier
			if speed > 0.0:
				var new_hz := (ticks - _last_server_ticks) / (real_s * speed)
				if new_hz > 0.01:
					_server_hz = new_hz  # Use directly — we only apply Hz on (re-)anchor
					hz_measured = true

	_last_server_ticks = ticks
	_last_poll_ms = now_ms

	if not hz_measured:
		# No Hz data yet (first poll) — _sim_elapsed from initialize() is already correct.
		# Don't anchor with uncalibrated _server_hz; that would snap wildly.
		return 0.0

	var new_sim := ticks / _server_hz
	if not _hz_anchored or absf(new_sim - _sim_elapsed) > 86400.0:
		# Anchor on: initial connect, or large discontinuity (reconnect after long offline).
		# Speed-change drift is ~hundreds of sim-sec — well under threshold, never triggers.
		var delta := new_sim - _sim_elapsed
		_sim_elapsed = new_sim
		_hz_anchored = true
		_dirty = true
		return delta

	# Already anchored and no large discontinuity — advance(dt) stays in sync.
	return 0.0

## Called when user changes sim speed. Invalidates poll reference for fresh Hz
## measurement — but does NOT clear the anchor. Re-anchoring after a speed
## change causes a snap because the server may still be at the old speed when
## the next poll arrives. The transient drift (~hundreds of sim-sec) is invisible.
func scale_server_rate(_old_speed: float, _new_speed: float) -> void:
	_last_server_ticks = -1.0
	_last_poll_ms = -1

## Get current sim elapsed time
func get_sim_elapsed() -> float:
	return _sim_elapsed

## Get JD from accumulated sim time
func _get_sim_jd() -> float:
	return 2440587.5 + (GAME_EPOCH_UNIX + _sim_elapsed) / SECONDS_PER_DAY

## Compute position for a planet at the current sim time
func get_position(body_name: String) -> Vector2:
	if _sim_elapsed < 0.0:
		_sim_elapsed = GameState.total_ticks
		_dirty = true
	if _dirty:
		_recompute_positions()
	return _cached_positions.get(body_name, Vector2.ZERO)

## Predict position at a future sim time (current + dt_seconds)
func get_position_at_time(body_name: String, dt_seconds: float) -> Vector2:
	var future_jd := _get_sim_jd() + (dt_seconds / SECONDS_PER_DAY)
	var T := (future_jd - J2000_JD) / DAYS_PER_CENTURY
	return _compute_position(body_name, T)

## Recompute all planet positions from current sim elapsed time
func _recompute_positions() -> void:
	_dirty = false
	var T := (_get_sim_jd() - J2000_JD) / DAYS_PER_CENTURY
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
