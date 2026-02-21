extends Node

## AI Corporation — plays the game autonomously.
## Toggle with 5 key. Cranks speed to max, makes decisions every game-day.
## Future basis for AI competitor corps in multiplayer.

var enabled: bool = false

# Accumulators
var day_accumulator: float = 0.0
const DAY_TICKS: float = 86400.0
var overlay_timer: float = 0.0

# Stats — missions & trade
var elapsed_days: float = 0.0
var error_count: int = 0
var missions_started: int = 0
var missions_completed: int = 0
var deploy_missions_started: int = 0
var deploy_missions_completed: int = 0
var collect_missions_started: int = 0
var collect_missions_completed: int = 0
var trade_missions_started: int = 0
var trade_missions_completed: int = 0

# Stats — contracts
var contracts_accepted: int = 0
var contracts_completed: int = 0
var contracts_expired: int = 0
var contracts_failed: int = 0

# Stats — fleet
var ships_bought: int = 0
var breakdowns_count: int = 0
var rescues_started: int = 0
var stranger_rescues: int = 0
var ships_destroyed: int = 0
var life_support_warnings: int = 0
var food_depletions: int = 0

# Stats — workers
var workers_hired: int = 0
var rides_given: int = 0
var waiting_count: int = 0
var tardies_count: int = 0
var forgiven_count: int = 0
var docked_count: int = 0
var fired_count: int = 0
var quit_count: int = 0
var worker_level_ups: int = 0
var worker_injuries: int = 0

# Stats — gear
var equipment_bought: int = 0
var upgrades_bought: int = 0
var supplies_bought: int = 0

# Stats — market
var market_events_seen: int = 0

# Stats — mission extras
var missions_redirected: int = 0
var missions_queued: int = 0

# Stats — mining units
var units_broken: int = 0
var stockpile_collects: int = 0
var stockpile_tons_collected: float = 0.0

# UI
var overlay_label: Label = null

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_create_overlay()

	# Worker signals
	EventBus.worker_waiting_for_ride.connect(func(_w: Worker, _l: String) -> void: waiting_count += 1)
	EventBus.worker_hitched_ride.connect(func(_w: Worker, _s: Ship) -> void: rides_given += 1)
	EventBus.worker_tardy.connect(func(_w: Worker, _r: String) -> void: tardies_count += 1)
	EventBus.worker_tardiness_resolved.connect(_on_tardiness_resolved)
	EventBus.worker_fired.connect(func(w: Worker) -> void:
		if w.loyalty <= 0.0: quit_count += 1
	)
	EventBus.worker_skill_leveled.connect(func(_w: Worker, _skill: int, _val: float) -> void: worker_level_ups += 1)
	EventBus.worker_injured.connect(func(_w: Worker) -> void: worker_injuries += 1)

	# Mission signals
	EventBus.mission_started.connect(_on_mission_started)
	EventBus.mission_completed.connect(_on_mission_completed)
	EventBus.trade_mission_started.connect(func(_m: TradeMission) -> void: trade_missions_started += 1)
	EventBus.trade_mission_completed.connect(func(_m: TradeMission) -> void: trade_missions_completed += 1)

	# Contract signals
	EventBus.contract_accepted.connect(func(_c: Contract) -> void: contracts_accepted += 1)
	EventBus.contract_completed.connect(func(_c: Contract) -> void: contracts_completed += 1)
	EventBus.contract_expired.connect(func(_c: Contract) -> void: contracts_expired += 1)
	EventBus.contract_failed.connect(func(_c: Contract) -> void: contracts_failed += 1)

	# Ship signals
	EventBus.ship_breakdown.connect(func(_s: Ship, _r: String) -> void: breakdowns_count += 1)
	EventBus.ship_derelict.connect(_on_ship_derelict)
	EventBus.ship_destroyed.connect(func(_s: Ship, _b: String) -> void: ships_destroyed += 1)
	EventBus.ship_food_depleted.connect(func(_s: Ship, _w: int) -> void: food_depletions += 1)
	EventBus.rescue_mission_started.connect(func(_s: Ship, _c: int) -> void: rescues_started += 1)
	EventBus.stranger_rescue_offered.connect(_on_stranger_offered)
	EventBus.life_support_warning.connect(func(_s: Ship, _p: float) -> void: life_support_warnings += 1)

	# Market signals
	EventBus.market_event_started.connect(func(_e: MarketEvent) -> void: market_events_seen += 1)

	# Mission redirect signals
	EventBus.mission_redirected.connect(func(_s: Ship, _a: AsteroidData, _c: int) -> void: missions_redirected += 1)

	# Mining unit signals
	EventBus.mining_unit_broken.connect(func(_u: MiningUnit) -> void: units_broken += 1)
	EventBus.stockpile_collected.connect(func(_a: AsteroidData, tons: float) -> void:
		stockpile_collects += 1
		stockpile_tons_collected += tons
	)

	# React to idle ships immediately
	EventBus.ship_idle_at_destination.connect(_on_ship_idle)
	EventBus.ship_idle_at_colony.connect(_on_ship_idle_colony)

	# Tick
	EventBus.tick.connect(_on_tick)

func _create_overlay() -> void:
	overlay_label = Label.new()
	overlay_label.name = "TestHarnessOverlay"
	overlay_label.anchor_left = 0.0
	overlay_label.anchor_top = 0.0
	overlay_label.offset_left = 8.0
	overlay_label.offset_top = 8.0
	overlay_label.add_theme_font_size_override("font_size", 11)
	overlay_label.add_theme_color_override("font_color", Color.YELLOW)
	overlay_label.z_index = 4096
	overlay_label.visible = false
	call_deferred("_add_overlay")

func _add_overlay() -> void:
	get_tree().root.add_child.call_deferred(overlay_label)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_5:
		_toggle()
		get_viewport().set_input_as_handled()

func _toggle() -> void:
	enabled = !enabled
	overlay_label.visible = false
	if enabled:
		GameState.settings["auto_sell_at_markets"] = true
		TimeScale.set_speed(TimeScale.SPEED_MAX)
		print("AUTOTEST: ENABLED — AI corp active at max speed")
	else:
		GameState.settings["auto_sell_at_markets"] = false
		TimeScale.set_speed(1.0)
		print("AUTOTEST: DISABLED — AI corp inactive, speed reset to 1x")

# ========== Mission signal handlers ==========

func _on_mission_started(m: Mission) -> void:
	missions_started += 1
	match m.mission_type:
		Mission.MissionType.DEPLOY_UNIT: deploy_missions_started += 1
		Mission.MissionType.COLLECT_ORE: collect_missions_started += 1

func _on_mission_completed(m: Mission) -> void:
	missions_completed += 1
	match m.mission_type:
		Mission.MissionType.DEPLOY_UNIT: deploy_missions_completed += 1
		Mission.MissionType.COLLECT_ORE: collect_missions_completed += 1

# ========== Tick ==========

var _validate_accumulator: float = 0.0
const VALIDATE_INTERVAL: float = 43200.0  # Every half game-day

func _on_tick(delta_ticks: float) -> void:
	if not enabled:
		return
	day_accumulator += delta_ticks
	elapsed_days += delta_ticks / DAY_TICKS
	_validate_accumulator += delta_ticks
	if _validate_accumulator >= VALIDATE_INTERVAL:
		_validate_accumulator -= VALIDATE_INTERVAL
		_validate_state()
	if day_accumulator >= DAY_TICKS:
		day_accumulator -= DAY_TICKS
		_daily_decision_loop()

func _process(delta: float) -> void:
	if not enabled:
		return
	overlay_timer += delta
	if overlay_timer >= 0.5:
		overlay_timer = 0.0
		_update_overlay()

# ========== THE AI BRAIN — runs every game-day ==========

func _daily_decision_loop() -> void:
	# 1. Rescue — save derelict crews before anything else
	_rescue_derelicts()

	# 2. Workforce — always maintain enough crew
	_manage_workforce()

	# 3. Handle discipline immediately (don't let tardies pile up)
	_resolve_all_tardy()

	# 4. Maintenance — repair everything we can before making decisions
	_maintain_fleet()

	# 5. Contracts — accept everything, fulfill what we can
	_manage_contracts()

	# 6. Fleet — the core loop: every ship should be DOING something
	_assign_all_ships()

	# 7. Opportunistic redirects — occasionally send in-transit ships to better targets
	_try_redirect_missions()

	# 8. Queue next missions — pre-plan for ships heading home
	_queue_next_missions()

	# 9. Growth — spend profits to expand
	_manage_growth()

# ---------- 1. Rescue ----------

func _rescue_derelicts() -> void:
	for ship in GameState.ships:
		if ship.is_derelict:
			_try_rescue_ship(ship)

# ---------- 2. Workforce ----------

func _manage_workforce() -> void:
	var total_crew_needed := 0
	for ship in GameState.ships:
		if not ship.is_derelict:
			total_crew_needed += ship.min_crew

	# Operational ships + small buffer
	var target := total_crew_needed + 2
	target = clampi(target, 3, 20)

	# Hire 1 per day if under target (rotate specialties)
	if GameState.workers.size() < target:
		var primary := workers_hired % 3
		var worker := Worker.generate_with_primary(primary)
		GameState.hire_worker(worker)
		workers_hired += 1

	# Fire excess available workers (keep it gentle — 1 per day)
	if GameState.workers.size() > target + 1:
		var available := GameState.get_available_workers()
		if available.size() > 2:
			var worst: Worker = null
			for w in available:
				if worst == null or w.wage > worst.wage:
					worst = w
			if worst:
				GameState.fire_worker(worst)

func _resolve_all_tardy() -> void:
	var snapshot := GameState.tardy_workers.duplicate()
	for entry in snapshot:
		var worker: Worker = entry["worker"]
		var still_tardy := false
		for tw in GameState.tardy_workers:
			if tw["worker"] == worker:
				still_tardy = true
				break
		if not still_tardy:
			continue
		# Smart discipline: keep loyal workers, fine middling, fire disloyal
		if worker.loyalty > 60.0:
			GameState.forgive_tardy_worker(worker)
		elif worker.loyalty > 30.0:
			GameState.dock_pay_tardy_worker(worker)
		else:
			GameState.fire_tardy_worker(worker)

# ---------- 3. Contracts ----------

func _manage_contracts() -> void:
	# Accept all available contracts
	var snapshot := GameState.available_contracts.duplicate()
	for contract in snapshot:
		GameState.accept_contract(contract)

	# Fulfill from Earth stockpile (generic) or deliver to specific colony
	var active := GameState.active_contracts.duplicate()
	for contract in active:
		if contract.status == Contract.Status.ACCEPTED:
			GameState.fulfill_contract(contract)

# ---------- 4. Maintenance — proactive repairs ----------

func _maintain_fleet() -> void:
	for ship in GameState.ships:
		if ship.is_derelict:
			continue

		# Repair engines on docked or stationed-idle ships
		if (ship.is_docked or ship.is_stationed_idle) and ship.engine_condition < 90.0:
			if GameState.money >= ship.get_engine_repair_cost():
				GameState.repair_engine(ship)

		# Repair broken equipment on any ship
		_repair_broken_equipment(ship)

		# Refuel docked ships proactively
		if ship.is_docked:
			_refuel_ship(ship)
			_provision_ship(ship)

		# Recall stationed ships with badly damaged engines for proper repair
		if ship.is_stationed and ship.is_stationed_idle and ship.engine_condition < 40.0:
			GameState.unstation_ship(ship)
			GameState.order_return_to_earth(ship)

# ---------- 5. Fleet — keep every ship busy ----------

func _assign_all_ships() -> void:
	for ship in GameState.ships:
		if ship.is_derelict:
			continue
		if ship.is_stationed:
			continue  # Autonomous
		if ship.current_mission != null and not ship.is_idle_remote:
			continue  # Already on a job
		if ship.current_trade_mission != null and not ship.is_idle_remote:
			continue  # Already trading

		if ship.is_docked:
			_send_docked_ship(ship)
		elif ship.is_idle_remote:
			_handle_idle_remote(ship)

func _refuel_ship(ship: Ship) -> void:
	var fuel_needed := ship.get_effective_fuel_capacity() - ship.fuel
	if fuel_needed <= 0.0:
		return
	var cost := int(fuel_needed * Ship.FUEL_COST_PER_UNIT)
	if GameState.money >= cost:
		ship.fuel = ship.get_effective_fuel_capacity()
		GameState.money -= cost

func _provision_ship(ship: Ship) -> void:
	const DAYS_BUFFER := 30.0
	const KG_PER_WORKER_PER_DAY := 2.8
	const KG_PER_FOOD_UNIT := 100.0

	var crew_size := ship.last_crew.size() if ship.last_crew.size() > 0 else ship.min_crew
	var target_food_units := (crew_size * DAYS_BUFFER * KG_PER_WORKER_PER_DAY) / KG_PER_FOOD_UNIT
	var current_food: float = ship.supplies.get("food", 0.0)

	if current_food >= target_food_units:
		return

	var amount_needed := target_food_units - current_food
	if GameState.buy_supplies(ship, "food", amount_needed):
		supplies_bought += 1

func _repair_broken_equipment(ship: Ship) -> void:
	for equip in ship.equipment:
		if not equip.is_functional() and equip.durability <= 0.0:
			if GameState.money >= equip.repair_cost():
				GameState.repair_equipment(ship, equip)

func _send_docked_ship(ship: Ship) -> void:
	var desperate := GameState.money < 500_000

	# Repair damaged engines before sending out
	if ship.engine_condition < 70.0:
		if GameState.money >= ship.get_engine_repair_cost():
			GameState.repair_engine(ship)
		elif not desperate or ship.engine_condition < 25.0:
			return

	_repair_broken_equipment(ship)
	_refuel_ship(ship)

	if ship.fuel < ship.get_effective_fuel_capacity() * 0.5:
		if not desperate or ship.fuel < ship.get_effective_fuel_capacity() * 0.25:
			return

	var available := GameState.get_available_workers()
	if available.size() < ship.min_crew:
		return

	var crew: Array[Worker] = []
	for i in range(ship.min_crew):
		crew.append(available[i])

	# Priority 1: deploy mining units if we have inventory and enough workers
	if not GameState.mining_unit_inventory.is_empty() and GameState.money > 1_000_000:
		if _try_deploy_units(ship, crew, available):
			return

	# Priority 2: collect ore from stockpiles
	var best_collect_asteroid: AsteroidData = _find_best_stockpile_asteroid(ship)
	if best_collect_asteroid != null:
		GameState.start_collect_mission(ship, best_collect_asteroid, crew)
		missions_started += 1
		ship.last_crew = crew.duplicate()
		return

	# Priority 3: trade stockpile, or mine
	var stockpile_tons := _get_stockpile_tons()
	if stockpile_tons > 1.0 and not GameState.colonies.is_empty():
		_send_trade_mission(ship, crew)
	elif ship.get_cargo_remaining() > ship.get_effective_cargo_capacity() * 0.1:
		_send_mining_mission(ship, crew)
	else:
		if not GameState.colonies.is_empty():
			_send_trade_mission(ship, crew)
		else:
			_send_mining_mission(ship, crew)

func _find_best_stockpile_asteroid(ship: Ship) -> AsteroidData:
	var best: AsteroidData = null
	var best_tons := 0.0
	for asteroid_name in GameState.ore_stockpiles:
		var pile: Dictionary = GameState.ore_stockpiles[asteroid_name]
		var pile_total := 0.0
		for _ot in pile:
			pile_total += pile[_ot]
		if pile_total > best_tons and pile_total > 10.0 and ship.get_cargo_remaining() > 10.0:
			best_tons = pile_total
			for a in GameState.asteroids:
				if a.asteroid_name == asteroid_name:
					best = a
					break
	return best

func _try_deploy_units(ship: Ship, crew: Array[Worker], available: Array[Worker]) -> bool:
	var asteroid := _pick_good_asteroid()
	if asteroid == null:
		return false
	var slots_avail := asteroid.get_max_mining_slots() - GameState.get_occupied_slots(asteroid.asteroid_name)
	if slots_avail <= 0:
		return false

	var units_to_deploy: Array[MiningUnit] = []
	var total_mass := 0.0
	var total_volume := 0.0
	var total_workers_needed := 0
	var max_cargo_mass := ship.get_effective_cargo_capacity() - ship.get_cargo_total()
	var max_cargo_volume := ship.get_effective_cargo_volume()
	var workers_spare := available.size() - ship.min_crew

	for unit in GameState.mining_unit_inventory:
		if units_to_deploy.size() >= slots_avail:
			break
		if total_mass + unit.mass > max_cargo_mass:
			break
		if total_volume + unit.volume > max_cargo_volume:
			break
		if total_workers_needed + unit.workers_required > workers_spare:
			break
		units_to_deploy.append(unit)
		total_mass += unit.mass
		total_volume += unit.volume
		total_workers_needed += unit.workers_required

	if units_to_deploy.is_empty():
		return false

	var deploy_workers: Array[Worker] = []
	for w in available:
		if w in crew:
			continue
		if deploy_workers.size() >= total_workers_needed:
			break
		deploy_workers.append(w)

	if deploy_workers.size() < total_workers_needed:
		return false

	_refuel_ship(ship)
	GameState.start_deploy_mission(ship, asteroid, crew, units_to_deploy, deploy_workers)
	ship.last_crew = crew.duplicate()
	return true

func _send_mining_mission(ship: Ship, crew: Array[Worker]) -> void:
	var asteroid: AsteroidData = _pick_good_asteroid()
	if asteroid == null:
		return
	GameState.start_mission(ship, asteroid, crew)

func _send_trade_mission(ship: Ship, crew: Array[Worker]) -> void:
	if GameState.colonies.is_empty():
		return
	var colony: Colony = GameState.colonies[randi() % GameState.colonies.size()]
	var cargo_to_load: Dictionary = {}
	var remaining: float = ship.get_effective_cargo_capacity()
	for ore_type in GameState.resources:
		var amount: float = float(GameState.resources[ore_type])
		if amount <= 0.0:
			continue
		var load_amt: float = minf(amount, remaining)
		if load_amt > 0.0:
			cargo_to_load[ore_type] = load_amt
			remaining -= load_amt
		if remaining <= 0.0:
			break
	if cargo_to_load.is_empty():
		_send_mining_mission(ship, crew)
		return
	GameState.start_trade_mission(ship, colony, crew, cargo_to_load)

func _handle_idle_remote(ship: Ship) -> void:
	# Damaged or low fuel — head home for repair/refuel
	if ship.engine_condition < 50.0 or ship.fuel < ship.fuel_capacity * 0.2:
		GameState.order_return_to_earth(ship)
		return

	# Deploy missions: ship just unloaded units, return empty
	if ship.current_mission != null and ship.current_mission.mission_type == Mission.MissionType.DEPLOY_UNIT:
		GameState.order_return_to_earth(ship)
		return

	# If ship has cargo, check for a nearby colony to sell at directly
	if ship.get_cargo_total() > 0.1:
		var nearby_colony := _find_nearby_colony(ship.position_au, 1.5)
		if nearby_colony != null and not GameState.colonies.is_empty():
			# Trade from here instead of hauling all the way home
			var cargo_to_load: Dictionary = {}
			for ore_type in ship.current_cargo:
				var amount: float = float(ship.current_cargo[ore_type])
				if amount > 0.0:
					cargo_to_load[ore_type] = amount
			if not cargo_to_load.is_empty():
				var avail := GameState.get_available_workers()
				var crew: Array[Worker] = []
				for i in range(mini(ship.min_crew, avail.size())):
					crew.append(avail[i])
				if crew.size() >= ship.min_crew or ship.min_crew == 0:
					GameState.dispatch_idle_ship_trade(ship, nearby_colony, crew, cargo_to_load)
					return
		GameState.order_return_to_earth(ship)
		return

	# Check for ore to collect at current or nearby location
	var idle_asteroid: AsteroidData = null
	if ship.current_mission != null and ship.current_mission.asteroid != null:
		idle_asteroid = ship.current_mission.asteroid
	if idle_asteroid != null:
		var pile := GameState.get_ore_stockpile(idle_asteroid.asteroid_name)
		var pile_tons := 0.0
		for _ot in pile:
			pile_tons += pile[_ot]
		if pile_tons > 10.0 and ship.get_cargo_remaining() > 10.0:
			var available := GameState.get_available_workers()
			if available.size() >= ship.min_crew:
				var crew: Array[Worker] = []
				for i in range(ship.min_crew):
					crew.append(available[i])
				GameState.start_collect_mission(ship, idle_asteroid, crew)
				return

	# If we have available crew, send to a new asteroid from here
	var available := GameState.get_available_workers()
	if available.size() >= ship.min_crew:
		var crew: Array[Worker] = []
		for i in range(ship.min_crew):
			crew.append(available[i])
		var asteroid: AsteroidData = _pick_good_asteroid()
		if asteroid:
			GameState.dispatch_idle_ship(ship, asteroid, crew)
			return

	# No crew and no cargo — head home
	GameState.order_return_to_earth(ship)

func _try_redirect_missions() -> void:
	# Redirect ships mid-flight to exercise the redirect mechanic
	if GameState.money < 1_000_000:
		return  # Don't waste money on redirects when tight

	# Redirect mining missions
	for ship in GameState.ships:
		if ship.current_mission == null:
			continue
		var m := ship.current_mission
		if m.mission_type != Mission.MissionType.MINING:
			continue
		if m.status != Mission.Status.TRANSIT_OUT:
			continue
		if randf() > 0.3:  # 30% chance (increased from 15%)
			continue
		var better := _pick_good_asteroid()
		if better == null or better == m.asteroid:
			continue
		GameState.redirect_mission(m, better)

	# Redirect trade missions to different colonies
	for ship in GameState.ships:
		if ship.current_trade_mission == null or GameState.colonies.size() < 2:
			continue
		var tm := ship.current_trade_mission
		if tm.status != TradeMission.Status.TRANSIT_TO_COLONY:
			continue
		if randf() > 0.2:  # 20% chance
			continue
		var other_colonies := GameState.colonies.filter(func(c): return c != tm.colony)
		if other_colonies.is_empty():
			continue
		var new_colony: Colony = other_colonies[randi() % other_colonies.size()]
		GameState.redirect_trade_mission(tm, new_colony)

func _queue_next_missions() -> void:
	# Pre-queue next missions for ships to keep them continuously working
	for ship in GameState.ships:
		if ship.is_derelict or ship.is_stationed:
			continue
		if ship.has_queued_mission():
			continue  # Already planned

		# Queue for ships returning from mining
		if ship.current_mission != null:
			var m := ship.current_mission
			if m.mission_type == Mission.MissionType.MINING and m.status == Mission.Status.TRANSIT_BACK:
				var next_asteroid := _pick_good_asteroid()
				if next_asteroid != null:
					var crew := ship.last_crew.duplicate() if not ship.last_crew.is_empty() else _get_crew_for_ship(ship)
					if crew.size() >= ship.min_crew:
						ship.queue_mission(next_asteroid, crew, Mission.TransitMode.BRACHISTOCHRONE)
						missions_queued += 1

		# Queue for ships idle at remote destinations
		elif ship.is_idle_remote:
			if randf() < 0.5:  # 50% chance to queue instead of immediate dispatch
				var next_asteroid := _pick_good_asteroid()
				if next_asteroid != null:
					var crew := _get_crew_for_ship(ship)
					if crew.size() >= ship.min_crew:
						ship.queue_mission(next_asteroid, crew, Mission.TransitMode.BRACHISTOCHRONE)
						missions_queued += 1

func _get_crew_for_ship(ship: Ship) -> Array[Worker]:
	var crew: Array[Worker] = []
	if not ship.last_crew.is_empty():
		crew = ship.last_crew.duplicate()
	else:
		var avail := GameState.get_available_workers()
		for i in range(mini(ship.min_crew, avail.size())):
			crew.append(avail[i])
	return crew

func _pick_good_asteroid() -> AsteroidData:
	if GameState.asteroids.is_empty():
		return null
	var pool_size := mini(30, GameState.asteroids.size())
	var best: AsteroidData = null
	var best_score := -1.0
	for i in range(pool_size):
		var a: AsteroidData = GameState.asteroids[i]
		var score := 0.0
		for ore_type in a.ore_yields:
			score += float(a.ore_yields[ore_type]) * MarketData.get_ore_price(ore_type)
		score /= maxf(a.orbit_au, 0.5)
		score *= randf_range(0.5, 1.5)
		if score > best_score:
			best_score = score
			best = a
	return best

func _find_nearby_colony(pos: Vector2, max_dist_au: float) -> Colony:
	var best: Colony = null
	var best_dist := max_dist_au
	for colony in GameState.colonies:
		var d := pos.distance_to(colony.get_position_au())
		if d < best_dist:
			best_dist = d
			best = colony
	return best

func _get_stockpile_tons() -> float:
	var total := 0.0
	for ore_type in GameState.resources:
		total += float(GameState.resources[ore_type])
	return total

# ---------- 6. Growth ----------

func _manage_growth() -> void:
	var money: int = GameState.money
	var num_ships := GameState.ships.size()
	var operational := 0
	for s in GameState.ships:
		if not s.is_derelict:
			operational += 1

	# Install any fabricated equipment or purchased upgrades first (free actions)
	_install_available_gear()

	# Emergency: buy a ship if we have zero operational and can afford one
	if operational == 0 and money > 800_000:
		if GameState.purchase_ship(ShipData.ShipClass.PROSPECTOR):
			ships_bought += 1
	elif num_ships < 4 and money > 15_000_000:
		var ship_class := _pick_ship_class()
		if GameState.purchase_ship(ship_class):
			ships_bought += 1

	# Equipment: only when flush and ships need it
	if money > 5_000_000:
		_buy_needed_equipment()

	# Upgrades: luxury purchase
	if money > 10_000_000:
		_buy_and_install_upgrades()

	# Supplies: cheap, always worth it
	if money > 500_000:
		_buy_supplies_for_docked()

	# Mining units: buy and deploy when profitable
	if money > 2_000_000:
		_manage_mining_units()

	# Station a ship once fleet is established and profitable
	if GameState.ships.size() >= 3 and money > 5_000_000:
		_consider_stationing()

func _pick_ship_class() -> int:
	var counts := {}
	for ship in GameState.ships:
		counts[ship.ship_class] = counts.get(ship.ship_class, 0) + 1
	if counts.get(ShipData.ShipClass.HAULER, 0) < 2:
		return ShipData.ShipClass.HAULER
	if counts.get(ShipData.ShipClass.PROSPECTOR, 0) < 2:
		return ShipData.ShipClass.PROSPECTOR
	if counts.get(ShipData.ShipClass.EXPLORER, 0) < 1:
		return ShipData.ShipClass.EXPLORER
	return ShipData.ShipClass.HAULER

func _install_available_gear() -> void:
	var docked := GameState.get_docked_ships()
	for ship in docked:
		if ship.equipment.size() >= ship.max_equipment_slots:
			continue
		if GameState.equipment_inventory.is_empty():
			break
		GameState.install_equipment(ship, GameState.equipment_inventory[0])
	for ship in docked:
		if GameState.upgrade_inventory.is_empty():
			break
		GameState.install_upgrade(ship, GameState.upgrade_inventory[0])

func _buy_needed_equipment() -> void:
	if not GameState.fabrication_queue.is_empty() or not GameState.equipment_inventory.is_empty():
		return
	for ship in GameState.ships:
		if ship.equipment.size() < ship.max_equipment_slots:
			var catalog: Array[Dictionary] = MarketData.EQUIPMENT_CATALOG
			if not catalog.is_empty():
				var best: Dictionary = {}
				for entry in catalog:
					if int(entry["cost"]) <= GameState.money:
						if best.is_empty() or float(entry["mining_bonus"]) > float(best["mining_bonus"]):
							best = entry
				if not best.is_empty():
					if GameState.purchase_equipment(best):
						equipment_bought += 1
			return

func _buy_and_install_upgrades() -> void:
	if not GameState.upgrade_inventory.is_empty():
		return
	var catalog := UpgradeCatalog.get_available_upgrades()
	if not catalog.is_empty():
		var affordable: Array[Dictionary] = []
		for entry in catalog:
			if int(entry["cost"]) <= GameState.money:
				affordable.append(entry)
		if not affordable.is_empty():
			if GameState.purchase_upgrade(affordable[randi() % affordable.size()]):
				upgrades_bought += 1

func _buy_supplies_for_docked() -> void:
	# Note: Food is now handled in maintenance phase via _provision_ship
	var docked := GameState.get_docked_ships()
	for ship in docked:
		var parts: float = float(ship.supplies.get("repair_parts", 0.0))
		if parts < 3.0:
			if GameState.buy_supplies(ship, "repair_parts", 5.0):
				supplies_bought += 1
		var fuel_cells: float = float(ship.supplies.get("fuel_cells", 0.0))
		if fuel_cells < 2.0:
			if GameState.buy_supplies(ship, "fuel_cells", 5.0):
				supplies_bought += 1

func _consider_stationing() -> void:
	if GameState.colonies.is_empty():
		return
	var any_stationed := false
	for ship in GameState.ships:
		if ship.is_stationed:
			any_stationed = true
			break
	if any_stationed:
		return
	var docked := GameState.get_docked_ships()
	if docked.is_empty():
		return
	var colony: Colony = GameState.colonies[randi() % GameState.colonies.size()]
	GameState.station_ship(docked[0], colony, ["mining", "trading"])

func _manage_mining_units() -> void:
	# Repair worn units
	for unit in GameState.deployed_mining_units:
		if unit.durability < 40.0 and GameState.money > unit.repair_cost():
			GameState.repair_mining_unit(unit)

	# Recall units that need rebuild or are broken
	var to_recall: Array[MiningUnit] = []
	for unit in GameState.deployed_mining_units:
		if not unit.is_functional() or unit.needs_rebuild():
			to_recall.append(unit)
	for unit in to_recall:
		GameState.recall_mining_unit(unit)

	# Rebuild recalled units
	for unit in GameState.mining_unit_inventory:
		if unit.max_durability < 100.0 and GameState.money > unit.rebuild_cost():
			GameState.rebuild_mining_unit(unit)

	# Buy a mining unit if fleet is small
	var total_units := GameState.mining_unit_inventory.size() + GameState.deployed_mining_units.size()
	if total_units < 3 and GameState.money > 2_000_000:
		var catalog := MiningUnitCatalog.get_available_units()
		if not catalog.is_empty():
			var entry := catalog[mini(total_units, catalog.size() - 1)]
			GameState.purchase_mining_unit(entry)

	# Deploy from docked ships is handled by _send_docked_ship via _try_deploy_units

# ========== Reactive signal handlers ==========

func _on_ship_derelict(ship: Ship) -> void:
	if not enabled:
		return
	_try_rescue_ship(ship)

func _try_rescue_ship(ship: Ship) -> bool:
	if not ship.is_derelict:
		return false
	if ship in GameState.rescue_missions or ship in GameState.refuel_missions:
		return false

	if ship.derelict_reason == "out_of_fuel":
		var fuel_amount := ship.get_effective_fuel_capacity() * 0.5
		if GameState.start_refuel(ship, fuel_amount):
			rescues_started += 1
			return true

	var info: Dictionary = GameState.calculate_rescue_info(ship)
	if info["feasible"] and GameState.money >= int(info["cost"]):
		if GameState.start_rescue(ship):
			rescues_started += 1
			return true
	return false

func _on_stranger_offered(ship: Ship, _stranger_name: String) -> void:
	if not enabled:
		return
	GameState.accept_stranger_rescue(ship, true)
	stranger_rescues += 1

func _on_ship_idle(ship: Ship, _mission: Mission) -> void:
	if not enabled:
		return
	_handle_idle_remote(ship)

func _on_ship_idle_colony(ship: Ship, _trade_mission: TradeMission) -> void:
	if not enabled:
		return
	GameState.order_return_to_earth(ship)

func _on_tardiness_resolved(_worker: Worker, action: String) -> void:
	match action:
		"forgiven": forgiven_count += 1
		"docked": docked_count += 1
		"fired": fired_count += 1

# ========== State validation ==========

func _validate_state() -> void:
	_validate_workers()
	_validate_ships()
	_validate_missions()
	_validate_mining_units()
	_validate_stockpiles()
	_validate_contracts()

func _validate_workers() -> void:
	for worker in GameState.workers:
		if worker.leave_status != 0 and worker.assigned_mission != null:
			_error("Worker '%s' leave_status=%d but assigned_mission set" % [worker.worker_name, worker.leave_status])
		if worker.leave_status == 2:
			var found := false
			for entry in GameState.hitchhike_pool:
				if entry["worker"] == worker:
					found = true
					break
			if not found:
				_error("Worker '%s' leave_status=2 but NOT in hitchhike_pool" % worker.worker_name)
		if worker.leave_status == 3:
			var found := false
			for entry in GameState.tardy_workers:
				if entry["worker"] == worker:
					found = true
					break
			if not found:
				_error("Worker '%s' leave_status=3 but NOT in tardy_workers" % worker.worker_name)
		if worker.loyalty < 0.0 or worker.loyalty > 100.0:
			_error("Worker '%s' loyalty=%.1f out of range [0,100]" % [worker.worker_name, worker.loyalty])
		if worker.fatigue < 0.0 or worker.fatigue > 100.0:
			_error("Worker '%s' fatigue=%.1f out of range [0,100]" % [worker.worker_name, worker.fatigue])
		for skill_val in [worker.pilot_skill, worker.engineer_skill, worker.mining_skill]:
			if skill_val < 0.0 or skill_val > 2.0:
				_error("Worker '%s' has skill=%.2f out of expected range [0, 2.0]" % [worker.worker_name, skill_val])
		if worker.assigned_mission != null and worker.assigned_mission not in GameState.missions:
			_error("Worker '%s' assigned_mission not in GameState.missions" % worker.worker_name)

	for entry in GameState.hitchhike_pool:
		if entry["worker"] not in GameState.workers:
			_error("Hitchhike pool orphan: '%s'" % entry["worker"].worker_name)

	for entry in GameState.tardy_workers:
		if entry["worker"] not in GameState.workers:
			_error("Tardy list orphan: '%s'" % entry["worker"].worker_name)

func _validate_ships() -> void:
	for ship in GameState.ships:
		if ship.fuel < -0.01:
			_error("Ship '%s' negative fuel=%.2f" % [ship.ship_name, ship.fuel])
		if ship.fuel > ship.get_effective_fuel_capacity() + 0.1:
			_error("Ship '%s' fuel=%.1f exceeds capacity=%.1f" % [ship.ship_name, ship.fuel, ship.get_effective_fuel_capacity()])
		if ship.engine_condition < -0.01 or ship.engine_condition > 100.01:
			_error("Ship '%s' engine_condition=%.1f out of range [0,100]" % [ship.ship_name, ship.engine_condition])
		if ship.is_stationed and ship.station_colony == null:
			_error("Ship '%s' stationed but colony is null" % ship.ship_name)
		if ship.current_mission != null and ship.current_trade_mission != null:
			_error("Ship '%s' has BOTH current_mission and current_trade_mission" % ship.ship_name)
		# Cargo mass shouldn't exceed capacity (allow 1% tolerance for rounding)
		var cargo := ship.get_cargo_total()
		var cap := ship.get_effective_cargo_capacity()
		if cargo > cap * 1.01 + 0.1:
			_error("Ship '%s' cargo=%.1ft exceeds capacity=%.1ft" % [ship.ship_name, cargo, cap])
		# Volume check for active deploy missions
		if ship.current_mission != null and ship.current_mission.mission_type == Mission.MissionType.DEPLOY_UNIT:
			var vol_used := ship.get_cargo_volume_used()
			var vol_cap := ship.get_effective_cargo_volume()
			if vol_used > vol_cap * 1.01 + 0.1:
				_error("Ship '%s' cargo volume=%.1fm³ exceeds capacity=%.1fm³" % [ship.ship_name, vol_used, vol_cap])

func _validate_missions() -> void:
	for mission in GameState.missions:
		if mission.ship == null:
			_error("Mission with null ship (status=%d type=%d)" % [mission.status, mission.mission_type])
			continue
		if mission.ship not in GameState.ships:
			_error("Mission ship '%s' not in GameState.ships" % mission.ship.ship_name)
		# Workers in mission should have this as their assigned_mission
		for w in mission.workers:
			if w.assigned_mission != mission and w.assigned_mission != null:
				_error("Mission worker '%s' assigned_mission mismatch" % w.worker_name)
		# Deploy missions: units being transported should still be in inventory (not deployed)
		if mission.mission_type == Mission.MissionType.DEPLOY_UNIT and mission.status == Mission.Status.TRANSIT_OUT:
			for unit in mission.mining_units_to_deploy:
				if unit not in GameState.mining_unit_inventory:
					_error("Deploy mission transporting unit '%s' not in inventory" % unit.unit_name)

	for tm in GameState.trade_missions:
		if tm.ship == null:
			_error("TradeMission with null ship (status=%d)" % tm.status)
		elif tm.ship not in GameState.ships:
			_error("TradeMission ship '%s' not in GameState.ships" % tm.ship.ship_name)

func _validate_mining_units() -> void:
	for unit in GameState.deployed_mining_units:
		if unit.deployed_at_asteroid == "":
			_error("Deployed mining unit '%s' has empty asteroid name" % unit.unit_name)
		if unit.durability < -0.01:
			_error("Mining unit '%s' negative durability=%.1f" % [unit.unit_name, unit.durability])
		if unit.max_durability < -0.01 or unit.max_durability > 100.01:
			_error("Mining unit '%s' max_durability=%.1f out of range [0,100]" % [unit.unit_name, unit.max_durability])
		for w in unit.assigned_workers:
			if w not in GameState.workers:
				_error("Mining unit '%s' has orphan worker '%s'" % [unit.unit_name, w.worker_name])
		# A deployed unit must not also appear in inventory
		if unit in GameState.mining_unit_inventory:
			_error("Mining unit '%s' is in BOTH deployed_mining_units AND inventory" % unit.unit_name)

	for unit in GameState.mining_unit_inventory:
		if unit.durability < -0.01:
			_error("Inventory mining unit '%s' negative durability=%.1f" % [unit.unit_name, unit.durability])

func _validate_stockpiles() -> void:
	for asteroid_name in GameState.ore_stockpiles:
		var pile: Dictionary = GameState.ore_stockpiles[asteroid_name]
		for ore_type in pile:
			var amount: float = float(pile[ore_type])
			if amount < -0.01:
				_error("Stockpile '%s' ore_type=%d negative amount=%.2f" % [asteroid_name, ore_type, amount])

func _validate_contracts() -> void:
	for contract in GameState.active_contracts:
		if contract.quantity_delivered < -0.01:
			_error("Contract quantity_delivered=%.2f is negative" % contract.quantity_delivered)
		if contract.quantity_delivered > contract.quantity + 0.01:
			_error("Contract delivered=%.1f exceeds required=%.1f" % [contract.quantity_delivered, contract.quantity])
		if contract.deadline_ticks < -86400.0:
			_error("Contract deadline=%.0f severely overdue without expiry" % contract.deadline_ticks)

func _error(msg: String) -> void:
	error_count += 1
	printerr("ERROR: [AUTOTEST] %s" % msg)

# ========== Overlay ==========

func _update_overlay() -> void:
	var on_leave := 0
	var waiting := 0
	var tardy := 0
	var ships_active := 0
	var ships_idle := 0
	for w in GameState.workers:
		match w.leave_status:
			1: on_leave += 1
			2: waiting += 1
			3: tardy += 1
	for s in GameState.ships:
		if s.is_derelict:
			continue
		if s.current_mission != null or s.current_trade_mission != null:
			if not s.is_idle_remote:
				ships_active += 1
			else:
				ships_idle += 1
		elif s.is_stationed:
			ships_active += 1
		elif s.is_docked:
			ships_idle += 1

	var stockpile_total := 0.0
	for ore_type in GameState.resources:
		stockpile_total += float(GameState.resources[ore_type])
	var deployed_stockpile := 0.0
	for _an in GameState.ore_stockpiles:
		for _ot in GameState.ore_stockpiles[_an]:
			deployed_stockpile += float(GameState.ore_stockpiles[_an][_ot])

	var money_m := "%.1fM" % (GameState.money / 1_000_000.0)
	var derelict_count := 0
	for _ds in GameState.ships:
		if _ds.is_derelict:
			derelict_count += 1

	overlay_label.text = (
		"AI CORP | %dd | $%s | Err: %d\n" % [int(elapsed_days), money_m, error_count]
		+ "Ships: %d (act %d idle %d derl %d) | Workers: %d (avail %d)\n" % [
			GameState.ships.size(), ships_active, ships_idle, derelict_count,
			GameState.workers.size(), GameState.get_available_workers().size()]
		+ "Mine: %d/%d | Trade: %d/%d | Deploy: %d/%d | Collect: %d/%d\n" % [
			missions_completed, missions_started,
			trade_missions_completed, trade_missions_started,
			deploy_missions_completed, deploy_missions_started,
			collect_missions_completed, collect_missions_started]
		+ "Redirected: %d | Queued: %d | Market Events: %d\n" % [missions_redirected, missions_queued, market_events_seen]
		+ "Contracts: %d done / %d acc / %d exp / %d fail\n" % [contracts_completed, contracts_accepted, contracts_expired, contracts_failed]
		+ "Leave: %d | Wait: %d | Tardy: %d | Rides: %d | LvlUps: %d | Inj: %d\n" % [on_leave, waiting, tardy, rides_given, worker_level_ups, worker_injuries]
		+ "Bkdn: %d | Resc: %d | Strgr: %d | Destr: %d | LS: %d | Food: %d\n" % [breakdowns_count, rescues_started, stranger_rescues, ships_destroyed, life_support_warnings, food_depletions]
		+ "Bought: %d ships %d equip %d upgr %d supply\n" % [ships_bought, equipment_bought, upgrades_bought, supplies_bought]
		+ "Units: %d inv %d dep %d broken | Stockpile: %.0ft depot / %.0ft field" % [
			GameState.mining_unit_inventory.size(), GameState.deployed_mining_units.size(),
			units_broken, stockpile_total, deployed_stockpile]
	)
