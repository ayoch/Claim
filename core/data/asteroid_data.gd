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

# Reserve depletion system
@export var estimated_mass_kg: float = 0.0  # Total asteroid mass
@export var composition_pct: Dictionary = {}  # Material -> percentage (e.g. {"iron": 25.0, "water_ice": 15.0})
@export var reserves: Dictionary = {}  # Material -> remaining tonnes
@export var original_reserves: Dictionary = {}  # Material -> original tonnes (for UI display)

func get_type_name() -> String:
	return BODY_TYPE_NAMES.get(body_type, "Unknown")

## Get reserve status for a specific ore type
## Returns {remaining: float, original: float, pct: float, status_color: Color}
func get_reserve_status(ore_type: String) -> Dictionary:
	if ore_type not in reserves:
		return {"remaining": 0.0, "original": 0.0, "pct": 0.0, "status_color": Color.GRAY}

	var remaining: float = reserves[ore_type]
	var original: float = original_reserves.get(ore_type, 0.0)
	var pct: float = (remaining / original * 100.0) if original > 0.0 else 0.0

	# Color-code by depletion level
	var color := Color.GREEN
	if pct < 10.0:
		color = Color.RED
	elif pct < 25.0:
		color = Color.ORANGE
	elif pct < 75.0:
		color = Color.YELLOW

	return {
		"remaining": remaining,
		"original": original,
		"pct": pct,
		"status_color": color
	}

## Check if an ore type is depleted (less than 1 tonne remaining)
func is_depleted(ore_type: String) -> bool:
	return reserves.get(ore_type, 0.0) < 1.0

func get_max_mining_slots() -> int:
	match body_type:
		BodyType.NEO: return 3
		BodyType.ASTEROID: return 6
		BodyType.COMET: return 2
		BodyType.TROJAN: return 8
		BodyType.CENTAUR: return 5
		BodyType.KBO: return 10
	return 4

## Kepler's third law: orbital period in real seconds
## T = a^1.5 years for bodies orbiting the Sun
func get_orbital_period() -> float:
	const SECONDS_PER_YEAR := 31557600.0  # 365.25 days
	var period_years: float = pow(orbit_au, 1.5)
	return period_years * SECONDS_PER_YEAR

## Advance orbital position by dt ticks
func advance_orbit(dt: float) -> void:
	var period := get_orbital_period()
	if period > 0:
		orbital_angle += (TAU / period) * dt
		orbital_angle = fmod(orbital_angle, TAU)

## Get current 2D position in AU
func get_position_au() -> Vector2:
	return Vector2(cos(orbital_angle), sin(orbital_angle)) * orbit_au

## Predict position at a future time (current time + dt_ticks)
func get_position_at_time(dt_ticks: float) -> Vector2:
	var period := get_orbital_period()
	if period <= 0:
		return get_position_au()
	var future_angle := orbital_angle + (TAU / period) * dt_ticks
	return Vector2(cos(future_angle), sin(future_angle)) * orbit_au

## Estimate profit for a mission to this body.
## Returns { revenue, wage_cost, profit, transit_time, mining_time, total_time, cargo_breakdown,
##           transit_mode, hohmann_available, hohmann_estimate }
static func estimate_mission(
	asteroid: AsteroidData,
	ship: Ship,
	workers: Array[Worker],
	mining_duration: float = -1.0,  # -1 = auto-calculate to fill cargo
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
		# Auto-decide based on fuel capacity (ship is always refueled before dispatch)
		var fuel_cap := ship.get_effective_fuel_capacity()
		var fuel_brach := ship.calc_fuel_for_distance(dist, ship.get_cargo_total()) \
			+ ship.calc_fuel_for_distance(dist, ship.cargo_capacity)
		if fuel_brach <= fuel_cap:
			use_hohmann = false
		else:
			use_hohmann = (fuel_brach * Brachistochrone.hohmann_fuel_multiplier()) <= fuel_cap

	var transit := hohmann_transit if use_hohmann else brach_transit

	# Calculate total mining skill and best pilot skill
	var skill_total := 0.0
	var best_pilot := 0.0
	var wage_per_tick := 0.0
	for w in workers:
		skill_total += w.mining_skill
		if w.pilot_skill > best_pilot:
			best_pilot = w.pilot_skill
		wage_per_tick += w.wage
	if skill_total < 0.1:
		skill_total = 0.1  # Minimum so crew can still mine (slowly)

	# Apply pilot skill modifier to transit time
	var pilot_factor := 1.15 - (best_pilot * 0.2)  # 0.0 = 1.15x slower, 1.0 = 0.95x, 1.5 = 0.85x
	brach_transit *= pilot_factor
	hohmann_transit *= pilot_factor
	transit = hohmann_transit if use_hohmann else brach_transit

	var equip_mult := ship.get_mining_multiplier()

	# Calculate mining rate (tons per tick across all ore types)
	var mining_rate: float = Simulation.BASE_MINING_RATE
	var total_yield_per_tick := 0.0
	for ore_type in asteroid.ore_yields:
		var base_yield: float = asteroid.ore_yields[ore_type]
		total_yield_per_tick += base_yield * skill_total * equip_mult * mining_rate

	# Auto-calculate mining duration: time to fill cargo hold
	if mining_duration < 0:
		if total_yield_per_tick > 0:
			mining_duration = ship.cargo_capacity / total_yield_per_tick
		else:
			mining_duration = 86400.0  # Fallback: 1 day

	var total_time := transit * 2.0 + mining_duration

	# Estimate ore mined over mining_duration ticks
	var cargo_breakdown: Dictionary = {}  # OreType -> tons
	var total_mined := 0.0
	for ore_type in asteroid.ore_yields:
		var base_yield: float = asteroid.ore_yields[ore_type]
		var per_tick: float = base_yield * skill_total * equip_mult * mining_rate
		var total_ore: float = per_tick * mining_duration
		total_mined += total_ore
		cargo_breakdown[ore_type] = total_ore

	# Cap to cargo capacity - scale each proportionally
	if total_mined > ship.cargo_capacity and total_mined > 0:
		var scale_factor: float = ship.cargo_capacity / total_mined
		for ore_type in cargo_breakdown:
			cargo_breakdown[ore_type] *= scale_factor
		total_mined = ship.cargo_capacity

	# Calculate revenue using dynamic prices
	var revenue := 0.0
	for ore_type in cargo_breakdown:
		revenue += cargo_breakdown[ore_type] * MarketData.get_ore_price(ore_type)

	# Wage cost covers the full mission duration, prorated from payroll interval
	var payroll_cycles: float = total_time / Simulation.PAYROLL_INTERVAL
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
	var alt_payroll_cycles: float = alt_total_time / Simulation.PAYROLL_INTERVAL
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
