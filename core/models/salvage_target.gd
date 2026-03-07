class_name SalvageTarget
extends Resource

@export var target_name: String = ""
@export var position_au: Vector2 = Vector2.ZERO
@export var scrap_credits: int = 0
@export var salvage_equipment: Array[Equipment] = []  # Equipment recoverable from the wreck
@export var cargo: Dictionary = {}                     # OreType -> tons of recoverable ore
@export var fuel_remaining: float = 0.0               # Fuel recoverable from wreck tanks
@export var spawned_at_ticks: float = 0.0
@export var expires_at_ticks: float = 0.0             # 0 = never expires
@export var source: String = ""                        # "rival" | "random"

const SALVAGE_DURATION: float = 7200.0  # 2 game-hours to strip a wreck

static func create_from_rival(corp_name: String, position: Vector2, cargo_tons: float, ticks: float) -> SalvageTarget:
	var t := SalvageTarget.new()
	t.target_name = "Derelict (%s)" % corp_name
	t.position_au = position
	t.scrap_credits = randi_range(40_000, 120_000)
	t.fuel_remaining = randf_range(5.0, 25.0)
	# 60% chance of one salvageable equipment piece (non-weapon only)
	if randf() < 0.6:
		var non_weapon: Array = MarketData.EQUIPMENT_CATALOG.filter(
			func(e: Dictionary) -> bool: return e.get("type", "") != "weapon"
		)
		if not non_weapon.is_empty():
			var entry: Dictionary = non_weapon[randi() % non_weapon.size()]
			var equip := Equipment.from_catalog(entry)
			equip.durability = randf_range(15.0, 55.0)
			equip.max_durability = 100.0
			t.salvage_equipment.append(equip)
	# Partial cargo recovery from rival's haul
	if cargo_tons > 0.0:
		var ore_type := ResourceTypes.OreType.IRON if randf() < 0.5 else ResourceTypes.OreType.NICKEL
		t.cargo[ore_type] = cargo_tons * randf_range(0.2, 0.5)
	t.spawned_at_ticks = ticks
	t.expires_at_ticks = ticks + 86400.0 * 20.0  # 20 game-days
	t.source = "rival"
	return t

static func create_random(position: Vector2, ticks: float) -> SalvageTarget:
	var names: Array[String] = [
		"Unknown Derelict", "Abandoned Prospector", "Wrecked Freighter",
		"Lost Hauler", "Ghost Ship", "Derelict Ore Carrier"
	]
	var t := SalvageTarget.new()
	t.target_name = names[randi() % names.size()]
	t.position_au = position
	t.scrap_credits = randi_range(20_000, 180_000)
	t.fuel_remaining = randf_range(0.0, 15.0)
	# 0–2 equipment pieces at varying condition
	var equip_count := randi() % 3
	for _i in range(equip_count):
		var idx := randi() % MarketData.EQUIPMENT_CATALOG.size()
		var entry: Dictionary = MarketData.EQUIPMENT_CATALOG[idx]
		var equip := Equipment.from_catalog(entry)
		equip.durability = randf_range(10.0, 65.0)
		equip.max_durability = 100.0
		t.salvage_equipment.append(equip)
	t.spawned_at_ticks = ticks
	t.expires_at_ticks = ticks + 86400.0 * float(randi_range(15, 30))
	t.source = "random"
	return t
