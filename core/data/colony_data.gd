class_name ColonyData
extends RefCounted

static func get_colonies() -> Array[Colony]:
	var list: Array[Colony] = []
	var O := ResourceTypes.OreType

	# Inner system colonies
	list.append(_make_orbiting("Lunar Base", 2, 0.003, {
		O.IRON: 1.2, O.NICKEL: 1.1, O.PLATINUM: 0.9,
		O.WATER_ICE: 1.5, O.CARBON_ORGANICS: 1.3,
	}, true))

	list.append(_make_orbiting("Mars Colony", 3, 0.002, {
		O.IRON: 0.8, O.NICKEL: 0.9, O.PLATINUM: 1.3,
		O.WATER_ICE: 1.8, O.CARBON_ORGANICS: 1.6,
	}, true))

	# Belt colonies
	list.append(_make("Ceres Station", 2.77, {
		O.IRON: 0.7, O.NICKEL: 0.8, O.PLATINUM: 1.5,
		O.WATER_ICE: 1.4, O.CARBON_ORGANICS: 1.2,
	}, true))

	list.append(_make("Vesta Refinery", 2.36, {
		O.IRON: 0.6, O.NICKEL: 0.7, O.PLATINUM: 1.4,
		O.WATER_ICE: 2.0, O.CARBON_ORGANICS: 1.5,
	}))

	# Outer system colonies
	list.append(_make_orbiting("Europa Lab", 4, 0.004, {
		O.IRON: 1.5, O.NICKEL: 1.4, O.PLATINUM: 2.0,
		O.WATER_ICE: 0.6, O.CARBON_ORGANICS: 1.8,
	}, true))

	list.append(_make_orbiting("Ganymede Port", 4, 0.007, {
		O.IRON: 1.6, O.NICKEL: 1.5, O.PLATINUM: 2.1,
		O.WATER_ICE: 0.7, O.CARBON_ORGANICS: 1.7,
	}, true))

	list.append(_make_orbiting("Titan Outpost", 5, 0.008, {
		O.IRON: 2.0, O.NICKEL: 1.8, O.PLATINUM: 2.5,
		O.WATER_ICE: 0.5, O.CARBON_ORGANICS: 0.7,
	}))

	# Remote colonies
	list.append(_make_orbiting("Callisto Base", 4, 0.012, {
		O.IRON: 1.7, O.NICKEL: 1.6, O.PLATINUM: 2.2,
		O.WATER_ICE: 0.8, O.CARBON_ORGANICS: 1.9,
	}))

	list.append(_make_orbiting("Triton Station", 7, 0.002, {
		O.IRON: 2.5, O.NICKEL: 2.3, O.PLATINUM: 3.0,
		O.WATER_ICE: 0.4, O.CARBON_ORGANICS: 0.6,
	}))

	return list

static func _make(p_name: String, p_au: float, p_multipliers: Dictionary, p_rescue_ops: bool = false) -> Colony:
	var c := Colony.new()
	c.colony_name = p_name
	c.orbit_au = p_au
	c.orbital_angle = randf() * TAU
	c.price_multipliers = p_multipliers
	c.has_rescue_ops = p_rescue_ops
	return c

static func _make_orbiting(p_name: String, parent_planet_idx: int, p_au: float, p_multipliers: Dictionary, p_rescue_ops: bool = false) -> Colony:
	var c := Colony.new()
	c.colony_name = p_name
	c.parent_planet_index = parent_planet_idx
	c.orbit_au = p_au
	c.orbital_angle = randf() * TAU
	c.price_multipliers = p_multipliers
	c.has_rescue_ops = p_rescue_ops
	return c
