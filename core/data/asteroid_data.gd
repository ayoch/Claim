class_name AsteroidData
extends Resource

enum BodyType {
	ASTEROID,
	COMET,
	NEO,          # Near-Earth Object
	TROJAN,       # Jupiter Trojans
	CENTAUR,      # Between Jupiter and Neptune
	KBO,          # Kuiper Belt Object
}

const BODY_TYPE_NAMES: Dictionary = {
	BodyType.ASTEROID: "Asteroid",
	BodyType.COMET: "Comet",
	BodyType.NEO: "Near-Earth Object",
	BodyType.TROJAN: "Trojan",
	BodyType.CENTAUR: "Centaur",
	BodyType.KBO: "Kuiper Belt Object",
}

@export var asteroid_name: String = ""
@export var orbit_au: float = 0.0
@export var body_type: BodyType = BodyType.ASTEROID
@export var ore_yields: Dictionary = {} # OreType -> tons per tick per worker
@export var orbital_angle: float = 0.0  # radians, current position on orbit

func get_type_name() -> String:
	return BODY_TYPE_NAMES.get(body_type, "Unknown")

## Kepler's third law: orbital period in game ticks
func get_orbital_period() -> float:
	return pow(orbit_au, 1.5) * 600.0

## Advance orbital position by dt ticks
func advance_orbit(dt: float) -> void:
	var period := get_orbital_period()
	if period > 0:
		orbital_angle += (TAU / period) * dt
		orbital_angle = fmod(orbital_angle, TAU)

## Get current 2D position in AU
func get_position_au() -> Vector2:
	return Vector2(cos(orbital_angle), sin(orbital_angle)) * orbit_au

## Estimate profit for a mission to this body.
## Returns { revenue, wage_cost, profit, transit_time, mining_time, total_time, cargo_breakdown,
##           transit_mode, hohmann_available, hohmann_estimate }
static func estimate_mission(
	asteroid: AsteroidData,
	ship: Ship,
	workers: Array[Worker],
	mining_duration: float = 30.0,
	from_position_au: Vector2 = Vector2(-999, -999),  # Sentinel value
	force_transit_mode: int = -1  # -1 = auto, 0 = brachistochrone, 1 = hohmann
) -> Dictionary:
	# Use ship position if not explicitly specified
	var ship_pos := from_position_au
	if ship_pos.x == -999 and ship_pos.y == -999:
		ship_pos = ship.position_au

	var dist := ship_pos.distance_to(asteroid.get_position_au())

	# Calculate both transit options
	var brach_transit := Brachistochrone.transit_time(dist, ship.get_effective_thrust())
	var hohmann_transit := Brachistochrone.hohmann_time(dist)

	# Determine which mode to use (default to brachistochrone)
	var use_hohmann := false
	if force_transit_mode == 1:
		use_hohmann = true
	elif force_transit_mode == -1:
		# Auto-decide based on fuel availability
		use_hohmann = Brachistochrone.should_use_hohmann(ship, dist, ship.cargo_capacity)

	var transit := hohmann_transit if use_hohmann else brach_transit
	var total_time := transit * 2.0 + mining_duration

	# Calculate total worker skill
	var skill_total := 0.0
	var wage_per_tick := 0.0
	for w in workers:
		skill_total += w.skill
		wage_per_tick += w.wage

	var equip_mult := ship.get_mining_multiplier()

	# Estimate ore mined over mining_duration ticks
	var cargo_breakdown: Dictionary = {}  # OreType -> tons
	var total_mined := 0.0
	for ore_type in asteroid.ore_yields:
		var base_yield: float = asteroid.ore_yields[ore_type]
		var per_tick: float = base_yield * skill_total * equip_mult
		var total_ore: float = per_tick * mining_duration
		total_mined += total_ore
		cargo_breakdown[ore_type] = total_ore

	# Cap to cargo capacity - scale each proportionally
	if total_mined > ship.cargo_capacity and total_mined > 0:
		var scale: float = ship.cargo_capacity / total_mined
		for ore_type in cargo_breakdown:
			cargo_breakdown[ore_type] *= scale
		total_mined = ship.cargo_capacity

	# Calculate revenue using dynamic prices
	var revenue := 0.0
	for ore_type in cargo_breakdown:
		revenue += cargo_breakdown[ore_type] * MarketData.get_ore_price(ore_type)

	# Wage cost covers the full mission duration, prorated from payroll interval
	var payroll_cycles := total_time / 60.0  # PAYROLL_INTERVAL = 60
	var wage_cost := wage_per_tick * payroll_cycles

	# Fuel cost - account for cargo mass difference on outbound vs return
	# Outbound: current cargo (usually 0 for mining)
	var current_cargo_mass := ship.get_cargo_total()
	var fuel_outbound := ship.calc_fuel_for_distance(dist, current_cargo_mass)

	# Return: current cargo + mined ore
	var fuel_return := ship.calc_fuel_for_distance(dist, current_cargo_mass + total_mined)

	var fuel_needed := fuel_outbound + fuel_return

	# Apply Hohmann fuel savings if using that mode
	if use_hohmann:
		fuel_needed *= Brachistochrone.hohmann_fuel_multiplier()

	# Use dynamic fuel pricing based on ship location
	var fuel_price_per_unit := FuelPricing.get_fuel_price_at_location(ship.position_au)
	var fuel_cost := fuel_needed * fuel_price_per_unit

	# Calculate alternate mode estimate (for UI comparison)
	var alt_use_hohmann := not use_hohmann
	var alt_transit := hohmann_transit if alt_use_hohmann else brach_transit
	var alt_total_time := alt_transit * 2.0 + mining_duration
	var alt_fuel := fuel_outbound + fuel_return
	if alt_use_hohmann:
		alt_fuel *= Brachistochrone.hohmann_fuel_multiplier()
	var alt_payroll_cycles := alt_total_time / 60.0
	var alt_wage_cost := wage_per_tick * alt_payroll_cycles
	var alt_fuel_cost := alt_fuel * fuel_price_per_unit  # Use same dynamic pricing
	var alt_profit := revenue - alt_wage_cost - alt_fuel_cost

	# Check if Hohmann is actually viable (has enough fuel)
	var hohmann_fuel := (fuel_outbound + fuel_return) * Brachistochrone.hohmann_fuel_multiplier()
	var hohmann_viable := hohmann_fuel <= ship.fuel

	return {
		"revenue": revenue,
		"wage_cost": wage_cost,
		"fuel_cost": fuel_cost,
		"fuel_needed": fuel_needed,
		"profit": revenue - wage_cost - fuel_cost,
		"transit_time": transit,
		"mining_time": mining_duration,
		"total_time": total_time,
		"cargo_breakdown": cargo_breakdown,
		"cargo_total": minf(total_mined, ship.cargo_capacity),
		"transit_mode": Mission.TransitMode.HOHMANN if use_hohmann else Mission.TransitMode.BRACHISTOCHRONE,
		"hohmann_available": hohmann_viable,
		"alternate_estimate": {
			"transit_time": alt_transit,
			"total_time": alt_total_time,
			"fuel_cost": alt_fuel_cost,
			"fuel_needed": alt_fuel,
			"wage_cost": alt_wage_cost,
			"profit": alt_profit,
			"transit_mode": Mission.TransitMode.HOHMANN if alt_use_hohmann else Mission.TransitMode.BRACHISTOCHRONE,
		}
	}
