extends Node

## MarketManager
## Centralized market, stockpile, and supply management logic
## Extracted from GameState to improve code organization and maintainability

# Dependencies (injected from GameState)
var _game_state: Node = null


func _ready() -> void:
	# Wait for GameState to be ready, then link dependencies
	call_deferred("_initialize")


func _initialize() -> void:
	_game_state = get_node("/root/GameState")
	if not _game_state:
		push_error("[MarketManager] Failed to find GameState autoload")


## ═══════════════════════════════════════════════════════════════════
## STOCKPILE MANAGEMENT
## ═══════════════════════════════════════════════════════════════════

## Get ore stockpile for an asteroid
func get_ore_stockpile(asteroid_name: String) -> Dictionary:
	if not _game_state:
		push_error("[MarketManager] GameState not initialized")
		return {}
	return _game_state.ore_stockpiles.get(asteroid_name, {})

## Add ore to asteroid stockpile
func add_to_stockpile(asteroid_name: String, ore_type: ResourceTypes.OreType, amount: float) -> void:
	if not _game_state:
		push_error("[MarketManager] GameState not initialized")
		return

	if not _game_state.ore_stockpiles.has(asteroid_name):
		_game_state.ore_stockpiles[asteroid_name] = {}
	var pile: Dictionary = _game_state.ore_stockpiles[asteroid_name]
	pile[ore_type] = pile.get(ore_type, 0.0) + amount

## Collect stockpiled ore into ship cargo
func collect_from_stockpile(asteroid_name: String, ship: Ship) -> float:
	if not _game_state:
		push_error("[MarketManager] GameState not initialized")
		return 0.0

	if not _game_state.ore_stockpiles.has(asteroid_name):
		return 0.0
	var pile: Dictionary = _game_state.ore_stockpiles[asteroid_name]
	var space_remaining := ship.cargo_capacity - ship.get_cargo_total()
	var total_collected := 0.0
	# Load proportionally if not enough space
	var total_available := 0.0
	for ore_type in pile:
		total_available += pile[ore_type]
	if total_available <= 0.0:
		return 0.0
	var scale := 1.0
	if total_available > space_remaining:
		scale = space_remaining / total_available
	for ore_type in pile.keys():
		var amount: float = pile[ore_type] * scale
		if amount > 0.0:
			ship.current_cargo[ore_type] = ship.current_cargo.get(ore_type, 0.0) + amount
			pile[ore_type] -= amount
			total_collected += amount
	# Clean up empty entries
	for ore_type in pile.keys():
		if pile[ore_type] <= 0.001:
			pile.erase(ore_type)
	if pile.is_empty():
		_game_state.ore_stockpiles.erase(asteroid_name)
	return total_collected


## ═══════════════════════════════════════════════════════════════════
## SUPPLY MANAGEMENT
## ═══════════════════════════════════════════════════════════════════

## Get supplies dict for an asteroid (food, water, oxygen, repair_parts)
func get_asteroid_supplies(asteroid_name: String) -> Dictionary:
	if not _game_state:
		push_error("[MarketManager] GameState not initialized")
		return {}
	return _game_state.asteroid_supplies.get(asteroid_name, {"food": 0.0, "water": 0.0, "oxygen": 0.0, "repair_parts": 0.0})

## Add supplies to an asteroid
func add_to_asteroid_supplies(asteroid_name: String, supply_key: String, amount: float) -> void:
	if not _game_state:
		push_error("[MarketManager] GameState not initialized")
		return

	if not _game_state.asteroid_supplies.has(asteroid_name):
		_game_state.asteroid_supplies[asteroid_name] = {"food": 0.0, "water": 0.0, "oxygen": 0.0, "repair_parts": 0.0}
	_game_state.asteroid_supplies[asteroid_name][supply_key] = _game_state.asteroid_supplies[asteroid_name].get(supply_key, 0.0) + amount

## Consume supplies from an asteroid (returns actual amount consumed)
func consume_asteroid_supply(asteroid_name: String, supply_key: String, amount: float) -> float:
	if not _game_state:
		push_error("[MarketManager] GameState not initialized")
		return 0.0

	if not _game_state.asteroid_supplies.has(asteroid_name):
		return 0.0
	var current: float = _game_state.asteroid_supplies[asteroid_name].get(supply_key, 0.0)
	var consumed: float = minf(amount, current)
	_game_state.asteroid_supplies[asteroid_name][supply_key] = current - consumed
	return consumed

## Calculate days remaining for a supply based on deployed units/workers
func get_asteroid_supply_days(asteroid_name: String, supply_key: String) -> float:
	if not _game_state:
		push_error("[MarketManager] GameState not initialized")
		return 0.0

	var supply: float = _game_state.asteroid_supplies.get(asteroid_name, {}).get(supply_key, 0.0)
	if supply <= 0.0:
		return 0.0
	match supply_key:
		"food":
			var worker_count := 0
			for unit in _game_state.deployed_mining_units:
				if unit.deployed_at_asteroid == asteroid_name:
					worker_count += unit.assigned_workers.size()
			if worker_count <= 0:
				return INF
			return supply / (worker_count * 0.028)
		"repair_parts":
			var unit_count := 0
			for unit in _game_state.deployed_mining_units:
				if unit.deployed_at_asteroid == asteroid_name:
					unit_count += 1
			if unit_count <= 0:
				return INF
			return supply / (unit_count * 0.05)
	return INF

## Purchase supplies for a ship
func buy_supplies(ship: Ship, supply_key: String, amount: float) -> bool:
	if not _game_state:
		push_error("[MarketManager] GameState not initialized")
		return false

	# Find supply type from key
	var cost_per_unit := 0
	var mass_per_unit := 0.0
	var volume_per_unit := 0.0
	for supply_type in SupplyData.SUPPLY_INFO:
		var info: Dictionary = SupplyData.SUPPLY_INFO[supply_type]
		if info["key"] == supply_key:
			cost_per_unit = info["cost_per_unit"]
			mass_per_unit = info["mass_per_unit"]
			volume_per_unit = info.get("volume_per_unit", 0.0)
			break

	if cost_per_unit <= 0:
		return false

	var total_mass := amount * mass_per_unit
	# Check cargo capacity (supplies share space with ore)
	var available_space := ship.get_cargo_remaining() - ship.get_supplies_mass()
	if total_mass > available_space + 0.01:
		return false

	# Check cargo volume
	var total_volume := amount * volume_per_unit
	if total_volume > ship.get_cargo_volume_remaining() + 0.01:
		return false

	var total_cost := int(amount * cost_per_unit)
	if _game_state.money < total_cost:
		return false

	_game_state.money -= total_cost
	_game_state.record_transaction(-total_cost, "Supplies: %s ×%.1f" % [supply_key, amount], ship.ship_name)
	ship.supplies[supply_key] = ship.supplies.get(supply_key, 0.0) + amount
	return true


## ═══════════════════════════════════════════════════════════════════
## TRADING & MARKET EVENTS
## ═══════════════════════════════════════════════════════════════════

## Sell equipment from a ship (routes to LOCAL/SERVER backend)
func sell_equipment_any_mode(equipment: Equipment, ship: Ship) -> void:
	if not _game_state:
		push_error("[MarketManager] GameState not initialized")
		return

	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		# SERVER mode: equipment needs server_id
		# For now, use equipment name to find it (requires server sync)
		# TODO: Add equipment.server_id field
		push_warning("sell_equipment_any_mode() SERVER mode requires equipment.server_id field")
	else:
		# LOCAL mode: remove from ship and refund 50% of cost
		ship.equipment.erase(equipment)
		_game_state.money += equipment.cost / 2
		EventBus.equipment_sold.emit(equipment, ship)

## Apply market price update event from server (SSE)
func apply_market_update_event(event: Dictionary) -> void:
	if not _game_state:
		push_error("[MarketManager] GameState not initialized")
		return

	var prices: Dictionary = event.get("prices", {})

	if prices.is_empty():
		return

	# Log market updates for now
	# TODO: Integrate with local economy system (MarketState is per-instance, needs refactor)
	var updated_count := prices.size()
	if updated_count > 0:
		print("[MarketManager] Market prices updated via SSE: %d ore types" % updated_count)
		for ore_name in prices:
			var new_price: float = float(prices[ore_name])
			print("  - %s: $%.0f" % [ore_name, new_price])
		EventBus.market_state_changed.emit()
