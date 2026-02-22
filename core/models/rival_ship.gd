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
