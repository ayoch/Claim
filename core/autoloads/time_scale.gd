extends Node

# Simulation speed control
# 1.0x = real-time (1 real second = 1 game second)
# Game starts at accelerated speed for playable testing

# Current speed (shown and editable in UI)
var speed_multiplier: float = 20.0  # Start at 20x (playable default)

# Speed presets for quick adjustment
const SPEED_REALTIME: float = 1.0      # True real-time
const SPEED_SLOW: float = 5.0          # 5x (slow)
const SPEED_NORMAL: float = 20.0       # 20x (default)
const SPEED_FAST: float = 50.0         # 50x (fast)
const SPEED_VERYFAST: float = 100.0    # 100x (very fast)
const SPEED_MAX: float = 200000.0      # 200000x (maximum allowed)

func _ready() -> void:
	# Listen for speed control keys
	pass

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			slow_down()
		elif event.keycode == KEY_2:
			speed_up()
		elif event.keycode == KEY_3:
			set_speed(SPEED_NORMAL)
		elif event.keycode == KEY_0:
			set_speed(SPEED_REALTIME)

func slow_down() -> void:
	if speed_multiplier > SPEED_REALTIME:
		speed_multiplier = maxf(SPEED_REALTIME, speed_multiplier * 0.5)
		print("Simulation speed: %s" % get_speed_display())

func speed_up() -> void:
	if speed_multiplier < SPEED_MAX:
		speed_multiplier = minf(SPEED_MAX, speed_multiplier * 2.0)
		print("Simulation speed: %s" % get_speed_display())

func set_speed(new_speed: float) -> void:
	speed_multiplier = clampf(new_speed, SPEED_REALTIME, SPEED_MAX)
	print("Simulation speed: %s" % get_speed_display())

## Auto-slow to 1x on critical events (breakdown, stranger rescue offer, etc.)
func slow_for_critical_event() -> void:
	if speed_multiplier > SPEED_REALTIME:
		speed_multiplier = SPEED_REALTIME
		print("Auto-slowed to 1x for critical event")

func get_speed_display() -> String:
	if speed_multiplier >= 1000.0:
		return "%.0fx" % speed_multiplier
	elif speed_multiplier >= 10.0:
		return "%.1fx" % speed_multiplier
	else:
		return "%.2fx" % speed_multiplier

func get_delta_multiplier() -> float:
	return speed_multiplier

## Format seconds as real game time
static func format_time(seconds: float) -> String:
	var hours := seconds / 3600.0

	if hours < 1.0:
		var minutes := int(seconds / 60.0)
		return "%dm" % minutes
	elif hours < 24.0:
		var h := int(hours)
		var m := int((seconds - h * 3600) / 60.0)
		if m > 0:
			return "%dh %dm" % [h, m]
		return "%dh" % h
	else:
		var days := int(hours / 24.0)
		var remaining_hours := int(hours) % 24
		if remaining_hours > 0:
			return "%dd %dh" % [days, remaining_hours]
		return "%dd" % days

## Format time with more detail for longer durations
static func format_time_detailed(seconds: float) -> String:
	var hours := seconds / 3600.0

	if hours < 1.0:
		var minutes := int(seconds / 60.0)
		return "%d minutes" % minutes
	elif hours < 48.0:
		var h := int(hours)
		var m := int((seconds - h * 3600) / 60.0)
		return "%d hours %d minutes" % [h, m]
	else:
		var days := int(hours / 24.0)
		var remaining_hours := int(hours) % 24
		return "%d days %d hours" % [days, remaining_hours]
