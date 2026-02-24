class_name UpgradeCatalog
extends RefCounted

static func get_available_upgrades() -> Array[Dictionary]:
	var catalog: Array[Dictionary] = []

	# ── MODULAR UPGRADES ─────────────────────────────────────────────────────
	# Physical units that can be purchased, stored, and installed at any dock.

	# Fuel Tank Upgrades
	catalog.append({
		"name": "Extended Fuel Tank",
		"type": ShipUpgrade.UpgradeType.FUEL_TANK,
		"cost": 3000,
		"description": "Bolt-on auxiliary tank. Adds 100t propellant capacity.",
		"fuel_capacity_bonus": 100.0,
		"requires_dry_dock": false,
	})

	# Engine Upgrades
	catalog.append({
		"name": "Improved Thrust Nozzles",
		"type": ShipUpgrade.UpgradeType.ENGINE,
		"cost": 5000,
		"description": "Replacement nozzle assembly. Increases thrust by 0.1g.",
		"thrust_bonus": 0.1,
		"requires_dry_dock": false,
	})

	# ── DRY DOCK WORK ────────────────────────────────────────────────────────
	# Structural modifications performed on the ship in dock. No physical unit
	# to store — work is commissioned directly on a docked ship.

	# Fuel system
	catalog.append({
		"name": "High-Capacity Fuel System",
		"type": ShipUpgrade.UpgradeType.FUEL_TANK,
		"cost": 8000,
		"description": "Internal tankage restructuring. Adds 250t propellant capacity.",
		"fuel_capacity_bonus": 250.0,
		"requires_dry_dock": true,
	})

	# Engine rebuilds
	catalog.append({
		"name": "High-Efficiency Engine",
		"type": ShipUpgrade.UpgradeType.ENGINE,
		"cost": 10000,
		"description": "Engine core rebuild. Reduces fuel consumption by 20%.",
		"fuel_efficiency_multiplier": 0.8,
		"requires_dry_dock": true,
	})

	catalog.append({
		"name": "Racing Engine",
		"type": ShipUpgrade.UpgradeType.ENGINE,
		"cost": 15000,
		"description": "Full drive replacement. Increases thrust by 0.2g.",
		"thrust_bonus": 0.2,
		"requires_dry_dock": true,
	})

	# Cargo bay work
	catalog.append({
		"name": "Cargo Bay Extension",
		"type": ShipUpgrade.UpgradeType.CARGO_BAY,
		"cost": 4000,
		"description": "Hull section added. Adds 50t / 70m³ cargo capacity.",
		"cargo_capacity_bonus": 50.0,
		"cargo_volume_bonus": 70.0,
		"requires_dry_dock": true,
	})

	catalog.append({
		"name": "Heavy Hauler Conversion",
		"type": ShipUpgrade.UpgradeType.CARGO_BAY,
		"cost": 12000,
		"description": "Major structural conversion. Adds 150t / 210m³ cargo capacity.",
		"cargo_capacity_bonus": 150.0,
		"cargo_volume_bonus": 210.0,
		"requires_dry_dock": true,
	})

	# Hull work
	catalog.append({
		"name": "Lightweight Alloy Hull",
		"type": ShipUpgrade.UpgradeType.HULL,
		"cost": 7000,
		"description": "Hull panel replacement with alloy composite. Reduces ship mass by 15%.",
		"base_mass_multiplier": 0.85,
		"requires_dry_dock": true,
	})

	catalog.append({
		"name": "Advanced Composite Hull",
		"type": ShipUpgrade.UpgradeType.HULL,
		"cost": 18000,
		"description": "Full hull rebuild in advanced composite. Reduces ship mass by 30%.",
		"base_mass_multiplier": 0.7,
		"requires_dry_dock": true,
	})

	return catalog
