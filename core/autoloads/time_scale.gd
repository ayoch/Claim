extends Node

# Simulation speed control and time display conversion

# Speed multipliers
var speed_multiplier: float = 1.0  # Default to 1x (real-time for compressed game physics)
const SPEED_SLOW: float = 0.5
const SPEED_NORMAL: float = 1.0
const SPEED_FAST: float = 2.0
const SPEED_VERY_FAST: float = 5.0
const SPEED_MAX: float = 10.0

# Fictional time conversion
# Based on orbital mechanics: Earth (1 AU) orbits in 600 ticks = 1 year
# Therefore: 1 tick = 365 days / 600 ticks = 14.6 hours
const TICK_TO_HOURS: float = 14.6

func _ready() -> void:
	# Listen for speed control keys
	pass

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1:
			slow_down()
		elif event.keycode == KEY_2:
			speed_up()

func slow_down() -> void:
	if speed_multiplier > SPEED_SLOW:
		speed_multiplier = maxf(SPEED_SLOW, speed_multiplier * 0.5)
		print("Simulation speed: %.1fx" % speed_multiplier)

func speed_up() -> void:
	if speed_multiplier < SPEED_MAX:
		speed_multiplier = minf(SPEED_MAX, speed_multiplier * 2.0)
		print("Simulation speed: %.1fx" % speed_multiplier)

func get_delta_multiplier() -> float:
	return speed_multiplier

## Format ticks as fictional game time (always shows the same regardless of speed)
static func format_time(ticks: float) -> String:
	var hours := ticks * TICK_TO_HOURS

	if hours < 1.0:
		var minutes := int(hours * 60)
		return "%dm" % minutes
	elif hours < 24.0:
		var h := int(hours)
		var m := int((hours - h) * 60)
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
static func format_time_detailed(ticks: float) -> String:
	var hours := ticks * TICK_TO_HOURS

	if hours < 1.0:
		var minutes := int(hours * 60)
		return "%d minutes" % minutes
	elif hours < 48.0:
		var h := int(hours)
		var m := int((hours - h) * 60)
		return "%d hours %d minutes" % [h, m]
	else:
		var days := int(hours / 24.0)
		var remaining_hours := int(hours) % 24
		return "%d days %d hours" % [days, remaining_hours]
