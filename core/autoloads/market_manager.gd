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

## TODO: Extract supply functions from GameState


## ═══════════════════════════════════════════════════════════════════
## TRADING & MARKET EVENTS
## ═══════════════════════════════════════════════════════════════════

## TODO: Extract trading functions from GameState
