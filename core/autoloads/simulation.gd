extends Node

# Note: game_speed is now controlled by TimeScale autoload (1/2 keys)
# Default is 1.0, but speeds up to 5x for development

var _tick_accumulator: float = 0.0
const TICK_INTERVAL: float = 1.0  # 1 second per tick at 1x speed
var _payroll_accumulator: float = 0.0
const PAYROLL_INTERVAL: float = 86400.0  # pay wages every game-day (86400 ticks = 24h at 1x)
var _survey_accumulator: float = 0.0
const SURVEY_INTERVAL: float = 120.0  # check for survey events every 120 ticks

# Market price drift
var _market_accumulator: float = 0.0
const MARKET_INTERVAL: float = 90.0  # drift prices every 90 ticks
const MARKET_EVENT_CHANCE: float = 0.08  # 8% chance of scripted event per interval

# Contract generation
var _contract_accumulator: float = 0.0
const CONTRACT_INTERVAL: float = 150.0
const CONTRACT_CHANCE: float = 0.40  # 40% chance per interval

# Mining yield varies randomly each tick by this factor (0.7x to 1.3x)
const MINING_VARIANCE_MIN: float = 0.7
const MINING_VARIANCE_MAX: float = 1.3

# Scale factor for ore yields: converts abstract yield values to tons per tick
# With this rate, a typical asteroid fills a 100t cargo hold in ~1 game-day
const BASE_MINING_RATE: float = 0.0001

# Chance per survey interval that a random asteroid gets re-surveyed
const SURVEY_CHANCE: float = 0.15

const MAX_STEPS_PER_FRAME: int = 30  # Max simulation steps per frame
const MAX_DT_PER_STEP: float = 500.0  # Max ticks batched into one step (random events stay accurate at this scale)

func _ready() -> void:
	# Auto-slow to 1x on critical events
	EventBus.ship_breakdown.connect(func(_s: Ship, _r: String) -> void: TimeScale.slow_for_critical_event())
	EventBus.stranger_rescue_offered.connect(func(_s: Ship, _n: String) -> void: TimeScale.slow_for_critical_event())
	EventBus.ship_destroyed.connect(func(_s: Ship, _b: String) -> void: TimeScale.slow_for_critical_event())

func _process(delta: float) -> void:
	var game_speed := TimeScale.speed_multiplier
	if game_speed <= 0.0:
		return

	_tick_accumulator += delta * game_speed
	var steps := 0
	while _tick_accumulator >= TICK_INTERVAL and steps < MAX_STEPS_PER_FRAME:
		# Batch ticks into larger steps when backlog is large
		var dt := minf(_tick_accumulator, MAX_DT_PER_STEP)
		_tick_accumulator -= dt
		_process_tick(dt)
		steps += 1

func _process_tick(dt: float, emit_event: bool = true) -> void:
	GameState.total_ticks += dt
	_process_orbits(dt)

	# Only emit tick event when throttled (prevents UI spam at high speeds)
	if emit_event:
		EventBus.tick.emit(dt)
	_process_missions(dt)
	_process_trade_missions(dt)
	_update_ship_positions(dt)
	_check_breakdowns(dt)
	_process_rescues(dt)
	_process_refuels(dt)
	_process_fabrication(dt)
	_process_stranger_rescue(dt)
	_process_payroll(dt)
	_process_survey_events(dt)
	_process_market_events(dt)
	_process_contracts(dt)

func _process_orbits(dt: float) -> void:
	# Advance all planets (including Earth)
	CelestialData.advance_planets(dt)
	# Advance all asteroids
	for asteroid in GameState.asteroids:
		asteroid.advance_orbit(dt)
	# Advance colonies
	for colony in GameState.colonies:
		colony.advance_orbit(dt)

	# Sync docked ships with their dock location
	var earth_pos := CelestialData.get_earth_position_au()
	for ship in GameState.ships:
		if ship.is_docked:
			if ship.docked_at_colony != null:
				ship.position_au = ship.docked_at_colony.get_position_au()
			else:
				ship.position_au = earth_pos
		# Auto-dock at nearby colonies with services
		elif not ship.is_derelict and ship.current_mission == null and ship.current_trade_mission == null:
			_check_auto_dock_colony(ship)

func _process_missions(dt: float) -> void:
	var missions := GameState.missions.duplicate()
	for mission: Mission in missions:
		mission.elapsed_ticks += dt

		match mission.status:
			Mission.Status.TRANSIT_OUT:
				_burn_fuel(mission, dt)
				if mission.elapsed_ticks >= mission.transit_time:
					# Check if using slingshot with more waypoints
					if mission.outbound_waypoint_index < mission.outbound_waypoints.size():
						# Reached waypoint - transition to next leg
						_process_waypoint_transition(mission, true)  # true = outbound
					else:
						# Reached final destination
						if mission.ship.get_cargo_total() >= mission.ship.cargo_capacity:
							# Ship is full, skip mining phase
							mission.status = Mission.Status.IDLE_AT_DESTINATION
							mission.ship.position_au = mission.asteroid.get_position_au()
							for w in mission.workers:
								w.assigned_mission = null
							EventBus.ship_idle_at_destination.emit(mission.ship, mission)
						else:
							mission.status = Mission.Status.MINING
							mission.elapsed_ticks = 0.0
						EventBus.mission_phase_changed.emit(mission)

			Mission.Status.MINING:
				_mine_tick(mission, dt)
				# Check if cargo is full (mining complete early)
				var cargo_full := mission.ship.get_cargo_total() >= mission.ship.cargo_capacity
				if mission.elapsed_ticks >= mission.mining_duration or cargo_full:
					mission.status = Mission.Status.IDLE_AT_DESTINATION
					mission.elapsed_ticks = 0.0
					# Set ship position to asteroid location
					mission.ship.position_au = mission.asteroid.get_position_au()
					# Free workers so they're available for next dispatch
					for w in mission.workers:
						w.assigned_mission = null
					EventBus.mission_phase_changed.emit(mission)
					EventBus.ship_idle_at_destination.emit(mission.ship, mission)

			Mission.Status.IDLE_AT_DESTINATION:
				# Ship idles here until player orders return or new dispatch
				pass

			Mission.Status.TRANSIT_BACK:
				_burn_fuel(mission, dt)
				if mission.elapsed_ticks >= mission.transit_time:
					# Check if using slingshot with more waypoints
					if mission.return_waypoint_index < mission.return_waypoints.size():
						# Reached waypoint - transition to next leg
						_process_waypoint_transition(mission, false)  # false = return
					else:
						# Reached final destination
						mission.ship.position_au = mission.return_position_au
						GameState.complete_mission(mission)

func _process_waypoint_transition(mission: Mission, is_outbound: bool) -> void:
	# Handle transition to next leg of slingshot journey
	if is_outbound:
		# Update ship position to waypoint
		mission.ship.position_au = mission.outbound_waypoints[mission.outbound_waypoint_index]

		# Increment to next leg
		mission.outbound_waypoint_index += 1
		mission.elapsed_ticks = 0.0

		# Set transit time for next leg
		if mission.outbound_waypoint_index < mission.outbound_leg_times.size():
			mission.transit_time = mission.outbound_leg_times[mission.outbound_waypoint_index]
		else:
			# Last leg to destination - use brachistochrone
			var dist := mission.ship.position_au.distance_to(mission.asteroid.get_position_au())
			mission.transit_time = Brachistochrone.transit_time(dist, mission.ship.get_effective_thrust())
	else:
		# Return journey
		mission.ship.position_au = mission.return_waypoints[mission.return_waypoint_index]

		mission.return_waypoint_index += 1
		mission.elapsed_ticks = 0.0

		if mission.return_waypoint_index < mission.return_leg_times.size():
			mission.transit_time = mission.return_leg_times[mission.return_waypoint_index]
		else:
			# Last leg to destination
			var dist := mission.ship.position_au.distance_to(mission.return_position_au)
			mission.transit_time = Brachistochrone.transit_time(dist, mission.ship.get_effective_thrust())

	EventBus.mission_phase_changed.emit(mission)

func _burn_fuel(mission: Mission, dt: float) -> void:
	var ship := mission.ship
	ship.fuel = maxf(ship.fuel - mission.fuel_per_tick * dt, 0.0)

	# If fuel reaches 0, ship becomes stranded
	if ship.fuel <= 0 and not ship.is_derelict:
		_trigger_fuel_depletion(ship)

func _mine_tick(mission: Mission, dt: float) -> void:
	var ship := mission.ship

	# Don't mine if cargo is already full
	var cargo_total := ship.get_cargo_total()
	if cargo_total >= ship.cargo_capacity:
		return  # Skip mining this tick

	if ship.get_cargo_remaining() <= 0:
		return

	var mining_skill_total := 0.0
	var best_engineer := 0.0
	for w in mission.workers:
		mining_skill_total += w.mining_skill
		if w.engineer_skill > best_engineer:
			best_engineer = w.engineer_skill
	if mining_skill_total < 0.1:
		mining_skill_total = 0.1  # Minimum so crew can still mine (slowly)

	var equip_mult := ship.get_mining_multiplier()
	var engineer_wear_factor := 1.0 - (best_engineer * 0.3)  # 1.0 = 0.7x wear, 1.5 = 0.55x

	# Random variance on this tick's output
	var luck := randf_range(MINING_VARIANCE_MIN, MINING_VARIANCE_MAX)

	for ore_type in mission.asteroid.ore_yields:
		var base_yield: float = mission.asteroid.ore_yields[ore_type]
		var mined: float = base_yield * mining_skill_total * equip_mult * luck * BASE_MINING_RATE * dt
		var remaining := ship.get_cargo_remaining()
		mined = minf(mined, remaining)
		if mined > 0:
			ship.current_cargo[ore_type] = ship.current_cargo.get(ore_type, 0.0) + mined

	# Degrade equipment during mining (reduced by engineer skill)
	for equip in ship.equipment:
		if equip.is_functional() and equip.durability > 0:
			var old_durability := equip.durability
			equip.durability = maxf(equip.durability - equip.wear_per_tick * engineer_wear_factor * dt, 0.0)
			if equip.durability <= 0.0 and old_durability > 0.0:
				EventBus.equipment_broken.emit(ship, equip)

func _process_fabrication(dt: float) -> void:
	# Tick down fabrication timers on queued items
	var completed: Array[Equipment] = []
	for equip in GameState.fabrication_queue:
		if equip.fabrication_ticks > 0:
			equip.fabrication_ticks = maxf(equip.fabrication_ticks - dt, 0.0)
			if equip.fabrication_ticks <= 0:
				completed.append(equip)

	# Move completed equipment to inventory
	for equip in completed:
		GameState.fabrication_queue.erase(equip)
		GameState.equipment_inventory.append(equip)
		EventBus.equipment_fabricated.emit(equip)

func _process_trade_missions(dt: float) -> void:
	var trade_missions := GameState.trade_missions.duplicate()
	for tm: TradeMission in trade_missions:
		tm.elapsed_ticks += dt

		match tm.status:
			TradeMission.Status.TRANSIT_TO_COLONY:
				tm.ship.fuel = maxf(tm.ship.fuel - tm.fuel_per_tick * dt, 0.0)
				# Check for fuel depletion
				if tm.ship.fuel <= 0 and not tm.ship.is_derelict:
					_trigger_fuel_depletion(tm.ship)
				if tm.elapsed_ticks >= tm.transit_time:
					# Check if auto-sell is enabled
					if GameState.settings.get("auto_sell_at_markets", false):
						tm.status = TradeMission.Status.SELLING
						tm.elapsed_ticks = 0.0
						# Auto-sell cargo at colony prices
						var revenue := 0
						for ore_type in tm.cargo:
							var amount: float = tm.cargo[ore_type]
							var price: float = tm.colony.get_ore_price(ore_type, GameState.market)
							revenue += int(amount * price)
						tm.revenue = revenue
						GameState.money += revenue
						# Clear cargo after selling
						tm.cargo.clear()
						tm.ship.current_cargo.clear()
						EventBus.trade_mission_phase_changed.emit(tm)
					else:
						# Manual selling: go directly to idle at colony
						tm.status = TradeMission.Status.IDLE_AT_COLONY
						tm.elapsed_ticks = 0.0
						# Dock ship at colony
						tm.ship.position_au = tm.colony.get_position_au()
						if tm.colony.has_rescue_ops:
							tm.ship.docked_at_colony = tm.colony
						# Auto-refuel at colony
						_auto_refuel_at_colony(tm.ship)
						EventBus.trade_mission_phase_changed.emit(tm)
						EventBus.ship_idle_at_colony.emit(tm.ship, tm)

			TradeMission.Status.SELLING:
				if tm.elapsed_ticks >= TradeMission.SELL_DURATION:
					tm.status = TradeMission.Status.IDLE_AT_COLONY
					tm.elapsed_ticks = 0.0
					# Dock ship at colony
					tm.ship.position_au = tm.colony.get_position_au()
					if tm.colony.has_rescue_ops:
						tm.ship.docked_at_colony = tm.colony
					# Auto-refuel at colony
					_auto_refuel_at_colony(tm.ship)
					# Workers are already freed (trade missions don't lock them)
					EventBus.trade_mission_phase_changed.emit(tm)
					EventBus.ship_idle_at_colony.emit(tm.ship, tm)

			TradeMission.Status.IDLE_AT_COLONY:
				# Ship idles here until player orders return or new dispatch
				pass

			TradeMission.Status.TRANSIT_BACK:
				tm.ship.fuel = maxf(tm.ship.fuel - tm.fuel_per_tick * dt, 0.0)
				# Check for fuel depletion
				if tm.ship.fuel <= 0 and not tm.ship.is_derelict:
					_trigger_fuel_depletion(tm.ship)
				if tm.elapsed_ticks >= tm.transit_time:
					# Set ship position to return destination
					tm.ship.position_au = tm.return_position_au
					GameState.complete_trade_mission(tm)

func _update_ship_positions(dt: float) -> void:
	# Save previous positions for collision detection (enter-radius check)
	var prev_positions: Dictionary = {}  # Ship -> Vector2
	for ship in GameState.ships:
		prev_positions[ship] = ship.position_au

	# Update ship positions and velocities during transit based on mission progress
	for mission: Mission in GameState.missions:
		var ship := mission.ship
		if ship.is_derelict:
			continue  # Derelicts handled in drift loop below
		match mission.status:
			Mission.Status.TRANSIT_OUT, Mission.Status.TRANSIT_BACK:
				var progress := mission.get_progress()
				var start_pos := mission.get_current_leg_start_pos()
				var end_pos := mission.get_current_leg_end_pos()
				_update_ship_transit_physics(ship, start_pos, end_pos, progress, mission.transit_mode, mission.transit_time, dt)
			Mission.Status.MINING, Mission.Status.IDLE_AT_DESTINATION:
				ship.position_au = mission.asteroid.get_position_au()
				ship.velocity_au_per_tick = Vector2.ZERO
				ship.speed_au_per_tick = 0.0

	for tm: TradeMission in GameState.trade_missions:
		var ship := tm.ship
		if ship.is_derelict:
			continue  # Derelicts handled in drift loop below
		match tm.status:
			TradeMission.Status.TRANSIT_TO_COLONY, TradeMission.Status.TRANSIT_BACK:
				var progress := tm.get_progress()
				var start_pos := tm.get_current_leg_start_pos()
				var end_pos := tm.get_current_leg_end_pos()
				_update_ship_transit_physics(ship, start_pos, end_pos, progress, tm.transit_mode, tm.transit_time, dt)
			TradeMission.Status.SELLING, TradeMission.Status.IDLE_AT_COLONY:
				ship.position_au = tm.colony.get_position_au()
				ship.velocity_au_per_tick = Vector2.ZERO
				ship.speed_au_per_tick = 0.0

	# Drift with n-body gravity: Sun + planets influence drifting ships
	for ship in GameState.ships:
		if ship.speed_au_per_tick > 0.0 and ship.current_mission == null and ship.current_trade_mission == null:
			# Symplectic Euler: update velocity first, then position
			var accel := CelestialData.gravitational_acceleration(ship.position_au)
			ship.velocity_au_per_tick += accel * dt
			ship.speed_au_per_tick = ship.velocity_au_per_tick.length()
			ship.position_au += ship.velocity_au_per_tick * dt

	# Check all moving ships for collisions with Sun or planets
	_check_ship_collisions(prev_positions)

func _check_ship_collisions(prev_positions: Dictionary) -> void:
	var destroyed_ships: Array[Ship] = []
	for ship in GameState.ships:
		# Only check collisions for derelict ships (no power/control)
		# Ships with working engines can navigate around obstacles
		if not ship.is_derelict:
			continue
		if ship.speed_au_per_tick <= 0.0:
			continue
		var prev_pos: Vector2 = prev_positions.get(ship, ship.position_au)
		var collision := CelestialData.check_collision(prev_pos, ship.position_au)
		if collision["hit"]:
			destroyed_ships.append(ship)
			var body_name: String = collision["body"]
			EventBus.ship_destroyed.emit(ship, body_name)

	for ship in destroyed_ships:
		# Remove all crew
		for w in ship.last_crew:
			if w is Worker:
				GameState.workers.erase(w)
		# Clean up missions
		if ship.current_mission:
			GameState.missions.erase(ship.current_mission)
			ship.current_mission = null
		if ship.current_trade_mission:
			GameState.trade_missions.erase(ship.current_trade_mission)
			ship.current_trade_mission = null
		# Clean up any pending rescue/refuel
		GameState.rescue_missions.erase(ship)
		GameState.refuel_missions.erase(ship)
		GameState.stranger_offers.erase(ship)
		# Remove the ship
		GameState.ships.erase(ship)

func _update_ship_transit_physics(ship: Ship, start_pos: Vector2, end_pos: Vector2, time_fraction: float, transit_mode: int, total_time: float, dt: float) -> void:
	# Update ship position and velocity based on transit physics + gravity
	var direction := (end_pos - start_pos).normalized()
	var total_distance := start_pos.distance_to(end_pos)

	if transit_mode == Mission.TransitMode.HOHMANN:
		ship.position_au = start_pos.lerp(end_pos, time_fraction)
		if total_time > 0:
			ship.velocity_au_per_tick = direction * (total_distance / total_time)
			ship.speed_au_per_tick = total_distance / total_time
		else:
			ship.velocity_au_per_tick = Vector2.ZERO
			ship.speed_au_per_tick = 0.0
	else:
		# Brachistochrone: constant thrust acceleration/deceleration
		var distance_fraction := _brachistochrone_distance_fraction(time_fraction)
		var velocity_fraction := _brachistochrone_velocity_fraction(time_fraction)

		ship.position_au = start_pos.lerp(end_pos, distance_fraction)

		if total_time > 0:
			var avg_velocity := total_distance / total_time
			var current_speed := avg_velocity * velocity_fraction
			ship.velocity_au_per_tick = direction * current_speed
			ship.speed_au_per_tick = current_speed
		else:
			ship.velocity_au_per_tick = Vector2.ZERO
			ship.speed_au_per_tick = 0.0

	# Apply gravitational perturbation from Sun + planets
	# Gravity bends the trajectory; thrust course-corrects to stay on target
	# Net effect: perpendicular deflection accumulates then gets corrected
	var grav_accel := CelestialData.gravitational_acceleration(ship.position_au)
	# Only apply the component perpendicular to thrust direction
	# (the along-track component is already handled by the thrust model)
	var perp := grav_accel - direction * grav_accel.dot(direction)
	ship.velocity_au_per_tick += perp * dt
	ship.speed_au_per_tick = ship.velocity_au_per_tick.length()

func _brachistochrone_distance_fraction(time_fraction: float) -> float:
	# Convert time progress to distance progress for constant-acceleration trajectory
	# Physics: x(t) = (1/2)*a*t² during acceleration, symmetric during deceleration
	# Results in S-curve: slow start (accelerating), fast middle, slow end (decelerating)
	if time_fraction <= 0.5:
		# Acceleration phase: quadratic growth
		# At t=0.25: distance = 2*(0.25)² = 0.125 (12.5%)
		return 2.0 * time_fraction * time_fraction
	else:
		# Deceleration phase: mirror of acceleration
		# At t=0.75: distance = 1 - 2*(0.25)² = 0.875 (87.5%)
		var t_from_end := 1.0 - time_fraction
		return 1.0 - 2.0 * t_from_end * t_from_end

func _brachistochrone_velocity_fraction(time_fraction: float) -> float:
	# Velocity as fraction of peak velocity for constant-acceleration trajectory
	# Physics: v(t) = a*t during acceleration, v(t) = a*(T-t) during deceleration
	# Peak velocity at midpoint is 2x the average velocity
	# Returns multiplier in range [0, 2] where 2 = peak velocity at midpoint
	if time_fraction <= 0.5:
		# Acceleration phase: linear ramp from 0 to 2
		# At t=0: velocity = 0
		# At t=0.5: velocity = 2 (peak)
		return 4.0 * time_fraction
	else:
		# Deceleration phase: linear ramp from 2 to 0
		# At t=0.5: velocity = 2 (peak)
		# At t=1.0: velocity = 0
		return 4.0 * (1.0 - time_fraction)

func _check_breakdowns(dt: float) -> void:
	for mission: Mission in GameState.missions:
		var ship := mission.ship
		if ship.is_derelict:
			continue
		if mission.status == Mission.Status.TRANSIT_OUT or mission.status == Mission.Status.TRANSIT_BACK:
			# Find best engineer skill in crew for wear reduction
			var best_engineer := 0.0
			for w in mission.workers:
				if w.engineer_skill > best_engineer:
					best_engineer = w.engineer_skill
			var eng_factor := 1.0 - (best_engineer * 0.3)

			# Degrade engine during transit (reduced by engineer skill)
			ship.engine_condition = maxf(ship.engine_condition - ship.engine_wear_per_tick * eng_factor * dt, 0.0)
			# Roll for breakdown (reduced by engineer skill)
			var chance := ship.get_breakdown_chance_per_tick() * eng_factor
			if chance > 0 and randf() < chance * dt:
				_trigger_breakdown(ship, "Engine failure during transit")

	for tm: TradeMission in GameState.trade_missions:
		var ship := tm.ship
		if ship.is_derelict:
			continue
		if tm.status == TradeMission.Status.TRANSIT_TO_COLONY or tm.status == TradeMission.Status.TRANSIT_BACK:
			# Find best engineer skill (trade missions store workers but don't lock them)
			var best_engineer := 0.0
			for w in ship.last_crew:
				if w.engineer_skill > best_engineer:
					best_engineer = w.engineer_skill
			var eng_factor := 1.0 - (best_engineer * 0.3)

			ship.engine_condition = maxf(ship.engine_condition - ship.engine_wear_per_tick * eng_factor * dt, 0.0)
			var chance := ship.get_breakdown_chance_per_tick() * eng_factor
			if chance > 0 and randf() < chance * dt:
				_trigger_breakdown(ship, "Engine failure during transit")

func _trigger_breakdown(ship: Ship, reason: String) -> void:
	ship.is_derelict = true
	ship.derelict_reason = "breakdown"

	# Remove from active mission tracking BEFORE emitting signals
	# so _refresh_ship_markers creates a derelict marker, not a mission marker
	if ship.current_mission:
		ship.current_mission.status = Mission.Status.COMPLETED
		GameState.missions.erase(ship.current_mission)
		for w in ship.current_mission.workers:
			w.assigned_mission = null
		ship.current_mission = null
	if ship.current_trade_mission:
		ship.current_trade_mission.status = TradeMission.Status.COMPLETED
		GameState.trade_missions.erase(ship.current_trade_mission)
		ship.current_trade_mission = null

	EventBus.ship_breakdown.emit(ship, reason)
	EventBus.ship_derelict.emit(ship)

func _trigger_fuel_depletion(ship: Ship) -> void:
	ship.is_derelict = true
	ship.derelict_reason = "out_of_fuel"

	# Remove from active mission tracking BEFORE emitting signals
	if ship.current_mission:
		ship.current_mission.status = Mission.Status.COMPLETED
		GameState.missions.erase(ship.current_mission)
		for w in ship.current_mission.workers:
			w.assigned_mission = null
		ship.current_mission = null
	if ship.current_trade_mission:
		ship.current_trade_mission.status = TradeMission.Status.COMPLETED
		GameState.trade_missions.erase(ship.current_trade_mission)
		ship.current_trade_mission = null

	EventBus.ship_breakdown.emit(ship, "Fuel depleted")
	EventBus.ship_derelict.emit(ship)

## Check if ship is near a colony with services and auto-dock
func _check_auto_dock_colony(ship: Ship) -> void:
	for colony in GameState.colonies:
		if not colony.has_rescue_ops:
			continue  # Only dock at colonies with services

		var dist := ship.position_au.distance_to(colony.get_position_au())
		if dist < Ship.COLONY_PROXIMITY_AU:
			ship.docked_at_colony = colony
			ship.position_au = colony.get_position_au()
			print("%s auto-docked at %s" % [ship.ship_name, colony.colony_name])
			return

func _process_rescues(dt: float) -> void:
	var completed_rescues: Array[Ship] = []
	for ship: Ship in GameState.rescue_missions:
		var data: Dictionary = GameState.rescue_missions[ship]
		data["elapsed_ticks"] += dt
		if data["elapsed_ticks"] >= data["transit_time"]:
			completed_rescues.append(ship)

	for ship in completed_rescues:
		var data: Dictionary = GameState.rescue_missions[ship]
		GameState.rescue_missions.erase(ship)

		# Rescue ship matches course, repairs in place, transfers fuel
		# Ship keeps its position and velocity — continues drifting
		ship.is_derelict = false
		ship.derelict_reason = ""
		ship.engine_condition = 50.0
		ship.fuel = ship.get_effective_fuel_capacity() * 0.5

		# 10% worker loss chance per worker
		var workers_to_check: Array = data.get("workers", [])
		for w in workers_to_check:
			if w is Worker and randf() < 0.1:
				GameState.workers.erase(w)
				EventBus.worker_fired.emit(w)

		EventBus.rescue_mission_completed.emit(ship)

func _process_refuels(dt: float) -> void:
	var completed_refuels: Array[Ship] = []
	for ship: Ship in GameState.refuel_missions:
		var data: Dictionary = GameState.refuel_missions[ship]
		data["elapsed_ticks"] += dt
		if data["elapsed_ticks"] >= data["transit_time"]:
			completed_refuels.append(ship)

	for ship in completed_refuels:
		var data: Dictionary = GameState.refuel_missions[ship]
		GameState.refuel_missions.erase(ship)

		# Add fuel to ship (capped at capacity)
		var fuel_delivered: float = data.get("fuel_amount", 0.0)
		ship.fuel = minf(ship.fuel + fuel_delivered, ship.fuel_capacity)

		# If ship was derelict due to fuel, restore it
		if ship.is_derelict and ship.derelict_reason == "out_of_fuel":
			ship.is_derelict = false
			ship.derelict_reason = ""
			ship.velocity_au_per_tick = Vector2.ZERO
			ship.speed_au_per_tick = 0.0

		EventBus.refuel_mission_completed.emit(ship, fuel_delivered)

const STRANGER_NAMES: Array[String] = [
	"ISV Wanderer", "MV Perseverance", "ISV Nomad", "FV Mercy",
	"MV Starlight", "ISV Vagrant", "FV Good Hope", "MV Solidarity",
	"ISV Horizon", "FV Kindred Spirit", "MV Dawn Treader", "ISV Wayfarer",
]

func _process_stranger_rescue(dt: float) -> void:
	# Expire old offers
	var expired_ships: Array[Ship] = []
	for ship: Ship in GameState.stranger_offers:
		var offer: Dictionary = GameState.stranger_offers[ship]
		offer["expires_ticks"] -= dt
		if offer["expires_ticks"] <= 0:
			expired_ships.append(ship)

	for ship in expired_ships:
		var offer: Dictionary = GameState.stranger_offers[ship]
		GameState.stranger_offers.erase(ship)
		EventBus.stranger_rescue_declined.emit(ship, offer["stranger_name"])

	# Check for new stranger rescue offers
	for ship: Ship in GameState.ships:
		if not ship.is_derelict:
			continue
		if ship in GameState.rescue_missions:
			continue
		if ship in GameState.refuel_missions:
			continue
		if ship in GameState.stranger_offers:
			continue

		# Base chance: 1 in 500,000 per tick (~once per 6 game-days)
		var chance := 1.0 / 500000.0

		# Traffic multiplier based on proximity to Earth/colonies
		var earth_dist := ship.position_au.distance_to(CelestialData.get_earth_position_au())
		var min_dist := earth_dist
		for colony in GameState.colonies:
			var d := ship.position_au.distance_to(colony.get_position_au())
			if d < min_dist:
				min_dist = d

		if min_dist < 1.0:
			chance *= 3.0  # Near civilization
		elif min_dist > 3.0:
			chance *= 0.5  # Deep space

		if randf() < chance * dt:
			var stranger_name: String = STRANGER_NAMES[randi() % STRANGER_NAMES.size()]
			var suggested_tip := randi_range(2000, 5000)
			GameState.stranger_offers[ship] = {
				"stranger_name": stranger_name,
				"expires_ticks": 43200.0,  # 12 hours game-time
				"suggested_tip": suggested_tip,
			}
			EventBus.stranger_rescue_offered.emit(ship, stranger_name)

func _process_payroll(dt: float) -> void:
	_payroll_accumulator += dt
	if _payroll_accumulator >= PAYROLL_INTERVAL:
		_payroll_accumulator -= PAYROLL_INTERVAL
		var total_wages := 0
		for w in GameState.workers:
			total_wages += w.wage
		if total_wages > 0:
			GameState.money -= total_wages

func _process_survey_events(dt: float) -> void:
	_survey_accumulator += dt
	if _survey_accumulator < SURVEY_INTERVAL:
		return
	_survey_accumulator -= SURVEY_INTERVAL

	if randf() > SURVEY_CHANCE:
		return
	if GameState.asteroids.is_empty():
		return

	# Pick a random asteroid and adjust one of its yields
	var asteroid: AsteroidData = GameState.asteroids[randi() % GameState.asteroids.size()]
	if asteroid.ore_yields.is_empty():
		return

	var ore_keys := asteroid.ore_yields.keys()
	var ore_type = ore_keys[randi() % ore_keys.size()]
	var old_yield: float = asteroid.ore_yields[ore_type]

	# Shift yield by -30% to +50% (slight upward bias to keep things interesting)
	var change := randf_range(-0.3, 0.5)
	var new_yield := maxf(old_yield * (1.0 + change), 0.1)
	asteroid.ore_yields[ore_type] = new_yield

	var ore_name: String = ResourceTypes.get_ore_name(ore_type)
	var message: String
	if new_yield > old_yield:
		message = "New survey: %s %s deposits richer than expected (%.1f -> %.1f)" % [
			asteroid.asteroid_name, ore_name, old_yield, new_yield
		]
	else:
		message = "New survey: %s %s deposits thinner than expected (%.1f -> %.1f)" % [
			asteroid.asteroid_name, ore_name, old_yield, new_yield
		]

	EventBus.survey_update.emit(asteroid, message)

func _process_market_events(dt: float) -> void:
	if not GameState.market:
		return

	# Advance time on active events
	var expired: Array[MarketEvent] = []
	for event in GameState.active_market_events:
		event.advance_time(dt)
		if not event.is_active:
			expired.append(event)

	# Remove expired events
	for event in expired:
		GameState.active_market_events.erase(event)
		EventBus.market_event_ended.emit(event)

	_market_accumulator += dt
	if _market_accumulator < MARKET_INTERVAL:
		return
	_market_accumulator -= MARKET_INTERVAL

	# Apply drift to all prices
	GameState.market.apply_drift()

	# Chance of new market event
	if randf() < MARKET_EVENT_CHANCE and GameState.active_market_events.size() < GameState.MAX_ACTIVE_EVENTS:
		_trigger_market_event()

func _trigger_market_event() -> void:
	var event := MarketEvent.generate_random()
	GameState.active_market_events.append(event)
	EventBus.market_event_started.emit(event)

func _process_contracts(dt: float) -> void:
	# Tick down active contract deadlines
	var failed: Array[Contract] = []
	for contract in GameState.active_contracts:
		contract.deadline_ticks -= dt
		if contract.deadline_ticks <= 0:
			contract.status = Contract.Status.FAILED
			failed.append(contract)

	for contract in failed:
		GameState.active_contracts.erase(contract)
		EventBus.contract_failed.emit(contract)

	# Expire available contracts
	var expired: Array[Contract] = []
	for contract in GameState.available_contracts:
		contract.deadline_ticks -= dt
		if contract.deadline_ticks <= 0:
			contract.status = Contract.Status.EXPIRED
			expired.append(contract)

	for contract in expired:
		GameState.available_contracts.erase(contract)
		EventBus.contract_expired.emit(contract)

	# Generate new contracts periodically
	_contract_accumulator += dt
	if _contract_accumulator >= CONTRACT_INTERVAL:
		_contract_accumulator -= CONTRACT_INTERVAL
		if randf() < CONTRACT_CHANCE and GameState.available_contracts.size() < GameState.MAX_AVAILABLE_CONTRACTS:
			var contract := Contract.generate_random()
			GameState.available_contracts.append(contract)
			EventBus.contract_offered.emit(contract)

func _auto_refuel_at_colony(ship: Ship) -> void:
	# Automatically refuel ship when it arrives at a colony
	if ship.fuel >= ship.get_effective_fuel_capacity():
		return  # Already full

	var fuel_needed := ship.get_effective_fuel_capacity() - ship.fuel
	# Use colony's local fuel price (no shipping cost)
	var fuel_cost := int(fuel_needed * FuelPricing.COLONY_BASE_COST)

	# Only refuel if player can afford it
	if GameState.money >= fuel_cost:
		ship.fuel = ship.get_effective_fuel_capacity()
		GameState.money -= fuel_cost
		# Note: Could add an event here if we want to notify player
