class_name WaypointLeg
extends Resource

enum WaypointType {
	GRAVITY_ASSIST,  # Flyby planet for delta-v boost
	REFUEL_STOP,     # Stop at colony to refuel
}

@export var position_au: Vector2 = Vector2.ZERO
@export var transit_time: float = 0.0       # time to reach THIS waypoint from the previous one
@export var planet_id: int = -1             # planet index (-1 if not a gravity assist)
@export var waypoint_type: int = WaypointType.GRAVITY_ASSIST
@export var colony_ref: Colony = null       # colony reference (refuel stops only)
@export var fuel_amount: float = 0.0        # fuel to purchase at this stop
@export var fuel_cost: int = 0              # cost of that fuel

static func make(pos: Vector2, time: float, type: int = WaypointType.GRAVITY_ASSIST, pid: int = -1, colony: Colony = null, fuel: float = 0.0, cost: int = 0) -> WaypointLeg:
	var leg := WaypointLeg.new()
	leg.position_au = pos
	leg.transit_time = time
	leg.waypoint_type = type
	leg.planet_id = pid
	leg.colony_ref = colony
	leg.fuel_amount = fuel
	leg.fuel_cost = cost
	return leg

func get_live_position() -> Vector2:
	if waypoint_type == WaypointType.REFUEL_STOP and colony_ref:
		return colony_ref.get_position_au()
	return position_au

func to_dict() -> Dictionary:
	return {
		"position_au": [position_au.x, position_au.y],
		"transit_time": transit_time,
		"planet_id": planet_id,
		"waypoint_type": waypoint_type,
		"colony_name": colony_ref.colony_name if colony_ref else "",
		"fuel_amount": fuel_amount,
		"fuel_cost": fuel_cost,
	}

static func from_dict(d: Dictionary, colonies: Array) -> WaypointLeg:
	var leg := WaypointLeg.new()
	var pos_arr: Array = d.get("position_au", [0.0, 0.0])
	leg.position_au = Vector2(pos_arr[0], pos_arr[1])
	leg.transit_time = float(d.get("transit_time", 0.0))
	leg.planet_id = int(d.get("planet_id", -1))
	leg.waypoint_type = int(d.get("waypoint_type", WaypointType.GRAVITY_ASSIST))
	leg.fuel_amount = float(d.get("fuel_amount", 0.0))
	leg.fuel_cost = int(d.get("fuel_cost", 0))
	var cname: String = d.get("colony_name", "")
	if cname != "":
		for c in colonies:
			if c.colony_name == cname:
				leg.colony_ref = c
				break
	return leg
