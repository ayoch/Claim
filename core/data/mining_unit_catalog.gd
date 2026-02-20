class_name MiningUnitCatalog
extends RefCounted

static func get_available_units() -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []

	catalog.append({
		"name": "Basic Mining Unit",
		"type": MiningUnit.UnitType.BASIC,
		"mass": 7.6,
		"workers_required": 1,
		"mining_multiplier": 1.0,
		"wear_per_day": 0.3,
		"cost": 50000,
		"description": "Standard autonomous drill. Requires 1 worker to operate.",
	})

	catalog.append({
		"name": "Advanced Mining Unit",
		"type": MiningUnit.UnitType.ADVANCED,
		"mass": 13.2,
		"workers_required": 2,
		"mining_multiplier": 2.0,
		"wear_per_day": 0.5,
		"cost": 150000,
		"description": "High-yield extraction platform. Requires 2 workers.",
	})

	catalog.append({
		"name": "Refinery Unit",
		"type": MiningUnit.UnitType.REFINERY,
		"mass": 21.5,
		"workers_required": 3,
		"mining_multiplier": 3.5,
		"wear_per_day": 0.8,
		"cost": 350000,
		"description": "On-site processing and extraction. Requires 3 workers.",
	})

	return catalog
