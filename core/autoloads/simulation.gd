extends Node

var game_speed: float = 5.0  # Fast fixed speed for testing

var _tick_accumulator: float = 0.0
const TICK_INTERVAL: float = 1.0  # 1 second per tick at 1x speed
var _payroll_accumulator: float = 0.0
const PAYROLL_INTERVAL: float = 60.0  # pay wages every 60 ticks
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

# Chance per survey interval that a random asteroid gets re-surveyed
const SURVEY_CHANCE: float = 0.15

func _process(delta: float) -> void:
	if game_speed <= 0.0:
		return

	_tick_accumulator += delta * game_speed
	while _tick_accumulator >= TICK_INTERVAL:
		_tick_accumulator -= TICK_INTERVAL
		_process_tick(TICK_INTERVAL)

func _process_tick(dt: float) -> void:
	_process_orbits(dt)
	EventBus.tick.emit(dt)
	_process_missions(dt)
	_process_trade_missions(dt)
	_update_ship_positions(dt)
	_check_breakdowns(dt)
	_process_rescues(dt)
	_process_refuels(dt)
	_process_fabrication(dt)
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

	# Sync docked ships with Earth's position
	var earth_pos := CelestialData.get_earth_position_au()
	for ship in GameState.ships:
		if ship.is_docked:
			ship.position_au = earth_pos

func _process_missions(dt: float) -> void:
	var missions := GameState.missions.duplicate()
	for mission: Mission in missions:
		mission.elapsed_ticks += dt

		match mission.status:
			Mission.Status.TRANSIT_OUT:
				_burn_fuel(mission, dt)
				if mission.elapsed_ticks >= mission.transit_time:
					# Check if ship is already full before mining
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
					# Set ship position to return destination
					mission.ship.position_au = mission.return_position_au
					GameState.complete_mission(mission)

func _burn_fuel(mission: Mission, dt: float) -> void:
	var ship := mission.ship
	ship.fuel = maxf(ship.fuel - mission.fuel_per_tick * dt, 0.0)

	# If fuel reaches 0, ship becomes stranded
	if ship.fuel <= 0 and not ship.is_derelict:
		_trigger_fuel_depletion(ship)

func _mine_tick(mission: Mission, _dt: float) -> void:
	var ship := mission.ship

	# Don't mine if cargo is already full
	var cargo_total := ship.get_cargo_total()
	if cargo_total >= ship.cargo_capacity:
		return  # Skip mining this tick

	if ship.get_cargo_remaining() <= 0:
		return

	var worker_skill_total := 0.0
	for w in mission.workers:
		worker_skill_total += w.skill
	if worker_skill_total <= 0:
		return

	var equip_mult := ship.get_mining_multiplier()

	# Random variance on this tick's output
	var luck := randf_range(MINING_VARIANCE_MIN, MINING_VARIANCE_MAX)

	for ore_type in mission.asteroid.ore_yields:
		var base_yield: float = mission.asteroid.ore_yields[ore_type]
		var mined: float = base_yield * worker_skill_total * equip_mult * luck
		var remaining := ship.get_cargo_remaining()
		mined = minf(mined, remaining)
		if mined > 0:
			ship.current_cargo[ore_type] = ship.current_cargo.get(ore_type, 0.0) + mined

	# Degrade equipment during mining
	for equip in ship.equipment:
		if equip.is_functional() and equip.durability > 0:
			var old_durability := equip.durability
			equip.durability = maxf(equip.durability - equip.wear_per_tick, 0.0)
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
					# Clear cargo after selling to prevent double-payment exploits
					tm.cargo.clear()
					EventBus.trade_mission_phase_changed.emit(tm)

			TradeMission.Status.SELLING:
				if tm.elapsed_ticks >= TradeMission.SELL_DURATION:
					tm.status = TradeMission.Status.IDLE_AT_COLONY
					tm.elapsed_ticks = 0.0
					# Set ship position to colony location
					tm.ship.position_au = tm.colony.get_position_au()
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
	# Interpolate ship positions during transit based on mission progress
	for mission: Mission in GameState.missions:
		var ship := mission.ship
		if ship.is_derelict:
			continue
		match mission.status:
			Mission.Status.TRANSIT_OUT:
				var progress := mission.get_progress()
				ship.position_au = mission.origin_position_au.lerp(
					mission.asteroid.get_position_au(), progress
				)
			Mission.Status.MINING:
				ship.position_au = mission.asteroid.get_position_au()
			Mission.Status.IDLE_AT_DESTINATION:
				ship.position_au = mission.asteroid.get_position_au()
			Mission.Status.TRANSIT_BACK:
				var progress := mission.get_progress()
				var start_pos: Vector2
				if mission.asteroid:
					start_pos = mission.asteroid.get_position_au()
				else:
					start_pos = mission.origin_position_au
				ship.position_au = start_pos.lerp(mission.return_position_au, progress)

	for tm: TradeMission in GameState.trade_missions:
		var ship := tm.ship
		if ship.is_derelict:
			continue
		match tm.status:
			TradeMission.Status.TRANSIT_TO_COLONY:
				var progress := tm.get_progress()
				ship.position_au = tm.origin_position_au.lerp(
					tm.colony.get_position_au(), progress
				)
			TradeMission.Status.SELLING, TradeMission.Status.IDLE_AT_COLONY:
				ship.position_au = tm.colony.get_position_au()
			TradeMission.Status.TRANSIT_BACK:
				var progress := tm.get_progress()
				ship.position_au = tm.colony.get_position_au().lerp(
					tm.return_position_au, progress
				)

func _check_breakdowns(dt: float) -> void:
	for mission: Mission in GameState.missions:
		var ship := mission.ship
		if ship.is_derelict:
			continue
		if mission.status == Mission.Status.TRANSIT_OUT or mission.status == Mission.Status.TRANSIT_BACK:
			# Degrade engine during transit
			ship.engine_condition = maxf(ship.engine_condition - ship.engine_wear_per_tick * dt, 0.0)
			# Roll for breakdown
			var chance := ship.get_breakdown_chance_per_tick()
			if chance > 0 and randf() < chance * dt:
				_trigger_breakdown(ship, "Engine failure during transit")

	for tm: TradeMission in GameState.trade_missions:
		var ship := tm.ship
		if ship.is_derelict:
			continue
		if tm.status == TradeMission.Status.TRANSIT_TO_COLONY or tm.status == TradeMission.Status.TRANSIT_BACK:
			ship.engine_condition = maxf(ship.engine_condition - ship.engine_wear_per_tick * dt, 0.0)
			var chance := ship.get_breakdown_chance_per_tick()
			if chance > 0 and randf() < chance * dt:
				_trigger_breakdown(ship, "Engine failure during transit")

func _trigger_breakdown(ship: Ship, reason: String) -> void:
	ship.is_derelict = true
	ship.derelict_reason = "breakdown"
	EventBus.ship_breakdown.emit(ship, reason)
	EventBus.ship_derelict.emit(ship)

	# Remove from active mission tracking but keep the mission reference for position
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

func _trigger_fuel_depletion(ship: Ship) -> void:
	ship.is_derelict = true
	ship.derelict_reason = "out_of_fuel"
	EventBus.ship_breakdown.emit(ship, "Fuel depleted")
	EventBus.ship_derelict.emit(ship)

	# Remove from active mission tracking but keep the mission reference for position
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

		# Ship returns to Earth at 50% condition/fuel, cargo lost
		ship.is_derelict = false
		ship.derelict_reason = ""
		ship.position_au = CelestialData.get_earth_position_au()
		ship.engine_condition = 50.0
		ship.fuel = ship.fuel_capacity * 0.5
		ship.current_cargo.clear()

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

		EventBus.refuel_mission_completed.emit(ship, fuel_delivered)

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
	var fuel_cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)

	# Only refuel if player can afford it
	if GameState.money >= fuel_cost:
		ship.fuel = ship.get_effective_fuel_capacity()
		GameState.money -= fuel_cost
		# Note: Could add an event here if we want to notify player
