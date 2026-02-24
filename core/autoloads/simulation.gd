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
var _supply_alert_last_fired: Dictionary = {}  # "asteroid:supply_key" -> game_tick of last alert

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

# Rival corporation AI
var _rival_accumulator: float = 0.0
const RIVAL_CHECK_INTERVAL: float = 3600.0   # AI decisions every game-hour
const RIVAL_BASE_MINING_DURATION: float = 86400.0  # 1 game-day of mining per run

# Ghost contact tracking system
var _observation_accumulator: float = 0.0
const OBSERVATION_INTERVAL: float = 60.0    # Scan for observations once per game-minute
const MIN_VISIBILITY: float = 0.15           # Minimum exhaust-cone visibility to record
const CONTACT_MATCH_RADIUS: float = 0.15     # AU — max distance to match observation to existing contact
var _next_contact_id: int = 0
const CONTACT_COLORS: Array = [
	Color(1.0, 0.30, 0.30),  # Red
	Color(1.0, 0.60, 0.10),  # Orange
	Color(1.0, 1.00, 0.20),  # Yellow
	Color(0.3, 1.00, 0.45),  # Green
	Color(0.3, 0.80, 1.00),  # Cyan
	Color(0.5, 0.30, 1.00),  # Violet
	Color(1.0, 0.30, 0.80),  # Magenta
	Color(0.8, 1.00, 0.55),  # Lime
]

# Worker fatigue (piggybacks on payroll accumulator interval)

# Worker leave processing
var _leave_accumulator: float = 0.0
const LEAVE_CHECK_INTERVAL: float = 86400.0  # Check once per game-day

# Greedy worker wage pressure
var _greedy_wage_accumulator: float = 0.0
const GREEDY_WAGE_INTERVAL: float = 86400.0 * 30.0  # Every 30 game-days

# Life support, food, and fatigue throttling
var _life_support_accumulator: float = 0.0
const LIFE_SUPPORT_INTERVAL: float = 3600.0  # Every game-hour
var _food_consumption_accumulator: float = 0.0
const FOOD_CONSUMPTION_INTERVAL: float = 3600.0  # Every game-hour
var _worker_fatigue_accumulator: float = 0.0
const WORKER_FATIGUE_INTERVAL: float = 86400.0  # Every game-day

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
	# Policy dispatch: re-evaluate idle Earth ships immediately when a mission completes
	EventBus.mission_completed.connect(func(mission: Mission) -> void:
		var ship := mission.ship
		if ship == null or ship.is_derelict or ship.is_stationed:
			return
		# Queued missions are launched after provision/repair in the transit completion block.
		# Only policy-dispatch ships with no queued plan.
		if ship.is_at_earth and ship.current_mission == null and ship.current_trade_mission == null:
			if not ship.has_queued_mission() and GameState.settings.get("autoplay", false):
				_policy_dispatch_idle_ship(ship)
	)

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
	_process_rival_corps(dt)
	GameState.process_pending_orders()

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
				for w in mission.ship.crew:
					if w.pilot_skill > best_pilot_skill:
						best_pilot = w
						best_pilot_skill = w.pilot_skill
				if best_pilot:
					best_pilot.add_xp(0, dt)  # 0 = pilot skill
				_burn_fuel(mission, dt)
				if mission.elapsed_ticks >= mission.get_current_phase_duration():
					# Check if more intermediate waypoints remain
					if mission.outbound_waypoint_index < mission.outbound_legs.size():
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
										EventBus.ship_idle_at_destination.emit(mission.ship, mission)
								else:
									mission.status = Mission.Status.MINING
									mission.elapsed_ticks = 0.0
							Mission.MissionType.REPOSITION:
								# Just move to destination and idle
								mission.status = Mission.Status.IDLE_AT_DESTINATION
								mission.elapsed_ticks = 0.0
								if mission.asteroid:
									mission.ship.position_au = mission.asteroid.get_position_au()
								EventBus.ship_idle_at_destination.emit(mission.ship, mission)
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
					_complete_refuel_stop(mission, not mission.refueling_is_return)

			Mission.Status.MINING:
				# Grant mining XP to crew during mining
				for w in mission.ship.crew:
					w.add_xp(2, dt)  # 2 = mining skill
				_mine_tick(mission, dt)
				# Stay until hold is full; safety timeout at 2x estimated duration
				var cargo_full := mission.ship.get_cargo_total() >= mission.ship.get_effective_cargo_capacity() * 0.99
				if cargo_full or mission.elapsed_ticks >= mission.mining_duration * 2.0:
					# Stationed ships and autoplay missions auto-return instead of idling
					if mission.ship.is_stationed or mission.return_to_station:
						_start_station_return(mission)
					else:
						mission.status = Mission.Status.IDLE_AT_DESTINATION
						mission.elapsed_ticks = 0.0
						# Set ship position to asteroid location
						mission.ship.position_au = mission.asteroid.get_position_au()
						# Free workers so they're available for next dispatch
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
				for w in mission.ship.crew:
					if w.pilot_skill > best_pilot_skill:
						best_pilot = w
						best_pilot_skill = w.pilot_skill
				if best_pilot:
					best_pilot.add_xp(0, dt)  # 0 = pilot skill
				_burn_fuel(mission, dt)
				if mission.elapsed_ticks >= mission.get_current_phase_duration():
					# Check if using slingshot with more waypoints
					if mission.return_waypoint_index < mission.return_legs.size():
						# Reached waypoint - transition to next leg
						_process_waypoint_transition(mission, false)  # false = return
					else:
						# Reached final destination — use current Earth position (Earth orbits!)
						var _mission_ship := mission.ship
						var _provision_after_complete := false
						if mission.ship.is_stationed and mission.ship.station_colony:
							mission.ship.position_au = mission.ship.station_colony.get_position_au()
						elif not mission.return_to_station:
							mission.ship.position_au = CelestialData.get_earth_position_au()
							mission.ship.docked_at_colony = null  # Returning to Earth, not a colony
							_auto_refuel_at_earth(mission.ship)
							# Provision AFTER complete_mission clears ore cargo (so food fits)
							_provision_after_complete = true
						else:
							if mission.ship.station_colony == null:
								mission.ship.position_au = CelestialData.get_earth_position_au()
								_auto_refuel_at_earth(mission.ship)
								# Provision AFTER complete_mission clears ore cargo (so food fits)
								_provision_after_complete = true
							else:
								mission.ship.position_au = mission.return_position_au
							if not mission.ship.is_stationed:
								mission.ship.docked_at_colony = null
						# Stationed ships: dock at colony, refuel and provision before complete_mission
						# (stationed ships keep cargo; complete_mission won't clear it)
						if mission.ship.is_stationed and mission.ship.station_colony:
							mission.ship.docked_at_colony = mission.ship.station_colony
							_auto_refuel_at_colony(mission.ship)
							_auto_provision_at_location(mission.ship)
							_auto_repair_at_location(mission.ship)
							var cargo := mission.ship.get_cargo_total()
							if cargo > 0.1:
								mission.ship.add_station_log("Returned with %.0ft cargo" % cargo, "mining")
							# Crew ferry: fatigued passengers enter hitchhike pool at station
							if mission.mission_type == Mission.MissionType.CREW_FERRY:
								var station_name: String = mission.ship.station_colony.colony_name
								var station_pos: Vector2 = mission.ship.station_colony.get_position_au()
								for w in mission.ship.crew:
									if w not in mission.ship.crew and w.needs_rotation:
										GameState.add_to_hitchhike_pool(w, station_name, station_pos)
						GameState.complete_mission(mission)
						# Provision and repair after cargo is cleared for Earth returns
						if _provision_after_complete:
							_auto_provision_at_location(_mission_ship)
							_auto_repair_at_location(_mission_ship)
						# Launch queued mission only after all prep work (refuel/provision/repair)
						if not _mission_ship.is_stationed and _mission_ship.has_queued_mission():
							GameState._start_queued_mission(_mission_ship)

func _process_waypoint_transition(mission: Mission, is_outbound: bool) -> void:
	var legs := mission.outbound_legs if is_outbound else mission.return_legs
	var idx := mission.outbound_waypoint_index if is_outbound else mission.return_waypoint_index
	var leg: WaypointLeg = legs[idx]

	mission.ship.position_au = leg.get_live_position()

	match leg.waypoint_type:
		WaypointLeg.WaypointType.REFUEL_STOP:
			mission.status = Mission.Status.REFUELING
			mission.refueling_is_return = not is_outbound
			mission.elapsed_ticks = 0.0
			if is_outbound:
				mission.outbound_waypoint_index += 1
			else:
				mission.return_waypoint_index += 1
			EventBus.mission_phase_changed.emit(mission)
			return

		WaypointLeg.WaypointType.GRAVITY_ASSIST:
			mission.elapsed_ticks = 0.0
			if is_outbound:
				mission.outbound_waypoint_index += 1
				var next_idx := mission.outbound_waypoint_index
				if next_idx < mission.outbound_legs.size():
					mission.transit_time = mission.outbound_legs[next_idx].transit_time
				# else: transit_time already holds the final leg time
			else:
				mission.return_waypoint_index += 1
				var next_idx := mission.return_waypoint_index
				if next_idx < mission.return_legs.size():
					mission.transit_time = mission.return_legs[next_idx].transit_time

	EventBus.mission_phase_changed.emit(mission)

func _complete_refuel_stop(mission: Mission, is_outbound: bool) -> void:
	var legs := mission.outbound_legs if is_outbound else mission.return_legs
	var cur_idx := (mission.outbound_waypoint_index if is_outbound else mission.return_waypoint_index) - 1
	var next_idx := mission.outbound_waypoint_index if is_outbound else mission.return_waypoint_index

	# Add purchased fuel
	if cur_idx >= 0 and cur_idx < legs.size():
		mission.ship.fuel = minf(mission.ship.fuel + legs[cur_idx].fuel_amount, mission.ship.get_effective_fuel_capacity())

	# Determine next destination position
	var next_dest_pos: Vector2
	if next_idx < legs.size():
		next_dest_pos = legs[next_idx].get_live_position()
	elif is_outbound:
		next_dest_pos = mission.asteroid.get_position_au()
	else:
		next_dest_pos = mission.return_position_au

	var dist_to_next := mission.ship.position_au.distance_to(next_dest_pos)
	var fuel_needed := mission.ship.calc_fuel_for_distance(dist_to_next, mission.ship.get_cargo_total())

	if fuel_needed > mission.ship.fuel:
		mission.status = Mission.Status.IDLE_AT_DESTINATION
		mission.elapsed_ticks = 0.0
		EventBus.mission_phase_changed.emit(mission)
		print("Mission aborted: next waypoint unreachable from fuel stop (orbital drift)")
		return

	mission.elapsed_ticks = 0.0
	mission.status = Mission.Status.TRANSIT_OUT if is_outbound else Mission.Status.TRANSIT_BACK

	# Set next leg transit time
	if next_idx < legs.size():
		mission.transit_time = legs[next_idx].transit_time
	# else: transit_time already holds the final leg time

	EventBus.mission_phase_changed.emit(mission)

func _process_trade_waypoint_transition(tm: TradeMission, is_outbound: bool) -> void:
	var legs := tm.outbound_legs if is_outbound else tm.return_legs
	var idx := tm.outbound_waypoint_index if is_outbound else tm.return_waypoint_index
	var leg: WaypointLeg = legs[idx]

	tm.ship.position_au = leg.get_live_position()

	match leg.waypoint_type:
		WaypointLeg.WaypointType.REFUEL_STOP:
			tm.status = TradeMission.Status.REFUELING
			tm.refueling_is_return = not is_outbound
			tm.elapsed_ticks = 0.0
			if is_outbound:
				tm.outbound_waypoint_index += 1
			else:
				tm.return_waypoint_index += 1
			EventBus.trade_mission_phase_changed.emit(tm)
			return

		WaypointLeg.WaypointType.GRAVITY_ASSIST:
			tm.elapsed_ticks = 0.0
			if is_outbound:
				tm.outbound_waypoint_index += 1
				var next_idx := tm.outbound_waypoint_index
				if next_idx < tm.outbound_legs.size():
					tm.transit_time = tm.outbound_legs[next_idx].transit_time
			else:
				tm.return_waypoint_index += 1
				var next_idx := tm.return_waypoint_index
				if next_idx < tm.return_legs.size():
					tm.transit_time = tm.return_legs[next_idx].transit_time

	EventBus.trade_mission_phase_changed.emit(tm)

func _complete_trade_refuel_stop(tm: TradeMission, is_outbound: bool) -> void:
	var legs := tm.outbound_legs if is_outbound else tm.return_legs
	var cur_idx := (tm.outbound_waypoint_index if is_outbound else tm.return_waypoint_index) - 1
	var next_idx := tm.outbound_waypoint_index if is_outbound else tm.return_waypoint_index

	# Add purchased fuel
	if cur_idx >= 0 and cur_idx < legs.size():
		tm.ship.fuel = minf(tm.ship.fuel + legs[cur_idx].fuel_amount, tm.ship.get_effective_fuel_capacity())

	# Determine next destination position
	var next_dest_pos: Vector2
	if next_idx < legs.size():
		next_dest_pos = legs[next_idx].get_live_position()
	elif is_outbound:
		next_dest_pos = tm.colony.get_position_au()
	else:
		next_dest_pos = tm.return_position_au

	var dist_to_next := tm.ship.position_au.distance_to(next_dest_pos)
	var fuel_needed := tm.ship.calc_fuel_for_distance(dist_to_next, tm.ship.get_cargo_total())

	if fuel_needed > tm.ship.fuel:
		tm.status = TradeMission.Status.IDLE_AT_COLONY
		tm.elapsed_ticks = 0.0
		EventBus.trade_mission_phase_changed.emit(tm)
		print("Trade mission aborted: next waypoint unreachable from fuel stop (orbital drift)")
		return

	tm.elapsed_ticks = 0.0
	tm.status = TradeMission.Status.TRANSIT_TO_COLONY if is_outbound else TradeMission.Status.TRANSIT_BACK

	if next_idx < legs.size():
		tm.transit_time = legs[next_idx].transit_time
	# else: transit_time already holds the final leg time

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
	for w in mission.ship.crew:
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
	var worker_count := mission.ship.crew.size()
	for w in mission.ship.crew:
		loyalty_total += w.loyalty_modifier
	var avg_loyalty_mod := loyalty_total / float(worker_count) if worker_count > 0 else 1.0

	var personality_mining_mult := _get_personality_mining_multiplier(mission.ship.crew)
	var leader_mining_mult := _get_leader_mining_modifier(mission.ship.crew)

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
				for w in tm.ship.crew:
					if w.pilot_skill > best_pilot_skill:
						best_pilot = w
						best_pilot_skill = w.pilot_skill
				if best_pilot:
					best_pilot.add_xp(0, dt)  # 0 = pilot skill
				tm.ship.fuel = maxf(tm.ship.fuel - tm.fuel_per_tick * dt, 0.0)
				# Check for fuel depletion
				if tm.ship.fuel <= 0 and not tm.ship.is_derelict:
					_trigger_fuel_depletion(tm.ship)
				if tm.elapsed_ticks >= tm.get_current_phase_duration():
					# Check if using waypoints with more stops
					if tm.outbound_waypoint_index < tm.outbound_legs.size():
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
							# Auto-refuel and provision at colony
							_auto_refuel_at_colony(tm.ship)
							_auto_provision_at_location(tm.ship)
							EventBus.trade_mission_phase_changed.emit(tm)
							EventBus.ship_idle_at_colony.emit(tm.ship, tm)

			TradeMission.Status.REFUELING:
				if tm.elapsed_ticks >= TradeMission.REFUEL_DURATION:
					_complete_trade_refuel_stop(tm, not tm.refueling_is_return)

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
				for w in tm.ship.crew:
					if w.pilot_skill > best_pilot_skill:
						best_pilot = w
						best_pilot_skill = w.pilot_skill
				if best_pilot:
					best_pilot.add_xp(0, dt)  # 0 = pilot skill
				tm.ship.fuel = maxf(tm.ship.fuel - tm.fuel_per_tick * dt, 0.0)
				# Check for fuel depletion
				if tm.ship.fuel <= 0 and not tm.ship.is_derelict:
					_trigger_fuel_depletion(tm.ship)
				if tm.elapsed_ticks >= tm.get_current_phase_duration():
					# Check if using waypoints with more stops
					if tm.return_waypoint_index < tm.return_legs.size():
						# Reached waypoint - transition to next leg
						_process_trade_waypoint_transition(tm, false)  # false = return
					else:
						# Reached final destination — use current position (bodies orbit!)
						if tm.ship.is_stationed and tm.ship.station_colony:
							tm.ship.position_au = tm.ship.station_colony.get_position_au()
						else:
							tm.ship.position_au = CelestialData.get_earth_position_au()
							tm.ship.docked_at_colony = null  # Returning to Earth, not a colony
							_auto_refuel_at_earth(tm.ship)
							_auto_provision_at_location(tm.ship)
						var _trade_ship := tm.ship
						GameState.complete_trade_mission(tm)
						if not _trade_ship.is_stationed and _trade_ship.has_queued_mission():
							GameState._start_queued_mission(_trade_ship)

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
		for w in ship.crew:
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
			for w in mission.ship.crew:
				if w.engineer_skill > best_engineer:
					best_engineer = w.engineer_skill
			var eng_factor := 1.0 - (best_engineer * 0.3)

			# Degrade engine during transit (reduced by engineer skill)
			ship.engine_condition = maxf(ship.engine_condition - ship.engine_wear_per_tick * eng_factor * dt, 0.0)

			# Grant engineer XP during transit (active maintenance while under thrust)
			for w in mission.ship.crew:
				w.add_xp(1, dt)  # 1 = engineer skill

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
			for w in ship.crew:
				if w.engineer_skill > best_engineer:
					best_engineer = w.engineer_skill
			var eng_factor := 1.0 - (best_engineer * 0.3)

			ship.engine_condition = maxf(ship.engine_condition - ship.engine_wear_per_tick * eng_factor * dt, 0.0)

			# Grant engineer XP during transit (active maintenance while under thrust)
			for w in ship.crew:
				w.add_xp(1, dt)  # 1 = engineer skill

			var chance := ship.get_breakdown_chance_per_tick() * eng_factor
			if chance > 0 and randf() < chance * dt:
				_trigger_breakdown(ship, "Engine failure during transit")

func _trigger_breakdown(ship: Ship, reason: String) -> void:
	# Check for engineer self-repair before declaring breakdown
	var crew: Array[Worker] = ship.crew

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

		# Check warning thresholds — skip if player has already responded
		var player_responded := ship in GameState.rescue_missions \
			or ship in GameState.refuel_missions \
			or ship in GameState.stranger_offers
		var max_life_support := ship.calculate_life_support_duration(maxi(ship.crew.size(), 1))
		var pct := ship.life_support_remaining / max_life_support
		var fired: Array = _life_support_warnings_fired[ship]
		for threshold in LIFE_SUPPORT_WARN_THRESHOLDS:
			if pct <= threshold and threshold not in fired:
				fired.append(threshold)
				if not player_responded:
					EventBus.life_support_warning.emit(ship, pct)
					# Auto-pause at 10% to give player time to react
					if threshold <= 0.10:
						TimeScale.slow_for_critical_event()

		# Check if crew has died
		if ship.life_support_remaining <= 0:
			_ships_to_destroy_buf.append(ship)

	# Destroy ships with dead crews
	for ship in _ships_to_destroy_buf:
		var crew_count := ship.crew.size()
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

	# Autoplay: station colony-docked ships
	if GameState.settings.get("autoplay", false):
		for ship in GameState.ships:
			if ship.is_derelict or ship.is_stationed:
				continue
			if ship.docked_at_colony != null:
				GameState.station_ship(ship, ship.docked_at_colony, _autoplay_jobs(ship))

	# Policy dispatch: idle Earth-docked ships find work (autoplay only; queued missions always launch)
	for ship in GameState.ships:
		if ship.is_derelict or ship.is_stationed:
			continue
		if ship.is_at_earth and ship.current_mission == null and ship.current_trade_mission == null:
			if ship.has_queued_mission():
				GameState._start_queued_mission(ship)
			elif GameState.settings.get("autoplay", false):
				_policy_dispatch_idle_ship(ship)

	for ship in GameState.ships:
		if not ship.is_stationed_idle:
			continue
		# Validate crew — check that last_crew workers are still in the company
		var valid_crew: Array[Worker] = []
		for w in ship.crew:
			if w in GameState.workers and (w.assigned_ship == ship or w.is_available):
				valid_crew.append(w)
			elif w.assigned_ship == ship:
				w.assigned_ship = null  # Worker left company, clean up
		ship.crew = valid_crew
		if ship.crew.size() < ship.min_crew:
			continue  # Not enough crew to do anything

		# Grant passive engineer XP to stationed crew (reduced rate for passive maintenance)
		for w in ship.crew:
			w.add_xp(1, STATION_CHECK_INTERVAL * 0.5)  # 1 = engineer skill, half rate

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
				"collect_ore":
					took_job = _station_try_collect_ore(ship)
				"crew_ferry":
					took_job = _station_try_crew_ferry(ship)
				"patrol":
					took_job = _station_try_patrol(ship)
			if took_job:
				break  # Only do one job at a time

func _autoplay_jobs(ship: Ship) -> Array[String]:
	# Build a priority-ordered job list from effective policies (respects per-ship overrides).
	# Jobs whose policy is MANUAL are excluded -- the player handles those manually.
	var jobs: Array[String] = []
	jobs.append("mining")  # Core operation -- always included
	if GameState.get_collection_policy(ship) != CompanyPolicy.CollectionPolicy.MANUAL:
		jobs.append("collect_ore")
	if GameState.get_supply_policy(ship) != CompanyPolicy.SupplyPolicy.MANUAL:
		jobs.append("provisioning")
	jobs.append("parts_delivery")
	if GameState.get_encounter_policy(ship) in [CompanyPolicy.EncounterPolicy.CONFRONT, CompanyPolicy.EncounterPolicy.DEFEND]:
		jobs.append("patrol")
	return jobs

func _policy_dispatch_idle_ship(ship: Ship) -> void:
	# Policy-driven dispatch for idle Earth-docked ships. Always active.
	# Priority 1: collect ore stockpiles (if CollectionPolicy allows)
	# Priority 2: mine the best reachable asteroid

	if ship.get_cargo_remaining() < 1.0:
		return  # No room for anything

	var crew := _get_policy_crew(ship)
	if crew.size() < ship.min_crew:
		return  # Not enough workers

	# Priority 1: collect stockpiles
	if GameState.get_collection_policy(ship) != CompanyPolicy.CollectionPolicy.MANUAL:
		var threshold: float = CompanyPolicy.COLLECTION_POLICY_THRESHOLDS[GameState.get_collection_policy(ship)]
		var trigger_tons: float = ship.get_effective_cargo_capacity() * threshold
		var best_collect: AsteroidData = null
		var best_tons: float = 0.0
		for asteroid in GameState.asteroids:
			var pile: Dictionary = GameState.get_ore_stockpile(asteroid.asteroid_name)
			var pile_tons: float = 0.0
			for _ot in pile:
				pile_tons += float(pile[_ot])
			if pile_tons < trigger_tons or pile_tons <= best_tons:
				continue
			var dist := ship.position_au.distance_to(asteroid.get_position_au())
			var fuel_needed := ship.calc_fuel_for_distance(dist, 0.0) \
				+ ship.calc_fuel_for_distance(dist, minf(pile_tons, ship.get_effective_cargo_capacity()))
			if fuel_needed > ship.fuel:
				continue
			best_tons = pile_tons
			best_collect = asteroid
		if best_collect != null:
			ship.crew = crew
			var m := GameState.start_collect_mission(ship, best_collect)
			if m:
				m.return_to_station = true
				return

	# Priority 2: mine
	if ship.get_cargo_remaining() < ship.get_effective_cargo_capacity() * 0.1:
		return
	var ship_pos := ship.position_au
	var best_asteroid: AsteroidData = null
	var best_score: float = -1.0
	for asteroid in GameState.asteroids:
		var score := _score_mining_trip(ship, asteroid, ship_pos)
		if score > best_score:
			best_score = score
			best_asteroid = asteroid
	if best_asteroid == null:
		return
	ship.crew = crew
	var mission := GameState.start_mission(ship, best_asteroid)
	if mission:
		mission.return_to_station = true
		EventBus.station_job_started.emit(ship, "mining", best_asteroid.asteroid_name)

## Score an asteroid for a mining trip from origin_pos with the given ship.
## Returns expected net profit per game-second, or -1 if the trip is infeasible.
func _score_mining_trip(ship: Ship, asteroid: AsteroidData, origin_pos: Vector2, mining_duration: float = 86400.0) -> float:
	if asteroid.ore_yields.is_empty():
		return -1.0
	var slots_left := asteroid.get_max_mining_slots() - GameState.get_occupied_slots(asteroid.asteroid_name)
	if slots_left <= 0:
		return -1.0
	var dist := origin_pos.distance_to(asteroid.get_position_au())
	if dist <= 0.0:
		return -1.0
	var fuel_out := ship.calc_fuel_for_distance(dist, ship.get_cargo_total())
	var fuel_back := ship.calc_fuel_for_distance(dist, ship.get_effective_cargo_capacity())
	if fuel_out + fuel_back > ship.fuel:
		return -1.0
	# Estimated haul: yield rate × duration, capped at cargo capacity
	var haul_tons := 0.0
	var haul_value := 0.0
	for ore_type in asteroid.ore_yields:
		var rate: float = float(asteroid.ore_yields[ore_type])  # tons/day
		var tons := minf(rate * (mining_duration / 86400.0), ship.get_effective_cargo_capacity())
		haul_tons += tons
		haul_value += tons * float(GameState.market.current_prices.get(ore_type, 1000.0))
	haul_tons = minf(haul_tons, ship.get_effective_cargo_capacity())
	# Revenue minus fuel cost
	var fuel_cost := (fuel_out + fuel_back) * Ship.FUEL_COST_PER_UNIT
	var net_profit := haul_value - fuel_cost
	if net_profit <= 0.0:
		return -1.0
	# Divide by total trip time to get profit/second
	var thrust := ship.get_effective_thrust()
	if thrust <= 0.0:
		return -1.0
	var one_way_time := Brachistochrone.transit_time(dist, thrust)
	var total_time := 2.0 * one_way_time + mining_duration
	return net_profit / total_time

func _get_policy_crew(ship: Ship) -> Array[Worker]:
	var crew: Array[Worker] = []
	for w in ship.crew:
		if w in GameState.workers and w.is_available:
			crew.append(w)
	if crew.size() < ship.min_crew:
		crew.clear()
		var available := GameState.get_available_workers()
		for i in mini(ship.min_crew, available.size()):
			crew.append(available[i])
	return crew

func _autoplay_dispatch_from_earth(ship: Ship) -> void:
	# For ships docked at Earth, pick the best reachable asteroid and send them mining.
	# Mirrors _station_try_mining but without the colony-radius restriction.
	if ship.get_ore_total() > ship.get_effective_cargo_capacity() * 0.9:
		# Cargo nearly full — sell first; skip for now (future: auto-sell at Earth)
		return
	if ship.get_cargo_remaining() < ship.get_effective_cargo_capacity() * 0.1:
		return

	var ship_pos := ship.position_au
	var best_asteroid: AsteroidData = null
	var best_score: float = -1.0

	for asteroid in GameState.asteroids:
		var score := _score_mining_trip(ship, asteroid, ship_pos)
		if score > best_score:
			best_score = score
			best_asteroid = asteroid

	if best_asteroid == null:
		return

	# Assign crew — use last_crew if valid, otherwise grab available workers
	var crew: Array[Worker] = []
	for w in ship.crew:
		if w in GameState.workers and w.is_available:
			crew.append(w)
	if crew.size() < ship.min_crew:
		crew.clear()
		var available := GameState.get_available_workers()
		for i in mini(ship.min_crew, available.size()):
			crew.append(available[i])
	if crew.size() < ship.min_crew:
		return  # Not enough workers

	ship.crew = crew
	var mission := GameState.start_mission(ship, best_asteroid)
	if mission:
		mission.return_to_station = true  # Auto-return when done; no idle-at-destination
		EventBus.station_job_started.emit(ship, "mining", best_asteroid.asteroid_name)

func _station_try_mining(ship: Ship) -> bool:
	# Actionable if: cargo space > 10%, fuel sufficient, crew aboard
	if ship.get_cargo_remaining() < ship.get_effective_cargo_capacity() * 0.1:
		return false

	var station_pos: Vector2 = ship.station_colony.get_position_au()

	# Find best-return mineable asteroid within station radius
	var best_asteroid: AsteroidData = null
	var best_score: float = -1.0
	for asteroid in GameState.asteroids:
		var dist := station_pos.distance_to(asteroid.get_position_au())
		if dist >= STATION_RADIUS_AU:
			continue
		var score := _score_mining_trip(ship, asteroid, station_pos)
		if score > best_score:
			best_score = score
			best_asteroid = asteroid

	if best_asteroid == null:
		return false

	# Dispatch mining mission that returns to station
	var mission := GameState.start_mission(ship, best_asteroid)
	if mission:
		mission.return_to_station = true
		mission.return_position_au = station_pos
		ship.add_station_log("Mining %s" % best_asteroid.asteroid_name, "mining")
		EventBus.station_job_started.emit(ship, "mining", best_asteroid.asteroid_name)
	return mission != null

func _station_try_trading(ship: Ship) -> bool:
	# Actionable if: ship has ore cargo to sell (supplies don't count)
	if ship.get_ore_total() < 0.1:
		return false

	var colony: Colony = ship.station_colony
	# Build cargo dict from ship's current cargo
	var cargo_to_sell: Dictionary = ship.current_cargo.duplicate()

	# Create trade mission to the station colony itself (local sale)
	var tm := GameState.start_trade_mission(ship, colony, cargo_to_sell)
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
	var workers: Array[Worker] = ship.crew.duplicate()
	var mission := Mission.new()
	mission.mission_type = Mission.MissionType.REPAIR
	mission.ship = ship
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

	var workers: Array[Worker] = ship.crew.duplicate()
	var mission := Mission.new()
	mission.mission_type = Mission.MissionType.SUPPLY_RUN
	mission.ship = ship
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
	GameState.missions.append(mission)
	EventBus.mission_started.emit(mission)

	ship.add_station_log("Delivering parts to %s" % best_target.ship_name, "supply")
	EventBus.station_job_started.emit(ship, "parts_delivery", best_target.ship_name)
	return true

func _station_try_provisioning(ship: Ship) -> bool:
	# Skip if player has disabled auto-supply
	if GameState.get_supply_policy(ship) == CompanyPolicy.SupplyPolicy.MANUAL:
		return false

	var threshold_days: float = CompanyPolicy.SUPPLY_POLICY_THRESHOLDS[GameState.get_supply_policy(ship)]
	var station_pos: Vector2 = ship.station_colony.get_position_au()
	var food_on_ship: float = ship.supplies.get("food", 0.0)

	if food_on_ship < 1.0:
		return false  # Nothing to deliver

	# Find the asteroid in range that is most critically undersupplied
	var best_asteroid: AsteroidData = null
	var best_dist: float = INF
	var best_days: float = INF

	for asteroid_name in GameState.asteroid_supplies.keys():
		var food_days := GameState.get_asteroid_supply_days(asteroid_name, "food")
		if food_days >= threshold_days:
			continue  # Supply is adequate per policy

		# Locate this asteroid
		var asteroid: AsteroidData = null
		for a in GameState.asteroids:
			if a.asteroid_name == asteroid_name:
				asteroid = a
				break
		if asteroid == null:
			continue

		var dist := station_pos.distance_to(asteroid.get_position_au())
		if dist >= STATION_RADIUS_AU:
			continue
		var fuel_needed := ship.calc_fuel_for_distance(dist, 0.0) * 2.0
		if fuel_needed > ship.fuel:
			continue

		# Prefer most critically undersupplied, then nearest
		if food_days < best_days or (food_days == best_days and dist < best_dist):
			best_asteroid = asteroid
			best_dist = dist
			best_days = food_days

	if best_asteroid == null:
		return false

	var crew: Array[Worker] = ship.crew.duplicate()
	var mission := Mission.new()
	mission.mission_type = Mission.MissionType.SUPPLY_RUN
	mission.ship = ship
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ship.position_au
	mission.origin_is_earth = false
	mission.return_position_au = ship.station_colony.get_position_au()
	mission.return_to_station = true
	mission.destination_position_au = best_asteroid.get_position_au()
	mission.transit_time = Brachistochrone.transit_time(best_dist, ship.get_effective_thrust())
	mission.station_job_duration = 1800.0
	mission.elapsed_ticks = 0.0

	var fuel_needed := ship.calc_fuel_for_distance(best_dist, 0.0) * 2.0
	mission.fuel_per_tick = fuel_needed / (mission.transit_time * 2.0) if mission.transit_time > 0 else 0.0

	ship.current_mission = mission
	ship.reset_life_support(crew.size())
	GameState.missions.append(mission)
	EventBus.mission_started.emit(mission)

	ship.add_station_log("Resupplying %s (%.0f days food remaining)" % [best_asteroid.asteroid_name, best_days], "provisioning")
	EventBus.station_job_started.emit(ship, "provisioning", best_asteroid.asteroid_name)
	return true

func _station_try_collect_ore(ship: Ship) -> bool:
	# Auto-collect stockpiled ore when stockpile meets collection policy threshold
	if GameState.get_collection_policy(ship) == CompanyPolicy.CollectionPolicy.MANUAL:
		return false

	var threshold_fraction: float = CompanyPolicy.COLLECTION_POLICY_THRESHOLDS[GameState.get_collection_policy(ship)]
	var threshold_tons: float = ship.get_effective_cargo_capacity() * threshold_fraction
	if threshold_tons <= 0.0:
		return false

	# Need cargo space to make it worthwhile
	if ship.get_cargo_remaining() < ship.get_effective_cargo_capacity() * 0.25:
		return false

	var station_pos: Vector2 = ship.station_colony.get_position_au()

	# Find the asteroid with the largest eligible stockpile within range
	var best_asteroid: AsteroidData = null
	var best_dist: float = INF
	var best_stockpile: float = 0.0

	for asteroid_name in GameState.ore_stockpiles.keys():
		var pile: Dictionary = GameState.ore_stockpiles[asteroid_name]
		var total: float = 0.0
		for ore_type in pile:
			total += pile[ore_type]
		if total < threshold_tons:
			continue

		var asteroid: AsteroidData = null
		for a in GameState.asteroids:
			if a.asteroid_name == asteroid_name:
				asteroid = a
				break
		if asteroid == null:
			continue

		var dist := station_pos.distance_to(asteroid.get_position_au())
		if dist >= STATION_RADIUS_AU:
			continue
		var fuel_needed := ship.calc_fuel_for_distance(dist, ship.get_cargo_total()) + \
			ship.calc_fuel_for_distance(dist, ship.get_effective_cargo_capacity())
		if fuel_needed > ship.fuel:
			continue

		if total > best_stockpile or (total == best_stockpile and dist < best_dist):
			best_asteroid = asteroid
			best_dist = dist
			best_stockpile = total

	if best_asteroid == null:
		return false

	var mission := GameState.start_collect_mission(ship, best_asteroid)
	if mission:
		mission.return_to_station = true
		mission.return_position_au = station_pos
		ship.add_station_log("Collecting %.0ft ore from %s" % [best_stockpile, best_asteroid.asteroid_name], "mining")
		EventBus.station_job_started.emit(ship, "collect_ore", best_asteroid.asteroid_name)
	return mission != null

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
		for w in other_ship.crew:
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
	var crew: Array[Worker] = ship.crew.duplicate()
	# Add replacement workers as passengers
	for w in replacements:
		if w not in crew:
			crew.append(w)

	var mission := Mission.new()
	mission.mission_type = Mission.MissionType.CREW_FERRY
	mission.ship = ship
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

	var workers: Array[Worker] = ship.crew.duplicate()
	var mission := Mission.new()
	mission.mission_type = Mission.MissionType.PATROL
	mission.ship = ship
	mission.asteroid = best_asteroid  # Use asteroid for position tracking
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

		# Consume food: 2.8 kg per worker per game-day
		var food_consumed := worker_count * 2.8 * days
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
	var days := dt / 86400.0
	if days < 0.001:
		return  # Skip tiny increments

	for w in GameState.workers:
		if w.assigned_mission != null:
			# On mission: fatigue increases, modified by personality and leader aura
			var fatigue_mult: float = w.get_fatigue_multiplier()
			if w.personality != Worker.Personality.LEADER:
				fatigue_mult *= _get_leader_fatigue_modifier(w.assigned_mission.ship.crew)
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
			var crew_count := maxi(other_ship.crew.size(), 1)
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

	# Deliver food/parts to deployed crews (legacy model) and asteroid supplies (mining units model)
	var food_delivered := false
	var parts_delivered := false

	# Legacy deployed_crews model
	for crew_data in GameState.deployed_crews:
		var asteroid: AsteroidData = crew_data["asteroid"]
		if asteroid.get_position_au().distance_to(delivery_pos) > 0.05:
			continue
		var food: float = ship.supplies.get("food", 0.0)
		if food > 0:
			crew_data["supplies"]["food"] = crew_data["supplies"].get("food", 0.0) + food
			ship.supplies["food"] = 0.0
			food_delivered = true
		break

	# Mining units model — match by nearest asteroid to delivery position
	var nearest_asteroid_name := ""
	var nearest_dist := INF
	for asteroid in GameState.asteroids:
		var d := asteroid.get_position_au().distance_to(delivery_pos)
		if d < nearest_dist and d < 0.05:
			nearest_dist = d
			nearest_asteroid_name = asteroid.asteroid_name

	if nearest_asteroid_name != "":
		var food: float = ship.supplies.get("food", 0.0)
		if food > 0.0:
			GameState.add_to_asteroid_supplies(nearest_asteroid_name, "food", food)
			ship.supplies["food"] = 0.0
			food_delivered = true
		var parts: float = ship.supplies.get("repair_parts", 0.0)
		if parts > 0.0:
			GameState.add_to_asteroid_supplies(nearest_asteroid_name, "repair_parts", parts)
			ship.supplies["repair_parts"] = 0.0
			parts_delivered = true

	if food_delivered or parts_delivered:
		var what := "supplies" if (food_delivered and parts_delivered) else ("food" if food_delivered else "parts")
		ship.add_station_log("Delivered %s to %s" % [what, nearest_asteroid_name if nearest_asteroid_name != "" else "crew"], "supply")
		EventBus.station_job_completed.emit(ship, "provisioning", "Delivered %s" % what)

	_start_station_return(mission)

func _find_nearest_crew_location(from_pos: Vector2) -> Vector2:
	# Returns position of nearest place where crew can be hired (Earth or any colony).
	var best_pos := CelestialData.get_earth_position_au()
	var best_dist := from_pos.distance_to(best_pos)
	for colony in GameState.colonies:
		var colony_pos := colony.get_position_au()
		var d := from_pos.distance_to(colony_pos)
		if d < best_dist:
			best_dist = d
			best_pos = colony_pos
	return best_pos

func _start_return_for_crew(ship: Ship, crew: Array[Worker]) -> void:
	# Creates a TRANSIT_BACK mission for a ship carrying a skeleton crew,
	# heading to the nearest place to pick up more crew.
	var target_pos := _find_nearest_crew_location(ship.position_au)
	var dist := ship.position_au.distance_to(target_pos)

	var m := Mission.new()
	m.mission_type = Mission.MissionType.CREW_FERRY
	m.ship = ship
	m.workers = crew.duplicate()
	m.status = Mission.Status.TRANSIT_BACK
	m.origin_position_au = ship.position_au
	m.return_position_au = target_pos
	m.origin_is_earth = false
	m.return_to_station = false  # Go to Earth / nearest location, not a station
	m.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())
	m.elapsed_ticks = 0.0
	var fuel_needed := ship.calc_fuel_for_distance(dist)
	m.fuel_per_tick = fuel_needed / m.transit_time if m.transit_time > 0.0 else 0.0

	ship.crew = crew.duplicate()
	ship.current_mission = m
	GameState.missions.append(m)
	EventBus.mission_started.emit(m)
	EventBus.mission_phase_changed.emit(m)

func _complete_boarding_job(mission: Mission) -> void:
	var ferry_ship := mission.ship

	# Derelict rescue: drop off rescue crew + supplies, clear derelict status
	if mission.is_derelict_rescue:
		var target_ship: Ship = null
		var target_name := mission.destination_name
		for other in GameState.ships:
			if other == ferry_ship:
				continue
			if other.ship_name == target_name or other.position_au.distance_to(mission.destination_position_au) < 0.05:
				target_ship = other
				break

		if target_ship != null and target_ship.is_derelict:
			# Transfer supplies
			var food_xfer: float = mission.supplies_to_transfer.get("food", 0.0)
			var parts_xfer: float = mission.supplies_to_transfer.get("repair_parts", 0.0)
			target_ship.supplies["food"] = target_ship.supplies.get("food", 0.0) + food_xfer
			target_ship.supplies["repair_parts"] = target_ship.supplies.get("repair_parts", 0.0) + parts_xfer

			# Auto-determine rescue crew: give target ship as many as possible while
			# keeping at least 1 on the ferry.
			if mission.rescue_crew.is_empty() and ferry_ship.crew.size() > 1:
				var rescue_count := mini(ferry_ship.crew.size() - 1, target_ship.min_crew)
				rescue_count = maxi(rescue_count, 1)
				for i in rescue_count:
					mission.rescue_crew.append(ferry_ship.crew[i])

			if mission.rescue_crew.size() > 0:
				# Apply loyalty penalty to rescue crew (they're replacing people the corp let die)
				const DERELICT_TAKEOVER_LOYALTY_PENALTY: float = -20.0
				for w in mission.rescue_crew:
					w.loyalty = clampf(w.loyalty + DERELICT_TAKEOVER_LOYALTY_PENALTY, 0.0, 100.0)


				# Assign rescue crew as skeleton crew on target ship
				target_ship.crew = mission.rescue_crew.duplicate()

				# Restore engine and fuel so the ship can make it home
				# (rescue crew perform emergency repairs using transferred parts)
				target_ship.engine_condition = maxf(target_ship.engine_condition, 50.0)
				target_ship.fuel = maxf(target_ship.fuel, target_ship.get_effective_fuel_capacity() * 0.5)

				# Clear derelict status
				target_ship.is_derelict = false
				target_ship.derelict_reason = ""
				GameState.rescue_missions.erase(target_ship)
				GameState.refuel_missions.erase(target_ship)
				GameState.stranger_offers.erase(target_ship)

				# Remove rescue crew from ferry (they ride on the target ship now)
				for w in mission.rescue_crew:
					ferry_ship.crew.erase(w)

				var sent_count := mission.rescue_crew.size()
				ferry_ship.add_station_log("Rescued %s: %d crew transferred, both returning for more crew" % [target_ship.ship_name, sent_count], "crew_ferry")
				EventBus.station_job_completed.emit(ferry_ship, "crew_ferry", "Rescued %s" % target_ship.ship_name)
				EventBus.rescue_mission_completed.emit(target_ship)

				# Target ship heads to nearest crew pickup location with its skeleton crew
				_start_return_for_crew(target_ship, mission.rescue_crew.duplicate())
			else:
				# Ferry arrived with only 1 crew — supplies transferred but no one can be left behind
				ferry_ship.add_station_log("Rescue of %s: ferry crew lost in transit, supplies transferred — send another ferry" % target_ship.ship_name, "crew_ferry")
				EventBus.station_job_completed.emit(ferry_ship, "crew_ferry", "Partial rescue: no crew to leave")
		else:
			ferry_ship.add_station_log("Fleet rescue: target not found or already recovered", "crew_ferry")
			EventBus.station_job_completed.emit(ferry_ship, "crew_ferry", "Target not found")

		# Ferry also returns home to pick up more crew
		_start_station_return(mission)
		return

	# Standard crew rotation ferry
	var target_pos := mission.destination_position_au
	var target_ship_rot: Ship = null

	for other in GameState.ships:
		if other == ferry_ship:
			continue
		if other.position_au.distance_to(target_pos) < 0.01:
			if other.current_mission != null:
				target_ship_rot = other
				break

	var swapped := 0
	if target_ship_rot != null and target_ship_rot.current_mission != null:
		var target_mission := target_ship_rot.current_mission
		# Find fatigued workers on target
		var fatigued: Array[Worker] = []
		for w in target_ship_rot.crew:
			if w.needs_rotation:
				fatigued.append(w)

		# Find fresh workers on ferry
		var fresh: Array[Worker] = []
		for w in ferry_ship.crew:
			if not w.needs_rotation:
				fresh.append(w)

		# Swap: remove fatigued from target, add fresh; fatigued board ferry
		for i in range(mini(fatigued.size(), fresh.size())):
			var tired_w: Worker = fatigued[i]
			var fresh_w: Worker = fresh[i]

			# Remove tired from target ship
			target_ship_rot.crew.erase(tired_w)
			tired_w.assigned_mission = null

			# Add fresh to target ship
			target_ship_rot.crew.append(fresh_w)
			fresh_w.assigned_mission = target_mission

			# Tired worker boards ferry for return trip
			if tired_w not in ferry_ship.crew:
				ferry_ship.crew.append(tired_w)
			tired_w.assigned_mission = mission

			# Remove fresh from ferry (they stay on target)
			ferry_ship.crew.erase(fresh_w)

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
	# Remove deployed workers from ship crew (they stay at the asteroid)
	for w in mission.workers_to_deploy:
		if w.assigned_mining_unit != null:
			mission.ship.crew.erase(w)

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
			var food_needed: float = workers * 2.8 * days
			GameState.consume_asteroid_supply(asteroid_name, "food", food_needed)
			# Alert if low — throttled to once per game-day
			var food_days := GameState.get_asteroid_supply_days(asteroid_name, "food")
			if food_days < SUPPLY_ALERT_DAYS and food_days > 0.0:
				var food_key: String = asteroid_name + ":food"
				var last: float = _supply_alert_last_fired.get(food_key, -86400.0)
				if GameState.total_ticks - last >= 86400.0:
					_supply_alert_last_fired[food_key] = GameState.total_ticks
					EventBus.asteroid_supplies_low.emit(asteroid_name, "food", food_days)

		# Consume repair parts
		if units > 0:
			var parts_needed: float = units * 0.05 * days
			GameState.consume_asteroid_supply(asteroid_name, "repair_parts", parts_needed)
			# Alert if low — throttled to once per game-day
			var parts_days := GameState.get_asteroid_supply_days(asteroid_name, "repair_parts")
			if parts_days < SUPPLY_ALERT_DAYS and parts_days > 0.0:
				var parts_key: String = asteroid_name + ":repair_parts"
				var last: float = _supply_alert_last_fired.get(parts_key, -86400.0)
				if GameState.total_ticks - last >= 86400.0:
					_supply_alert_last_fired[parts_key] = GameState.total_ticks
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

	# Grace periods after supplies run out (in game-seconds)
	const FOOD_GRACE_PERIOD: float = 17.0 * 86400.0   # 17 days
	const WATER_GRACE_PERIOD: float = 3.0 * 86400.0   # 3 days
	const OXYGEN_GRACE_PERIOD: float = 1.0 * 86400.0  # 1 day

	# Process deployed mining units
	for unit in GameState.deployed_mining_units:
		if unit.assigned_workers.is_empty():
			continue
		# Workers at mining units don't have a ship - they need supply deliveries
		# For now, just track this as a TODO - they'll need a separate food supply at the asteroid
		pass  # TODO: Implement asteroid-based food stockpiles for deployed workers

	# Process ships on missions
	for mission in GameState.missions:
		if mission.ship.crew.is_empty():
			continue
		var ship := mission.ship
		if ship.is_derelict:
			continue

		# Calculate food consumption in kg
		var food_needed_kg := ship.crew.size() * food_per_worker_per_day_kg * days
		var current_food_kg: float = ship.supplies.get("food", 0.0)

		if current_food_kg >= food_needed_kg:
			ship.supplies["food"] = current_food_kg - food_needed_kg
			ship.food_depleted_at = -1.0  # Reset if resupplied
		else:
			# Food depleted - start grace period or check if expired
			ship.supplies["food"] = 0.0
			if ship.food_depleted_at < 0:
				ship.food_depleted_at = GameState.total_ticks

			# Loyalty degradation while without food (-0.5 loyalty per half-day)
			const LOYALTY_CHECK_INTERVAL: float = 43200.0  # 0.5 game-days
			if GameState.total_ticks - ship.last_supply_loyalty_penalty >= LOYALTY_CHECK_INTERVAL:
				ship.last_supply_loyalty_penalty = GameState.total_ticks
				for worker in ship.crew:
					worker.loyalty = maxf(0.0, worker.loyalty - 0.5)

			if GameState.total_ticks - ship.food_depleted_at > FOOD_GRACE_PERIOD:
				_trigger_starvation(ship, mission)

	# Process trade missions
	for tm in GameState.trade_missions:
		if tm.ship.crew.is_empty():
			continue
		var ship := tm.ship
		if ship.is_derelict:
			continue

		var food_needed_kg := ship.crew.size() * food_per_worker_per_day_kg * days
		var current_food_kg: float = ship.supplies.get("food", 0.0)

		if current_food_kg >= food_needed_kg:
			ship.supplies["food"] = current_food_kg - food_needed_kg
			ship.food_depleted_at = -1.0  # Reset if resupplied
		else:
			ship.supplies["food"] = 0.0
			if ship.food_depleted_at < 0:
				ship.food_depleted_at = GameState.total_ticks

			# Loyalty degradation while without food (-0.5 loyalty per half-day)
			const LOYALTY_CHECK_INTERVAL: float = 43200.0  # 0.5 game-days
			if GameState.total_ticks - ship.last_supply_loyalty_penalty >= LOYALTY_CHECK_INTERVAL:
				ship.last_supply_loyalty_penalty = GameState.total_ticks
				for worker in ship.crew:
					worker.loyalty = maxf(0.0, worker.loyalty - 0.5)

			if GameState.total_ticks - ship.food_depleted_at > FOOD_GRACE_PERIOD:
				_trigger_starvation(ship, null, tm)

func _trigger_starvation(ship: Ship, mission: Mission = null, trade_mission: TradeMission = null) -> void:
	# Crew starve to death after grace period expires
	ship.supplies["food"] = 0.0

	var dead_workers: Array[Worker] = ship.crew.duplicate()
	ship.crew.clear()
	if mission:
		mission.status = Mission.Status.COMPLETED
		GameState.missions.erase(mission)
		ship.current_mission = null
	elif trade_mission:
		trade_mission.status = TradeMission.Status.COMPLETED
		GameState.trade_missions.erase(trade_mission)
		ship.current_trade_mission = null

	# Remove dead workers from the game entirely
	for w in dead_workers:
		GameState.workers.erase(w)

	# Ship becomes derelict — no crew to fly it back
	ship.is_derelict = true
	ship.derelict_reason = "breakdown"
	ship.docked_at_colony = null

	var worker_names := ", ".join(dead_workers.map(func(w: Worker) -> String: return w.worker_name))
	EventBus.ship_breakdown.emit(ship, "Food depleted — crew starved")
	EventBus.ship_derelict.emit(ship)
	EventBus.ship_food_depleted.emit(ship, dead_workers.size())
	print("Ship %s: Food depleted — %d crew starved (%s)" % [ship.ship_name, dead_workers.size(), worker_names])

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

func _auto_refuel_at_earth(ship: Ship) -> void:
	# Automatically refuel ship when it returns to Earth (if auto_refuel enabled)
	if not GameState.settings.get("auto_refuel", true):
		return
	if ship.fuel >= ship.get_effective_fuel_capacity():
		return  # Already full
	var fuel_needed := ship.get_effective_fuel_capacity() - ship.fuel
	var fuel_cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)
	if GameState.money >= fuel_cost:
		ship.fuel = ship.get_effective_fuel_capacity()
		GameState.money -= fuel_cost
		if fuel_cost > 0:
			GameState.record_transaction(-fuel_cost, "Refuel at Earth", ship.ship_name)

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

func _auto_repair_at_location(ship: Ship) -> void:
	# Auto-repair engine based on company/ship repair policy.
	# Check location directly rather than is_docked — this is called during mission
	# completion when current_mission may still be set (timing artifact).
	if ship.engine_condition >= 100.0:
		return
	var at_service := ship.is_at_earth or \
		(ship.docked_at_colony != null and ship.docked_at_colony.has_rescue_ops)
	if not at_service:
		return
	var policy := GameState.get_repair_policy(ship)
	var should_repair := false
	match policy:
		CompanyPolicy.RepairPolicy.ALWAYS:
			should_repair = true
		CompanyPolicy.RepairPolicy.AS_NEEDED:
			should_repair = ship.engine_condition < CompanyPolicy.REPAIR_AS_NEEDED_THRESHOLD
		CompanyPolicy.RepairPolicy.NEVER:
			should_repair = false
	if not should_repair:
		return
	var cost := ship.get_engine_repair_cost()
	if cost <= 0:
		return
	if GameState.money < cost:
		ship.add_station_log("Cannot afford engine repair ($%d)" % cost, "repair")
		return
	GameState.money -= cost
	GameState.record_transaction(-cost, "Engine repair", ship.ship_name)
	ship.engine_condition = 100.0
	ship.add_station_log("Engine repaired ($%d)" % cost, "repair")
	EventBus.station_job_completed.emit(ship, "repair", "Engine repaired")

func _auto_provision_at_location(ship: Ship) -> void:
	# Automatically stock food, water, and O2 when ship is docked (at colony or Earth)
	const DAYS_BUFFER := 30.0  # Maintain 30 days of life support supplies

	# Determine crew size (use min_crew if no crew assigned)
	var crew_size := ship.crew.size() if ship.crew.size() > 0 else ship.min_crew

	# ── Food ──────────────────────────────────────────────────────────────────
	# 2.8 kg/person/day
	var target_food_kg := crew_size * DAYS_BUFFER * 2.8
	var current_food: float = ship.supplies.get("food", 0.0)
	if current_food < target_food_kg:
		var needed := target_food_kg - current_food
		var success := GameState.buy_supplies(ship, "food", needed)
		if not success:
			_log_provision_failure(ship, "food", needed, crew_size)

	# ── Water (recycled) ──────────────────────────────────────────────────────
	# 0.25 L/person/day makeup with 90% recycling; 1 tank = 20 L
	var target_water_units := crew_size * DAYS_BUFFER * 0.25 / 20.0
	var current_water: float = ship.supplies.get("water", 0.0)
	if current_water < target_water_units:
		var needed := target_water_units - current_water
		var success := GameState.buy_supplies(ship, "water", needed)
		if not success:
			_log_provision_failure(ship, "water", needed, crew_size)

	# ── Oxygen (recycled) ─────────────────────────────────────────────────────
	# 0.05 kg/person/day makeup with CO2 scrubbing; 1 canister = 2 kg
	var target_o2_units := crew_size * DAYS_BUFFER * 0.05 / 2.0
	var current_o2: float = ship.supplies.get("oxygen", 0.0)
	if current_o2 < target_o2_units:
		var needed := target_o2_units - current_o2
		var success := GameState.buy_supplies(ship, "oxygen", needed)
		if not success:
			_log_provision_failure(ship, "oxygen", needed, crew_size)

func _log_provision_failure(ship: Ship, supply_key: String, amount: float, crew_size: int) -> void:
	# Log why auto-provisioning failed (for debugging starvation issues)
	var log := FileAccess.open("res://provision_failures.txt", FileAccess.READ_WRITE)
	if log:
		log.seek_end()
		var unit_label := SupplyData.get_unit_label_from_key(supply_key)
		var cargo_remaining := ship.get_cargo_remaining()
		var cargo_volume_remaining := ship.get_cargo_volume_remaining()
		log.store_line("[%.1f] %s failed to provision %s %.2f %s for %d crew" % [
			GameState.game_clock_ticks / 86400.0,
			ship.ship_name,
			supply_key,
			amount,
			unit_label,
			crew_size
		])
		log.store_line("  Money: $%d | Cargo: %.1ft remaining | Volume: %.1fm³ remaining" % [
			GameState.money,
			cargo_remaining,
			cargo_volume_remaining
		])
		log.close()

# ─── Rival Corporations ───────────────────────────────────────────────────────

func _process_rival_corps(dt: float) -> void:
	# Advance all rival ships every tick (transit & mining progress)
	for corp: RivalCorp in GameState.rival_corps:
		for ship: RivalShip in corp.ships:
			_advance_rival_ship(corp, ship, dt)

	# Ghost contact tracking update every OBSERVATION_INTERVAL
	_update_ghost_contacts(dt)

	# AI decision logic runs every RIVAL_CHECK_INTERVAL
	_rival_accumulator += dt
	if _rival_accumulator < RIVAL_CHECK_INTERVAL:
		return
	_rival_accumulator -= RIVAL_CHECK_INTERVAL
	for corp: RivalCorp in GameState.rival_corps:
		_update_rival_corp_decisions(corp)

func _update_ghost_contacts(dt: float) -> void:
	_observation_accumulator += dt
	if _observation_accumulator < OBSERVATION_INTERVAL:
		return
	_observation_accumulator -= OBSERVATION_INTERVAL

	var current_ticks := GameState.total_ticks
	var earth_pos := CelestialData.get_earth_position_au()

	# Observer list: Earth/HQ + all non-derelict player ships
	var observers: Array[Vector2] = [earth_pos]
	for ship: Ship in GameState.ships:
		if not ship.is_derelict:
			observers.append(ship.position_au)

	for corp: RivalCorp in GameState.rival_corps:
		for ship_idx in range(corp.ships.size()):
			var rship: RivalShip = corp.ships[ship_idx]
			var ship_pos := rship.get_position_au()

			# Best observer: highest exhaust-cone visibility from any player asset
			var best_visibility: float = 0.0
			var best_observer: Vector2 = earth_pos
			for obs_pos: Vector2 in observers:
				var vis := rship.get_visibility_from(obs_pos)
				if vis > best_visibility:
					best_visibility = vis
					best_observer = obs_pos

			if best_visibility < MIN_VISIBILITY:
				continue  # Exhaust not facing any observer — invisible this interval

			# Full light-speed delay: rival ship → observer → HQ
			var dist_to_obs: float = ship_pos.distance_to(best_observer)
			var dist_obs_to_hq: float = best_observer.distance_to(earth_pos)
			var total_delay: float = (dist_to_obs + dist_obs_to_hq) * GameState.LIGHT_SECONDS_PER_AU

			# Back-calculate position: where was the ship when photons left it?
			var velocity := rship.get_velocity_au_per_tick()
			var observed_pos := ship_pos - velocity * total_delay

			var obs := GhostObservation.new()
			obs.observed_position_au = observed_pos
			obs.observed_velocity_au_per_tick = velocity
			obs.received_at_ticks = current_ticks
			obs.initial_confidence = best_visibility

			# Match to existing contact or create a new one
			var contact = _find_matching_contact(observed_pos, velocity, current_ticks)
			if contact == null:
				contact = GhostContact.new()  # class_name defined in ghost_contact.gd
				contact.contact_id = _next_contact_id
				_next_contact_id += 1
				contact.contact_color = CONTACT_COLORS[contact.contact_id % CONTACT_COLORS.size()]
				contact.first_seen_ticks = current_ticks
				GameState.ghost_contacts.append(contact)

			contact.update_obs(obs, current_ticks)
			_infer_contact_corp(contact)

	# Prune contacts that have decayed past the display threshold
	var pruned: Array = []  # Array[GhostContact]
	for c in GameState.ghost_contacts:
		if not c.is_expired(current_ticks):
			pruned.append(c)
	GameState.ghost_contacts = pruned

## Find an existing contact whose predicted position matches obs_pos and whose
## velocity direction is consistent. Returns null if no match found.
func _find_matching_contact(obs_pos: Vector2, velocity: Vector2, current_ticks: float):  # -> GhostContact
	var best = null
	var best_dist: float = CONTACT_MATCH_RADIUS
	for contact in GameState.ghost_contacts:
		var predicted: Vector2 = contact.get_estimated_position(current_ticks)
		var dist: float = obs_pos.distance_to(predicted)
		if dist > CONTACT_MATCH_RADIUS:
			continue
		# Velocity direction check — reject if headings are more than ~60° apart
		var prev_vel: Vector2 = contact.latest_obs.observed_velocity_au_per_tick
		if velocity.length_squared() > 1e-10 and prev_vel.length_squared() > 1e-10:
			if velocity.normalized().dot(prev_vel.normalized()) < 0.5:
				continue
		if dist < best_dist:
			best_dist = dist
			best = contact
	return best

## Infer which corp owns a contact based on velocity direction relative to known home positions.
## A ship heading toward or away from a corp's home scores highly for that corp.
## False attributions happen naturally when trajectories are ambiguous.
func _infer_contact_corp(contact) -> void:  # contact: GhostContact
	if contact.latest_obs == null:
		return
	var vel: Vector2 = contact.latest_obs.observed_velocity_au_per_tick
	if vel.length_squared() < 1e-10:
		return  # No velocity — can't infer direction
	var vel_dir := vel.normalized()
	var pos: Vector2 = contact.latest_obs.observed_position_au

	var best_corp: String = ""
	var best_score: float = 0.0
	for corp: RivalCorp in GameState.rival_corps:
		var to_home := corp.home_position_au - pos
		if to_home.length_squared() < 1e-6:
			continue
		var to_home_dir := to_home.normalized()
		# Inbound (heading toward home) or outbound (heading away) both count
		var score := maxf(vel_dir.dot(to_home_dir), vel_dir.dot(-to_home_dir))
		if score > best_score:
			best_score = score
			best_corp = corp.corp_name

	if best_score >= 0.70:
		contact.inferred_corp = best_corp
		contact.corp_confidence = remap(best_score, 0.70, 1.0, 0.35, 0.90)
	elif best_score >= 0.50:
		contact.inferred_corp = best_corp
		contact.corp_confidence = remap(best_score, 0.50, 0.70, 0.10, 0.35)
	# else: leave as unknown — happens when ship heading is nearly perpendicular to all home vectors

func _advance_rival_ship(corp: RivalCorp, ship: RivalShip, dt: float) -> void:
	match ship.status:
		RivalShip.Status.TRANSIT_TO:
			ship.elapsed_ticks += dt
			if ship.elapsed_ticks >= ship.transit_time:
				ship.status = RivalShip.Status.MINING
				ship.elapsed_ticks = 0.0
				ship.mining_elapsed = 0.0
				EventBus.rival_corp_arrived.emit(corp.corp_name, ship.target_asteroid_name)
				# Check for contested slots
				if GameState.get_player_units_at(ship.target_asteroid_name) > 0:
					EventBus.rival_corps_contested.emit(corp.corp_name, ship.target_asteroid_name)

		RivalShip.Status.MINING:
			ship.mining_elapsed += dt
			# Accumulate cargo based on asteroid ore density
			var asteroid := _find_asteroid(ship.target_asteroid_name)
			if asteroid != null and not asteroid.ore_yields.is_empty():
				var total_yield_rate: float = 0.0
				for ore_type in asteroid.ore_yields:
					total_yield_rate += float(asteroid.ore_yields[ore_type])
				var mined := total_yield_rate * BASE_MINING_RATE * dt
				ship.cargo_tons = minf(ship.cargo_tons + mined, ship.cargo_capacity)
			if ship.mining_elapsed >= ship.mining_duration or ship.cargo_tons >= ship.cargo_capacity * 0.95:
				# Head home
				ship.status = RivalShip.Status.TRANSIT_HOME
				ship.elapsed_ticks = 0.0
				var dist := ship.target_position_au.distance_to(ship.home_position_au)
				ship.transit_time = Brachistochrone.transit_time(dist, ship.thrust_g)

		RivalShip.Status.TRANSIT_HOME:
			ship.elapsed_ticks += dt
			if ship.elapsed_ticks >= ship.transit_time:
				ship.status = RivalShip.Status.IDLE
				ship.elapsed_ticks = 0.0
				var revenue := _sell_rival_cargo(corp, ship)
				EventBus.rival_corp_departed.emit(corp.corp_name, ship.target_asteroid_name, ship.cargo_tons)
				ship.cargo_tons = 0.0
				ship.target_asteroid_name = ""
				if revenue > 0:
					corp.money += revenue

func _update_rival_corp_decisions(corp: RivalCorp) -> void:
	for ship: RivalShip in corp.ships:
		if ship.status != RivalShip.Status.IDLE:
			continue
		_rival_try_dispatch(corp, ship)

func _rival_try_dispatch(corp: RivalCorp, ship: RivalShip) -> void:
	var best_asteroid: AsteroidData = null
	var best_score: float = -1.0

	for asteroid in GameState.asteroids:
		var score := _score_asteroid_for_rival(corp, ship, asteroid)
		if score > best_score:
			best_score = score
			best_asteroid = asteroid

	if best_asteroid == null or best_score <= 0.0:
		return

	var dist := ship.home_position_au.distance_to(best_asteroid.get_position_au())
	ship.target_asteroid_name = best_asteroid.asteroid_name
	ship.target_position_au = best_asteroid.get_position_au()
	ship.transit_time = Brachistochrone.transit_time(dist, ship.thrust_g)
	ship.elapsed_ticks = 0.0
	ship.mining_duration = RIVAL_BASE_MINING_DURATION * randf_range(0.7, 1.3)
	ship.status = RivalShip.Status.TRANSIT_TO
	EventBus.rival_corp_dispatched.emit(corp.corp_name, best_asteroid.asteroid_name)

func _score_asteroid_for_rival(corp: RivalCorp, ship: RivalShip, asteroid: AsteroidData) -> float:
	if asteroid.ore_yields.is_empty():
		return -1.0

	var dist := ship.home_position_au.distance_to(asteroid.get_position_au())
	if dist <= 0.0:
		return -1.0

	# Range filter — only attempt reachable asteroids (fuel heuristic: 2× transit fuel)
	var max_range := _get_rival_max_range(ship)
	if dist > max_range:
		return -1.0

	# Base ore value of asteroid
	var ore_value := _calc_rival_ore_rate(asteroid)

	# Slot availability — penalise contested asteroids
	var occupied := GameState.get_occupied_slots(asteroid.asteroid_name)
	var max_slots := asteroid.get_max_mining_slots()
	if occupied >= max_slots:
		return -1.0

	var slot_factor := 1.0 - float(occupied) / float(max_slots)
	var player_units := GameState.get_player_units_at(asteroid.asteroid_name)

	# Personality modifiers
	var proximity_penalty := dist  # Closer is better by default
	match corp.personality:
		RivalCorp.Personality.AGGRESSIVE:
			# Targets richest regardless of competition
			return ore_value * slot_factor / proximity_penalty
		RivalCorp.Personality.SYSTEMATIC:
			# Prefers less-contested bodies; penalises player presence
			var contest_penalty := 1.0 + player_units * 0.5
			return (ore_value / contest_penalty) / proximity_penalty
		RivalCorp.Personality.OPPORTUNISTIC:
			# Follows the richest opportunity, boosted by player presence (follows the money)
			var follow_bonus := 1.0 + player_units * 0.3
			return ore_value * follow_bonus / proximity_penalty
		RivalCorp.Personality.CONSERVATIVE:
			# Prefers safe nearby bodies; avoids conflict
			if player_units > 0 or occupied > 0:
				return -1.0
			return ore_value / (proximity_penalty * proximity_penalty)
		RivalCorp.Personality.EXPANSIONIST:
			# Sends many ships; prefers any open slot, less picky about value
			return slot_factor / proximity_penalty
	return -1.0

func _get_rival_max_range(ship: RivalShip) -> float:
	# Simple heuristic: rivals operate within 4 AU of home (adjustable)
	return 4.0 + ship.thrust_g * 4.0

func _calc_rival_ore_rate(asteroid: AsteroidData) -> float:
	var total := 0.0
	for ore_type in asteroid.ore_yields:
		var rate: float = float(asteroid.ore_yields[ore_type])
		# Weight by current market price if available
		var price: float = float(GameState.market.current_prices.get(ore_type, 1000.0))
		total += rate * price
	return total

func _sell_rival_cargo(corp: RivalCorp, ship: RivalShip) -> int:
	if ship.cargo_tons <= 0.0:
		return 0
	# Estimate value using average price across all ores
	var avg_price := 0.0
	var count := 0
	for ore_type in GameState.market.current_prices:
		avg_price += float(GameState.market.current_prices[ore_type])
		count += 1
	if count > 0:
		avg_price /= count
	var revenue := int(ship.cargo_tons * avg_price * 0.8)  # 80% of market (they sell at discount)
	corp.total_ore_mined += ship.cargo_tons
	corp.total_revenue += revenue
	return revenue

func _find_asteroid(name: String) -> AsteroidData:
	for asteroid in GameState.asteroids:
		if asteroid.asteroid_name == name:
			return asteroid
	return null
