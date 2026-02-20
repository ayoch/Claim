extends Node

# Periodically verifies Keplerian orbital computations against JPL Horizons API
# Runs on startup and then every VERIFY_INTERVAL_HOURS real hours.
# All output goes to user://ephemeris_verification.log instead of the console.

const LOG_PATH := "res://ephemeris_verification.log"
const VERIFY_INTERVAL_HOURS: float = 24.0  # Verify once per real day
const WARN_THRESHOLD_AU: float = 0.05      # Log warning if error exceeds this
const ERROR_THRESHOLD_AU: float = 0.2      # Log error if error exceeds this

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

var _last_verify_time: float = 0.0
var _pending_fetches: Dictionary = {}  # url -> body_name
var _jpl_positions: Dictionary = {}    # body_name -> Vector2
var _fetches_remaining: int = 0
var _verify_game_ticks: float = 0.0    # Game ticks at time of verification request
var _network_available: bool = true    # Set false after first failure to avoid spamming

func _ready() -> void:
	# Verify after a short delay to let everything initialize
	get_tree().create_timer(5.0).timeout.connect(_run_verification)

func _process(_delta: float) -> void:
	if _last_verify_time <= 0.0:
		return
	var now := Time.get_unix_time_from_system()
	if now - _last_verify_time >= VERIFY_INTERVAL_HOURS * 3600.0:
		_network_available = true  # Retry network on each verification cycle
		_run_verification()

func _run_verification() -> void:
	if not _network_available:
		return

	_last_verify_time = Time.get_unix_time_from_system()
	_verify_game_ticks = GameState.total_ticks
	_pending_fetches.clear()
	_jpl_positions.clear()
	_fetches_remaining = BODY_IDS.size()

	# Compute the game date to query JPL for the same date
	var date_str := _get_game_date_string()
	_log("Starting verification for game date %s" % date_str)

	if not HTTPFetcher.fetch_completed.is_connected(_on_fetch_completed):
		HTTPFetcher.fetch_completed.connect(_on_fetch_completed)
	if not HTTPFetcher.fetch_failed.is_connected(_on_fetch_failed):
		HTTPFetcher.fetch_failed.connect(_on_fetch_failed)

	# Only fetch one planet first to test connectivity before sending all 8
	var first_body: String = BODY_IDS.keys()[0]
	var first_id: String = BODY_IDS[first_body]
	var first_url := _build_jpl_url(first_id, date_str)
	_pending_fetches[first_url] = first_body
	HTTPFetcher.fetch_with_timeout(first_url, 15.0)

func _send_remaining_fetches() -> void:
	var date_str := _get_game_date_string()
	var first_body: String = BODY_IDS.keys()[0]
	for body_name in BODY_IDS:
		if body_name == first_body:
			continue
		var body_id: String = BODY_IDS[body_name]
		var url := _build_jpl_url(body_id, date_str)
		_pending_fetches[url] = body_name
		HTTPFetcher.fetch_with_timeout(url, 20.0)

func _get_game_date_string() -> String:
	var d := GameState.get_game_date()
	return "%04d-%02d-%02d" % [d["year"], d["month"], d["day"]]

func _get_next_day_string(date_str: String) -> String:
	var parts := date_str.split("-")
	var year := parts[0].to_int()
	var month := parts[1].to_int()
	var day := parts[2].to_int() + 1
	var days_in_month := [0, 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
	if year % 4 == 0 and (year % 100 != 0 or year % 400 == 0):
		days_in_month[2] = 29
	if day > days_in_month[month]:
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
	return "%04d-%02d-%02d" % [year, month, day]

func _build_jpl_url(body_id: String, date_str: String) -> String:
	var base_url := "https://ssd.jpl.nasa.gov/api/horizons.api"
	# STOP_TIME must be after START_TIME for JPL Horizons
	var stop_date := _get_next_day_string(date_str)
	var params := {
		"format": "json",
		"COMMAND": "'%s'" % body_id,
		"OBJ_DATA": "'NO'",
		"MAKE_EPHEM": "'YES'",
		"EPHEM_TYPE": "'VECTORS'",
		"CENTER": "'@0'",
		"START_TIME": "'%s'" % date_str,
		"STOP_TIME": "'%s'" % stop_date,
		"STEP_SIZE": "'1 d'",
		"VEC_TABLE": "'2'",
		"OUT_UNITS": "'AU-D'",
		"CSV_FORMAT": "'YES'",
	}
	var query_parts: Array = []
	for key in params:
		query_parts.append("%s=%s" % [key, params[key]])
	return base_url + "?" + "&".join(query_parts)

func _on_fetch_completed(url: String, _result: int, _response_code: int, body: String) -> void:
	if not _pending_fetches.has(url):
		return
	var body_name: String = _pending_fetches[url]
	_pending_fetches.erase(url)

	# If this was the connectivity test (first planet), send the rest
	var is_first: bool = (body_name == BODY_IDS.keys()[0] and _fetches_remaining == BODY_IDS.size())
	if is_first:
		_send_remaining_fetches()

	var position := _parse_jpl_response(body)
	if position != Vector2.ZERO:
		_jpl_positions[body_name] = position

	_fetches_remaining -= 1
	if _fetches_remaining <= 0:
		_compare_results()

func _on_fetch_failed(url: String, error: String) -> void:
	if not _pending_fetches.has(url):
		return
	var body_name: String = _pending_fetches[url]
	_pending_fetches.erase(url)

	# If the first fetch failed, network is unavailable — don't send the rest
	var is_first: bool = (body_name == BODY_IDS.keys()[0] and _fetches_remaining == BODY_IDS.size())
	if is_first:
		_network_available = false
		_pending_fetches.clear()
		_fetches_remaining = 0
		_log("Network unavailable — skipping verification. Will retry next cycle.")
		return

	_log("WARN: Failed to fetch %s: %s" % [body_name, error])

	_fetches_remaining -= 1
	if _fetches_remaining <= 0:
		_compare_results()

func _compare_results() -> void:
	if _jpl_positions.is_empty():
		_log("No JPL data received — skipping verification (network may be unavailable)")
		return

	_log("Comparing %d planets against JPL Horizons:" % _jpl_positions.size())

	# Temporarily compute Keplerian positions at the same game time the verification was requested
	var ephemeris := CelestialData.ephemeris
	if not ephemeris:
		_log("No ephemeris available")
		return

	var days_elapsed := _verify_game_ticks / EphemerisData.SECONDS_PER_DAY
	var jd := EphemerisData.START_JD + days_elapsed
	var T := (jd - EphemerisData.J2000_JD) / EphemerisData.DAYS_PER_CENTURY

	var max_error := 0.0
	var total_error := 0.0
	var count := 0

	for body_name in _jpl_positions:
		var jpl_pos: Vector2 = _jpl_positions[body_name]
		var kep_pos: Vector2 = ephemeris._compute_position(body_name, T)
		var error_au := jpl_pos.distance_to(kep_pos)

		total_error += error_au
		count += 1
		if error_au > max_error:
			max_error = error_au

		if error_au >= ERROR_THRESHOLD_AU:
			_log("  %s: ERROR %.4f AU off (Kep: %.3f,%.3f  JPL: %.3f,%.3f)" % [
				body_name, error_au, kep_pos.x, kep_pos.y, jpl_pos.x, jpl_pos.y
			])
		elif error_au >= WARN_THRESHOLD_AU:
			_log("  %s: WARN %.4f AU off (Kep: %.3f,%.3f  JPL: %.3f,%.3f)" % [
				body_name, error_au, kep_pos.x, kep_pos.y, jpl_pos.x, jpl_pos.y
			])
		else:
			_log("  %s: OK (%.4f AU error)" % [body_name, error_au])

	var avg_error := total_error / count if count > 0 else 0.0
	_log("Summary: %d/%d verified, avg error %.4f AU, max error %.4f AU" % [
		count, BODY_IDS.size(), avg_error, max_error
	])

func _parse_jpl_response(json_text: String) -> Vector2:
	var json := JSON.new()
	var error := json.parse(json_text)
	if error != OK:
		return Vector2.ZERO

	var data = json.data
	if not data is Dictionary or not data.has("result"):
		return Vector2.ZERO

	var result_text: String = data["result"]
	var lines := result_text.split("\n")
	var in_data_section := false

	for line in lines:
		line = line.strip_edges()
		if line.begins_with("$$SOE"):
			in_data_section = true
			continue
		elif line.begins_with("$$EOE"):
			break

		if not in_data_section or line.is_empty():
			continue

		var parts := line.split(",")
		if parts.size() < 4:
			continue

		var x_str := parts[1].strip_edges()
		var y_str := parts[2].strip_edges()

		if x_str.is_valid_float() and y_str.is_valid_float():
			return Vector2(x_str.to_float(), y_str.to_float())

	return Vector2.ZERO

## Append a timestamped line to the verification log file
func _log(msg: String) -> void:
	var timestamp := Time.get_datetime_string_from_system(true)
	var line := "[%s] %s\n" % [timestamp, msg]
	var file := FileAccess.open(LOG_PATH, FileAccess.READ_WRITE)
	if file == null:
		file = FileAccess.open(LOG_PATH, FileAccess.WRITE)
	if file:
		file.seek_end(0)
		file.store_string(line)
