class_name RivalShip
extends Resource

enum Status {
	IDLE,
	TRANSIT_TO,
	MINING,
	TRANSIT_HOME,
}

@export var status: Status = Status.IDLE
@export var home_position_au: Vector2 = Vector2.ZERO
@export var target_asteroid_name: String = ""
@export var target_position_au: Vector2 = Vector2.ZERO
@export var cargo_tons: float = 0.0
@export var cargo_capacity: float = 100.0
@export var thrust_g: float = 0.25
@export var transit_time: float = 0.0   # seconds for current leg
@export var elapsed_ticks: float = 0.0  # time into current leg
@export var mining_elapsed: float = 0.0
@export var mining_duration: float = 86400.0  # 1 game-day default

func get_position_au() -> Vector2:
	match status:
		Status.IDLE:
			return home_position_au
		Status.TRANSIT_TO:
			if transit_time <= 0.0:
				return target_position_au
			var t := clampf(elapsed_ticks / transit_time, 0.0, 1.0)
			return home_position_au.lerp(target_position_au, t)
		Status.MINING:
			return target_position_au
		Status.TRANSIT_HOME:
			if transit_time <= 0.0:
				return home_position_au
			var t := clampf(elapsed_ticks / transit_time, 0.0, 1.0)
			return target_position_au.lerp(home_position_au, t)
	return home_position_au

## Returns the direction the engine is thrusting (unit vector, or ZERO if coasting/idle).
## Brachistochrone profile: first half of transit accelerates, second half decelerates.
func get_thrust_direction() -> Vector2:
	match status:
		Status.TRANSIT_TO:
			if transit_time <= 0.0:
				return Vector2.ZERO
			var dir := (target_position_au - home_position_au).normalized()
			var t := clampf(elapsed_ticks / transit_time, 0.0, 1.0)
			return dir if t < 0.5 else -dir
		Status.TRANSIT_HOME:
			if transit_time <= 0.0:
				return Vector2.ZERO
			var dir := (home_position_au - target_position_au).normalized()
			var t := clampf(elapsed_ticks / transit_time, 0.0, 1.0)
			return dir if t < 0.5 else -dir
	return Vector2.ZERO

## Average velocity in AU/tick for the current leg. Not instantaneous — used for delay back-calc.
func get_velocity_au_per_tick() -> Vector2:
	match status:
		Status.TRANSIT_TO:
			if transit_time <= 0.0:
				return Vector2.ZERO
			var dir := (target_position_au - home_position_au).normalized()
			var total_dist := home_position_au.distance_to(target_position_au)
			return dir * (total_dist / transit_time)
		Status.TRANSIT_HOME:
			if transit_time <= 0.0:
				return Vector2.ZERO
			var dir := (home_position_au - target_position_au).normalized()
			var total_dist := target_position_au.distance_to(home_position_au)
			return dir * (total_dist / transit_time)
	return Vector2.ZERO

## Visibility of this ship's fusion exhaust cone from an observer position (in AU).
## Returns 0–1: 0 = invisible (exhaust pointing away), 1 = full-face exhaust cone.
## Ships with no thrust (coasting, mining, idle) return 0.
func get_visibility_from(observer_pos_au: Vector2) -> float:
	var thrust_dir := get_thrust_direction()
	if thrust_dir == Vector2.ZERO:
		return 0.0
	# Fusion exhaust points opposite to thrust
	var exhaust_dir := -thrust_dir
	var ship_to_obs := observer_pos_au - get_position_au()
	if ship_to_obs.length_squared() < 1e-6:
		return 0.5  # Observer co-located — partial visibility
	return (exhaust_dir.dot(ship_to_obs.normalized()) + 1.0) / 2.0
