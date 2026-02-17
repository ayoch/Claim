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

func _process_missions(dt: float) -> void:
	var missions := GameState.missions.duplicate()
	for mission: Mission in missions:
		mission.elapsed_ticks += dt

		match mission.status:
			Mission.Status.TRANSIT_OUT:
				_burn_fuel(mission, dt)
				if mission.elapsed_ticks >= mission.transit_time:
					mission.status = Mission.Status.MINING
					mission.elapsed_ticks = 0.0
					EventBus.mission_phase_changed.emit(mission)

			Mission.Status.MINING:
				_mine_tick(mission, dt)
				if mission.elapsed_ticks >= mission.mining_duration:
					mission.status = Mission.Status.TRANSIT_BACK
					mission.elapsed_ticks = 0.0
					EventBus.mission_phase_changed.emit(mission)

			Mission.Status.TRANSIT_BACK:
				_burn_fuel(mission, dt)
				if mission.elapsed_ticks >= mission.transit_time:
					GameState.complete_mission(mission)

func _burn_fuel(mission: Mission, dt: float) -> void:
	var ship := mission.ship
	ship.fuel = maxf(ship.fuel - mission.fuel_per_tick * dt, 0.0)

func _mine_tick(mission: Mission, _dt: float) -> void:
	var ship := mission.ship
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
	# Tick down fabrication timers on inventory items
	var completed: Array[Equipment] = []
	for equip in GameState.equipment_inventory:
		if equip.fabrication_ticks > 0:
			equip.fabrication_ticks = maxf(equip.fabrication_ticks - dt, 0.0)
			if equip.fabrication_ticks <= 0:
				completed.append(equip)
	for equip in completed:
		EventBus.equipment_fabricated.emit(equip)

func _process_trade_missions(dt: float) -> void:
	var trade_missions := GameState.trade_missions.duplicate()
	for tm: TradeMission in trade_missions:
		tm.elapsed_ticks += dt

		match tm.status:
			TradeMission.Status.TRANSIT_TO_COLONY:
				tm.ship.fuel = maxf(tm.ship.fuel - tm.fuel_per_tick * dt, 0.0)
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
					EventBus.trade_mission_phase_changed.emit(tm)

			TradeMission.Status.SELLING:
				if tm.elapsed_ticks >= TradeMission.SELL_DURATION:
					tm.status = TradeMission.Status.TRANSIT_BACK
					tm.elapsed_ticks = 0.0
					EventBus.trade_mission_phase_changed.emit(tm)

			TradeMission.Status.TRANSIT_BACK:
				tm.ship.fuel = maxf(tm.ship.fuel - tm.fuel_per_tick * dt, 0.0)
				if tm.elapsed_ticks >= tm.transit_time:
					GameState.complete_trade_mission(tm)

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
	_market_accumulator += dt
	if _market_accumulator < MARKET_INTERVAL:
		return
	_market_accumulator -= MARKET_INTERVAL

	# Apply drift to all prices
	GameState.market.apply_drift()

	# Chance of scripted market event
	if randf() < MARKET_EVENT_CHANCE:
		_trigger_market_event()

func _trigger_market_event() -> void:
	var ore_values := ResourceTypes.OreType.values()
	var ore_type: ResourceTypes.OreType = ore_values[randi() % ore_values.size()]
	var old_price: float = GameState.market.get_price(ore_type)
	var ore_name: String = ResourceTypes.get_ore_name(ore_type)

	var event_type: int = randi() % 4
	var message: String
	match event_type:
		0:  # GLUT - prices drop
			GameState.market.apply_event_multiplier(ore_type, randf_range(0.6, 0.8))
			message = "Market Glut: %s supply surge drives prices down" % ore_name
		1:  # SHORTAGE - prices rise
			GameState.market.apply_event_multiplier(ore_type, randf_range(1.2, 1.5))
			message = "Supply Shortage: %s scarcity pushes prices up" % ore_name
		2:  # DEMAND SPIKE
			GameState.market.apply_event_multiplier(ore_type, randf_range(1.3, 1.6))
			message = "Demand Spike: Industrial demand for %s surges" % ore_name
		3:  # DISCOVERY
			GameState.market.apply_event_multiplier(ore_type, randf_range(0.5, 0.75))
			message = "New Discovery: Major %s deposit found, prices fall" % ore_name

	var new_price: float = GameState.market.get_price(ore_type)
	EventBus.market_event.emit(ore_type, old_price, new_price, message)

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
