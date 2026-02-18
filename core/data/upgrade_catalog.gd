class_name UpgradeCatalog
extends RefCounted

static func get_available_upgrades() -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []

	# Fuel Tank Upgrades
	catalog.append({
		"name": "Extended Fuel Tank",
		"type": ShipUpgrade.UpgradeType.FUEL_TANK,
		"cost": 3000,
		"description": "Adds 100 fuel capacity",
		"fuel_capacity_bonus": 100.0,
	})

	catalog.append({
		"name": "High-Capacity Fuel System",
		"type": ShipUpgrade.UpgradeType.FUEL_TANK,
		"cost": 8000,
		"description": "Adds 250 fuel capacity",
		"fuel_capacity_bonus": 250.0,
	})

	# Engine Upgrades
	catalog.append({
		"name": "Improved Thrust Nozzles",
		"type": ShipUpgrade.UpgradeType.ENGINE,
		"cost": 5000,
		"description": "Increases thrust by 0.1g",
		"thrust_bonus": 0.1,
	})

	catalog.append({
		"name": "High-Efficiency Engine",
		"type": ShipUpgrade.UpgradeType.ENGINE,
		"cost": 10000,
		"description": "Reduces fuel consumption by 20%",
		"fuel_efficiency_multiplier": 0.8,
	})

	catalog.append({
		"name": "Racing Engine",
		"type": ShipUpgrade.UpgradeType.ENGINE,
		"cost": 15000,
		"description": "Increases thrust by 0.2g",
		"thrust_bonus": 0.2,
	})

	# Cargo Bay Upgrades
	catalog.append({
		"name": "Cargo Bay Extension",
		"type": ShipUpgrade.UpgradeType.CARGO_BAY,
		"cost": 4000,
		"description": "Adds 50t cargo capacity",
		"cargo_capacity_bonus": 50.0,
	})

	catalog.append({
		"name": "Heavy Hauler Conversion",
		"type": ShipUpgrade.UpgradeType.CARGO_BAY,
		"cost": 12000,
		"description": "Adds 150t cargo capacity",
		"cargo_capacity_bonus": 150.0,
	})

	# Hull Upgrades
	catalog.append({
		"name": "Lightweight Alloy Hull",
		"type": ShipUpgrade.UpgradeType.HULL,
		"cost": 7000,
		"description": "Reduces ship mass by 15% (improves fuel efficiency)",
		"base_mass_multiplier": 0.85,
	})

	catalog.append({
		"name": "Advanced Composite Hull",
		"type": ShipUpgrade.UpgradeType.HULL,
		"cost": 18000,
		"description": "Reduces ship mass by 30% (greatly improves fuel efficiency)",
		"base_mass_multiplier": 0.7,
	})

	return catalog
