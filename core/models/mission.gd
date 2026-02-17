class_name Mission
extends Resource

enum Status {
	TRANSIT_OUT,
	MINING,
	TRANSIT_BACK,
	COMPLETED,
}

@export var status: Status = Status.TRANSIT_OUT
@export var ship: Ship = null
@export var workers: Array[Worker] = []
@export var asteroid: AsteroidData = null
@export var transit_time: float = 0.0     # ticks for one-way transit
@export var elapsed_ticks: float = 0.0    # ticks elapsed in current phase
@export var mining_duration: float = 30.0 # ticks to mine before returning

func get_progress() -> float:
	match status:
		Status.TRANSIT_OUT, Status.TRANSIT_BACK:
			return elapsed_ticks / transit_time if transit_time > 0 else 1.0
		Status.MINING:
			return elapsed_ticks / mining_duration if mining_duration > 0 else 1.0
		Status.COMPLETED:
			return 1.0
	return 0.0

func get_status_text() -> String:
	match status:
		Status.TRANSIT_OUT:
			return "In transit to " + asteroid.asteroid_name
		Status.MINING:
			return "Mining at " + asteroid.asteroid_name
		Status.TRANSIT_BACK:
			return "Returning from " + asteroid.asteroid_name
		Status.COMPLETED:
			return "Mission complete"
	return "Unknown"
