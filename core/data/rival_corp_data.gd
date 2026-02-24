class_name RivalCorpData

## Factory for the five canonical rival corporations.
## Call create_all() once at game start to populate GameState.rival_corps.

static func create_all() -> Array[RivalCorp]:
	var corps: Array[RivalCorp] = []
	corps.append(_make("Helios Extraction",
		"We take what the Sun gives us.",
		RivalCorp.Personality.AGGRESSIVE,
		Vector2(2.77, 0.0),  # ~Ceres orbit
		5, 120.0))
	corps.append(_make("Meridian Heavy Industries",
		"Precision. Patience. Profit.",
		RivalCorp.Personality.SYSTEMATIC,
		Vector2(2.36, 0.0),  # ~Vesta orbit
		4, 100.0))
	corps.append(_make("Vanguard Prospecting",
		"First in, first paid.",
		RivalCorp.Personality.OPPORTUNISTIC,
		Vector2(1.52, 0.0),  # ~Mars orbit
		3, 80.0))
	corps.append(_make("Consolidated Belt Resources",
		"Safe yields, steady returns.",
		RivalCorp.Personality.CONSERVATIVE,
		Vector2(1.0, 0.0),   # ~Earth–Moon L4
		3, 90.0))
	corps.append(_make("Arcturus Syndicate",
		"Everywhere at once.",
		RivalCorp.Personality.EXPANSIONIST,
		Vector2(9.5, 0.0),   # ~Saturn orbit
		6, 70.0))
	return corps

static func _roll_normal_trait(mean: float, std_dev: float) -> float:
	# Box-Muller transform: generates normal distribution from uniform random
	# Most values near mean (0.5), fewer at extremes
	var u1 := randf()
	var u2 := randf()
	var z := sqrt(-2.0 * log(u1)) * cos(2.0 * PI * u2)  # Standard normal (mean=0, std=1)
	var value := mean + z * std_dev  # Scale to desired mean/std_dev
	return clampf(value, 0.0, 1.0)  # Clamp to valid range

static func _make(
		name: String,
		tagline: String,
		personality: RivalCorp.Personality,
		home_pos: Vector2,
		ship_count: int,
		cargo_cap: float) -> RivalCorp:
	var corp := RivalCorp.new()
	corp.corp_name = name
	corp.tagline = tagline
	corp.personality = personality
	corp.home_position_au = home_pos
	corp.money = randi_range(2_000_000, 8_000_000)

	# Realistic human personality distribution (normal distribution centered at 0.5)
	# Most people are moderate (0.4-0.6), fewer extremes (0.0-0.3 or 0.7-1.0)
	corp.aggression = _roll_normal_trait(0.5, 0.2)  # Mean 0.5, StdDev 0.2
	corp.skill = _roll_normal_trait(0.5, 0.2)       # Mean 0.5, StdDev 0.2

	corp.ships.clear()
	for i in ship_count:
		var s := RivalShip.new()
		s.home_position_au = home_pos
		s.cargo_capacity = cargo_cap
		s.thrust_g = randf_range(0.18, 0.45)
		corp.ships.append(s)
	return corp
