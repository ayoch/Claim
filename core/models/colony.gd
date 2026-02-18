class_name Colony
extends Resource

@export var colony_name: String = ""
@export var orbit_au: float = 1.0
@export var orbital_angle: float = 0.0  # radians
@export var price_multipliers: Dictionary = {}  # OreType -> float
@export var orbits_earth: bool = false  # if true, orbit_au is distance from Earth

func get_ore_price(ore_type: ResourceTypes.OreType, market: MarketState) -> float:
	var base_market_price: float = market.get_price(ore_type)
	var mult: float = price_multipliers.get(ore_type, 1.0)

	# Distance from Earth increases scarcity and price
	var earth_pos := CelestialData.get_earth_position_au()
	var dist_from_earth := get_position_au().distance_to(earth_pos)
	# Price increases by 20% per AU of distance
	var scarcity_multiplier := 1.0 + (dist_from_earth * 0.2)

	# Apply market event modifiers
	var event_multiplier := 1.0
	for event in GameState.active_market_events:
		event_multiplier *= event.get_price_modifier(ore_type, self)

	return base_market_price * mult * scarcity_multiplier * event_multiplier

func get_position_au() -> Vector2:
	var local_pos := Vector2(cos(orbital_angle), sin(orbital_angle)) * orbit_au
	if orbits_earth:
		return CelestialData.get_earth_position_au() + local_pos
	return local_pos

func advance_orbit(dt: float) -> void:
	var period := get_orbital_period()
	if period > 0:
		orbital_angle += (TAU / period) * dt
		orbital_angle = fmod(orbital_angle, TAU)

func get_orbital_period() -> float:
	# Kepler's third law approximation for game ticks
	# For Earth-orbiting bodies, use a faster period so they visibly orbit
	if orbits_earth:
		return maxf(orbit_au * 200.0, 5.0)  # Much faster for nearby bodies
	return pow(orbit_au, 1.5) * 600.0
