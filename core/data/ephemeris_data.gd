class_name EphemerisData
extends RefCounted

# Real-time ephemeris system using NASA JPL Horizons data
# Maps current real-world day-of-year to same day in 2112
# Interpolates positions over 24 real hours
# Designed to be server-compatible: parsing logic is static and can run on Linux

const GAME_YEAR: int = 2112

# Cached ephemeris data for current and next day
var current_day_positions: Dictionary = {}  # body_id -> Vector2 (AU)
var next_day_positions: Dictionary = {}     # body_id -> Vector2 (AU)
var data_fetch_time: float = 0.0  # Real-world timestamp of data fetch
var current_day_of_year: int = 0

# Fetch state tracking
var _pending_fetches: Dictionary = {}  # url -> body_name
var _fetch_results: Dictionary = {}   # body_name -> {day: int, position: Vector2}
var _current_day_fetches_remaining: int = 0
var _next_day_fetches_remaining: int = 0

# JPL Horizons body IDs
const BODY_IDS := {
	"Mercury": "199",
	"Venus": "299",
	"Earth": "399",
	"Mars": "499",
	"Jupiter": "599",
	"Saturn": "699",
	"Uranus": "799",
	"Neptune": "899",
}

## Initialize ephemeris data for current day
func initialize() -> void:
	current_day_of_year = get_current_day_of_year()
	fetch_ephemeris_data()

## Get current day of year (1-365/366) in UTC
## IMPORTANT: Uses UTC to match JPL Horizons API timezone
static func get_current_day_of_year() -> int:
	var now := Time.get_datetime_dict_from_system(true)  # true = UTC time
	var year: int = now["year"]
	var month: int = now["month"]
	var day: int = now["day"]

	# Days in each month (non-leap year)
	var days_in_month := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

	# Check for leap year
	if (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0):
		days_in_month[1] = 29

	# Sum days from previous months
	var day_of_year: int = day
	for i in range(month - 1):
		day_of_year += days_in_month[i]

	return day_of_year

## Fetch ephemeris data from JPL Horizons for current and next day in 2112
func fetch_ephemeris_data() -> void:
	print("Fetching ephemeris data for day %d of year %d..." % [current_day_of_year, GAME_YEAR])

	# Check if HTTPFetcher is available (may not be ready during static init)
	# We can't directly check HTTPFetcher because it would error if nil
	# Instead, try to call it and catch the error
	var http_available := false
	@warning_ignore("unsafe_method_access")
	if typeof(HTTPFetcher) != TYPE_NIL:
		http_available = true

	if not http_available:
		print("HTTPFetcher not available - using placeholder orbital data")
		_use_placeholder_data()
		data_fetch_time = Time.get_unix_time_from_system()
		return

	# Fetch positions for today and tomorrow in 2112
	var next_day := current_day_of_year + 1
	if next_day > 365:  # Handle year wrap (simplified)
		next_day = 1

	# Clear previous fetch state
	_pending_fetches.clear()
	_fetch_results.clear()
	current_day_positions.clear()
	next_day_positions.clear()

	# Start async fetches for all bodies, both days
	_current_day_fetches_remaining = BODY_IDS.size()
	_next_day_fetches_remaining = BODY_IDS.size()

	for body_name in BODY_IDS.keys():
		var body_id: String = BODY_IDS[body_name]
		_fetch_body_for_day(body_id, body_name, current_day_of_year, GAME_YEAR, true)
		_fetch_body_for_day(body_id, body_name, next_day, GAME_YEAR, false)

## Fetch a single body's position for a specific day
## NOTE: Only call this if HTTPFetcher is available (checked in fetch_ephemeris_data)
func _fetch_body_for_day(body_id: String, body_name: String, day_of_year: int, year: int, is_current_day: bool) -> void:
	var date_dict := _day_of_year_to_date(day_of_year, year)
	var date_str := "%04d-%02d-%02d" % [year, date_dict["month"], date_dict["day"]]

	var url := _build_jpl_url(body_id, date_str)

	# Track this fetch
	_pending_fetches[url] = {"body_name": body_name, "day": day_of_year, "is_current_day": is_current_day}

	# Connect to HTTPFetcher signals if not already connected
	if not HTTPFetcher.fetch_completed.is_connected(_on_fetch_completed):
		HTTPFetcher.fetch_completed.connect(_on_fetch_completed)
	if not HTTPFetcher.fetch_failed.is_connected(_on_fetch_failed):
		HTTPFetcher.fetch_failed.connect(_on_fetch_failed)

	# Start fetch
	HTTPFetcher.fetch_with_timeout(url, 15.0)

## Handle successful HTTP fetch
func _on_fetch_completed(url: String, _result: int, _response_code: int, body: String) -> void:
	if not _pending_fetches.has(url):
		return  # Not our request

	var fetch_info: Dictionary = _pending_fetches[url]
	var body_name: String = fetch_info["body_name"]
	var is_current_day: bool = fetch_info["is_current_day"]

	# Parse the JPL response
	var position := parse_jpl_response(body)

	if position != Vector2.ZERO:
		print("Parsed position for %s: (%.3f, %.3f) AU" % [body_name, position.x, position.y])

		# Store in appropriate dictionary
		if is_current_day:
			current_day_positions[body_name] = position
			_current_day_fetches_remaining -= 1
		else:
			next_day_positions[body_name] = position
			_next_day_fetches_remaining -= 1
	else:
		push_warning("Failed to parse position for %s from JPL response" % body_name)
		_mark_fetch_failed(is_current_day)

	_pending_fetches.erase(url)
	_check_fetch_completion()

## Handle failed HTTP fetch
func _on_fetch_failed(url: String, error: String) -> void:
	if not _pending_fetches.has(url):
		return

	var fetch_info: Dictionary = _pending_fetches[url]
	var body_name: String = fetch_info["body_name"]
	var is_current_day: bool = fetch_info["is_current_day"]

	push_warning("Failed to fetch %s: %s" % [body_name, error])

	_mark_fetch_failed(is_current_day)
	_pending_fetches.erase(url)
	_check_fetch_completion()

func _mark_fetch_failed(is_current_day: bool) -> void:
	if is_current_day:
		_current_day_fetches_remaining -= 1
	else:
		_next_day_fetches_remaining -= 1

## Check if all fetches are complete
func _check_fetch_completion() -> void:
	if _current_day_fetches_remaining <= 0 and _next_day_fetches_remaining <= 0:
		print("All ephemeris fetches complete")

		# If we got no data, fall back to placeholder
		if current_day_positions.is_empty() or next_day_positions.is_empty():
			push_warning("Some or all JPL fetches failed - using placeholder data")
			_use_placeholder_data()

		data_fetch_time = Time.get_unix_time_from_system()

## Placeholder data until we implement JPL API
func _use_placeholder_data() -> void:
	# Use circular orbits as placeholder
	# Real implementation will fetch from JPL Horizons
	var planet_data := CelestialData.PLANETS

	for i in range(planet_data.size()):
		var planet: Dictionary = planet_data[i]
		var body_name: String = planet["name"]
		var orbit_au: float = planet["orbit_au"]

		# Random starting positions (will be replaced with real data)
		var angle_today := randf() * TAU
		var angle_tomorrow := angle_today + (TAU / (orbit_au * 365.25))  # Approximate daily motion

		current_day_positions[body_name] = Vector2(cos(angle_today), sin(angle_today)) * orbit_au
		next_day_positions[body_name] = Vector2(cos(angle_tomorrow), sin(angle_tomorrow)) * orbit_au

## Get interpolated position for a body based on real time elapsed today
func get_position(body_name: String) -> Vector2:
	if not current_day_positions.has(body_name):
		return Vector2.ZERO

	# Calculate fraction of day elapsed (0.0 to 1.0)
	var fraction_of_day := get_fraction_of_day_elapsed()

	# Lerp between today and tomorrow positions
	var pos_today: Vector2 = current_day_positions[body_name]
	var pos_tomorrow: Vector2 = next_day_positions[body_name]

	return pos_today.lerp(pos_tomorrow, fraction_of_day)

## Get fraction of real-world day elapsed since midnight UTC (0.0 to 1.0)
## IMPORTANT: Uses UTC to match JPL Horizons API timezone
## This ensures accurate interpolation regardless of user's local timezone
static func get_fraction_of_day_elapsed() -> float:
	var now := Time.get_datetime_dict_from_system(true)  # true = UTC time
	var hour: int = now["hour"]
	var minute: int = now["minute"]
	var second: int = now["second"]

	var seconds_elapsed := hour * 3600 + minute * 60 + second
	var seconds_in_day := 86400.0

	return seconds_elapsed / seconds_in_day

## Check if we need to refresh data (new day has started)
func should_refresh() -> bool:
	var today_doy := get_current_day_of_year()
	return today_doy != current_day_of_year

## Refresh to next day's data
func refresh_for_new_day() -> void:
	# Shift tomorrow's data to today
	current_day_positions = next_day_positions.duplicate()
	current_day_of_year = get_current_day_of_year()

	# Fetch new tomorrow data
	# TODO: Implement incremental fetch (only fetch new tomorrow)
	fetch_ephemeris_data()

	print("Ephemeris data refreshed for day %d" % current_day_of_year)

## Build JPL Horizons API URL (server-compatible static method)
static func _build_jpl_url(body_id: String, date_str: String) -> String:
	var base_url := "https://ssd.jpl.nasa.gov/api/horizons.api"

	# Build query parameters
	var params := {
		"format": "json",
		"COMMAND": "'%s'" % body_id,
		"OBJ_DATA": "'NO'",
		"MAKE_EPHEM": "'YES'",
		"EPHEM_TYPE": "'VECTORS'",
		"CENTER": "'@0'",  # Solar System Barycenter
		"START_TIME": "'%s'" % date_str,
		"STOP_TIME": "'%s'" % date_str,
		"STEP_SIZE": "'1 d'",
		"VEC_TABLE": "'2'",  # Position vectors only
		"OUT_UNITS": "'AU-D'",  # AU and days
		"CSV_FORMAT": "'YES'",
	}

	# Build query string
	var query_parts: Array = []
	for key in params.keys():
		query_parts.append("%s=%s" % [key, params[key]])
	var query_string := "&".join(query_parts)

	return base_url + "?" + query_string

## Parse JPL Horizons JSON response (server-compatible static method)
## Returns Vector2 position in AU, or Vector2.ZERO on error
static func parse_jpl_response(json_text: String) -> Vector2:
	# Parse JSON
	var json := JSON.new()
	var error := json.parse(json_text)

	if error != OK:
		push_error("Failed to parse JPL JSON response: %s" % json.get_error_message())
		return Vector2.ZERO

	var data = json.data
	if not data is Dictionary:
		push_error("JPL response is not a dictionary")
		return Vector2.ZERO

	# JPL Horizons returns ephemeris data in the "result" field as CSV text
	if not data.has("result"):
		push_error("JPL response missing 'result' field")
		return Vector2.ZERO

	var result_text: String = data["result"]

	# Parse CSV data from result text
	# Format: lines with position vectors after "$$SOE" marker
	# Example line: "2112-Feb-18 00:00, X = 1.234, Y = 5.678, Z = 0.123"
	# Or more commonly: " JD, X, Y, Z, VX, VY, VZ"

	var lines := result_text.split("\n")
	var in_data_section := false
	var x_value := 0.0
	var y_value := 0.0

	for line in lines:
		line = line.strip_edges()

		# Look for data section markers
		if line.begins_with("$$SOE"):
			in_data_section = true
			continue
		elif line.begins_with("$$EOE"):
			break

		if not in_data_section or line.is_empty():
			continue

		# Parse position vector line
		# Expected format: "2459..., X, Y, Z, ..." (CSV with Julian date, then X Y Z coordinates)
		var parts := line.split(",")
		if parts.size() < 4:
			continue

		# Try to parse X (column 2, index 1) and Y (column 3, index 2)
		# Skip first column (Julian Date)
		var x_str := parts[1].strip_edges()
		var y_str := parts[2].strip_edges()

		if x_str.is_valid_float() and y_str.is_valid_float():
			x_value = x_str.to_float()
			y_value = y_str.to_float()
			break  # Got our position

	if x_value == 0.0 and y_value == 0.0:
		push_warning("Could not extract position from JPL response")
		return Vector2.ZERO

	return Vector2(x_value, y_value)

## Convert day-of-year to month/day
func _day_of_year_to_date(day_of_year: int, year: int) -> Dictionary:
	var days_in_month := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

	# Check for leap year
	if (year % 4 == 0 and year % 100 != 0) or (year % 400 == 0):
		days_in_month[1] = 29

	var remaining_days := day_of_year
	var month := 1

	for i in range(12):
		if remaining_days <= days_in_month[i]:
			return {"month": i + 1, "day": remaining_days}
		remaining_days -= days_in_month[i]
		month += 1

	# Fallback
	return {"month": 12, "day": 31}
