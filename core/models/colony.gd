class_name Colony
extends Resource

@export var colony_name: String = ""
@export var orbit_au: float = 1.0
@export var orbital_angle: float = 0.0  # radians
@export var price_multipliers: Dictionary = {}  # OreType -> float
@export var orbits_earth: bool = false  # if true, orbit_au is distance from Earth (legacy)
@export var parent_planet_index: int = -1  # if >= 0, orbits this planet from CelestialData.PLANETS
@export var has_rescue_ops: bool = false  # Large colonies can dispatch rescue missions

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
	# Moons with tiny orbits (< 0.05 AU) sit at their parent's position
	# to avoid visual jitter on the map
	if parent_planet_index >= 0 and orbit_au < 0.05:
		return CelestialData.get_planet_position_au(parent_planet_index)

	var local_pos := Vector2(cos(orbital_angle), sin(orbital_angle)) * orbit_au

	# Check parent planet first
	if parent_planet_index >= 0:
		var parent_pos := CelestialData.get_planet_position_au(parent_planet_index)
		return parent_pos + local_pos

	# Legacy: orbits_earth flag
	if orbits_earth:
		return CelestialData.get_earth_position_au() + local_pos

	# No parent: orbit sun directly
	return local_pos

func advance_orbit(dt: float) -> void:
	var period := get_orbital_period()
	if period > 0:
		orbital_angle += (TAU / period) * dt
		orbital_angle = fmod(orbital_angle, TAU)

func get_orbital_period() -> float:
	# Kepler's third law: 200,000 base ticks per orbit at 1 AU
	if orbits_earth or parent_planet_index >= 0:
		# Moons orbit parent body: shorter period relative to their local orbit_au
		return maxf(orbit_au * 50000.0, 1000.0)
	return pow(orbit_au, 1.5) * 200000.0
