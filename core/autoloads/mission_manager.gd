extends Node

## MissionManager
## Centralized mission creation, updates, completion, and cancellation logic
## Extracted from GameState to improve code organization and maintainability

# Mission tracking
var missions: Array[Mission] = []
var trade_missions: Array[TradeMission] = []

# Dependencies (injected from GameState)
var _game_state: Node = null


func _ready() -> void:
	# Wait for GameState to be ready, then link dependencies
	call_deferred("_initialize")


func _initialize() -> void:
	_game_state = get_node("/root/GameState")
	if not _game_state:
		push_error("[MissionManager] Failed to find GameState autoload")


## Transfer existing missions from GameState
func import_missions_from_game_state(gs_missions: Array[Mission], gs_trade_missions: Array[TradeMission]) -> void:
	missions = gs_missions
	trade_missions = gs_trade_missions


## ═══════════════════════════════════════════════════════════════════
## MISSION CREATION
## ═══════════════════════════════════════════════════════════════════

## Start a basic mining mission to an asteroid
func start_mission(ship: Ship, asteroid: AsteroidData, transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
	# TODO: Move implementation from game_state.gd
	push_error("[MissionManager] start_mission not yet implemented")
	return null


## Start a deployment mission (deploy mining units and workers)
func start_deploy_mission(ship: Ship, asteroid: AsteroidData, units: Array[MiningUnit], deploy_workers: Array[Worker], transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
	# TODO: Move implementation from game_state.gd
	push_error("[MissionManager] start_deploy_mission not yet implemented")
	return null


## Start a collection mission (collect stockpiled ore from deployed units)
func start_collect_mission(ship: Ship, asteroid: AsteroidData, transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
	# TODO: Move implementation from game_state.gd
	push_error("[MissionManager] start_collect_mission not yet implemented")
	return null


## Start a trade mission to sell ore at a colony
func start_trade_mission(ship: Ship, colony_target: Colony, cargo_to_load: Dictionary, transit_mode: int = TradeMission.TransitMode.BRACHISTOCHRONE) -> TradeMission:
	# TODO: Move implementation from game_state.gd
	push_error("[MissionManager] start_trade_mission not yet implemented")
	return null


## Start a rescue mission to recover a derelict ship
func start_fleet_rescue(ferry_ship: Ship, target_ship: Ship, rescue_crew: Array[Worker], food_units: float, parts_units: float) -> Mission:
	# TODO: Move implementation from game_state.gd
	push_error("[MissionManager] start_fleet_rescue not yet implemented")
	return null


## ═══════════════════════════════════════════════════════════════════
## MISSION CONTROL
## ═══════════════════════════════════════════════════════════════════

## Redirect a mission to a new asteroid destination
func redirect_mission(mission: Mission, new_asteroid: AsteroidData) -> bool:
	# TODO: Move implementation from game_state.gd
	push_error("[MissionManager] redirect_mission not yet implemented")
	return false


## Redirect a trade mission to a new colony destination
func redirect_trade_mission(trade_mission: TradeMission, new_colony: Colony) -> bool:
	# TODO: Move implementation from game_state.gd
	push_error("[MissionManager] redirect_trade_mission not yet implemented")
	return false


## Dispatch an idle ship to an asteroid
func dispatch_idle_ship(ship: Ship, asteroid: AsteroidData, transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
	# TODO: Move implementation from game_state.gd
	push_error("[MissionManager] dispatch_idle_ship not yet implemented")
	return null


## Dispatch an idle ship to a colony for trading
func dispatch_idle_ship_trade(ship: Ship, colony_target: Colony, cargo_to_load: Dictionary, transit_mode: int = TradeMission.TransitMode.BRACHISTOCHRONE) -> TradeMission:
	# TODO: Move implementation from game_state.gd
	push_error("[MissionManager] dispatch_idle_ship_trade not yet implemented")
	return null


## ═══════════════════════════════════════════════════════════════════
## MISSION COMPLETION
## ═══════════════════════════════════════════════════════════════════

## Complete a mining/deploy/collect mission
func complete_mission(mission: Mission) -> void:
	# TODO: Move implementation from game_state.gd
	push_error("[MissionManager] complete_mission not yet implemented")


## Complete a trade mission
func complete_trade_mission(tm: TradeMission) -> void:
	# TODO: Move implementation from game_state.gd
	push_error("[MissionManager] complete_trade_mission not yet implemented")


## ═══════════════════════════════════════════════════════════════════
## HELPER FUNCTIONS
## ═══════════════════════════════════════════════════════════════════

## Calculate intercept position for a moving asteroid
func calculate_asteroid_intercept(start_pos: Vector2, asteroid: AsteroidData, thrust: float, transit_mode: int) -> Dictionary:
	# TODO: Move implementation from game_state.gd
	push_error("[MissionManager] calculate_asteroid_intercept not yet implemented")
	return {}
