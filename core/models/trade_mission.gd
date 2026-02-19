class_name TradeMission
extends Resource

enum Status { TRANSIT_TO_COLONY, SELLING, IDLE_AT_COLONY, TRANSIT_BACK, COMPLETED }

enum TransitMode {
	BRACHISTOCHRONE,  # Fast, expensive fuel
	HOHMANN,          # Slow, economical fuel
}

@export var status: Status = Status.TRANSIT_TO_COLONY
@export var ship: Ship = null
@export var colony: Colony = null
@export var workers: Array[Worker] = []
@export var cargo: Dictionary = {}       # OreType -> tons (loaded at dispatch)
@export var transit_time: float = 0.0    # one-way transit in ticks
@export var elapsed_ticks: float = 0.0
@export var fuel_per_tick: float = 0.0
@export var revenue: int = 0             # filled on sell at colony
@export var origin_position_au: Vector2 = Vector2.ZERO   # where ship departed from
@export var return_position_au: Vector2 = Vector2.ZERO    # where ship returns to
@export var transit_mode: TransitMode = TransitMode.BRACHISTOCHRONE  # orbit type

# Gravity assist / multi-leg journey support
@export var outbound_waypoints: Array[Vector2] = []
@export var outbound_waypoint_planet_ids: Array[int] = []
@export var outbound_leg_times: Array[float] = []
@export var outbound_waypoint_index: int = 0
@export var return_waypoints: Array[Vector2] = []
@export var return_waypoint_planet_ids: Array[int] = []
@export var return_leg_times: Array[float] = []
@export var return_waypoint_index: int = 0

const SELL_DURATION: float = 5.0  # ticks spent at colony selling

func get_current_phase_duration() -> float:
	match status:
		Status.TRANSIT_TO_COLONY:
			if outbound_leg_times.size() > outbound_waypoint_index:
				return outbound_leg_times[outbound_waypoint_index]
			return transit_time
		Status.TRANSIT_BACK:
			if return_leg_times.size() > return_waypoint_index:
				return return_leg_times[return_waypoint_index]
			return transit_time
		Status.SELLING:
			return SELL_DURATION
		_:
			return 0.0

func get_progress() -> float:
	var duration := get_current_phase_duration()
	if duration > 0:
		return elapsed_ticks / duration
	match status:
		Status.IDLE_AT_COLONY, Status.COMPLETED:
			return 1.0
		_:
			return 0.0

func get_status_text() -> String:
	var mode_suffix := " (Hohmann)" if transit_mode == TransitMode.HOHMANN else ""
	var slingshot_suffix := ""

	if status == Status.TRANSIT_TO_COLONY and outbound_waypoint_planet_ids.size() > 0:
		slingshot_suffix = " [Slingshot]"
	elif status == Status.TRANSIT_BACK and return_waypoint_planet_ids.size() > 0:
		slingshot_suffix = " [Slingshot]"

	match status:
		Status.TRANSIT_TO_COLONY:
			return "Trading: en route to %s%s%s" % [colony.colony_name, mode_suffix, slingshot_suffix]
		Status.SELLING:
			return "Selling at %s" % colony.colony_name
		Status.IDLE_AT_COLONY:
			return "Idle at %s" % colony.colony_name
		Status.TRANSIT_BACK:
			return "Returning from %s%s%s" % [colony.colony_name, mode_suffix, slingshot_suffix]
		Status.COMPLETED:
			return "Trade complete at %s" % colony.colony_name
	return "Unknown"

func get_current_leg_start_pos() -> Vector2:
	match status:
		Status.TRANSIT_TO_COLONY:
			if outbound_waypoint_index == 0:
				return origin_position_au
			elif outbound_waypoint_index > 0 and outbound_waypoint_index <= outbound_waypoints.size():
				return outbound_waypoints[outbound_waypoint_index - 1]
			return origin_position_au
		Status.TRANSIT_BACK:
			if return_waypoint_index == 0:
				return colony.get_position_au() if colony else origin_position_au
			elif return_waypoint_index > 0 and return_waypoint_index <= return_waypoints.size():
				return return_waypoints[return_waypoint_index - 1]
			return colony.get_position_au() if colony else origin_position_au
		_:
			return origin_position_au

func get_current_leg_end_pos() -> Vector2:
	match status:
		Status.TRANSIT_TO_COLONY:
			if outbound_waypoint_index < outbound_waypoints.size():
				return outbound_waypoints[outbound_waypoint_index]
			else:
				return colony.get_position_au() if colony else origin_position_au
		Status.TRANSIT_BACK:
			if return_waypoint_index < return_waypoints.size():
				return return_waypoints[return_waypoint_index]
			else:
				return return_position_au
		_:
			return origin_position_au
