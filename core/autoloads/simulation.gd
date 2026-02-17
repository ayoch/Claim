extends Node

var game_speed: float = 5.0  # Fast fixed speed for testing

var _tick_accumulator: float = 0.0
const TICK_INTERVAL: float = 1.0  # 1 second per tick at 1x speed
var _payroll_accumulator: float = 0.0
const PAYROLL_INTERVAL: float = 60.0  # pay wages every 60 ticks
var _survey_accumulator: float = 0.0
const SURVEY_INTERVAL: float = 120.0  # check for survey events every 120 ticks

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
	EventBus.tick.emit(dt)
	_process_missions(dt)
	_process_payroll(dt)
	_process_survey_events(dt)

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
