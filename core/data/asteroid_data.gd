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
## Returns { revenue, wage_cost, profit, transit_time, mining_time, total_time, cargo_breakdown }
static func estimate_mission(
	asteroid: AsteroidData,
	ship: Ship,
	workers: Array[Worker],
	mining_duration: float = 30.0,
) -> Dictionary:
	var dist := Brachistochrone.distance_to(asteroid)
	var transit := Brachistochrone.transit_time(dist, ship.thrust_g)
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

	# Fuel cost
	var fuel_needed := ship.calc_fuel_for_distance(dist)
	var fuel_cost := fuel_needed * Ship.FUEL_COST_PER_UNIT

	return {
		"revenue": revenue,
		"wage_cost": wage_cost,
		"fuel_cost": fuel_cost,
		"profit": revenue - wage_cost - fuel_cost,
		"transit_time": transit,
		"mining_time": mining_duration,
		"total_time": total_time,
		"cargo_breakdown": cargo_breakdown,
		"cargo_total": minf(total_mined, ship.cargo_capacity),
	}
