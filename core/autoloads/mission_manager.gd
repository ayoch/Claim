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
## Queues the order with lightspeed delay; returns true if order accepted/queued
func redirect_mission(mission: Mission, new_asteroid: AsteroidData) -> bool:
	if not _game_state:
		push_error("[MissionManager] GameState not initialized")
		return false

	if mission.status != Mission.Status.TRANSIT_OUT and mission.status != Mission.Status.TRANSIT_BACK:
		return false
	var ship := mission.ship
	var label := "Redirect to " + new_asteroid.asteroid_name
	_game_state.queue_ship_order(ship, label, func(): _apply_redirect_mission(mission, new_asteroid))
	return true


func _apply_redirect_mission(mission: Mission, new_asteroid: AsteroidData) -> void:
	if not _game_state:
		push_error("[MissionManager] GameState not initialized")
		return

	# Re-validate: mission may have completed or ship state changed during signal transit
	if mission == null or mission.ship == null:
		return
	if mission.status != Mission.Status.TRANSIT_OUT and mission.status != Mission.Status.TRANSIT_BACK:
		return

	var ship := mission.ship
	var thrust := ship.get_effective_thrust()

	# Calculate intercept trajectory (predicts where asteroid will be at arrival)
	var intercept := calculate_asteroid_intercept(ship.position_au, new_asteroid, thrust, mission.transit_mode)
	var new_dest: Vector2 = intercept["intercept_position"]
	var dist: float = intercept["distance"]
	var new_transit_time: float = intercept["transit_time"]
	var avg_velocity := dist / new_transit_time if new_transit_time > 0.0 else 0.0

	# Determine if a momentum arc is needed (ship is moving at significant angle to new dest)
	var velocity_dir := ship.velocity_au_per_tick.normalized() if ship.speed_au_per_tick > 1e-8 else Vector2.ZERO
	var dest_dir := (new_dest - ship.position_au).normalized() if dist > 1e-6 else Vector2.ZERO
	var dot := velocity_dir.dot(dest_dir) if ship.speed_au_per_tick > 1e-8 else 1.0
	var speed_fraction: float = clampf(ship.speed_au_per_tick / (2.0 * avg_velocity), 0.0, 1.0) if avg_velocity > 0.0 else 0.0
	var arc_fraction: float = clampf(sqrt((1.0 - dot) * 0.5) * speed_fraction * 0.4, 0.0, 0.30)

	# Compute arc waypoint and check if it makes sense
	var waypoint := ship.position_au + velocity_dir * (arc_fraction * dist)
	var dist1 := arc_fraction * dist
	var dist2 := waypoint.distance_to(new_dest)
	var use_arc := arc_fraction >= 0.05 and ship.speed_au_per_tick > 1e-8 and dist1 > 1e-6

	# Fuel check: outbound (redirect path) + return trip
	var total_path := dist1 + dist2 if use_arc else dist
	var fuel_out := ship.calc_fuel_for_distance(total_path)
	var return_origin: Vector2
	if mission.return_to_station and ship.station_colony:
		return_origin = ship.station_colony.get_position_au()
	else:
		return_origin = CelestialData.get_earth_position_au()
	var return_dist := new_dest.distance_to(return_origin)
	var fuel_ret := ship.calc_fuel_for_distance(return_dist, ship.cargo_capacity)
	var fuel_needed := fuel_out + fuel_ret

	if fuel_needed > ship.fuel:
		EventBus.mission_redirect_failed.emit(ship, "Insufficient fuel (need %.0f for redirect + return, have %.0f)" % [fuel_needed, ship.fuel])
		return

	# Redirect costs money (2x outbound fuel cost as opportunity cost penalty)
	var redirect_cost := int(fuel_out * Ship.FUEL_COST_PER_UNIT * 2.0)
	if _game_state.money < redirect_cost:
		EventBus.mission_redirect_failed.emit(ship, "Cannot afford redirect cost ($%d)" % redirect_cost)
		return

	_game_state.money -= redirect_cost
	mission.asteroid = new_asteroid
	mission.origin_is_earth = false
	mission.status = Mission.Status.TRANSIT_OUT
	mission.outbound_legs.clear()
	mission.outbound_waypoint_index = 0

	var return_transit_time := Brachistochrone.transit_time(return_dist, thrust)

	if use_arc:
		# Two-leg route: arc in current direction, then turn to destination
		var time1 := Brachistochrone.transit_time(dist1, thrust)
		var time2 := Brachistochrone.transit_time(dist2, thrust)
		var avg_velocity1 := dist1 / time1 if time1 > 0.0 else 0.0
		var initial_t := 0.0
		var adjusted_origin := ship.position_au
		if avg_velocity1 > 0.0 and ship.speed_au_per_tick > 0.0:
			initial_t = clampf(ship.speed_au_per_tick / (4.0 * avg_velocity1), 0.0, 0.5)
			var dfrac := 2.0 * initial_t * initial_t
			if dfrac < 0.98:
				adjusted_origin = (ship.position_au - waypoint * dfrac) / (1.0 - dfrac)
		mission.origin_position_au = adjusted_origin
		mission.outbound_legs.append(WaypointLeg.make(waypoint, time1))
		mission.elapsed_ticks = initial_t * time1
		mission.transit_time = time2
		var total_time_arc := time1 + time2 + return_transit_time
		mission.fuel_per_tick = fuel_needed / total_time_arc if total_time_arc > 0.0 else 0.0
	else:
		# Single-leg velocity-preserving redirect
		var initial_t := 0.0
		var adjusted_origin := ship.position_au
		if avg_velocity > 0.0 and ship.speed_au_per_tick > 0.0:
			initial_t = clampf(ship.speed_au_per_tick / (4.0 * avg_velocity), 0.0, 0.5)
			var dfrac := 2.0 * initial_t * initial_t
			if dfrac < 0.98:
				adjusted_origin = (ship.position_au - new_dest * dfrac) / (1.0 - dfrac)
		mission.origin_position_au = adjusted_origin
		mission.elapsed_ticks = initial_t * new_transit_time
		mission.transit_time = new_transit_time
		var total_time_single := new_transit_time + return_transit_time
		mission.fuel_per_tick = fuel_needed / total_time_single if total_time_single > 0.0 else 0.0

	# Recalculate trajectory visualization for new path
	mission.destination_position_au = new_dest
	mission.calculate_trajectory_curves()

	EventBus.mission_redirected.emit(ship, new_asteroid, redirect_cost)


## Redirect a trade mission to a new colony destination
## Queues the order with lightspeed delay; returns true if order accepted/queued
func redirect_trade_mission(trade_mission: TradeMission, new_colony: Colony) -> bool:
	if not _game_state:
		push_error("[MissionManager] GameState not initialized")
		return false

	if trade_mission.status != TradeMission.Status.TRANSIT_TO_COLONY and trade_mission.status != TradeMission.Status.TRANSIT_BACK:
		return false
	var ship := trade_mission.ship
	var label := "Redirect to " + new_colony.colony_name
	_game_state.queue_ship_order(ship, label, func(): _apply_redirect_trade_mission(trade_mission, new_colony))
	return true


func _apply_redirect_trade_mission(trade_mission: TradeMission, new_colony: Colony) -> void:
	if not _game_state:
		push_error("[MissionManager] GameState not initialized")
		return

	# Re-validate: mission may have completed or ship state changed during signal transit
	if trade_mission == null or trade_mission.ship == null:
		return
	if trade_mission.status != TradeMission.Status.TRANSIT_TO_COLONY and trade_mission.status != TradeMission.Status.TRANSIT_BACK:
		return

	var ship := trade_mission.ship
	var new_dest := new_colony.get_position_au()

	# Fuel check: outbound (redirect path) + return trip
	var dist := ship.position_au.distance_to(new_dest)
	var fuel_out_tm := ship.calc_fuel_for_distance(dist, ship.get_cargo_total())
	var tm_return_origin: Vector2
	if ship.is_stationed and ship.station_colony:
		tm_return_origin = ship.station_colony.get_position_au()
	else:
		tm_return_origin = CelestialData.get_earth_position_au()
	var tm_return_dist := new_dest.distance_to(tm_return_origin)
	var fuel_ret_tm := ship.calc_fuel_for_distance(tm_return_dist, 0.0)  # empty after selling
	var fuel_needed := fuel_out_tm + fuel_ret_tm

	if fuel_needed > ship.fuel:
		EventBus.trade_mission_redirect_failed.emit(ship, "Insufficient fuel (need %.0f for redirect + return, have %.0f)" % [fuel_needed, ship.fuel])
		return

	# Redirect cost (2x outbound fuel cost)
	var redirect_cost := int(fuel_out_tm * Ship.FUEL_COST_PER_UNIT * 2.0)
	if _game_state.money < redirect_cost:
		EventBus.trade_mission_redirect_failed.emit(ship, "Cannot afford redirect cost ($%d)" % redirect_cost)
		return

	_game_state.money -= redirect_cost
	trade_mission.colony = new_colony

	var thrust := ship.get_effective_thrust()
	var new_transit_time := Brachistochrone.transit_time(dist, thrust)
	var avg_velocity := dist / new_transit_time if new_transit_time > 0.0 else 0.0

	# Determine if a momentum arc is needed
	var velocity_dir := ship.velocity_au_per_tick.normalized() if ship.speed_au_per_tick > 1e-8 else Vector2.ZERO
	var dest_dir := (new_dest - ship.position_au).normalized() if dist > 1e-6 else Vector2.ZERO
	var dot := velocity_dir.dot(dest_dir) if ship.speed_au_per_tick > 1e-8 else 1.0
	var speed_fraction: float = clampf(ship.speed_au_per_tick / (2.0 * avg_velocity), 0.0, 1.0) if avg_velocity > 0.0 else 0.0
	var arc_fraction: float = clampf(sqrt((1.0 - dot) * 0.5) * speed_fraction * 0.4, 0.0, 0.30)

	var waypoint := ship.position_au + velocity_dir * (arc_fraction * dist)
	var dist1 := arc_fraction * dist
	var dist2 := waypoint.distance_to(new_dest)
	var use_arc := arc_fraction >= 0.05 and ship.speed_au_per_tick > 1e-8 and dist1 > 1e-6

	var tm_return_transit_time := Brachistochrone.transit_time(tm_return_dist, thrust)

	trade_mission.origin_is_earth = false
	trade_mission.status = TradeMission.Status.TRANSIT_TO_COLONY
	trade_mission.outbound_legs.clear()
	trade_mission.outbound_waypoint_index = 0

	if use_arc:
		var time1 := Brachistochrone.transit_time(dist1, thrust)
		var time2 := Brachistochrone.transit_time(dist2, thrust)
		var avg_velocity1 := dist1 / time1 if time1 > 0.0 else 0.0
		var initial_t := 0.0
		var adjusted_origin := ship.position_au
		if avg_velocity1 > 0.0 and ship.speed_au_per_tick > 0.0:
			initial_t = clampf(ship.speed_au_per_tick / (4.0 * avg_velocity1), 0.0, 0.5)
			var dfrac := 2.0 * initial_t * initial_t
			if dfrac < 0.98:
				adjusted_origin = (ship.position_au - waypoint * dfrac) / (1.0 - dfrac)
		trade_mission.origin_position_au = adjusted_origin
		trade_mission.outbound_legs.append(WaypointLeg.make(waypoint, time1))
		trade_mission.elapsed_ticks = initial_t * time1
		trade_mission.transit_time = time2
		var total_time_arc := time1 + time2 + tm_return_transit_time
		trade_mission.fuel_per_tick = fuel_needed / total_time_arc if total_time_arc > 0.0 else 0.0
	else:
		var initial_t := 0.0
		var adjusted_origin := ship.position_au
		if avg_velocity > 0.0 and ship.speed_au_per_tick > 0.0:
			initial_t = clampf(ship.speed_au_per_tick / (4.0 * avg_velocity), 0.0, 0.5)
			var dfrac := 2.0 * initial_t * initial_t
			if dfrac < 0.98:
				adjusted_origin = (ship.position_au - new_dest * dfrac) / (1.0 - dfrac)
		trade_mission.origin_position_au = adjusted_origin
		trade_mission.elapsed_ticks = initial_t * new_transit_time
		trade_mission.transit_time = new_transit_time
		var total_time_single := new_transit_time + tm_return_transit_time
		trade_mission.fuel_per_tick = fuel_needed / total_time_single if total_time_single > 0.0 else 0.0

	EventBus.trade_mission_redirected.emit(ship, new_colony, redirect_cost)


## Mode-aware mission dispatch - works in both LOCAL and SERVER modes
## Routes to BackendManager in SERVER mode, or direct start_mission() in LOCAL mode
func dispatch_mission_any_mode(ship: Ship, asteroid: AsteroidData) -> void:
	if not _game_state:
		push_error("[MissionManager] GameState not initialized")
		return

	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		# SERVER mode: route through BackendManager using server IDs
		if ship.server_id == 0:
			push_warning("Ship %s has no server_id, cannot dispatch in SERVER mode" % ship.ship_name)
			return

		# Find asteroid ID (index in asteroids array)
		var asteroid_index: int = -1
		for i in range(_game_state.asteroids.size()):
			if _game_state.asteroids[i] == asteroid:
				asteroid_index = i
				break

		if asteroid_index < 0:
			push_warning("Asteroid not found: %s" % asteroid.asteroid_name)
			return

		# Server database IDs start at 1, client array indices start at 0
		var server_asteroid_id: int = asteroid_index + 1

		# Dispatch via server backend (async, but we don't await - fire and forget for autoplay)
		BackendManager.dispatch_mission(ship.server_id, server_asteroid_id, 0, 86400.0, false)
	else:
		# LOCAL mode: use local start_mission directly
		start_mission(ship, asteroid)


## Dispatch an idle ship to an asteroid
## Queues the order with lightspeed delay; returns null (callers shouldn't rely on return)
func dispatch_idle_ship(ship: Ship, asteroid: AsteroidData, transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
	if not _game_state:
		push_error("[MissionManager] GameState not initialized")
		return null

	var label := "Dispatch to " + asteroid.asteroid_name
	_game_state.queue_ship_order(ship, label, func(): _apply_dispatch_idle_ship(ship, asteroid, transit_mode, slingshot_route))
	return null  # Callers should not rely on the return value when ship is remote


func _apply_dispatch_idle_ship(ship: Ship, asteroid: AsteroidData, transit_mode: int, slingshot_route) -> void:
	if not _game_state:
		push_error("[MissionManager] GameState not initialized")
		return

	if not ship.is_idle_remote:
		return  # Ship state changed while signal was in transit

	# Capture origin name before clearing missions
	var origin_asteroid_name := ""
	if ship.current_mission and ship.current_mission.asteroid:
		origin_asteroid_name = ship.current_mission.asteroid.asteroid_name
	elif ship.current_trade_mission and ship.current_trade_mission.colony:
		origin_asteroid_name = ship.current_trade_mission.colony.colony_name

	# End idle state and start new mission from current position
	if ship.current_mission:
		var old_mission := ship.current_mission
		ship.current_mission = null
		old_mission.cleanup()  # Break circular references
		missions.erase(old_mission)
	if ship.current_trade_mission:
		var old_trade_mission := ship.current_trade_mission
		ship.current_trade_mission = null
		old_trade_mission.cleanup()  # Break circular references
		trade_missions.erase(old_trade_mission)

	var mission := start_mission(ship, asteroid, transit_mode, slingshot_route)
	if mission == null:
		return
	mission.origin_is_earth = false
	mission.origin_name = origin_asteroid_name if origin_asteroid_name != "" else "deep space"


## Dispatch an idle ship to a colony for trading
## Queues the order with lightspeed delay; returns null (callers shouldn't rely on return)
func dispatch_idle_ship_trade(ship: Ship, colony_target: Colony, cargo_to_load: Dictionary, transit_mode: int = TradeMission.TransitMode.BRACHISTOCHRONE) -> TradeMission:
	if not _game_state:
		push_error("[MissionManager] GameState not initialized")
		return null

	var label := "Trade mission to " + colony_target.colony_name
	_game_state.queue_ship_order(ship, label, func(): _apply_dispatch_idle_ship_trade(ship, colony_target, cargo_to_load, transit_mode))
	return null  # Callers should not rely on the return value when ship is remote


func _apply_dispatch_idle_ship_trade(ship: Ship, colony_target: Colony, cargo_to_load: Dictionary, transit_mode: int) -> void:
	if not _game_state:
		push_error("[MissionManager] GameState not initialized")
		return

	if not ship.is_idle_remote:
		return  # Ship state changed while signal was in transit

	# Capture origin name before clearing missions
	var origin_loc_name := ""
	if ship.current_mission and ship.current_mission.asteroid:
		origin_loc_name = ship.current_mission.asteroid.asteroid_name
	elif ship.current_trade_mission and ship.current_trade_mission.colony:
		origin_loc_name = ship.current_trade_mission.colony.colony_name

	# End idle state and start new trade mission from current position
	if ship.current_mission:
		var old_mission := ship.current_mission
		ship.current_mission = null
		old_mission.cleanup()  # Break circular references
		missions.erase(old_mission)
	if ship.current_trade_mission:
		var old_trade_mission := ship.current_trade_mission
		ship.current_trade_mission = null
		old_trade_mission.cleanup()  # Break circular references
		trade_missions.erase(old_trade_mission)

	var tm := start_trade_mission(ship, colony_target, cargo_to_load, transit_mode)
	if tm == null:
		return
	tm.origin_is_earth = false
	tm.origin_name = origin_loc_name if origin_loc_name != "" else "deep space"


## ═══════════════════════════════════════════════════════════════════
## MISSION COMPLETION
## ═══════════════════════════════════════════════════════════════════

## Complete a mining/deploy/collect mission
func complete_mission(mission: Mission) -> void:
	if not _game_state:
		push_error("[MissionManager] GameState not initialized")
		return

	# Stationed ships keep cargo (they sell via trade mission autonomously)
	if mission.ship.is_stationed:
		# Don't transfer cargo, ship keeps it for trading
		pass
	elif mission.ship.is_at_earth:
		# Transfer cargo from ship to Earth — either sell immediately or stockpile
		if _game_state.settings.get("auto_sell_at_earth", true):
			var revenue := 0
			for ore_type in mission.ship.current_cargo:
				var amount: float = mission.ship.current_cargo[ore_type]
				var price: float = MarketData.get_ore_price(ore_type)
				revenue += int(amount * price)
			if revenue > 0:
				_game_state.money += revenue
				_game_state.record_transaction(revenue, "Ore sold at Earth", mission.ship.ship_name)
		else:
			for ore_type in mission.ship.current_cargo:
				_game_state.add_resource(ore_type, mission.ship.current_cargo[ore_type])
		mission.ship.current_cargo.clear()

	mission.ship.current_mission = null
	mission.status = Mission.Status.COMPLETED
	EventBus.mission_completed.emit(mission)
	mission.cleanup()  # Break circular references
	missions.erase(mission)

	# Stationed ships don't use queued missions — station logic handles next job
	if mission.ship.is_stationed:
		return
	# Queued missions are launched in simulation.gd after provision/repair completes


## Complete a trade mission
func complete_trade_mission(tm: TradeMission) -> void:
	if not _game_state:
		push_error("[MissionManager] GameState not initialized")
		return

	# If the ship still has unsold cargo (e.g. returned to Earth without selling),
	# return it to the stockpile rather than losing it.
	if not tm.cargo.is_empty():
		for ore_type in tm.cargo:
			_game_state.add_resource(ore_type, tm.cargo[ore_type])
		tm.cargo.clear()
	tm.ship.current_cargo.clear()
	tm.ship.current_trade_mission = null
	tm.status = TradeMission.Status.COMPLETED
	EventBus.trade_mission_completed.emit(tm)
	tm.cleanup()  # Break circular references
	trade_missions.erase(tm)

	# Stationed ships don't use queued missions — station logic handles next job
	if tm.ship.is_stationed:
		return
	# Queued missions are launched in simulation.gd after provision/repair completes


## ═══════════════════════════════════════════════════════════════════
## HELPER FUNCTIONS
## ═══════════════════════════════════════════════════════════════════

## Calculate intercept position for a moving asteroid
## Uses iterative convergence (3 iterations) to predict where asteroid will be when ship arrives
func calculate_asteroid_intercept(start_pos: Vector2, asteroid: AsteroidData, thrust: float, transit_mode: int) -> Dictionary:
	var iterations := 3  # Usually converges in 2-3 iterations
	var target_pos := asteroid.get_position_au()  # Start with current position
	var transit_time := 0.0

	for i in iterations:
		var dist := start_pos.distance_to(target_pos)
		if transit_mode == Mission.TransitMode.HOHMANN:
			transit_time = Brachistochrone.hohmann_time(dist)
		else:
			transit_time = Brachistochrone.transit_time(dist, thrust)

		# Predict where asteroid will be when ship arrives
		target_pos = asteroid.get_position_at_time(transit_time)

	# Final calculation with converged position
	var final_dist := start_pos.distance_to(target_pos)
	if transit_mode == Mission.TransitMode.HOHMANN:
		transit_time = Brachistochrone.hohmann_time(final_dist)
	else:
		transit_time = Brachistochrone.transit_time(final_dist, thrust)

	return {
		"intercept_position": target_pos,
		"distance": final_dist,
		"transit_time": transit_time
	}
