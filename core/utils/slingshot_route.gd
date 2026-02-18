class_name SlingshotRoute
extends RefCounted

# Structure for slingshot route option
var route_name: String = ""           # e.g., "Via Mars"
var planet_index: int = -1             # Index in CelestialData.PLANETS
var planet_name: String = ""
var waypoint_pos: Vector2 = Vector2.ZERO  # Current planet position
var total_distance: float = 0.0        # Total AU traveled
var fuel_cost: float = 0.0             # Fuel units
var transit_time: float = 0.0          # Total ticks
var fuel_savings: float = 0.0          # Fuel saved vs direct
var fuel_savings_percent: float = 0.0  # Percentage saved
var time_penalty: float = 0.0          # Extra time vs direct (ticks)
var leg1_distance: float = 0.0         # Start to waypoint
var leg2_distance: float = 0.0         # Waypoint to destination
var leg1_time: float = 0.0             # Ticks for leg 1
var leg2_time: float = 0.0             # Ticks for leg 2
var delta_v_bonus: float = 0.0         # Free velocity from gravity assist
