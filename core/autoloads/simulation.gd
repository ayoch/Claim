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

# Life support warning thresholds (percentage) — only fire once per threshold per ship
const LIFE_SUPPORT_WARN_THRESHOLDS: Array[float] = [0.75, 0.50, 0.25, 0.10]
var _life_support_warnings_fired: Dictionary = {}  # Ship -> Array of thresholds already fired

# Reusable buffers to avoid per-tick allocations
var _missions_buf: Array = []
var _trade_missions_buf: Array = []
var _prev_positions: Dictionary = {}
var _destroyed_ships_buf: Array[Ship] = []
var _ships_to_destroy_buf: Array[Ship] = []
var _expired_ships_buf: Array[Ship] = []

# Station ship autonomy
var _station_accumulator: float = 0.0
const STATION_CHECK_INTERVAL: float = 3600.0  # Check every game-hour
const STATION_RADIUS_AU: float = 1.0  # Ships consider targets within this radius of their station

# Worker fatigue (piggybacks on payroll accumulator interval)

# Worker leave processing
var _leave_accumulator: float = 0.0
const LEAVE_CHECK_INTERVAL: float = 86400.0  # Check once per game-day

# Greedy worker wage pressure
var _greedy_wage_accumulator: float = 0.0
const GREEDY_WAGE_INTERVAL: float = 86400.0 * 30.0  # Every 30 game-days

const TARDINESS_REASONS: Array[String] = [
	"Got drunk at a station bar and missed the shuttle",
	"Family emergency back home — needed extra time",
	"Missed the transport connection at %s",
	"Came down with Martian flu, quarantined for 3 days",
	"Got into a fistfight at %s, detained by station security",
	"Legal trouble — unpaid docking fines at %s",
	"Transport from %s delayed due to solar storm",
	"Took a mental health break — wasn't ready to come back",
	"Lost all their money gambling at %s, couldn't afford transport",
	"Got romantically entangled with someone at %s",
	"Lost their crew ID, took days to get a replacement",
	"Recreational zero-g injury — sprained ankle on shore leave",
]

# Real-time throttling for expensive operations (wall-clock time, not game time)
var _contracts_realtime_timer: float = 0.0
var _contracts_dt_accum: float = 0.0  # Accumulated game-time between throttled contract runs
var _survey_realtime_timer: float = 0.0
var _survey_dt_accum: float = 0.0  # Accumulated game-time between throttled survey runs
var _ship_positions_realtime_timer: float = 0.0
const CONTRACTS_REALTIME_INTERVAL: float = 0.5  # Process contracts twice per second max
const SURVEY_REALTIME_INTERVAL: float = 1.0  # Process surveys once per second max
const SHIP_POSITIONS_REALTIME_INTERVAL: float = 0.0333  # Update ship positions 30 times per second (smooth at high speeds)

func _ready() -> void:
	# Auto-slow to 1x on critical events
	EventBus.ship_breakdown.connect(func(_s: Ship, _r: String) -> void: TimeScale.slow_for_critical_event())
	EventBus.stranger_rescue_offered.connect(func(_s: Ship, _n: String) -> void: TimeScale.slow_for_critical_event())
	EventBus.ship_destroyed.connect(func(_s: Ship, _b: String) -> void: TimeScale.slow_for_critical_event())

func _process(delta: float) -> void:
	var game_speed := TimeScale.speed_multiplier
	if game_speed <= 0.0:
		return

	# Increment real-time throttle timers
	_contracts_realtime_timer += delta
	_survey_realtime_timer += delta
	_ship_positions_realtime_timer += delta

	_tick_accumulator += delta * game_speed
	var steps := 0
	var total_dt := 0.0
	while _tick_accumulator >= TICK_INTERVAL and steps < MAX_STEPS_PER_FRAME:
		# Batch ticks into larger steps when backlog is large
		var dt := minf(_tick_accumulator, MAX_DT_PER_STEP)
		_tick_accumulator -= dt
		_process_tick(dt, false)  # Don't emit tick per step — emit once below
		total_dt += dt
		steps += 1
	# Emit tick once per frame with total accumulated dt — prevents 30x signal spam
	if total_dt > 0.0:
		EventBus.tick.emit(total_dt)

func _process_tick(dt: float, emit_event: bool = true) -> void:

	GameState.total_ticks += dt

	# var t0 := Time.get_ticks_usec()
	_process_orbits(dt)
	# _record_perf("orbits", Time.get_ticks_usec() - t0)

	# Only emit tick event when throttled (prevents UI spam at high speeds)
	if emit_event:
		EventBus.tick.emit(dt)

	_process_missions(dt)
	_process_trade_missions(dt)
	_update_ship_positions(dt)
	_check_breakdowns(dt)
	_process_rescues(dt)
	_process_refuels(dt)
	_process_life_support(dt)
	_process_fabrication(dt)
	_process_stranger_rescue(dt)
	_process_payroll(dt)
	_process_worker_fatigue(dt)
	_process_deployed_crews(dt)
	_process_mining_units(dt)
	_process_asteroid_supplies(dt)
	_process_food_consumption(dt)
	_process_hitchhike_pool(dt)
	_process_worker_leave(dt)
	_process_greedy_wages(dt)
	_process_stationed_ships(dt)
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
	_missions_buf.assign(GameState.missions)
	for mission: Mission in _missions_buf:
		mission.elapsed_ticks += dt

		match mission.status:
			Mission.Status.TRANSIT_OUT:
				# Grant pilot XP to best pilot (they're flying)
				var best_pilot: Worker = null
				var best_pilot_skill := -1.0
				for w in mission.workers:
					if w.pilot_skill > best_pilot_skill:
						best_pilot = w
						best_pilot_skill = w.pilot_skill
				if best_pilot:
					best_pilot.add_xp(0, dt)  # 0 = pilot skill
				_burn_fuel(mission, dt)
				if mission.elapsed_ticks >= mission.transit_time:
					# Check if using slingshot with more waypoints
					if mission.outbound_waypoint_index < mission.outbound_waypoints.size():
						# Reached waypoint - transition to next leg
						_process_waypoint_transition(mission, true)  # true = outbound
					else:
						# Reached final destination — branch on mission type
						match mission.mission_type:
							Mission.MissionType.MINING:
								if mission.ship.get_cargo_total() >= mission.ship.cargo_capacity:
									# Ship is full, skip mining phase
									if mission.ship.is_stationed:
										_start_station_return(mission)
									else:
										mission.status = Mission.Status.IDLE_AT_DESTINATION
										mission.ship.position_au = mission.asteroid.get_position_au()
										for w in mission.workers:
											w.assigned_mission = null
										mission.workers.clear()
										EventBus.ship_idle_at_destination.emit(mission.ship, mission)
								else:
									mission.status = Mission.Status.MINING
									mission.elapsed_ticks = 0.0
							Mission.MissionType.REPAIR:
								mission.status = Mission.Status.REPAIRING
								mission.elapsed_ticks = 0.0
								if mission.destination_position_au != Vector2.ZERO:
									mission.ship.position_au = mission.destination_position_au
							Mission.MissionType.SUPPLY_RUN:
								mission.status = Mission.Status.DELIVERING
								mission.elapsed_ticks = 0.0
							Mission.MissionType.CREW_FERRY:
								mission.status = Mission.Status.BOARDING
								mission.elapsed_ticks = 0.0
							Mission.MissionType.PATROL:
								mission.status = Mission.Status.PATROLLING
								mission.elapsed_ticks = 0.0
								if mission.asteroid:
									mission.ship.position_au = mission.asteroid.get_position_au()
								# Create security zone
								_create_security_zone(mission.ship, mission.station_job_duration)
							Mission.MissionType.DEPLOY_UNIT:
								mission.status = Mission.Status.DEPLOYING
								mission.elapsed_ticks = 0.0
								if mission.asteroid:
									mission.ship.position_au = mission.asteroid.get_position_au()
							Mission.MissionType.COLLECT_ORE:
								mission.status = Mission.Status.COLLECTING
								mission.elapsed_ticks = 0.0
								if mission.asteroid:
									mission.ship.position_au = mission.asteroid.get_position_au()
						EventBus.mission_phase_changed.emit(mission)

			Mission.Status.REFUELING:
				if mission.elapsed_ticks >= Mission.REFUEL_DURATION:
					_complete_refuel_stop(mission, true)  # true = outbound

			Mission.Status.MINING:
				# Grant mining XP to crew during mining
				for w in mission.workers:
					w.add_xp(2, dt)  # 2 = mining skill
				_mine_tick(mission, dt)
				# Stay until hold is full; safety timeout at 2x estimated duration
				var cargo_full := mission.ship.get_cargo_total() >= mission.ship.get_effective_cargo_capacity() * 0.99
				if cargo_full or mission.elapsed_ticks >= mission.mining_duration * 2.0:
					# Stationed ships auto-return instead of idling
					if mission.ship.is_stationed:
						_start_station_return(mission)
					else:
						mission.status = Mission.Status.IDLE_AT_DESTINATION
						mission.elapsed_ticks = 0.0
						# Set ship position to asteroid location
						mission.ship.position_au = mission.asteroid.get_position_au()
						# Free workers so they're available for next dispatch
						for w in mission.workers:
							w.assigned_mission = null
						mission.workers.clear()
						EventBus.mission_phase_changed.emit(mission)
						EventBus.ship_idle_at_destination.emit(mission.ship, mission)

			Mission.Status.REPAIRING:
				if mission.elapsed_ticks >= mission.station_job_duration:
					_complete_repair_job(mission)

			Mission.Status.DELIVERING:
				if mission.elapsed_ticks >= mission.station_job_duration:
					_complete_delivery_job(mission)

			Mission.Status.BOARDING:
				if mission.elapsed_ticks >= mission.station_job_duration:
					_complete_boarding_job(mission)

			Mission.Status.PATROLLING:
				if mission.elapsed_ticks >= mission.station_job_duration:
					_expire_security_zone(mission.ship)
					_start_station_return(mission)

			Mission.Status.DEPLOYING:
				if mission.elapsed_ticks >= mission.deploy_duration:
					_complete_deploy(mission)

			Mission.Status.COLLECTING:
				if mission.elapsed_ticks >= 1800.0:  # 30 minutes to load ore
					_complete_collection(mission)

			Mission.Status.IDLE_AT_DESTINATION:
				# Ship idles here until player orders return or new dispatch
				pass

			Mission.Status.TRANSIT_BACK:
				# Grant pilot XP to best pilot (they're flying)
				var best_pilot: Worker = null
				var best_pilot_skill := -1.0
				for w in mission.workers:
					if w.pilot_skill > best_pilot_skill:
						best_pilot = w
						best_pilot_skill = w.pilot_skill
				if best_pilot:
					best_pilot.add_xp(0, dt)  # 0 = pilot skill
				_burn_fuel(mission, dt)
				if mission.elapsed_ticks >= mission.transit_time:
					# Check if using slingshot with more waypoints
					if mission.return_waypoint_index < mission.return_waypoints.size():
						# Reached waypoint - transition to next leg
						_process_waypoint_transition(mission, false)  # false = return
					else:
						# Reached final destination — use current Earth position (Earth orbits!)
						if mission.ship.is_stationed and mission.ship.station_colony:
							mission.ship.position_au = mission.ship.station_colony.get_position_au()
						elif not mission.return_to_station:
							mission.ship.position_au = CelestialData.get_earth_position_au()
							mission.ship.docked_at_colony = null  # Returning to Earth, not a colony
						else:
							mission.ship.position_au = mission.return_position_au
							# Clear docked_at_colony for non-stationed ships (will be set below if stationed)
							if not mission.ship.is_stationed:
								mission.ship.docked_at_colony = null
						# Stationed ships: dock at colony and refuel
						if mission.ship.is_stationed and mission.ship.station_colony:
							mission.ship.docked_at_colony = mission.ship.station_colony
							_auto_refuel_at_colony(mission.ship)
							_auto_provision_at_location(mission.ship)
							var cargo := mission.ship.get_cargo_total()
							if cargo > 0.1:
								mission.ship.add_station_log("Returned with %.0ft cargo" % cargo, "mining")
							# Crew ferry: fatigued passengers enter hitchhike pool at station
							if mission.mission_type == Mission.MissionType.CREW_FERRY:
								var station_name: String = mission.ship.station_colony.colony_name
								var station_pos: Vector2 = mission.ship.station_colony.get_position_au()
								for w in mission.workers:
									if w not in mission.ship.last_crew and w.needs_rotation:
										GameState.add_to_hitchhike_pool(w, station_name, station_pos)
						GameState.complete_mission(mission)

func _process_waypoint_transition(mission: Mission, is_outbound: bool) -> void:
	# Handle transition to next leg of multi-waypoint journey
	if is_outbound:
		# Get waypoint type
		var waypoint_type := Mission.WaypointType.GRAVITY_ASSIST
		if mission.outbound_waypoint_types.size() > mission.outbound_waypoint_index:
			waypoint_type = mission.outbound_waypoint_types[mission.outbound_waypoint_index] as Mission.WaypointType

		# Get waypoint position (may be updated colony position)
		var waypoint_pos := mission.outbound_waypoints[mission.outbound_waypoint_index]

		# If refuel stop, update to colony's CURRENT position (handles drift)
		if waypoint_type == Mission.WaypointType.REFUEL_STOP:
			var colony := mission.outbound_waypoint_colony_refs[mission.outbound_waypoint_index]
			if colony:
				waypoint_pos = colony.get_position_au()

		mission.ship.position_au = waypoint_pos

		# Handle based on type
		match waypoint_type:
			Mission.WaypointType.REFUEL_STOP:
				# Transition to REFUELING status
				mission.status = Mission.Status.REFUELING
				mission.elapsed_ticks = 0.0
				mission.outbound_waypoint_index += 1  # Advance now
				EventBus.mission_phase_changed.emit(mission)
				return  # Don't set transit_time yet

			Mission.WaypointType.GRAVITY_ASSIST:
				# Existing gravity assist behavior
				mission.outbound_waypoint_index += 1
				mission.elapsed_ticks = 0.0

				# Set transit time for next leg
				if mission.outbound_waypoint_index < mission.outbound_leg_times.size():
					mission.transit_time = mission.outbound_leg_times[mission.outbound_waypoint_index]
				else:
					# Last leg to destination
					var dist := mission.ship.position_au.distance_to(mission.asteroid.get_position_au())
					mission.transit_time = Brachistochrone.transit_time(dist, mission.ship.get_effective_thrust())
	else:
		# Return journey
		var waypoint_type := Mission.WaypointType.GRAVITY_ASSIST
		if mission.return_waypoint_types.size() > mission.return_waypoint_index:
			waypoint_type = mission.return_waypoint_types[mission.return_waypoint_index] as Mission.WaypointType

		var waypoint_pos := mission.return_waypoints[mission.return_waypoint_index]

		if waypoint_type == Mission.WaypointType.REFUEL_STOP:
			var colony := mission.return_waypoint_colony_refs[mission.return_waypoint_index]
			if colony:
				waypoint_pos = colony.get_position_au()

		mission.ship.position_au = waypoint_pos

		match waypoint_type:
			Mission.WaypointType.REFUEL_STOP:
				mission.status = Mission.Status.REFUELING
				mission.elapsed_ticks = 0.0
				mission.return_waypoint_index += 1
				EventBus.mission_phase_changed.emit(mission)
				return

			Mission.WaypointType.GRAVITY_ASSIST:
				mission.return_waypoint_index += 1
				mission.elapsed_ticks = 0.0

				if mission.return_waypoint_index < mission.return_leg_times.size():
					mission.transit_time = mission.return_leg_times[mission.return_waypoint_index]
				else:
					# Last leg to destination
					var dist := mission.ship.position_au.distance_to(mission.return_position_au)
					mission.transit_time = Brachistochrone.transit_time(dist, mission.ship.get_effective_thrust())

	EventBus.mission_phase_changed.emit(mission)

func _complete_refuel_stop(mission: Mission, is_outbound: bool) -> void:
	# Complete refueling at a waypoint and resume transit
	var waypoint_idx := mission.outbound_waypoint_index - 1 if is_outbound else mission.return_waypoint_index - 1

	# Add fuel to ship
	var fuel_amount: float = 0.0
	if is_outbound and waypoint_idx >= 0 and waypoint_idx < mission.outbound_waypoint_fuel_amounts.size():
		fuel_amount = mission.outbound_waypoint_fuel_amounts[waypoint_idx]
	elif not is_outbound and waypoint_idx >= 0 and waypoint_idx < mission.return_waypoint_fuel_amounts.size():
		fuel_amount = mission.return_waypoint_fuel_amounts[waypoint_idx]

	mission.ship.fuel = minf(mission.ship.fuel + fuel_amount, mission.ship.get_effective_fuel_capacity())

	# Check if NEXT leg is reachable (only validate immediate next destination)
	var next_dest_pos: Vector2
	if is_outbound:
		if mission.outbound_waypoint_index < mission.outbound_waypoints.size():
			# More waypoints ahead - check if we can reach the next one
			next_dest_pos = mission.outbound_waypoints[mission.outbound_waypoint_index]
		else:
			# No more waypoints - check if we can reach final destination
			next_dest_pos = mission.asteroid.get_position_au()
	else:
		if mission.return_waypoint_index < mission.return_waypoints.size():
			next_dest_pos = mission.return_waypoints[mission.return_waypoint_index]
		else:
			next_dest_pos = mission.return_position_au

	var cargo_mass := mission.ship.get_cargo_total()
	var dist_to_next := mission.ship.position_au.distance_to(next_dest_pos)
	var fuel_needed := mission.ship.calc_fuel_for_distance(dist_to_next, cargo_mass)

	if fuel_needed > mission.ship.fuel:
		# Next leg unreachable - abort mission at this fuel stop
		mission.status = Mission.Status.IDLE_AT_DESTINATION
		mission.elapsed_ticks = 0.0
		# Free workers
		for w in mission.workers:
			w.assigned_mission = null
		mission.workers.clear()
		EventBus.mission_phase_changed.emit(mission)
		# Notify player (could add a specific event for this)
		print("Mission aborted: next waypoint unreachable from fuel stop (orbital drift)")
		return

	# Resume transit
	mission.elapsed_ticks = 0.0
	mission.status = Mission.Status.TRANSIT_OUT if is_outbound else Mission.Status.TRANSIT_BACK

	# Set next leg transit time
	if is_outbound:
		if mission.outbound_waypoint_index < mission.outbound_leg_times.size():
			mission.transit_time = mission.outbound_leg_times[mission.outbound_waypoint_index]
		else:
			# Last leg to destination
			var dist := mission.ship.position_au.distance_to(mission.asteroid.get_position_au())
			mission.transit_time = Brachistochrone.transit_time(dist, mission.ship.get_effective_thrust())
	else:
		if mission.return_waypoint_index < mission.return_leg_times.size():
			mission.transit_time = mission.return_leg_times[mission.return_waypoint_index]
		else:
			# Last leg to destination
			var dist := mission.ship.position_au.distance_to(mission.return_position_au)
			mission.transit_time = Brachistochrone.transit_time(dist, mission.ship.get_effective_thrust())

	EventBus.mission_phase_changed.emit(mission)

func _process_trade_waypoint_transition(tm: TradeMission, is_outbound: bool) -> void:
	# Handle transition to next leg of multi-waypoint trade journey
	if is_outbound:
		var waypoint_type := TradeMission.WaypointType.GRAVITY_ASSIST
		if tm.outbound_waypoint_types.size() > tm.outbound_waypoint_index:
			waypoint_type = tm.outbound_waypoint_types[tm.outbound_waypoint_index] as TradeMission.WaypointType

		var waypoint_pos := tm.outbound_waypoints[tm.outbound_waypoint_index]

		if waypoint_type == TradeMission.WaypointType.REFUEL_STOP:
			var colony := tm.outbound_waypoint_colony_refs[tm.outbound_waypoint_index]
			if colony:
				waypoint_pos = colony.get_position_au()

		tm.ship.position_au = waypoint_pos

		match waypoint_type:
			TradeMission.WaypointType.REFUEL_STOP:
				tm.status = TradeMission.Status.REFUELING
				tm.elapsed_ticks = 0.0
				tm.outbound_waypoint_index += 1
				EventBus.trade_mission_phase_changed.emit(tm)
				return

			TradeMission.WaypointType.GRAVITY_ASSIST:
				tm.outbound_waypoint_index += 1
				tm.elapsed_ticks = 0.0

				if tm.outbound_waypoint_index < tm.outbound_leg_times.size():
					tm.transit_time = tm.outbound_leg_times[tm.outbound_waypoint_index]
				else:
					var dist := tm.ship.position_au.distance_to(tm.colony.get_position_au())
					tm.transit_time = Brachistochrone.transit_time(dist, tm.ship.get_effective_thrust())
	else:
		var waypoint_type := TradeMission.WaypointType.GRAVITY_ASSIST
		if tm.return_waypoint_types.size() > tm.return_waypoint_index:
			waypoint_type = tm.return_waypoint_types[tm.return_waypoint_index] as TradeMission.WaypointType

		var waypoint_pos := tm.return_waypoints[tm.return_waypoint_index]

		if waypoint_type == TradeMission.WaypointType.REFUEL_STOP:
			var colony := tm.return_waypoint_colony_refs[tm.return_waypoint_index]
			if colony:
				waypoint_pos = colony.get_position_au()

		tm.ship.position_au = waypoint_pos

		match waypoint_type:
			TradeMission.WaypointType.REFUEL_STOP:
				tm.status = TradeMission.Status.REFUELING
				tm.elapsed_ticks = 0.0
				tm.return_waypoint_index += 1
				EventBus.trade_mission_phase_changed.emit(tm)
				return

			TradeMission.WaypointType.GRAVITY_ASSIST:
				tm.return_waypoint_index += 1
				tm.elapsed_ticks = 0.0

				if tm.return_waypoint_index < tm.return_leg_times.size():
					tm.transit_time = tm.return_leg_times[tm.return_waypoint_index]
				else:
					var dist := tm.ship.position_au.distance_to(tm.return_position_au)
					tm.transit_time = Brachistochrone.transit_time(dist, tm.ship.get_effective_thrust())

	EventBus.trade_mission_phase_changed.emit(tm)

func _complete_trade_refuel_stop(tm: TradeMission, is_outbound: bool) -> void:
	# Complete refueling at a waypoint and resume transit
	var waypoint_idx := tm.outbound_waypoint_index - 1 if is_outbound else tm.return_waypoint_index - 1

	# Add fuel to ship
	var fuel_amount: float = 0.0
	if is_outbound and waypoint_idx >= 0 and waypoint_idx < tm.outbound_waypoint_fuel_amounts.size():
		fuel_amount = tm.outbound_waypoint_fuel_amounts[waypoint_idx]
	elif not is_outbound and waypoint_idx >= 0 and waypoint_idx < tm.return_waypoint_fuel_amounts.size():
		fuel_amount = tm.return_waypoint_fuel_amounts[waypoint_idx]

	tm.ship.fuel = minf(tm.ship.fuel + fuel_amount, tm.ship.get_effective_fuel_capacity())

	# Check if NEXT leg is reachable
	var next_dest_pos: Vector2
	if is_outbound:
		if tm.outbound_waypoint_index < tm.outbound_waypoints.size():
			next_dest_pos = tm.outbound_waypoints[tm.outbound_waypoint_index]
		else:
			next_dest_pos = tm.colony.get_position_au()
	else:
		if tm.return_waypoint_index < tm.return_waypoints.size():
			next_dest_pos = tm.return_waypoints[tm.return_waypoint_index]
		else:
			next_dest_pos = tm.return_position_au

	var cargo_mass := tm.ship.get_cargo_total()
	var dist_to_next := tm.ship.position_au.distance_to(next_dest_pos)
	var fuel_needed := tm.ship.calc_fuel_for_distance(dist_to_next, cargo_mass)

	if fuel_needed > tm.ship.fuel:
		# Next leg unreachable - abort mission at this fuel stop
		tm.status = TradeMission.Status.IDLE_AT_COLONY
		tm.elapsed_ticks = 0.0
		EventBus.trade_mission_phase_changed.emit(tm)
		print("Trade mission aborted: next waypoint unreachable from fuel stop (orbital drift)")
		return

	# Resume transit
	tm.elapsed_ticks = 0.0
	tm.status = TradeMission.Status.TRANSIT_TO_COLONY if is_outbound else TradeMission.Status.TRANSIT_BACK

	# Set next leg transit time
	if is_outbound:
		if tm.outbound_waypoint_index < tm.outbound_leg_times.size():
			tm.transit_time = tm.outbound_leg_times[tm.outbound_waypoint_index]
		else:
			var dist := tm.ship.position_au.distance_to(tm.colony.get_position_au())
			tm.transit_time = Brachistochrone.transit_time(dist, tm.ship.get_effective_thrust())
	else:
		if tm.return_waypoint_index < tm.return_leg_times.size():
			tm.transit_time = tm.return_leg_times[tm.return_waypoint_index]
		else:
			var dist := tm.ship.position_au.distance_to(tm.return_position_au)
			tm.transit_time = Brachistochrone.transit_time(dist, tm.ship.get_effective_thrust())

	EventBus.trade_mission_phase_changed.emit(tm)

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
	if cargo_total >= ship.get_effective_cargo_capacity():
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

	# Loyalty modifier: average across mission workers (0.9x to 1.0x range)
	var loyalty_total := 0.0
	var worker_count := mission.workers.size()
	for w in mission.workers:
		loyalty_total += w.loyalty_modifier
	var avg_loyalty_mod := loyalty_total / float(worker_count) if worker_count > 0 else 1.0

	var personality_mining_mult := _get_personality_mining_multiplier(mission.workers)
	var leader_mining_mult := _get_leader_mining_modifier(mission.workers)

	for ore_type in mission.asteroid.ore_yields:
		var base_yield: float = mission.asteroid.ore_yields[ore_type]
		var mined: float = base_yield * mining_skill_total * equip_mult * luck * avg_loyalty_mod * personality_mining_mult * leader_mining_mult * BASE_MINING_RATE * dt
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
	_trade_missions_buf.assign(GameState.trade_missions)
	for tm: TradeMission in _trade_missions_buf:
		tm.elapsed_ticks += dt

		match tm.status:
			TradeMission.Status.TRANSIT_TO_COLONY:
				# Grant pilot XP to best pilot (they're flying)
				var best_pilot: Worker = null
				var best_pilot_skill := -1.0
				for w in tm.workers:
					if w.pilot_skill > best_pilot_skill:
						best_pilot = w
						best_pilot_skill = w.pilot_skill
				if best_pilot:
					best_pilot.add_xp(0, dt)  # 0 = pilot skill
				tm.ship.fuel = maxf(tm.ship.fuel - tm.fuel_per_tick * dt, 0.0)
				# Check for fuel depletion
				if tm.ship.fuel <= 0 and not tm.ship.is_derelict:
					_trigger_fuel_depletion(tm.ship)
				if tm.elapsed_ticks >= tm.transit_time:
					# Check if using waypoints with more stops
					if tm.outbound_waypoint_index < tm.outbound_waypoints.size():
						# Reached waypoint - transition to next leg
						_process_trade_waypoint_transition(tm, true)  # true = outbound
					else:
						# Reached final destination (colony)
						# Auto-sell for stationed ships or when auto-sell setting is on
						if tm.ship.is_stationed or GameState.settings.get("auto_sell_at_markets", false):
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
							GameState.record_transaction(revenue, "Ore sold at %s" % tm.colony.colony_name, tm.ship.ship_name)
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

			TradeMission.Status.REFUELING:
				if tm.elapsed_ticks >= TradeMission.REFUEL_DURATION:
					_complete_trade_refuel_stop(tm, tm.status == TradeMission.Status.REFUELING and tm.outbound_waypoint_index > 0)

			TradeMission.Status.SELLING:
				if tm.elapsed_ticks >= TradeMission.SELL_DURATION:
					# Stationed ships: complete immediately (no idle), log the revenue
					if tm.ship.is_stationed:
						tm.ship.position_au = tm.colony.get_position_au()
						tm.ship.docked_at_colony = tm.colony
						_auto_refuel_at_colony(tm.ship)
						_auto_provision_at_location(tm.ship)
						tm.ship.add_station_log("Sold ore at %s — $%s" % [tm.colony.colony_name, tm.revenue], "trading")
						EventBus.station_job_completed.emit(tm.ship, "trading", "Sold ore for $%d" % tm.revenue)
						GameState.complete_trade_mission(tm)
					else:
						tm.status = TradeMission.Status.IDLE_AT_COLONY
						tm.elapsed_ticks = 0.0
						# Dock ship at colony
						tm.ship.position_au = tm.colony.get_position_au()
						tm.ship.docked_at_colony = tm.colony
						# Auto-refuel at colony
						_auto_refuel_at_colony(tm.ship)
						_auto_provision_at_location(tm.ship)
						EventBus.trade_mission_phase_changed.emit(tm)
						EventBus.ship_idle_at_colony.emit(tm.ship, tm)

			TradeMission.Status.IDLE_AT_COLONY:
				# Ship idles here until player orders return or new dispatch
				pass

			TradeMission.Status.TRANSIT_BACK:
				# Grant pilot XP to best pilot (they're flying)
				var best_pilot: Worker = null
				var best_pilot_skill := -1.0
				for w in tm.workers:
					if w.pilot_skill > best_pilot_skill:
						best_pilot = w
						best_pilot_skill = w.pilot_skill
				if best_pilot:
					best_pilot.add_xp(0, dt)  # 0 = pilot skill
				tm.ship.fuel = maxf(tm.ship.fuel - tm.fuel_per_tick * dt, 0.0)
				# Check for fuel depletion
				if tm.ship.fuel <= 0 and not tm.ship.is_derelict:
					_trigger_fuel_depletion(tm.ship)
				if tm.elapsed_ticks >= tm.transit_time:
					# Check if using waypoints with more stops
					if tm.return_waypoint_index < tm.return_waypoints.size():
						# Reached waypoint - transition to next leg
						_process_trade_waypoint_transition(tm, false)  # false = return
					else:
						# Reached final destination — use current position (bodies orbit!)
						if tm.ship.is_stationed and tm.ship.station_colony:
							tm.ship.position_au = tm.ship.station_colony.get_position_au()
						else:
							tm.ship.position_au = CelestialData.get_earth_position_au()
							tm.ship.docked_at_colony = null  # Returning to Earth, not a colony
						GameState.complete_trade_mission(tm)

func _update_ship_positions(dt: float) -> void:
	# Real-time throttle - only update 10 times per second for mobile performance
	# This is smooth enough for visuals while being much cheaper than every tick
	if _ship_positions_realtime_timer < SHIP_POSITIONS_REALTIME_INTERVAL:
		return
	_ship_positions_realtime_timer = 0.0

	# Save previous positions for collision detection (enter-radius check)
	_prev_positions.clear()
	for ship in GameState.ships:
		_prev_positions[ship] = ship.position_au

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
			Mission.Status.MINING, Mission.Status.IDLE_AT_DESTINATION, Mission.Status.DEPLOYING, Mission.Status.COLLECTING:
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

	# Drift with Sun gravity only (planets are ~1000x less massive, negligible for mobile perf)
	for ship in GameState.ships:
		if ship.speed_au_per_tick > 0.0 and ship.current_mission == null and ship.current_trade_mission == null:
			# Symplectic Euler: update velocity first, then position
			# Sun-only gravity (simple, fast, 90% accurate)
			var r_sun := -ship.position_au
			var dist_sq := r_sun.length_squared()
			var accel := Vector2.ZERO
			if dist_sq > 1e-12:
				var dist := sqrt(dist_sq)
				accel = r_sun * (CelestialData.GM_SUN / (dist_sq * dist))

			ship.velocity_au_per_tick += accel * dt
			ship.speed_au_per_tick = ship.velocity_au_per_tick.length()
			ship.position_au += ship.velocity_au_per_tick * dt

	# Check all moving ships for collisions with Sun or planets
	_check_ship_collisions(_prev_positions)

func _check_ship_collisions(prev_positions: Dictionary) -> void:
	_destroyed_ships_buf.clear()
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
			_destroyed_ships_buf.append(ship)
			var body_name: String = collision["body"]
			EventBus.ship_destroyed.emit(ship, body_name)

	for ship in _destroyed_ships_buf:
		# Remove all crew
		for w in ship.last_crew:
			if w is Worker:
				GameState.fire_worker(w)
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
		# Remove the ship and free its name for reuse
		ShipData.release_name(ship.ship_name)
		GameState.ships.erase(ship)

func _update_ship_transit_physics(ship: Ship, start_pos: Vector2, end_pos_stored: Vector2, time_fraction: float, transit_mode: int, total_time: float, dt: float) -> void:
	# Simplified physics for mobile: Sun-only gravity (planets negligible for performance)

	# IMPORTANT: If target is Earth, use current Earth position (it's orbiting!)
	# Otherwise ship aims where Earth WAS, not where it IS
	var end_pos := end_pos_stored
	var earth_pos := CelestialData.get_earth_position_au()
	if end_pos_stored.distance_to(earth_pos) < 0.05:  # Within 0.05 AU = targeting Earth
		end_pos = earth_pos  # Track Earth's current position

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

	# Apply Sun gravity (simple, fast, 90% accurate)
	# Gravity bends trajectory; thrust corrects to stay on target
	var r_sun := -ship.position_au
	var dist_sq := r_sun.length_squared()
	if dist_sq > 1e-12:
		var dist := sqrt(dist_sq)
		var grav_accel := r_sun * (CelestialData.GM_SUN / (dist_sq * dist))
		# Apply only perpendicular component (along-track handled by thrust model)
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
	# Check for engineer self-repair before declaring breakdown
	var crew: Array[Worker] = []
	if ship.current_mission:
		crew = ship.current_mission.workers
	elif ship.current_trade_mission:
		crew = ship.current_trade_mission.workers

	# Find best engineer
	var best_engineer := 0.0
	for w in crew:
		if w.engineer_skill > best_engineer:
			best_engineer = w.engineer_skill

	# Self-repair chance: 0% at 0.0 skill, 30% at 1.0 skill, 50% at 1.5 skill
	var repair_chance := best_engineer * 0.3 + (maxf(best_engineer - 1.0, 0.0) * 0.2)
	if repair_chance > 0 and randf() < repair_chance:
		# Engineer patched it! Reduce engine condition but continue mission
		ship.engine_condition = maxf(ship.engine_condition * 0.5, 20.0)
		print("Ship %s: Engineer patched breakdown in-situ (skill %.1f)" % [ship.ship_name, best_engineer])
		# Grant bonus engineer XP to the engineer who performed the repair
		for w in crew:
			if w.engineer_skill == best_engineer:
				w.add_xp(1, 43200.0)  # 1 = engineer skill, half a day's worth as bonus
				break
		EventBus.ship_breakdown.emit(ship, "Minor failure (repaired)")
		return

	# No repair - full breakdown
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
		for w in ship.current_trade_mission.workers:
			w.assigned_trade_mission = null
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
		for w in ship.current_trade_mission.workers:
			w.assigned_trade_mission = null
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

		# Reset life support (rescue brings supplies)
		var workers_to_check: Array = data.get("workers", [])
		ship.reset_life_support(workers_to_check.size())

		# 10% worker loss chance per worker
		for w in workers_to_check:
			if w is Worker and randf() < 0.1:
				GameState.fire_worker(w)

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
			# Ship keeps drifting velocity - refuel doesn't magically stop momentum

		EventBus.refuel_mission_completed.emit(ship, fuel_delivered)

func _process_life_support(dt: float) -> void:
	# Derelict ships consume life support (food, water, O2)
	# When life support runs out, crew dies and ship is total loss
	_ships_to_destroy_buf.clear()

	for ship in GameState.ships:
		if not ship.is_derelict:
			# Clean up warning tracking if ship was rescued
			_life_support_warnings_fired.erase(ship)
			continue

		# Initialize warning tracking for this ship
		if ship not in _life_support_warnings_fired:
			_life_support_warnings_fired[ship] = []

		# Consume life support
		ship.life_support_remaining -= dt

		# Check warning thresholds
		var max_life_support := ship.calculate_life_support_duration(maxi(ship.last_crew.size(), 1))
		var pct := ship.life_support_remaining / max_life_support
		var fired: Array = _life_support_warnings_fired[ship]
		for threshold in LIFE_SUPPORT_WARN_THRESHOLDS:
			if pct <= threshold and threshold not in fired:
				fired.append(threshold)
				EventBus.life_support_warning.emit(ship, pct)
				# Auto-pause at 10% to give player time to react
				if threshold <= 0.10:
					TimeScale.slow_for_critical_event()

		# Check if crew has died
		if ship.life_support_remaining <= 0:
			_ships_to_destroy_buf.append(ship)

	# Destroy ships with dead crews
	for ship in _ships_to_destroy_buf:
		var crew_count := ship.last_crew.size()
		print("Ship %s: crew of %d died from life support failure" % [ship.ship_name, crew_count])

		# Clean up mission tracking
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
		_life_support_warnings_fired.erase(ship)

		# Emit event before removing ship
		EventBus.ship_destroyed.emit(ship, "Life support failure")

		# Remove the ship and free its name for reuse
		ShipData.release_name(ship.ship_name)
		GameState.ships.erase(ship)

const STRANGER_NAMES: Array[String] = [
	"ISV Wanderer", "MV Perseverance", "ISV Nomad", "FV Mercy",
	"MV Starlight", "ISV Vagrant", "FV Good Hope", "MV Solidarity",
	"ISV Horizon", "FV Kindred Spirit", "MV Dawn Treader", "ISV Wayfarer",
]

func _process_stranger_rescue(dt: float) -> void:
	# Expire old offers
	_expired_ships_buf.clear()
	for ship: Ship in GameState.stranger_offers:
		var offer: Dictionary = GameState.stranger_offers[ship]
		offer["expires_ticks"] -= dt
		if offer["expires_ticks"] <= 0:
			_expired_ships_buf.append(ship)

	for ship in _expired_ships_buf:
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

func _process_stationed_ships(dt: float) -> void:
	_station_accumulator += dt
	if _station_accumulator < STATION_CHECK_INTERVAL:
		return
	_station_accumulator -= STATION_CHECK_INTERVAL
	_cleanup_expired_security_zones()

	for ship in GameState.ships:
		if not ship.is_stationed_idle:
			continue
		# Validate crew — check that last_crew workers are still in the company
		var valid_crew: Array[Worker] = []
		for w in ship.last_crew:
			if w in GameState.workers and (w.assigned_station_ship == ship or w.is_available):
				valid_crew.append(w)
			elif w.assigned_station_ship == ship:
				w.assigned_station_ship = null  # Worker left company, clean up
		ship.last_crew = valid_crew
		if ship.last_crew.size() < ship.min_crew:
			continue  # Not enough crew to do anything

		# Walk station_jobs in priority order, take first actionable job
		for job in ship.station_jobs:
			var took_job := false
			match job:
				"mining":
					took_job = _station_try_mining(ship)
				"trading":
					took_job = _station_try_trading(ship)
				"repair":
					took_job = _station_try_repair(ship)
				"parts_delivery":
					took_job = _station_try_parts_delivery(ship)
				"provisioning":
					took_job = _station_try_provisioning(ship)
				"crew_ferry":
					took_job = _station_try_crew_ferry(ship)
				"patrol":
					took_job = _station_try_patrol(ship)
			if took_job:
				break  # Only do one job at a time

func _station_try_mining(ship: Ship) -> bool:
	# Actionable if: cargo space > 10%, fuel sufficient, crew aboard
	if ship.get_cargo_remaining() < ship.get_effective_cargo_capacity() * 0.1:
		return false

	var station_pos: Vector2 = ship.station_colony.get_position_au()

	# Find nearest mineable asteroid within station radius
	var best_asteroid: AsteroidData = null
	var best_dist: float = INF
	for asteroid in GameState.asteroids:
		if asteroid.ore_yields.is_empty():
			continue
		var dist := station_pos.distance_to(asteroid.get_position_au())
		if dist < STATION_RADIUS_AU and dist < best_dist:
			# Check if we have fuel for round-trip
			var candidate_fuel := ship.calc_fuel_for_distance(dist, ship.get_cargo_total()) + ship.calc_fuel_for_distance(dist, ship.get_effective_cargo_capacity())
			if candidate_fuel <= ship.fuel:
				best_asteroid = asteroid
				best_dist = dist

	if best_asteroid == null:
		return false

	# Dispatch mining mission that returns to station
	var workers: Array[Worker] = ship.last_crew.duplicate()
	var mission := GameState.start_mission(ship, best_asteroid, workers)
	if mission:
		mission.return_to_station = true
		mission.return_position_au = station_pos
		ship.add_station_log("Mining %s" % best_asteroid.asteroid_name, "mining")
		EventBus.station_job_started.emit(ship, "mining", best_asteroid.asteroid_name)
	return mission != null

func _station_try_trading(ship: Ship) -> bool:
	# Actionable if: ship has ore cargo to sell
	if ship.get_cargo_total() < 0.1:
		return false

	var colony: Colony = ship.station_colony
	# Build cargo dict from ship's current cargo
	var cargo_to_sell: Dictionary = ship.current_cargo.duplicate()

	# Create trade mission to the station colony itself (local sale)
	var workers: Array[Worker] = ship.last_crew.duplicate()
	var tm := GameState.start_trade_mission(ship, colony, workers, cargo_to_sell)
	if tm:
		var cargo_total := ship.get_cargo_total()
		ship.add_station_log("Trading %.0ft ore at %s" % [cargo_total, colony.colony_name], "trading")
		EventBus.station_job_started.emit(ship, "trading", colony.colony_name)
	return tm != null

func _station_try_repair(ship: Ship) -> bool:
	# Find nearby derelict ships that need repair
	var station_pos: Vector2 = ship.station_colony.get_position_au()
	var best_target: Ship = null
	var best_dist: float = INF

	for other_ship in GameState.ships:
		if other_ship == ship:
			continue
		if not other_ship.is_derelict:
			continue
		if other_ship in GameState.rescue_missions:
			continue  # Already being rescued
		var dist := station_pos.distance_to(other_ship.position_au)
		if dist < STATION_RADIUS_AU and dist < best_dist:
			var candidate_fuel := ship.calc_fuel_for_distance(dist, 0.0) * 2.0  # Round trip
			if candidate_fuel <= ship.fuel:
				best_target = other_ship
				best_dist = dist

	if best_target == null:
		return false

	# Create repair mission
	var workers: Array[Worker] = ship.last_crew.duplicate()
	var mission := Mission.new()
	mission.mission_type = Mission.MissionType.REPAIR
	mission.ship = ship
	mission.workers = workers
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ship.position_au
	mission.origin_is_earth = false
	mission.return_position_au = ship.station_colony.get_position_au()
	mission.return_to_station = true
	mission.destination_position_au = best_target.position_au
	mission.transit_time = Brachistochrone.transit_time(best_dist, ship.get_effective_thrust())
	mission.station_job_duration = 3600.0  # 1 hour to repair
	mission.elapsed_ticks = 0.0

	var fuel_needed := ship.calc_fuel_for_distance(best_dist, 0.0) * 2.0
	mission.fuel_per_tick = fuel_needed / (mission.transit_time * 2.0) if mission.transit_time > 0 else 0.0

	ship.current_mission = mission
	ship.reset_life_support(workers.size())
	for w in workers:
		w.assigned_mission = mission
	GameState.missions.append(mission)
	EventBus.mission_started.emit(mission)

	ship.add_station_log("Repairing %s" % best_target.ship_name, "repair")
	EventBus.station_job_started.emit(ship, "repair", best_target.ship_name)
	return true

func _station_try_parts_delivery(ship: Ship) -> bool:
	# Deliver repair parts to damaged (but not derelict) ships with broken equipment
	var repair_parts: float = ship.supplies.get("repair_parts", 0.0)
	if repair_parts < 1.0:
		return false  # No parts to deliver

	var station_pos: Vector2 = ship.station_colony.get_position_au()
	var best_target: Ship = null
	var best_dist: float = INF

	for other_ship in GameState.ships:
		if other_ship == ship:
			continue
		if other_ship.is_derelict:
			continue  # Derelicts need full repair, not parts
		# Check for broken equipment
		var has_broken := false
		for equip in other_ship.equipment:
			if equip.durability <= 0:
				has_broken = true
				break
		if not has_broken:
			continue

		var dist := station_pos.distance_to(other_ship.position_au)
		if dist < STATION_RADIUS_AU and dist > 0.01 and dist < best_dist:
			var candidate_fuel := ship.calc_fuel_for_distance(dist, ship.get_supplies_mass()) * 2.0
			if candidate_fuel <= ship.fuel:
				best_target = other_ship
				best_dist = dist

	if best_target == null:
		return false

	var workers: Array[Worker] = ship.last_crew.duplicate()
	var mission := Mission.new()
	mission.mission_type = Mission.MissionType.SUPPLY_RUN
	mission.ship = ship
	mission.workers = workers
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ship.position_au
	mission.origin_is_earth = false
	mission.return_position_au = ship.station_colony.get_position_au()
	mission.return_to_station = true
	mission.destination_position_au = best_target.position_au
	mission.transit_time = Brachistochrone.transit_time(best_dist, ship.get_effective_thrust())
	mission.station_job_duration = 1800.0  # 30 min to transfer parts
	mission.elapsed_ticks = 0.0

	var fuel_needed := ship.calc_fuel_for_distance(best_dist, ship.get_supplies_mass()) * 2.0
	mission.fuel_per_tick = fuel_needed / (mission.transit_time * 2.0) if mission.transit_time > 0 else 0.0

	ship.current_mission = mission
	ship.docked_at_colony = null
	ship.reset_life_support(workers.size())
	for w in workers:
		w.assigned_mission = mission
	GameState.missions.append(mission)
	EventBus.mission_started.emit(mission)

	ship.add_station_log("Delivering parts to %s" % best_target.ship_name, "supply")
	EventBus.station_job_started.emit(ship, "parts_delivery", best_target.ship_name)
	return true

func _station_try_provisioning(ship: Ship) -> bool:
	# Find deployed crews in radius running low on food
	var station_pos: Vector2 = ship.station_colony.get_position_au()
	var food_on_ship: float = ship.supplies.get("food", 0.0)

	if food_on_ship < 1.0:
		return false  # No food to deliver

	var best_target: Dictionary = {}
	var best_dist: float = INF

	for crew_entry in GameState.deployed_crews:
		var asteroid: AsteroidData = crew_entry["asteroid"]
		var supplies: Dictionary = crew_entry["supplies"]
		var food_remaining: float = supplies.get("food", 0.0)
		var worker_count: int = crew_entry["workers"].size()

		# Need provisioning if food is below 50% of a 10-day supply
		var days_of_food := food_remaining / (worker_count * 0.5) if worker_count > 0 else 999.0
		if days_of_food >= 5.0:
			continue  # Still has enough

		var asteroid_pos := asteroid.get_position_au()
		var dist := station_pos.distance_to(asteroid_pos)
		if dist < STATION_RADIUS_AU and dist < best_dist:
			var candidate_fuel := ship.calc_fuel_for_distance(dist, 0.0) * 2.0
			if candidate_fuel <= ship.fuel:
				best_target = crew_entry
				best_dist = dist

	if best_target.is_empty():
		return false

	var target_asteroid: AsteroidData = best_target["asteroid"]

	# Create supply run mission with food
	var crew: Array[Worker] = ship.last_crew.duplicate()
	var mission := Mission.new()
	mission.mission_type = Mission.MissionType.SUPPLY_RUN
	mission.ship = ship
	mission.workers = crew
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ship.position_au
	mission.origin_is_earth = false
	mission.return_position_au = ship.station_colony.get_position_au()
	mission.return_to_station = true
	mission.destination_position_au = target_asteroid.get_position_au()
	mission.transit_time = Brachistochrone.transit_time(best_dist, ship.get_effective_thrust())
	mission.station_job_duration = 1800.0  # 30 min to offload supplies
	mission.elapsed_ticks = 0.0

	var fuel_needed := ship.calc_fuel_for_distance(best_dist, 0.0) * 2.0
	mission.fuel_per_tick = fuel_needed / (mission.transit_time * 2.0) if mission.transit_time > 0 else 0.0

	ship.current_mission = mission
	ship.reset_life_support(crew.size())
	for w in crew:
		w.assigned_mission = mission
	GameState.missions.append(mission)
	EventBus.mission_started.emit(mission)

	ship.add_station_log("Provisioning crew at %s" % target_asteroid.asteroid_name, "provisioning")
	EventBus.station_job_started.emit(ship, "provisioning", target_asteroid.asteroid_name)
	return true

func _station_try_crew_ferry(ship: Ship) -> bool:
	# Find nearby ships on missions with fatigued workers
	var station_pos: Vector2 = ship.station_colony.get_position_au()

	# Find fresh workers at station to swap in
	var fresh_workers: Array[Worker] = []
	for w in GameState.workers:
		if w.is_available and not w.needs_rotation:
			fresh_workers.append(w)

	if fresh_workers.is_empty():
		return false

	# Find target ship with fatigued crew
	var best_target: Ship = null
	var best_dist: float = INF
	var fatigued_count: int = 0

	for other_ship in GameState.ships:
		if other_ship == ship:
			continue
		if other_ship.current_mission == null:
			continue
		# Check if any crew need rotation
		var tired: int = 0
		for w in other_ship.current_mission.workers:
			if w.needs_rotation:
				tired += 1
		if tired == 0:
			continue
		var dist := station_pos.distance_to(other_ship.position_au)
		if dist < STATION_RADIUS_AU and dist < best_dist:
			var candidate_fuel := ship.calc_fuel_for_distance(dist, 0.0) * 2.0
			if candidate_fuel <= ship.fuel:
				best_target = other_ship
				best_dist = dist
				fatigued_count = tired

	if best_target == null:
		return false

	# Bring fresh replacements (up to fatigued count)
	var replacements: Array[Worker] = []
	for i in range(mini(fatigued_count, fresh_workers.size())):
		replacements.append(fresh_workers[i])

	if replacements.is_empty():
		return false

	# Create crew ferry mission
	var crew: Array[Worker] = ship.last_crew.duplicate()
	# Add replacement workers as passengers
	for w in replacements:
		if w not in crew:
			crew.append(w)

	var mission := Mission.new()
	mission.mission_type = Mission.MissionType.CREW_FERRY
	mission.ship = ship
	mission.workers = crew
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ship.position_au
	mission.origin_is_earth = false
	mission.return_position_au = ship.station_colony.get_position_au()
	mission.return_to_station = true
	mission.destination_position_au = best_target.position_au
	mission.transit_time = Brachistochrone.transit_time(best_dist, ship.get_effective_thrust())
	mission.station_job_duration = 1800.0  # 30 min for boarding
	mission.elapsed_ticks = 0.0

	var fuel_needed := ship.calc_fuel_for_distance(best_dist, 0.0) * 2.0
	mission.fuel_per_tick = fuel_needed / (mission.transit_time * 2.0) if mission.transit_time > 0 else 0.0

	ship.current_mission = mission
	ship.reset_life_support(crew.size())
	for w in crew:
		w.assigned_mission = mission
	GameState.missions.append(mission)
	EventBus.mission_started.emit(mission)

	ship.add_station_log("Crew ferry to %s (%d fatigued)" % [best_target.ship_name, fatigued_count], "crew_ferry")
	EventBus.station_job_started.emit(ship, "crew_ferry", best_target.ship_name)
	return true

func _station_try_patrol(ship: Ship) -> bool:
	# Minimal patrol: orbit nearby rocks for 1 game-day then return
	var station_pos: Vector2 = ship.station_colony.get_position_au()

	# Find a nearby asteroid to patrol around
	var best_asteroid: AsteroidData = null
	var best_dist: float = INF
	for asteroid in GameState.asteroids:
		var dist := station_pos.distance_to(asteroid.get_position_au())
		if dist < STATION_RADIUS_AU * 0.5 and dist > 0.01 and dist < best_dist:
			var candidate_fuel := ship.calc_fuel_for_distance(dist, 0.0) * 2.0
			if candidate_fuel <= ship.fuel:
				best_asteroid = asteroid
				best_dist = dist

	if best_asteroid == null:
		return false

	var workers: Array[Worker] = ship.last_crew.duplicate()
	var mission := Mission.new()
	mission.mission_type = Mission.MissionType.PATROL
	mission.ship = ship
	mission.asteroid = best_asteroid  # Use asteroid for position tracking
	mission.workers = workers
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ship.position_au
	mission.origin_is_earth = false
	mission.return_position_au = ship.station_colony.get_position_au()
	mission.return_to_station = true
	mission.transit_time = Brachistochrone.transit_time(best_dist, ship.get_effective_thrust())
	mission.station_job_duration = 86400.0  # 1 game-day patrol
	mission.elapsed_ticks = 0.0

	var fuel_needed := ship.calc_fuel_for_distance(best_dist, 0.0) * 2.0
	mission.fuel_per_tick = fuel_needed / (mission.transit_time * 2.0) if mission.transit_time > 0 else 0.0

	ship.current_mission = mission
	ship.reset_life_support(workers.size())
	for w in workers:
		w.assigned_mission = mission
	GameState.missions.append(mission)
	EventBus.mission_started.emit(mission)

	ship.add_station_log("Patrolling near %s" % best_asteroid.asteroid_name, "patrol")
	EventBus.station_job_started.emit(ship, "patrol", best_asteroid.asteroid_name)
	return true

func _create_security_zone(ship: Ship, duration: float) -> void:
	GameState.security_zones.append({
		"center_au": ship.position_au,
		"radius_au": STATION_RADIUS_AU * 0.3,
		"ship_name": ship.ship_name,
		"expires_at": GameState.total_ticks + duration,
	})

func _expire_security_zone(ship: Ship) -> void:
	for i in range(GameState.security_zones.size() - 1, -1, -1):
		if GameState.security_zones[i]["ship_name"] == ship.ship_name:
			GameState.security_zones.remove_at(i)

func _cleanup_expired_security_zones() -> void:
	for i in range(GameState.security_zones.size() - 1, -1, -1):
		if GameState.security_zones[i]["expires_at"] <= GameState.total_ticks:
			GameState.security_zones.remove_at(i)

func _process_deployed_crews(dt: float) -> void:
	var days := dt / 86400.0
	if days < 0.001:
		return

	for i in range(GameState.deployed_crews.size() - 1, -1, -1):
		var entry: Dictionary = GameState.deployed_crews[i]
		var crew_workers: Array = entry["workers"]
		var supplies: Dictionary = entry["supplies"]
		var worker_count := crew_workers.size()

		if worker_count == 0:
			continue

		# Consume food: 0.5 units per worker per game-day
		var food_consumed := worker_count * 0.5 * days
		var food_remaining: float = supplies.get("food", 0.0)
		food_remaining = maxf(food_remaining - food_consumed, 0.0)
		supplies["food"] = food_remaining

		# Accumulate fatigue for deployed workers (modified by personality and leader aura)
		var leader_fatigue_mod: float = _get_leader_fatigue_modifier(crew_workers)
		for w in crew_workers:
			var fatigue_mult: float = w.get_fatigue_multiplier()
			if w.personality != Worker.Personality.LEADER:
				fatigue_mult *= leader_fatigue_mod
			var fatigue_delta: float = days * fatigue_mult
			w.fatigue = minf(w.fatigue + fatigue_delta, 100.0)
			w.days_deployed += days
			if w.fatigue >= 80.0 and w.fatigue - fatigue_delta < 80.0:
				EventBus.worker_fatigued.emit(w)

func _process_worker_fatigue(dt: float) -> void:
	# Piggyback on payroll interval (every game-day)
	# We use payroll accumulator which already tracks this
	# So this is called every tick but only acts when payroll fires
	# Actually, let's just track per-tick since dt can be large
	var days := dt / 86400.0
	if days < 0.001:
		return  # Skip tiny increments

	for w in GameState.workers:
		if w.assigned_mission != null:
			# On mission: fatigue increases, modified by personality and leader aura
			var fatigue_mult: float = w.get_fatigue_multiplier()
			if w.personality != Worker.Personality.LEADER:
				fatigue_mult *= _get_leader_fatigue_modifier(w.assigned_mission.workers)
			var fatigue_delta: float = days * fatigue_mult
			w.fatigue = minf(w.fatigue + fatigue_delta, 100.0)
			w.days_deployed += days
			if w.fatigue >= 80.0 and w.fatigue - fatigue_delta < 80.0:
				EventBus.worker_fatigued.emit(w)
		else:
			# Idle: fatigue decreases (3x faster recovery)
			if w.fatigue > 0.0:
				w.fatigue = maxf(w.fatigue - days * 3.0, 0.0)
			# Injury heals after 5 days idle
			if w.is_injured and w.days_deployed <= 0.0:
				w.days_deployed = maxf(w.days_deployed - days, -5.0)
				if w.days_deployed <= -5.0:
					w.is_injured = false
					w.days_deployed = 0.0

func _start_station_return(mission: Mission) -> void:
	# Transition a stationed ship's mission to TRANSIT_BACK to station
	var ship := mission.ship
	var return_pos: Vector2 = mission.return_position_au
	if ship.station_colony:
		return_pos = ship.station_colony.get_position_au()
		mission.return_position_au = return_pos

	var current_pos := ship.position_au
	if mission.asteroid:
		current_pos = mission.asteroid.get_position_au()
		ship.position_au = current_pos

	var dist := current_pos.distance_to(return_pos)
	mission.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())
	mission.elapsed_ticks = 0.0
	mission.status = Mission.Status.TRANSIT_BACK

	var cargo_mass := ship.get_cargo_total()
	var fuel_needed := ship.calc_fuel_for_distance(dist, cargo_mass)
	mission.fuel_per_tick = fuel_needed / mission.transit_time if mission.transit_time > 0 else 0.0

	EventBus.mission_phase_changed.emit(mission)

func _complete_repair_job(mission: Mission) -> void:
	# Find the derelict ship near the destination and repair it
	var repair_pos := mission.destination_position_au
	for other_ship in GameState.ships:
		if other_ship == mission.ship:
			continue
		if not other_ship.is_derelict:
			continue
		if other_ship.position_au.distance_to(repair_pos) < 0.05:
			other_ship.is_derelict = false
			other_ship.derelict_reason = ""
			other_ship.engine_condition = maxf(other_ship.engine_condition, 50.0)
			other_ship.fuel = minf(other_ship.fuel + other_ship.get_effective_fuel_capacity() * 0.25, other_ship.get_effective_fuel_capacity())
			var crew_count := maxi(other_ship.last_crew.size(), 1)
			other_ship.reset_life_support(crew_count)

			mission.ship.add_station_log("Repaired %s" % other_ship.ship_name, "repair")
			EventBus.station_job_completed.emit(mission.ship, "repair", "Repaired %s" % other_ship.ship_name)
			break

	_start_station_return(mission)

func _complete_delivery_job(mission: Mission) -> void:
	# Transfer supplies to the target ship/crew at destination
	var delivery_pos := mission.destination_position_au
	var ship := mission.ship

	# Find target ship near delivery position and repair its equipment
	for other_ship in GameState.ships:
		if other_ship == ship:
			continue
		if other_ship.position_au.distance_to(delivery_pos) > 0.05:
			continue
		# Repair broken equipment using parts
		var parts: float = ship.supplies.get("repair_parts", 0.0)
		for equip in other_ship.equipment:
			if equip.durability <= 0 and parts >= 1.0:
				equip.durability = equip.max_durability
				parts -= 1.0
				EventBus.equipment_repaired.emit(other_ship, equip)
		ship.supplies["repair_parts"] = maxf(parts, 0.0)
		ship.add_station_log("Delivered parts to %s" % other_ship.ship_name, "supply")
		EventBus.station_job_completed.emit(ship, "parts_delivery", "Parts delivered to %s" % other_ship.ship_name)
		break

	# Also deliver food to deployed crews nearby
	for crew_data in GameState.deployed_crews:
		var asteroid: AsteroidData = crew_data["asteroid"]
		if asteroid.get_position_au().distance_to(delivery_pos) > 0.05:
			continue
		var food: float = ship.supplies.get("food", 0.0)
		if food > 0:
			crew_data["supplies"]["food"] = crew_data["supplies"].get("food", 0.0) + food
			ship.supplies["food"] = 0.0
			ship.add_station_log("Delivered food to crew at %s" % asteroid.asteroid_name, "supply")
			EventBus.station_job_completed.emit(ship, "provisioning", "Food delivered to %s" % asteroid.asteroid_name)
		break

	_start_station_return(mission)

func _complete_boarding_job(mission: Mission) -> void:
	# Find the target ship at this location
	var ferry_ship := mission.ship
	var target_pos := mission.destination_position_au
	var target_ship: Ship = null

	for other in GameState.ships:
		if other == ferry_ship:
			continue
		if other.position_au.distance_to(target_pos) < 0.01:
			if other.current_mission != null:
				target_ship = other
				break

	var swapped := 0
	if target_ship != null and target_ship.current_mission != null:
		var target_mission := target_ship.current_mission
		# Find fatigued workers on target
		var fatigued: Array[Worker] = []
		for w in target_mission.workers:
			if w.needs_rotation:
				fatigued.append(w)

		# Find fresh workers on ferry (not part of ferry's own crew)
		var fresh: Array[Worker] = []
		for w in mission.workers:
			if w not in ferry_ship.last_crew and not w.needs_rotation:
				fresh.append(w)

		# Swap: remove fatigued from target, add fresh; fatigued board ferry
		for i in range(mini(fatigued.size(), fresh.size())):
			var tired_w: Worker = fatigued[i]
			var fresh_w: Worker = fresh[i]

			# Remove tired from target mission
			target_mission.workers.erase(tired_w)
			tired_w.assigned_mission = null

			# Add fresh to target mission
			target_mission.workers.append(fresh_w)
			fresh_w.assigned_mission = target_mission

			# Tired worker joins ferry for return trip
			if tired_w not in mission.workers:
				mission.workers.append(tired_w)
			tired_w.assigned_mission = mission

			# Remove fresh from ferry passenger list (they stay on target)
			mission.workers.erase(fresh_w)

			swapped += 1

	ferry_ship.add_station_log("Crew transfer: %d swapped" % swapped, "crew_ferry")
	EventBus.station_job_completed.emit(ferry_ship, "crew_ferry", "Rotated %d crew" % swapped)
	_start_station_return(mission)

func _complete_deploy(mission: Mission) -> void:
	# Transfer mining units from ship to asteroid
	if not mission.asteroid:
		_start_station_return(mission)
		return
	for unit in mission.mining_units_to_deploy:
		# Find workers to assign from deploy_workers list
		var unit_crew: Array[Worker] = []
		for w in mission.workers_to_deploy:
			if w not in GameState.workers:
				print("[DEPLOY DEBUG] Skipping '%s' — not in GameState.workers. assigned_mission=%s assigned_mining_unit=%s" % [w.worker_name, str(w.assigned_mission), str(w.assigned_mining_unit)])
				continue  # Worker was fired/removed during transit — skip
			if w.assigned_mining_unit == null and unit_crew.size() < unit.workers_required:
				unit_crew.append(w)
		GameState.deploy_mining_unit(unit, mission.asteroid, unit_crew)
	# Remove deployed workers from mission crew (they stay at the asteroid)
	for w in mission.workers_to_deploy:
		if w.assigned_mining_unit != null:
			mission.workers.erase(w)
			w.assigned_mission = null
	mission.mining_units_to_deploy.clear()
	mission.workers_to_deploy.clear()
	# Transfer supplies from ship to asteroid site
	if mission.asteroid:
		var asteroid_name := mission.asteroid.asteroid_name
		# Count workers staying at the asteroid
		var staying_workers := 0
		for unit in GameState.deployed_mining_units:
			if unit.deployed_at_asteroid == asteroid_name:
				staying_workers += unit.assigned_workers.size()
		# Food: transfer enough minus a return-trip buffer (estimate return trip ~30 days, 1.5x safety)
		var food_on_ship: float = mission.ship.supplies.get("food", 0.0)
		var return_days := 30.0  # conservative estimate
		var return_buffer: float = staying_workers * 0.028 * return_days * 1.5
		var food_to_transfer := maxf(0.0, food_on_ship - return_buffer)
		if food_to_transfer > 0.0:
			mission.ship.supplies["food"] = food_on_ship - food_to_transfer
			GameState.add_to_asteroid_supplies(asteroid_name, "food", food_to_transfer)
		# Repair parts: transfer all (ship can resupply at colony, miners cannot)
		var parts_on_ship: float = mission.ship.supplies.get("repair_parts", 0.0)
		if parts_on_ship > 0.0:
			mission.ship.supplies["repair_parts"] = 0.0
			GameState.add_to_asteroid_supplies(asteroid_name, "repair_parts", parts_on_ship)
	# Transition to idle at destination
	if mission.ship.is_stationed:
		_start_station_return(mission)
	else:
		mission.status = Mission.Status.IDLE_AT_DESTINATION
		mission.elapsed_ticks = 0.0
		for w in mission.workers:
			w.assigned_mission = null
		mission.workers.clear()
		EventBus.mission_phase_changed.emit(mission)
		EventBus.ship_idle_at_destination.emit(mission.ship, mission)

func _complete_collection(mission: Mission) -> void:
	# Load stockpiled ore into ship
	if mission.asteroid:
		var tons := GameState.collect_from_stockpile(mission.asteroid.asteroid_name, mission.ship)
		if tons > 0.0:
			EventBus.stockpile_collected.emit(mission.asteroid, tons)
	# Transition to idle or return
	if mission.ship.is_stationed:
		_start_station_return(mission)
	else:
		mission.status = Mission.Status.IDLE_AT_DESTINATION
		mission.elapsed_ticks = 0.0
		for w in mission.workers:
			w.assigned_mission = null
		mission.workers.clear()
		EventBus.mission_phase_changed.emit(mission)
		EventBus.ship_idle_at_destination.emit(mission.ship, mission)

func _process_mining_units(dt: float) -> void:
	var days := dt / 86400.0
	for unit in GameState.deployed_mining_units:
		if not unit.is_functional():
			continue
		if unit.assigned_workers.is_empty():
			continue
		# Find asteroid data
		var asteroid: AsteroidData = null
		for a in GameState.asteroids:
			if a.asteroid_name == unit.deployed_at_asteroid:
				asteroid = a
				break
		if asteroid == null:
			continue
		# Calculate crew skills from assigned workers
		var skill_total := 0.0
		var best_eng := 0.0
		var loyalty_avg := 0.0
		for w in unit.assigned_workers:
			skill_total += w.mining_skill
			if w.engineer_skill > best_eng:
				best_eng = w.engineer_skill
			loyalty_avg += w.loyalty_modifier
		if unit.assigned_workers.size() > 0:
			loyalty_avg /= unit.assigned_workers.size()
		else:
			loyalty_avg = 1.0
		if skill_total < 0.1:
			skill_total = 0.1
		var luck := randf_range(MINING_VARIANCE_MIN, MINING_VARIANCE_MAX)
		var unit_mult := unit.get_effective_multiplier()
		var pers_mining_mult := _get_personality_mining_multiplier(unit.assigned_workers)
		var leader_mining_mult := _get_leader_mining_modifier(unit.assigned_workers)
		# Grant mining XP to assigned workers while unit is operational
		for w in unit.assigned_workers:
			w.add_xp(2, dt)  # 2 = mining skill
		# Mine each ore type and add to stockpile
		for ore_type in asteroid.ore_yields:
			var base_yield: float = asteroid.ore_yields[ore_type]
			var ore_per_tick := base_yield * skill_total * unit_mult * luck * loyalty_avg * pers_mining_mult * leader_mining_mult * BASE_MINING_RATE * dt
			if ore_per_tick > 0.0:
				GameState.add_to_stockpile(asteroid.asteroid_name, ore_type, ore_per_tick)
		# Degrade durability — better engineers slow wear; repair parts reduce wear by 20%
		# 0.0 eng = full wear, 1.5 eng = 70% wear
		var eng_wear_factor := 1.0 - (best_eng * 0.2)
		var parts_wear_factor := 0.8 if GameState.asteroid_supplies.get(unit.deployed_at_asteroid, {}).get("repair_parts", 0.0) > 0.0 else 1.0
		unit.durability -= unit.wear_per_day * eng_wear_factor * parts_wear_factor * days
		unit.max_durability -= unit.wear_per_day * MiningUnit.MAX_DURABILITY_DECAY_RATIO * eng_wear_factor * parts_wear_factor * days
		if unit.max_durability < 0.0:
			unit.max_durability = 0.0
		if unit.durability <= 0.0:
			unit.durability = 0.0
			EventBus.mining_unit_broken.emit(unit)
		# Accidents — heavy equipment is dangerous
		# Base chance: ~0.2% per game-day per unit. Better engineers and cautious personalities reduce risk.
		# 0.0 eng = full risk, 1.5 eng = 25% risk
		var accident_pers_mult := _get_personality_accident_multiplier(unit.assigned_workers)
		var accident_chance_per_day := 0.002 * (1.0 - best_eng * 0.5) * accident_pers_mult
		if days > 0.0 and randf() < accident_chance_per_day * days:
			# Pick a random worker on this unit
			var victim: Worker = unit.assigned_workers[randi() % unit.assigned_workers.size()]
			if not victim.is_injured:
				victim.is_injured = true
				victim.loyalty = clampf(victim.loyalty + victim.get_injury_loyalty_delta(), 0.0, 100.0)
				# Accident also damages the unit
				unit.durability = maxf(0.0, unit.durability - randf_range(5.0, 15.0))
				EventBus.worker_injured.emit(victim)

const SUPPLY_ALERT_DAYS := 5.0

func _process_asteroid_supplies(dt: float) -> void:
	var days := dt / 86400.0
	# Build per-asteroid summary of workers and units
	var asteroid_workers: Dictionary = {}  # asteroid_name -> worker count
	var asteroid_units: Dictionary = {}    # asteroid_name -> unit count
	for unit in GameState.deployed_mining_units:
		var name := unit.deployed_at_asteroid
		asteroid_units[name] = asteroid_units.get(name, 0) + 1
		asteroid_workers[name] = asteroid_workers.get(name, 0) + unit.assigned_workers.size()

	for asteroid_name in GameState.asteroid_supplies.keys():
		var workers: int = asteroid_workers.get(asteroid_name, 0)
		var units: int = asteroid_units.get(asteroid_name, 0)

		# Consume food
		if workers > 0:
			var food_needed: float = workers * 0.028 * days
			GameState.consume_asteroid_supply(asteroid_name, "food", food_needed)
			# Alert if low
			var food_days := GameState.get_asteroid_supply_days(asteroid_name, "food")
			if food_days < SUPPLY_ALERT_DAYS and food_days > 0.0:
				EventBus.asteroid_supplies_low.emit(asteroid_name, "food", food_days)

		# Consume repair parts
		if units > 0:
			var parts_needed: float = units * 0.05 * days
			GameState.consume_asteroid_supply(asteroid_name, "repair_parts", parts_needed)
			# Alert if low
			var parts_days := GameState.get_asteroid_supply_days(asteroid_name, "repair_parts")
			if parts_days < SUPPLY_ALERT_DAYS and parts_days > 0.0:
				EventBus.asteroid_supplies_low.emit(asteroid_name, "repair_parts", parts_days)

		# Clean up entries for asteroids with no deployed units
		if workers <= 0 and units <= 0:
			GameState.asteroid_supplies.erase(asteroid_name)

func _process_hitchhike_pool(_dt: float) -> void:
	# Expire pool entries where elapsed >= max_wait
	var expired: Array[Dictionary] = []
	for entry in GameState.hitchhike_pool:
		var elapsed: float = GameState.total_ticks - float(entry["entered_at"])
		if elapsed >= entry["max_wait"]:
			expired.append(entry)
	for entry in expired:
		var worker: Worker = entry["worker"]
		GameState.hitchhike_pool.erase(entry)
		worker.leave_status = 1  # Found own way home

func _process_worker_leave(dt: float) -> void:
	_leave_accumulator += dt
	if _leave_accumulator < LEAVE_CHECK_INTERVAL:
		return
	_leave_accumulator -= LEAVE_CHECK_INTERVAL

	# Pick a random colony name for tardiness reasons with %s
	var random_colonies: Array[String] = ["Ceres Station", "Mars Colony", "Lunar Base", "Europa Lab", "Ganymede Port"]
	var random_colony_name: String = random_colonies[randi() % random_colonies.size()]

	var workers_to_quit: Array[Worker] = []

	for w in GameState.workers:
		if w.leave_status == 1:  # On leave
			# Leave recovery is handled by _process_worker_fatigue (idle recovery)
			# Check if fatigue has dropped enough to return
			if w.fatigue < 20.0:
				# Ready to return — roll for tardiness (modified by personality)
				if randf() < 0.06 * w.get_tardiness_multiplier():
					# Tardy!
					w.leave_status = 3
					var reason_template: String = TARDINESS_REASONS[randi() % TARDINESS_REASONS.size()]
					var reason: String = reason_template % random_colony_name if reason_template.contains("%s") else reason_template
					GameState.tardy_workers.append({
						"worker": w,
						"reason": reason,
						"tardy_since": GameState.total_ticks,
					})
					EventBus.worker_tardy.emit(w, reason)
					TimeScale.slow_for_critical_event()
				else:
					# Returned on time
					w.leave_status = 0
					w.fatigue = 0.0

		# Loyalty-based quitting: workers with very low loyalty may quit (modified by personality)
		if w.loyalty < 15.0 and w.is_available:
			if randf() < 0.005 * w.get_quit_multiplier():
				workers_to_quit.append(w)

	for w in workers_to_quit:
		GameState.fire_worker(w)

func _process_greedy_wages(dt: float) -> void:
	_greedy_wage_accumulator += dt
	if _greedy_wage_accumulator < GREEDY_WAGE_INTERVAL:
		return
	_greedy_wage_accumulator -= GREEDY_WAGE_INTERVAL

	for w in GameState.workers:
		if w.personality == Worker.Personality.GREEDY and w.loyalty < 60.0:
			var raise_amount := 8
			w.wage += raise_amount
			EventBus.worker_wage_increased.emit(w, raise_amount)

func _get_leader_mining_modifier(workers: Array) -> float:
	for w in workers:
		if w.personality == Worker.Personality.LEADER:
			return 1.05
	return 1.0

func _get_leader_fatigue_modifier(workers: Array) -> float:
	for w in workers:
		if w.personality == Worker.Personality.LEADER:
			return 0.95
	return 1.0

func _get_personality_mining_multiplier(workers: Array) -> float:
	if workers.is_empty():
		return 1.0
	var product := 1.0
	for w in workers:
		product *= w.get_mining_multiplier()
	return pow(product, 1.0 / workers.size())

func _get_personality_accident_multiplier(workers: Array) -> float:
	if workers.is_empty():
		return 1.0
	var product := 1.0
	for w in workers:
		product *= w.get_accident_multiplier()
	return pow(product, 1.0 / workers.size())

func _process_payroll(dt: float) -> void:
	_payroll_accumulator += dt
	if _payroll_accumulator >= PAYROLL_INTERVAL:
		_payroll_accumulator -= PAYROLL_INTERVAL
		var total_wages := 0
		for w in GameState.workers:
			total_wages += w.wage
		if total_wages > 0:
			GameState.money -= total_wages
			GameState.record_transaction(-total_wages, "Payroll (%d workers)" % GameState.workers.size())

func _process_food_consumption(dt: float) -> void:
	var days := dt / 86400.0
	var food_per_worker_per_day_kg := 2.8  # kg, from SupplyData
	const KG_PER_FOOD_UNIT := 100.0  # SupplyData: 0.1t = 100kg per unit

	# Process deployed mining units
	for unit in GameState.deployed_mining_units:
		if unit.assigned_workers.is_empty():
			continue
		# Workers at mining units don't have a ship - they need supply deliveries
		# For now, just track this as a TODO - they'll need a separate food supply at the asteroid
		pass  # TODO: Implement asteroid-based food stockpiles for deployed workers

	# Process ships on missions
	for mission in GameState.missions:
		if mission.workers.is_empty():
			continue
		var ship := mission.ship
		if ship.is_derelict:
			continue

		# Calculate food consumption in kg, then convert to units
		var food_needed_kg := mission.workers.size() * food_per_worker_per_day_kg * days
		var food_needed_units := food_needed_kg / KG_PER_FOOD_UNIT
		var current_food_units: float = ship.supplies.get("food", 0.0)

		if current_food_units >= food_needed_units:
			ship.supplies["food"] = current_food_units - food_needed_units
		else:
			# Out of food - workers abandon the mission
			_trigger_food_depletion(ship, mission)

	# Process trade missions
	for tm in GameState.trade_missions:
		if tm.workers.is_empty():
			continue
		var ship := tm.ship
		if ship.is_derelict:
			continue

		var food_needed_kg := tm.workers.size() * food_per_worker_per_day_kg * days
		var food_needed_units := food_needed_kg / KG_PER_FOOD_UNIT
		var current_food_units: float = ship.supplies.get("food", 0.0)

		if current_food_units >= food_needed_units:
			ship.supplies["food"] = current_food_units - food_needed_units
		else:
			_trigger_food_depletion(ship, null, tm)

func _trigger_food_depletion(ship: Ship, mission: Mission = null, trade_mission: TradeMission = null) -> void:
	# Workers abandon the ship when food runs out
	ship.supplies["food"] = 0.0

	# Free workers
	var abandoned_workers: Array[Worker] = []
	if mission:
		abandoned_workers = mission.workers.duplicate()
		for w in mission.workers:
			w.assigned_mission = null
			w.loyalty = maxf(w.loyalty - 20.0 + w.get_injury_loyalty_delta(), 0.0)  # Major loyalty hit, modified by personality
		mission.workers.clear()
		mission.status = Mission.Status.COMPLETED
		GameState.missions.erase(mission)
		ship.current_mission = null
	elif trade_mission:
		abandoned_workers = trade_mission.workers.duplicate()
		for w in trade_mission.workers:
			w.assigned_trade_mission = null
			w.loyalty = maxf(w.loyalty - 20.0 + w.get_injury_loyalty_delta(), 0.0)
		trade_mission.workers.clear()
		trade_mission.status = TradeMission.Status.COMPLETED
		GameState.trade_missions.erase(trade_mission)
		ship.current_trade_mission = null

	# Ship becomes idle at current position
	ship.docked_at_colony = null

	var worker_names := ", ".join(abandoned_workers.map(func(w: Worker) -> String: return w.worker_name))
	EventBus.ship_breakdown.emit(ship, "Food depleted - crew abandoned ship")
	EventBus.ship_food_depleted.emit(ship, abandoned_workers.size())
	print("Ship %s: Food depleted, %d workers abandoned (%s)" % [ship.ship_name, abandoned_workers.size(), worker_names])

func _process_survey_events(dt: float) -> void:
	# Accumulate game-time even when throttled
	_survey_dt_accum += dt
	if _survey_realtime_timer < SURVEY_REALTIME_INTERVAL:
		return
	_survey_realtime_timer = 0.0

	_survey_accumulator += _survey_dt_accum
	_survey_dt_accum = 0.0
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
	# Accumulate game-time even when throttled, so deadlines stay accurate at high speed
	_contracts_dt_accum += dt
	if _contracts_realtime_timer < CONTRACTS_REALTIME_INTERVAL:
		return
	_contracts_realtime_timer = 0.0
	var accum_dt := _contracts_dt_accum
	_contracts_dt_accum = 0.0

	# Tick down active contract deadlines
	var failed: Array[Contract] = []
	for contract in GameState.active_contracts:
		contract.deadline_ticks -= accum_dt
		if contract.deadline_ticks <= 0:
			contract.status = Contract.Status.FAILED
			failed.append(contract)

	for contract in failed:
		GameState.active_contracts.erase(contract)
		EventBus.contract_failed.emit(contract)

	# Expire available contracts
	var expired: Array[Contract] = []
	for contract in GameState.available_contracts:
		contract.deadline_ticks -= accum_dt
		if contract.deadline_ticks <= 0:
			contract.status = Contract.Status.EXPIRED
			expired.append(contract)

	for contract in expired:
		GameState.available_contracts.erase(contract)
		EventBus.contract_expired.emit(contract)

	# Generate new contracts periodically
	_contract_accumulator += accum_dt
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
		if fuel_cost > 0:
			GameState.record_transaction(-fuel_cost, "Refuel at colony", ship.ship_name)

func _auto_provision_at_location(ship: Ship) -> void:
	# Automatically buy food when ship is docked (at colony or Earth)
	const DAYS_BUFFER := 30.0  # Maintain 30 days of food
	const KG_PER_WORKER_PER_DAY := 2.8  # From SupplyData
	const KG_PER_FOOD_UNIT := 100.0  # SupplyData: 0.1t = 100kg per unit

	# Determine crew size (use min_crew if no crew assigned)
	var crew_size := ship.last_crew.size() if ship.last_crew.size() > 0 else ship.min_crew

	# Calculate target food level (in kg, then convert to units)
	var target_food_kg := crew_size * DAYS_BUFFER * KG_PER_WORKER_PER_DAY
	var target_food_units := target_food_kg / KG_PER_FOOD_UNIT

	# Current food (in units)
	var current_food_units: float = ship.supplies.get("food", 0.0)

	# Only buy if below target
	if current_food_units >= target_food_units:
		return

	# Calculate amount to buy (in units)
	var amount_to_buy := target_food_units - current_food_units

	# Use GameState.buy_supplies which handles payment and cargo checks
	GameState.buy_supplies(ship, "food", amount_to_buy)
