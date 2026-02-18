class_name CelestialData
extends RefCounted

const EARTH_ORBIT_AU: float = 1.0
const AU_TO_METERS: float = 1.496e11

# Planet data: [name, orbit_au, color_r, color_g, color_b, radius_px]
const PLANETS: Array[Dictionary] = [
	{"name": "Mercury", "orbit_au": 0.39, "color": Color(0.7, 0.7, 0.6), "radius": 5.0},
	{"name": "Venus",   "orbit_au": 0.72, "color": Color(0.9, 0.8, 0.5), "radius": 6.0},
	{"name": "Earth",   "orbit_au": 1.00, "color": Color(0.2, 0.5, 1.0), "radius": 7.0},
	{"name": "Mars",    "orbit_au": 1.52, "color": Color(0.9, 0.4, 0.2), "radius": 6.0},
	{"name": "Jupiter", "orbit_au": 5.20, "color": Color(0.8, 0.7, 0.5), "radius": 12.0},
	{"name": "Saturn",  "orbit_au": 9.54, "color": Color(0.9, 0.8, 0.6), "radius": 10.0},
	{"name": "Uranus",  "orbit_au": 19.19, "color": Color(0.5, 0.8, 0.9), "radius": 8.0},
	{"name": "Neptune", "orbit_au": 30.07, "color": Color(0.3, 0.4, 0.9), "radius": 8.0},
]

# Keplerian ephemeris — computes positions from game time
static var ephemeris: EphemerisData = null
static var _initialized: bool = false

static func _ensure_init() -> void:
	if not _initialized:
		_initialized = true
		ephemeris = EphemerisData.new()
		ephemeris.initialize()

static func get_earth_position_au() -> Vector2:
	_ensure_init()
	return ephemeris.get_position("Earth")

static func get_planet_position_au(index: int) -> Vector2:
	_ensure_init()
	if index < 0 or index >= PLANETS.size():
		return Vector2.ZERO
	var planet_name: String = PLANETS[index]["name"]
	return ephemeris.get_position(planet_name)

static func advance_planets(_dt: float) -> void:
	# Positions are computed from GameState.total_ticks in EphemerisData
	# No explicit advancing needed — just ensure init
	_ensure_init()

# Legacy compatibility
static func advance_earth(_dt: float) -> void:
	_ensure_init()

static func _make(
	p_name: String,
	p_au: float,
	p_type: AsteroidData.BodyType,
	p_yields: Dictionary,
) -> AsteroidData:
	var a := AsteroidData.new()
	a.asteroid_name = p_name
	a.orbit_au = p_au
	a.body_type = p_type
	a.ore_yields = p_yields
	a.orbital_angle = randf() * TAU  # Random initial position
	return a

static func get_asteroids() -> Array[AsteroidData]:
	var list: Array[AsteroidData] = []
	var O := ResourceTypes.OreType
	var T := AsteroidData.BodyType

	# ═══════════════════════════════════════════════════════════════
	#  NEAR-EARTH OBJECTS (NEOs)
	# ═══════════════════════════════════════════════════════════════

	list.append(_make("Bennu", 1.26, T.NEO, {
		O.CARBON_ORGANICS: 2.5, O.WATER_ICE: 1.5, O.PLATINUM: 0.5,
	}))
	list.append(_make("Ryugu", 1.19, T.NEO, {
		O.CARBON_ORGANICS: 2.8, O.WATER_ICE: 1.2, O.NICKEL: 0.4,
	}))
	list.append(_make("Itokawa", 1.32, T.NEO, {
		O.IRON: 2.0, O.NICKEL: 1.0,
	}))
	list.append(_make("Apophis", 0.92, T.NEO, {
		O.IRON: 1.8, O.NICKEL: 1.5, O.PLATINUM: 0.3,
	}))
	list.append(_make("Eros", 1.46, T.NEO, {
		O.IRON: 3.5, O.NICKEL: 1.8, O.PLATINUM: 0.2,
	}))
	list.append(_make("Didymos", 1.64, T.NEO, {
		O.IRON: 2.2, O.NICKEL: 0.8,
	}))
	list.append(_make("Nereus", 1.49, T.NEO, {
		O.IRON: 1.5, O.PLATINUM: 0.8,
	}))
	list.append(_make("2011 UW158", 1.62, T.NEO, {
		O.PLATINUM: 1.5, O.NICKEL: 1.2, O.IRON: 1.0,
	}))
	list.append(_make("Anteros", 1.43, T.NEO, {
		O.IRON: 2.0, O.NICKEL: 0.6,
	}))
	list.append(_make("1999 RQ36", 1.13, T.NEO, {
		O.CARBON_ORGANICS: 1.8, O.WATER_ICE: 2.0,
	}))
	list.append(_make("2008 EV5", 0.96, T.NEO, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 2.5,
	}))
	list.append(_make("Toutatis", 2.51, T.NEO, {
		O.IRON: 2.5, O.NICKEL: 1.0, O.PLATINUM: 0.1,
	}))
	list.append(_make("Geographos", 1.24, T.NEO, {
		O.IRON: 2.8, O.NICKEL: 0.8,
	}))
	list.append(_make("Icarus", 1.08, T.NEO, {
		O.IRON: 1.5, O.NICKEL: 0.5,
	}))
	list.append(_make("Apollo", 1.47, T.NEO, {
		O.IRON: 2.0, O.NICKEL: 1.2,
	}))
	list.append(_make("Amor", 1.92, T.NEO, {
		O.IRON: 1.8, O.NICKEL: 0.6, O.CARBON_ORGANICS: 0.5,
	}))
	list.append(_make("Aten", 0.97, T.NEO, {
		O.IRON: 1.5, O.PLATINUM: 0.4,
	}))
	list.append(_make("Cruithne", 1.00, T.NEO, {
		O.IRON: 1.2, O.NICKEL: 0.8, O.PLATINUM: 0.2,
	}))
	list.append(_make("Hathor", 0.84, T.NEO, {
		O.IRON: 1.0, O.NICKEL: 0.4,
	}))
	list.append(_make("Castalia", 1.06, T.NEO, {
		O.IRON: 1.8, O.NICKEL: 0.5,
	}))
	list.append(_make("Toro", 1.37, T.NEO, {
		O.IRON: 2.2, O.NICKEL: 0.7,
	}))
	list.append(_make("Midas", 1.78, T.NEO, {
		O.IRON: 1.5, O.PLATINUM: 0.6, O.NICKEL: 0.3,
	}))
	list.append(_make("Khufu", 0.99, T.NEO, {
		O.IRON: 1.6, O.NICKEL: 0.9,
	}))
	list.append(_make("2001 CC21", 1.03, T.NEO, {
		O.IRON: 1.4, O.NICKEL: 0.5, O.PLATINUM: 0.3,
	}))
	list.append(_make("2002 AT4", 1.05, T.NEO, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.0,
	}))
	list.append(_make("Phaethon", 1.27, T.NEO, {
		O.IRON: 1.0, O.CARBON_ORGANICS: 1.5, O.NICKEL: 0.3,
	}))
	list.append(_make("Wilson-Harrington", 2.64, T.NEO, {
		O.CARBON_ORGANICS: 2.2, O.WATER_ICE: 1.8,
	}))
	list.append(_make("2000 SG344", 0.98, T.NEO, {
		O.IRON: 0.8, O.NICKEL: 0.4, O.PLATINUM: 0.2,
	}))
	list.append(_make("2009 BD", 1.01, T.NEO, {
		O.IRON: 0.6, O.NICKEL: 0.3,
	}))
	list.append(_make("2006 RH120", 1.03, T.NEO, {
		O.IRON: 0.5, O.NICKEL: 0.2,
	}))
	list.append(_make("3554 Amun", 0.97, T.NEO, {
		O.IRON: 4.0, O.NICKEL: 3.0, O.PLATINUM: 1.5,
	}))
	list.append(_make("1986 DA", 2.81, T.NEO, {
		O.IRON: 4.5, O.NICKEL: 3.5, O.PLATINUM: 2.0,
	}))
	list.append(_make("2011 AG5", 1.43, T.NEO, {
		O.IRON: 1.2, O.NICKEL: 0.6, O.PLATINUM: 0.3,
	}))
	list.append(_make("2001 SN263", 1.99, T.NEO, {
		O.IRON: 2.5, O.NICKEL: 1.5, O.CARBON_ORGANICS: 0.8,
	}))

	# ═══════════════════════════════════════════════════════════════
	#  MARS TROJANS (~1.52 AU, L5 point)
	# ═══════════════════════════════════════════════════════════════

	list.append(_make("5261 Eureka", 1.52, T.ASTEROID, {
		O.IRON: 2.0, O.NICKEL: 1.5, O.PLATINUM: 0.4,
	}))

	# ═══════════════════════════════════════════════════════════════
	#  MAIN BELT – INNER (2.0-2.5 AU)
	# ═══════════════════════════════════════════════════════════════

	list.append(_make("Ceres", 2.77, T.ASTEROID, {
		O.WATER_ICE: 4.0, O.CARBON_ORGANICS: 2.5, O.IRON: 1.0, O.NICKEL: 0.5,
	}))
	list.append(_make("Vesta", 2.36, T.ASTEROID, {
		O.IRON: 4.0, O.NICKEL: 2.0,
	}))
	list.append(_make("Flora", 2.20, T.ASTEROID, {
		O.IRON: 2.5, O.NICKEL: 1.0,
	}))
	list.append(_make("Massalia", 2.41, T.ASTEROID, {
		O.IRON: 2.0, O.NICKEL: 0.8,
	}))
	list.append(_make("Nysa", 2.42, T.ASTEROID, {
		O.IRON: 3.2, O.PLATINUM: 0.3,
	}))
	list.append(_make("Lutetia", 2.44, T.ASTEROID, {
		O.IRON: 2.8, O.NICKEL: 1.8, O.CARBON_ORGANICS: 0.5,
	}))
	list.append(_make("Hebe", 2.43, T.ASTEROID, {
		O.IRON: 3.5, O.NICKEL: 1.2,
	}))
	list.append(_make("Melpomene", 2.30, T.ASTEROID, {
		O.IRON: 2.0, O.NICKEL: 0.5, O.PLATINUM: 0.2,
	}))
	list.append(_make("Eunomia", 2.64, T.ASTEROID, {
		O.IRON: 3.0, O.NICKEL: 2.2,
	}))
	list.append(_make("Iris", 2.39, T.ASTEROID, {
		O.IRON: 2.8, O.NICKEL: 1.0,
	}))
	list.append(_make("Metis", 2.39, T.ASTEROID, {
		O.IRON: 2.5, O.NICKEL: 0.8, O.PLATINUM: 0.1,
	}))
	list.append(_make("Astraea", 2.58, T.ASTEROID, {
		O.IRON: 2.2, O.NICKEL: 0.6,
	}))
	list.append(_make("Victoria", 2.33, T.ASTEROID, {
		O.IRON: 2.0, O.NICKEL: 0.5,
	}))
	list.append(_make("Egeria", 2.58, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.5, O.IRON: 0.5,
	}))
	list.append(_make("Fortuna", 2.44, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.5, O.WATER_ICE: 1.0,
	}))
	list.append(_make("Amphitrite", 2.55, T.ASTEROID, {
		O.IRON: 2.8, O.NICKEL: 1.5,
	}))
	list.append(_make("Kalliope", 2.91, T.ASTEROID, {
		O.IRON: 3.0, O.NICKEL: 2.0, O.PLATINUM: 0.4,
	}))
	list.append(_make("Laetitia", 2.77, T.ASTEROID, {
		O.IRON: 2.2, O.NICKEL: 0.8,
	}))
	list.append(_make("Kleopatra", 2.79, T.ASTEROID, {
		O.IRON: 3.5, O.NICKEL: 2.5, O.PLATINUM: 0.6,
	}))
	list.append(_make("Daphne", 2.76, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.IRON: 1.0,
	}))
	list.append(_make("Eugenia", 2.72, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.8, O.IRON: 0.5, O.WATER_ICE: 0.8,
	}))
	list.append(_make("Hermione", 3.44, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.2, O.IRON: 0.6,
	}))
	list.append(_make("Ariadne", 2.20, T.ASTEROID, {
		O.IRON: 2.0, O.NICKEL: 0.5,
	}))
	list.append(_make("Thyra", 2.38, T.ASTEROID, {
		O.IRON: 2.5, O.NICKEL: 0.8,
	}))
	list.append(_make("Angelina", 2.68, T.ASTEROID, {
		O.IRON: 3.0, O.PLATINUM: 0.5,
	}))
	list.append(_make("Hungaria", 1.94, T.ASTEROID, {
		O.IRON: 2.0, O.PLATINUM: 0.3,
	}))
	list.append(_make("Phocaea", 2.40, T.ASTEROID, {
		O.IRON: 2.2, O.NICKEL: 0.6,
	}))
	list.append(_make("Agnia", 2.78, T.ASTEROID, {
		O.IRON: 1.8, O.NICKEL: 0.5,
	}))
	list.append(_make("Gefion", 2.78, T.ASTEROID, {
		O.IRON: 2.0, O.NICKEL: 0.7,
	}))
	list.append(_make("Maria", 2.55, T.ASTEROID, {
		O.IRON: 2.5, O.NICKEL: 1.0,
	}))
	list.append(_make("Adeona", 2.67, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.2,
	}))
	list.append(_make("Elvira", 2.62, T.ASTEROID, {
		O.IRON: 1.5, O.NICKEL: 0.5,
	}))
	list.append(_make("Concordia", 2.70, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.8, O.IRON: 0.5,
	}))
	list.append(_make("Echo", 2.39, T.ASTEROID, {
		O.IRON: 2.0, O.NICKEL: 0.8,
	}))
	list.append(_make("Tercidina", 2.33, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.2, O.WATER_ICE: 1.0,
	}))
	list.append(_make("Nemesis", 2.75, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.IRON: 0.8,
	}))
	list.append(_make("Ausonia", 2.39, T.ASTEROID, {
		O.IRON: 2.5, O.NICKEL: 1.0, O.PLATINUM: 0.1,
	}))

	# ═══════════════════════════════════════════════════════════════
	#  MAIN BELT – MIDDLE (2.5-2.82 AU, Kirkwood gaps)
	# ═══════════════════════════════════════════════════════════════

	list.append(_make("Pallas", 2.77, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.IRON: 1.5, O.WATER_ICE: 1.0,
	}))
	list.append(_make("Juno", 2.67, T.ASTEROID, {
		O.IRON: 3.0, O.NICKEL: 1.5,
	}))
	list.append(_make("Bamberga", 2.68, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 2.0, O.IRON: 0.5,
	}))
	list.append(_make("Thisbe", 2.77, T.ASTEROID, {
		O.IRON: 1.5, O.NICKEL: 1.0, O.CARBON_ORGANICS: 1.0,
	}))
	list.append(_make("Herculina", 2.77, T.ASTEROID, {
		O.IRON: 2.5, O.NICKEL: 1.0,
	}))
	list.append(_make("Alauda", 3.19, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.5, O.WATER_ICE: 1.5,
	}))
	list.append(_make("Bertha", 3.19, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.8, O.WATER_ICE: 1.2,
	}))
	list.append(_make("Loreley", 3.13, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.IRON: 0.5,
	}))
	list.append(_make("Winchester", 2.99, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.5, O.WATER_ICE: 1.0,
	}))
	list.append(_make("Lachesis", 3.12, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.2, O.WATER_ICE: 0.8,
	}))

	# ═══════════════════════════════════════════════════════════════
	#  MAIN BELT – OUTER (2.82-3.3 AU)
	# ═══════════════════════════════════════════════════════════════

	list.append(_make("Psyche", 2.92, T.ASTEROID, {
		O.IRON: 3.0, O.NICKEL: 3.5, O.PLATINUM: 2.0,
	}))
	list.append(_make("Hygiea", 3.14, T.ASTEROID, {
		O.CARBON_ORGANICS: 3.0, O.WATER_ICE: 2.5, O.NICKEL: 1.0,
	}))
	list.append(_make("Euphrosyne", 3.15, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.8, O.WATER_ICE: 1.8,
	}))
	list.append(_make("Themis", 3.13, T.ASTEROID, {
		O.WATER_ICE: 3.5, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("Davida", 3.17, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.5, O.IRON: 1.5, O.WATER_ICE: 1.0,
	}))
	list.append(_make("Interamnia", 3.06, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.8, O.IRON: 1.2, O.WATER_ICE: 1.5,
	}))
	list.append(_make("Europa (belt)", 3.10, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.2, O.IRON: 0.8,
	}))
	list.append(_make("Cybele", 3.43, T.ASTEROID, {
		O.WATER_ICE: 2.0, O.CARBON_ORGANICS: 2.5,
	}))
	list.append(_make("Sylvia", 3.49, T.ASTEROID, {
		O.IRON: 1.0, O.CARBON_ORGANICS: 1.5, O.WATER_ICE: 1.5,
	}))
	list.append(_make("Doris", 3.11, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.5, O.WATER_ICE: 2.5,
	}))
	list.append(_make("Diotima", 3.07, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.IRON: 0.8,
	}))
	list.append(_make("Camilla", 3.49, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.5, O.WATER_ICE: 1.5, O.IRON: 0.3,
	}))
	list.append(_make("Patientia", 3.06, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.8,
	}))
	list.append(_make("Palma", 3.15, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.8, O.WATER_ICE: 1.2,
	}))
	list.append(_make("Nemausa", 2.37, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.5, O.WATER_ICE: 1.5,
	}))
	list.append(_make("Ursula", 3.13, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.0,
	}))
	list.append(_make("Aurora", 3.16, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.5, O.IRON: 0.8, O.WATER_ICE: 0.5,
	}))
	list.append(_make("Elektra", 3.12, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.2, O.WATER_ICE: 1.0,
	}))
	list.append(_make("Elpis", 2.71, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.5,
	}))
	list.append(_make("Nuwa", 2.98, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.8, O.WATER_ICE: 1.0,
	}))
	list.append(_make("Dembowska", 2.92, T.ASTEROID, {
		O.IRON: 2.0, O.NICKEL: 0.5,
	}))
	list.append(_make("Juewa", 2.78, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.5, O.IRON: 0.5,
	}))
	list.append(_make("Prokne", 2.62, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.0,
	}))
	list.append(_make("Berbericia", 2.93, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.2, O.WATER_ICE: 0.8,
	}))
	list.append(_make("Pompeja", 2.74, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.5, O.WATER_ICE: 1.0,
	}))
	list.append(_make("Lumen", 2.67, T.ASTEROID, {
		O.IRON: 1.5, O.NICKEL: 0.5,
	}))
	list.append(_make("Germania", 3.05, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.8, O.WATER_ICE: 0.8,
	}))
	list.append(_make("Adorea", 3.09, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.5, O.WATER_ICE: 1.2,
	}))
	list.append(_make("Leukothea", 2.99, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 0.5,
	}))
	list.append(_make("Hispania", 2.84, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.2, O.WATER_ICE: 1.0,
	}))
	list.append(_make("Freia", 3.41, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 2.0,
	}))
	# ── Additional M-type metallic asteroids (high value) ────────

	list.append(_make("Mancunia", 3.19, T.ASTEROID, {
		O.IRON: 2.5, O.NICKEL: 1.8, O.PLATINUM: 0.3,
	}))
	list.append(_make("Zwetana", 2.57, T.ASTEROID, {
		O.IRON: 2.8, O.NICKEL: 1.5, O.PLATINUM: 0.2,
	}))
	list.append(_make("Holda", 2.73, T.ASTEROID, {
		O.IRON: 2.5, O.NICKEL: 1.2, O.PLATINUM: 0.3,
	}))
	list.append(_make("Lydia", 2.73, T.ASTEROID, {
		O.IRON: 2.2, O.NICKEL: 1.0, O.PLATINUM: 0.2,
	}))
	list.append(_make("Fredegundis", 2.57, T.ASTEROID, {
		O.IRON: 2.0, O.NICKEL: 1.0, O.PLATINUM: 0.2,
	}))
	list.append(_make("Antigone", 2.87, T.ASTEROID, {
		O.IRON: 2.8, O.NICKEL: 1.5, O.PLATINUM: 0.4,
	}))

	# ═══════════════════════════════════════════════════════════════
	#  HILDAS (~3.9-4.1 AU, 3:2 resonance with Jupiter)
	# ═══════════════════════════════════════════════════════════════

	list.append(_make("153 Hilda", 3.97, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.5, O.WATER_ICE: 2.0,
	}))
	list.append(_make("334 Chicago", 3.89, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.8, O.WATER_ICE: 1.5, O.IRON: 0.5,
	}))
	list.append(_make("1269 Rollandia", 3.93, T.ASTEROID, {
		O.WATER_ICE: 3.0, O.CARBON_ORGANICS: 1.0,
	}))
	list.append(_make("190 Ismene", 3.98, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.5,
	}))
	list.append(_make("748 Simeisa", 3.94, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.5, O.WATER_ICE: 1.8,
	}))
	list.append(_make("1162 Larissa", 3.93, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.2, O.WATER_ICE: 1.0,
	}))
	list.append(_make("1180 Rita", 3.99, T.ASTEROID, {
		O.WATER_ICE: 2.5, O.CARBON_ORGANICS: 1.5,
	}))
	list.append(_make("1748 Mauderli", 3.96, T.ASTEROID, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.2,
	}))
	list.append(_make("958 Asplinda", 3.91, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.8, O.WATER_ICE: 2.0,
	}))
	list.append(_make("1256 Normannia", 3.95, T.ASTEROID, {
		O.CARBON_ORGANICS: 1.5, O.WATER_ICE: 1.5, O.IRON: 0.3,
	}))

	# ═══════════════════════════════════════════════════════════════
	#  JUPITER TROJANS (~5.2 AU, L4 and L5 points)
	# ═══════════════════════════════════════════════════════════════

	list.append(_make("624 Hektor", 5.23, T.TROJAN, {
		O.CARBON_ORGANICS: 3.0, O.WATER_ICE: 2.5,
	}))
	list.append(_make("911 Agamemnon", 5.18, T.TROJAN, {
		O.CARBON_ORGANICS: 2.5, O.WATER_ICE: 2.0, O.IRON: 0.3,
	}))
	list.append(_make("588 Achilles", 5.21, T.TROJAN, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.5,
	}))
	list.append(_make("617 Patroclus", 5.22, T.TROJAN, {
		O.WATER_ICE: 4.0, O.CARBON_ORGANICS: 1.5,
	}))
	list.append(_make("3451 Mentor", 5.18, T.TROJAN, {
		O.CARBON_ORGANICS: 2.8, O.WATER_ICE: 1.0,
	}))
	list.append(_make("659 Nestor", 5.19, T.TROJAN, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.5,
	}))
	list.append(_make("1143 Odysseus", 5.21, T.TROJAN, {
		O.CARBON_ORGANICS: 2.5, O.WATER_ICE: 2.0,
	}))
	list.append(_make("1172 Aneas", 5.17, T.TROJAN, {
		O.CARBON_ORGANICS: 2.2, O.WATER_ICE: 1.8,
	}))
	list.append(_make("884 Priamus", 5.20, T.TROJAN, {
		O.CARBON_ORGANICS: 1.8, O.WATER_ICE: 2.0,
	}))
	list.append(_make("1437 Diomedes", 5.22, T.TROJAN, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.5,
	}))
	list.append(_make("3317 Paris", 5.19, T.TROJAN, {
		O.CARBON_ORGANICS: 2.2, O.WATER_ICE: 1.2,
	}))
	list.append(_make("1208 Troilus", 5.18, T.TROJAN, {
		O.WATER_ICE: 3.0, O.CARBON_ORGANICS: 1.5,
	}))
	list.append(_make("2797 Teucer", 5.21, T.TROJAN, {
		O.CARBON_ORGANICS: 1.8, O.WATER_ICE: 1.0,
	}))
	list.append(_make("2207 Antenor", 5.23, T.TROJAN, {
		O.CARBON_ORGANICS: 2.0, O.WATER_ICE: 1.5,
	}))
	list.append(_make("4709 Ennomos", 5.20, T.TROJAN, {
		O.CARBON_ORGANICS: 2.5, O.WATER_ICE: 2.0,
	}))

	# ═══════════════════════════════════════════════════════════════
	#  CENTAURS (between Jupiter and Neptune, 5-30 AU)
	# ═══════════════════════════════════════════════════════════════

	list.append(_make("2060 Chiron", 13.7, T.CENTAUR, {
		O.WATER_ICE: 5.0, O.CARBON_ORGANICS: 3.0,
	}))
	list.append(_make("5145 Pholus", 20.3, T.CENTAUR, {
		O.WATER_ICE: 4.5, O.CARBON_ORGANICS: 3.5,
	}))
	list.append(_make("10199 Chariklo", 15.8, T.CENTAUR, {
		O.WATER_ICE: 6.0, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("8405 Asbolus", 18.0, T.CENTAUR, {
		O.WATER_ICE: 4.0, O.CARBON_ORGANICS: 2.5,
	}))
	list.append(_make("7066 Nessus", 24.6, T.CENTAUR, {
		O.WATER_ICE: 5.0, O.CARBON_ORGANICS: 3.0,
	}))
	list.append(_make("10370 Hylonome", 19.1, T.CENTAUR, {
		O.WATER_ICE: 3.5, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("32532 Thereus", 10.6, T.CENTAUR, {
		O.WATER_ICE: 4.0, O.CARBON_ORGANICS: 2.0, O.IRON: 0.3,
	}))
	list.append(_make("54598 Bienor", 16.5, T.CENTAUR, {
		O.WATER_ICE: 4.5, O.CARBON_ORGANICS: 2.5,
	}))
	list.append(_make("52872 Okyrhoe", 8.4, T.CENTAUR, {
		O.WATER_ICE: 3.5, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("60558 Echeclus", 10.7, T.CENTAUR, {
		O.WATER_ICE: 4.0, O.CARBON_ORGANICS: 2.5,
	}))

	# ═══════════════════════════════════════════════════════════════
	#  COMETS (periodic, short-period preferred)
	# ═══════════════════════════════════════════════════════════════

	list.append(_make("67P/Churyumov", 3.46, T.COMET, {
		O.WATER_ICE: 4.0, O.CARBON_ORGANICS: 3.5,
	}))
	list.append(_make("Tempel 1", 3.12, T.COMET, {
		O.WATER_ICE: 3.0, O.CARBON_ORGANICS: 2.5,
	}))
	list.append(_make("Wild 2", 3.44, T.COMET, {
		O.WATER_ICE: 3.5, O.CARBON_ORGANICS: 2.0, O.IRON: 0.3,
	}))
	list.append(_make("Encke", 2.21, T.COMET, {
		O.WATER_ICE: 2.5, O.CARBON_ORGANICS: 3.0,
	}))
	list.append(_make("Borrelly", 3.61, T.COMET, {
		O.WATER_ICE: 2.0, O.CARBON_ORGANICS: 2.8,
	}))
	list.append(_make("Halley", 17.8, T.COMET, {
		O.WATER_ICE: 5.0, O.CARBON_ORGANICS: 4.0,
	}))
	list.append(_make("Hartley 2", 3.47, T.COMET, {
		O.WATER_ICE: 4.5, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("Giacobini-Zinner", 3.52, T.COMET, {
		O.WATER_ICE: 3.0, O.CARBON_ORGANICS: 2.5,
	}))
	list.append(_make("Kopff", 3.40, T.COMET, {
		O.WATER_ICE: 2.5, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("Wirtanen", 3.09, T.COMET, {
		O.WATER_ICE: 3.5, O.CARBON_ORGANICS: 1.5,
	}))
	list.append(_make("Arend-Roland", 5.80, T.COMET, {
		O.WATER_ICE: 4.0, O.CARBON_ORGANICS: 3.0,
	}))
	list.append(_make("Grigg-Skjellerup", 2.96, T.COMET, {
		O.WATER_ICE: 2.0, O.CARBON_ORGANICS: 1.5,
	}))
	list.append(_make("Honda-Mrkos", 2.58, T.COMET, {
		O.WATER_ICE: 2.5, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("Schwassmann-Wachmann 1", 5.99, T.COMET, {
		O.WATER_ICE: 5.0, O.CARBON_ORGANICS: 3.0,
	}))
	list.append(_make("Schwassmann-Wachmann 3", 3.06, T.COMET, {
		O.WATER_ICE: 3.0, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("Hale-Bopp", 186.0, T.COMET, {
		O.WATER_ICE: 8.0, O.CARBON_ORGANICS: 5.0, O.PLATINUM: 0.5,
	}))
	list.append(_make("ISON", 0.93, T.COMET, {
		O.WATER_ICE: 3.5, O.CARBON_ORGANICS: 4.0,
	}))

	# ═══════════════════════════════════════════════════════════════
	#  KUIPER BELT OBJECTS (30-50+ AU, no dwarf planets)
	# ═══════════════════════════════════════════════════════════════

	list.append(_make("Quaoar", 43.7, T.KBO, {
		O.WATER_ICE: 6.0, O.CARBON_ORGANICS: 2.5,
	}))
	list.append(_make("Orcus", 39.2, T.KBO, {
		O.WATER_ICE: 5.5, O.CARBON_ORGANICS: 2.0, O.IRON: 0.5,
	}))
	list.append(_make("Varuna", 42.9, T.KBO, {
		O.WATER_ICE: 4.5, O.CARBON_ORGANICS: 3.0,
	}))
	list.append(_make("Ixion", 39.6, T.KBO, {
		O.WATER_ICE: 4.0, O.CARBON_ORGANICS: 2.5, O.NICKEL: 0.3,
	}))
	list.append(_make("Sedna", 506.0, T.KBO, {
		O.WATER_ICE: 10.0, O.CARBON_ORGANICS: 5.0, O.PLATINUM: 2.0,
	}))
	list.append(_make("Salacia", 42.2, T.KBO, {
		O.WATER_ICE: 5.0, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("Varda", 45.6, T.KBO, {
		O.WATER_ICE: 4.5, O.CARBON_ORGANICS: 2.5,
	}))
	list.append(_make("2002 UX25", 42.5, T.KBO, {
		O.WATER_ICE: 4.0, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("2002 AW197", 47.1, T.KBO, {
		O.WATER_ICE: 5.0, O.CARBON_ORGANICS: 3.0,
	}))
	list.append(_make("Chaos", 45.9, T.KBO, {
		O.WATER_ICE: 4.0, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("Deucalion", 41.8, T.KBO, {
		O.WATER_ICE: 3.5, O.CARBON_ORGANICS: 1.5,
	}))
	list.append(_make("Huya", 39.7, T.KBO, {
		O.WATER_ICE: 4.5, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("Altjira", 44.1, T.KBO, {
		O.WATER_ICE: 3.0, O.CARBON_ORGANICS: 1.5,
	}))
	list.append(_make("Borasisi", 44.2, T.KBO, {
		O.WATER_ICE: 3.5, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("Teharonhiawako", 44.0, T.KBO, {
		O.WATER_ICE: 3.0, O.CARBON_ORGANICS: 1.5,
	}))
	list.append(_make("Sila-Nunam", 43.9, T.KBO, {
		O.WATER_ICE: 3.5, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("Logos", 45.1, T.KBO, {
		O.WATER_ICE: 3.0, O.CARBON_ORGANICS: 1.5,
	}))
	list.append(_make("Rhadamanthus", 42.0, T.KBO, {
		O.WATER_ICE: 3.5, O.CARBON_ORGANICS: 1.8,
	}))
	list.append(_make("2003 AZ84", 39.4, T.KBO, {
		O.WATER_ICE: 5.5, O.CARBON_ORGANICS: 2.5, O.IRON: 0.3,
	}))
	list.append(_make("2005 QU182", 48.0, T.KBO, {
		O.WATER_ICE: 4.0, O.CARBON_ORGANICS: 2.0,
	}))
	list.append(_make("Eris", 67.8, T.KBO, {
		O.WATER_ICE: 8.0, O.CARBON_ORGANICS: 4.0, O.PLATINUM: 1.0,
	}))
	list.append(_make("Makemake", 45.8, T.KBO, {
		O.WATER_ICE: 7.0, O.CARBON_ORGANICS: 3.5,
	}))
	list.append(_make("Haumea", 43.1, T.KBO, {
		O.WATER_ICE: 9.0, O.CARBON_ORGANICS: 2.0, O.IRON: 0.5,
	}))
	list.append(_make("Gonggong", 67.3, T.KBO, {
		O.WATER_ICE: 7.0, O.CARBON_ORGANICS: 3.0, O.PLATINUM: 0.5,
	}))
	list.append(_make("Arrokoth", 44.6, T.KBO, {
		O.WATER_ICE: 5.0, O.CARBON_ORGANICS: 4.0,
	}))

	return list
