extends Node

# HTTP fetching service for ephemeris and other data
# Designed to be easily replaceable with server-based fetching

signal fetch_completed(url: String, result: int, response_code: int, body: String)
signal fetch_failed(url: String, error: String)

# Active HTTP requests
var _active_requests: Dictionary = {}  # url -> HTTPRequest node

func _ready() -> void:
	print("HTTPFetcher service initialized")

## Fetch URL asynchronously
## Returns request_id for tracking, or -1 on error
func fetch(url: String) -> int:
	if _active_requests.has(url):
		push_warning("Request already in progress for: %s" % url)
		return -1

	var http := HTTPRequest.new()
	add_child(http)

	http.request_completed.connect(_on_request_completed.bind(url))

	var error := http.request(url)
	if error != OK:
		push_error("HTTP request failed to start: %s (error %d)" % [url, error])
		http.queue_free()
		fetch_failed.emit(url, "Failed to start request: error %d" % error)
		return -1

	_active_requests[url] = http
	print("HTTP request started: %s" % url)

	return http.get_instance_id()

## Fetch with timeout (in seconds)
func fetch_with_timeout(url: String, timeout_sec: float = 10.0) -> int:
	var request_id := fetch(url)
	if request_id == -1:
		return -1

	# Set timeout
	get_tree().create_timer(timeout_sec).timeout.connect(func() -> void:
		if _active_requests.has(url):
			push_warning("HTTP request timeout: %s" % url)
			_active_requests[url].cancel_request()
			_cleanup_request(url)
			fetch_failed.emit(url, "Request timeout after %.1f seconds" % timeout_sec)
	)

	return request_id

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray, url: String) -> void:
	print("HTTP request completed: %s (code %d)" % [url, response_code])

	var body_str := body.get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS:
		push_error("HTTP request failed: %s (result %d)" % [url, result])
		fetch_failed.emit(url, "Request failed with result %d" % result)
		_cleanup_request(url)
		return

	if response_code != 200:
		push_error("HTTP request bad response code: %s (code %d)" % [url, response_code])
		fetch_failed.emit(url, "Bad response code %d" % response_code)
		_cleanup_request(url)
		return

	fetch_completed.emit(url, result, response_code, body_str)
	_cleanup_request(url)

func _cleanup_request(url: String) -> void:
	if _active_requests.has(url):
		var http: HTTPRequest = _active_requests[url]
		http.queue_free()
		_active_requests.erase(url)

## Cancel all active requests
func cancel_all() -> void:
	for url in _active_requests.keys():
		_active_requests[url].cancel_request()
		_cleanup_request(url)
