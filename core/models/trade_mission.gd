class_name TradeMission
extends Resource

enum Status { TRANSIT_TO_COLONY, SELLING, TRANSIT_BACK, COMPLETED }

@export var status: Status = Status.TRANSIT_TO_COLONY
@export var ship: Ship = null
@export var colony: Colony = null
@export var workers: Array[Worker] = []
@export var cargo: Dictionary = {}       # OreType -> tons (loaded at dispatch)
@export var transit_time: float = 0.0    # one-way transit in ticks
@export var elapsed_ticks: float = 0.0
@export var fuel_per_tick: float = 0.0
@export var revenue: int = 0             # filled on sell at colony

const SELL_DURATION: float = 5.0  # ticks spent at colony selling

func get_progress() -> float:
	match status:
		Status.TRANSIT_TO_COLONY, Status.TRANSIT_BACK:
			return elapsed_ticks / transit_time if transit_time > 0 else 1.0
		Status.SELLING:
			return elapsed_ticks / SELL_DURATION if SELL_DURATION > 0 else 1.0
		Status.COMPLETED:
			return 1.0
	return 0.0

func get_status_text() -> String:
	match status:
		Status.TRANSIT_TO_COLONY:
			return "Trading: en route to %s" % colony.colony_name
		Status.SELLING:
			return "Selling at %s" % colony.colony_name
		Status.TRANSIT_BACK:
			return "Returning from %s" % colony.colony_name
		Status.COMPLETED:
			return "Trade complete at %s" % colony.colony_name
	return "Unknown"
