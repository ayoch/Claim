class_name ColonyData
extends RefCounted

static func get_colonies() -> Array[Colony]:
	var list: Array[Colony] = []
	var O := ResourceTypes.OreType

	list.append(_make_lunar("Lunar Base", 0.003, {
		O.IRON: 1.2, O.NICKEL: 1.1, O.PLATINUM: 0.9,
		O.WATER_ICE: 1.5, O.CARBON_ORGANICS: 1.3,
	}))

	list.append(_make("Mars Colony", 1.52, {
		O.IRON: 0.8, O.NICKEL: 0.9, O.PLATINUM: 1.3,
		O.WATER_ICE: 1.8, O.CARBON_ORGANICS: 1.6,
	}))

	list.append(_make("Ceres Station", 2.77, {
		O.IRON: 0.7, O.NICKEL: 0.8, O.PLATINUM: 1.5,
		O.WATER_ICE: 1.4, O.CARBON_ORGANICS: 1.2,
	}))

	list.append(_make("Europa Lab", 5.20, {
		O.IRON: 1.5, O.NICKEL: 1.4, O.PLATINUM: 2.0,
		O.WATER_ICE: 0.6, O.CARBON_ORGANICS: 1.8,
	}))

	list.append(_make("Titan Outpost", 9.54, {
		O.IRON: 2.0, O.NICKEL: 1.8, O.PLATINUM: 2.5,
		O.WATER_ICE: 0.5, O.CARBON_ORGANICS: 0.7,
	}))

	return list

static func _make(p_name: String, p_au: float, p_multipliers: Dictionary) -> Colony:
	var c := Colony.new()
	c.colony_name = p_name
	c.orbit_au = p_au
	c.orbital_angle = randf() * TAU
	c.price_multipliers = p_multipliers
	return c

static func _make_lunar(p_name: String, p_au: float, p_multipliers: Dictionary) -> Colony:
	var c := Colony.new()
	c.colony_name = p_name
	c.orbit_au = p_au
	c.orbital_angle = randf() * TAU
	c.price_multipliers = p_multipliers
	c.orbits_earth = true
	return c
