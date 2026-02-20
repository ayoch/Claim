extends Node

## AI Corporation — plays the game autonomously.
## Toggle with 5 key. Cranks speed to max, makes decisions every game-day.
## Future basis for AI competitor corps in multiplayer.

var enabled: bool = false

# Accumulators
var day_accumulator: float = 0.0
const DAY_TICKS: float = 86400.0
var overlay_timer: float = 0.0

# Stats
var elapsed_days: float = 0.0
var error_count: int = 0
var rides_given: int = 0
var waiting_count: int = 0
var tardies_count: int = 0
var forgiven_count: int = 0
var docked_count: int = 0
var fired_count: int = 0
var quit_count: int = 0
var missions_started: int = 0
var missions_completed: int = 0
var trade_missions_started: int = 0
var trade_missions_completed: int = 0
var contracts_accepted: int = 0
var contracts_completed: int = 0
var ships_bought: int = 0
var workers_hired: int = 0
var equipment_bought: int = 0
var upgrades_bought: int = 0
var rescues_started: int = 0
var breakdowns_count: int = 0
var supplies_bought: int = 0
var stranger_rescues: int = 0

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
	# Mission signals
	EventBus.mission_started.connect(func(_m: Mission) -> void: missions_started += 1)
	EventBus.mission_completed.connect(func(_m: Mission) -> void: missions_completed += 1)
	EventBus.trade_mission_started.connect(func(_m: TradeMission) -> void: trade_missions_started += 1)
	EventBus.trade_mission_completed.connect(func(_m: TradeMission) -> void: trade_missions_completed += 1)
	EventBus.contract_accepted.connect(func(_c: Contract) -> void: contracts_accepted += 1)
	EventBus.contract_completed.connect(func(_c: Contract) -> void: contracts_completed += 1)
	# Ship signals
	EventBus.ship_breakdown.connect(func(_s: Ship, _r: String) -> void: breakdowns_count += 1)
	EventBus.ship_derelict.connect(_on_ship_derelict)
	EventBus.rescue_mission_started.connect(func(_s: Ship, _c: int) -> void: rescues_started += 1)
	EventBus.stranger_rescue_offered.connect(_on_stranger_offered)
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

# ========== Tick ==========

var _validate_accumulator: float = 0.0
const VALIDATE_INTERVAL: float = 43200.0  # Every half game-day, not every tick

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

	# 7. Growth — spend profits to expand
	_manage_growth()

# ---------- 1. Rescue — crew lives are the top priority ----------

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

	# Only hire enough to crew operational ships + small buffer
	var target := total_crew_needed + 2
	target = clampi(target, 3, 20)

	# Hire 1 per day if under target
	if GameState.workers.size() < target:
		var primary := workers_hired % 3
		var worker := Worker.generate_with_primary(primary)
		GameState.hire_worker(worker)
		workers_hired += 1

	# Fire excess available workers to stop wage bleed (1 per day, keep it gentle)
	if GameState.workers.size() > target + 1:
		var available := GameState.get_available_workers()
		if available.size() > 2:
			# Fire the most expensive available worker
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
		# Smart discipline: keep loyal workers, fire disloyal ones
		if worker.loyalty > 60.0:
			GameState.forgive_tardy_worker(worker)
		elif worker.loyalty > 30.0:
			GameState.dock_pay_tardy_worker(worker)
		else:
			GameState.fire_tardy_worker(worker)

# ---------- 2. Contracts ----------

func _manage_contracts() -> void:
	# Accept all available contracts
	var snapshot := GameState.available_contracts.duplicate()
	for contract in snapshot:
		GameState.accept_contract(contract)

	# Fulfill from Earth stockpile
	var active := GameState.active_contracts.duplicate()
	for contract in active:
		if contract.status == Contract.Status.ACCEPTED:
			GameState.fulfill_contract(contract)

# ---------- 3. Maintenance — proactive repairs ----------

func _maintain_fleet() -> void:
	for ship in GameState.ships:
		if ship.is_derelict:
			continue

		# Repair engines on any docked or stationed-idle ship
		if (ship.is_docked or ship.is_stationed_idle) and ship.engine_condition < 90.0:
			if GameState.money >= ship.get_engine_repair_cost():
				GameState.repair_engine(ship)

		# Repair broken equipment on any ship (remote repair costs money but saves the mission)
		_repair_broken_equipment(ship)

		# Refuel docked ships proactively
		if ship.is_docked:
			_refuel_ship(ship)

		# Recall stationed ships with badly damaged engines for proper repair
		if ship.is_stationed and ship.is_stationed_idle and ship.engine_condition < 40.0:
			GameState.unstation_ship(ship)
			GameState.order_return_to_earth(ship)

# ---------- 4. Fleet — keep every ship busy ----------

func _assign_all_ships() -> void:
	for ship in GameState.ships:
		if ship.is_derelict:
			continue  # Handled by signal
		if ship.is_stationed:
			continue  # Autonomous
		if ship.current_mission != null and not ship.is_idle_remote:
			continue  # Already on a job
		if ship.current_trade_mission != null and not ship.is_idle_remote:
			continue  # Already trading

		# Ship needs orders
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

func _repair_broken_equipment(ship: Ship) -> void:
	for equip in ship.equipment:
		if not equip.is_functional() and equip.durability <= 0.0:
			if GameState.money >= equip.repair_cost():
				GameState.repair_equipment(ship, equip)

func _send_docked_ship(ship: Ship) -> void:
	var desperate := GameState.money < 500_000  # Running out of money

	# Repair damaged engines before sending out (if we can afford it)
	if ship.engine_condition < 70.0:
		if GameState.money >= ship.get_engine_repair_cost():
			GameState.repair_engine(ship)
		elif not desperate or ship.engine_condition < 25.0:
			return  # Too damaged even for a desperate run

	# Repair broken equipment before sending out
	_repair_broken_equipment(ship)

	# Refuel before dispatching
	_refuel_ship(ship)

	# Still too low on fuel after refuel attempt (couldn't afford it)
	# Require at least 50% fuel to prevent derelicts (30% was too risky)
	if ship.fuel < ship.get_effective_fuel_capacity() * 0.5:
		if not desperate or ship.fuel < ship.get_effective_fuel_capacity() * 0.25:
			return

	var available := GameState.get_available_workers()
	if available.size() < ship.min_crew:
		return  # Can't crew it yet

	var crew: Array[Worker] = []
	for i in range(ship.min_crew):
		crew.append(available[i])

	# Decision: collect ore, mine, or trade?
	# Check for mining unit stockpiles to collect
	var best_collect_asteroid: AsteroidData = null
	var best_collect_tons := 0.0
	for asteroid_name in GameState.ore_stockpiles:
		var pile: Dictionary = GameState.ore_stockpiles[asteroid_name]
		var pile_total := 0.0
		for ot in pile:
			pile_total += pile[ot]
		if pile_total > best_collect_tons and pile_total > 10.0:
			best_collect_tons = pile_total
			for a in GameState.asteroids:
				if a.asteroid_name == asteroid_name:
					best_collect_asteroid = a
					break

	if best_collect_asteroid != null and ship.get_cargo_remaining() > 10.0:
		# Collect ore from mining claim
		GameState.start_collect_mission(ship, best_collect_asteroid, crew)
		missions_started += 1
		ship.last_crew = crew.duplicate()
		return

	# Trade when we have stockpile to sell — prioritize income
	var stockpile_tons := _get_stockpile_tons()
	if stockpile_tons > 1.0 and not GameState.colonies.is_empty():
		_send_trade_mission(ship, crew)
	elif ship.get_cargo_remaining() > ship.get_effective_cargo_capacity() * 0.1:
		_send_mining_mission(ship, crew)
	else:
		# Hold is full — sell what's on board
		if not GameState.colonies.is_empty():
			_send_trade_mission(ship, crew)
		else:
			_send_mining_mission(ship, crew)  # No colonies, mine anyway

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
		# No ore to trade — mine instead
		_send_mining_mission(ship, crew)
		return
	GameState.start_trade_mission(ship, colony, crew, cargo_to_load)

func _handle_idle_remote(ship: Ship) -> void:
	# Ship is sitting idle at an asteroid or colony — give it new orders

	# Damaged or low fuel — head home for repair/refuel
	if ship.engine_condition < 50.0 or ship.fuel < ship.fuel_capacity * 0.2:
		GameState.order_return_to_earth(ship)
		return

	# If ship has cargo, head home (cargo transfers to stockpile, then next docked ship trades it)
	if ship.get_cargo_total() > 0.1:
		GameState.order_return_to_earth(ship)
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

func _pick_good_asteroid() -> AsteroidData:
	if GameState.asteroids.is_empty():
		return null
	# Score near-Earth asteroids by ore value and pick the best
	var pool_size := mini(30, GameState.asteroids.size())
	var best: AsteroidData = null
	var best_score := -1.0
	for i in range(pool_size):
		var a: AsteroidData = GameState.asteroids[i]
		var score := 0.0
		for ore_type in a.ore_yields:
			score += float(a.ore_yields[ore_type]) * MarketData.get_ore_price(ore_type)
		# Prefer closer asteroids (less fuel/time)
		score /= maxf(a.orbit_au, 0.5)
		# Add randomness so we don't always pick the same one
		score *= randf_range(0.5, 1.5)
		if score > best_score:
			best_score = score
			best = a
	return best

func _get_stockpile_tons() -> float:
	var total := 0.0
	for ore_type in GameState.resources:
		total += float(GameState.resources[ore_type])
	return total

# ---------- 4. Growth ----------

func _manage_growth() -> void:
	var money: int = GameState.money
	var num_ships := GameState.ships.size()
	# Count operational (non-derelict) ships
	var operational := 0
	for s in GameState.ships:
		if not s.is_derelict:
			operational += 1

	# Install any fabricated equipment or purchased upgrades first (free actions)
	_install_available_gear()

	# Emergency: buy a ship if we have zero operational ships and can afford one
	if operational == 0 and money > 800_000:
		if GameState.purchase_ship(ShipData.ShipClass.PROSPECTOR):
			ships_bought += 1
	# Normal growth: expand fleet when flush
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
	# Count existing classes
	var counts := {}
	for ship in GameState.ships:
		counts[ship.ship_class] = counts.get(ship.ship_class, 0) + 1

	# Prioritize: haulers for cargo, prospectors for mining
	if counts.get(ShipData.ShipClass.HAULER, 0) < 2:
		return ShipData.ShipClass.HAULER
	if counts.get(ShipData.ShipClass.PROSPECTOR, 0) < 2:
		return ShipData.ShipClass.PROSPECTOR
	if counts.get(ShipData.ShipClass.EXPLORER, 0) < 1:
		return ShipData.ShipClass.EXPLORER
	return ShipData.ShipClass.HAULER  # Default to more cargo capacity

func _install_available_gear() -> void:
	var docked := GameState.get_docked_ships()
	# Install fabricated equipment
	for ship in docked:
		if ship.equipment.size() >= ship.max_equipment_slots:
			continue
		if GameState.equipment_inventory.is_empty():
			break
		GameState.install_equipment(ship, GameState.equipment_inventory[0])
	# Install purchased upgrades
	for ship in docked:
		if GameState.upgrade_inventory.is_empty():
			break
		GameState.install_upgrade(ship, GameState.upgrade_inventory[0])

func _buy_needed_equipment() -> void:
	if not GameState.fabrication_queue.is_empty() or not GameState.equipment_inventory.is_empty():
		return  # Wait for current order
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
			return  # One purchase per day

func _buy_and_install_upgrades() -> void:
	if not GameState.upgrade_inventory.is_empty():
		return  # Wait for current to be installed
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
	var docked := GameState.get_docked_ships()
	for ship in docked:
		# Stock up repair parts if low
		var parts: float = float(ship.supplies.get("repair_parts", 0.0))
		if parts < 3.0:
			if GameState.buy_supplies(ship, "repair_parts", 5.0):
				supplies_bought += 1
		# Stock up food
		var food: float = float(ship.supplies.get("food", 0.0))
		if food < 5.0:
			if GameState.buy_supplies(ship, "food", 10.0):
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
	# Station a docked ship
	var docked := GameState.get_docked_ships()
	if docked.is_empty():
		return
	var colony: Colony = GameState.colonies[randi() % GameState.colonies.size()]
	GameState.station_ship(docked[0], colony, ["mining", "trading"])

func _manage_mining_units() -> void:
	# Repair worn units (buy parts, crew handles it on-site)
	for unit in GameState.deployed_mining_units:
		if unit.durability < 40.0 and GameState.money > unit.repair_cost():
			GameState.repair_mining_unit(unit)
	# Recall units that need rebuild or are broken beyond repair
	var to_recall: Array[MiningUnit] = []
	for unit in GameState.deployed_mining_units:
		if not unit.is_functional() or unit.needs_rebuild():
			to_recall.append(unit)
	for unit in to_recall:
		GameState.recall_mining_unit(unit)
	# Rebuild recalled units at facility
	for unit in GameState.mining_unit_inventory:
		if unit.max_durability < 100.0 and GameState.money > unit.rebuild_cost():
			GameState.rebuild_mining_unit(unit)

	# Buy a mining unit if we don't have many
	var total_units := GameState.mining_unit_inventory.size() + GameState.deployed_mining_units.size()
	if total_units < 3 and GameState.money > 2_000_000:
		var catalog := MiningUnitCatalog.get_available_units()
		if not catalog.is_empty():
			# Buy basic units first, then advanced
			var entry := catalog[mini(total_units, catalog.size() - 1)]
			if GameState.purchase_mining_unit(entry):
				pass  # Purchased

	# Deploy available units using docked ships
	if GameState.mining_unit_inventory.is_empty():
		return
	var docked := GameState.get_docked_ships()
	if docked.is_empty():
		return
	var ship := docked[0]
	if ship.current_mission != null:
		return
	var available_workers := GameState.get_available_workers()
	if available_workers.size() < ship.min_crew + 1:
		return  # Need crew for ship AND unit workers

	# Pick a good asteroid to deploy at
	var asteroid := _pick_good_asteroid()
	if asteroid == null:
		return
	var slots_avail := asteroid.get_max_mining_slots() - GameState.get_occupied_slots(asteroid.asteroid_name)
	if slots_avail <= 0:
		return

	# Select units that fit
	var units_to_deploy: Array[MiningUnit] = []
	var total_mass := 0.0
	var total_workers_needed := 0
	for unit in GameState.mining_unit_inventory:
		if units_to_deploy.size() >= slots_avail:
			break
		if total_mass + unit.mass > ship.cargo_capacity:
			break
		if total_workers_needed + unit.workers_required > available_workers.size() - ship.min_crew:
			break
		units_to_deploy.append(unit)
		total_mass += unit.mass
		total_workers_needed += unit.workers_required

	if units_to_deploy.is_empty():
		return

	# Select crew and deploy workers
	var crew: Array[Worker] = []
	for i in range(mini(ship.min_crew, available_workers.size())):
		crew.append(available_workers[i])
	var deploy_workers: Array[Worker] = []
	for i in range(available_workers.size()):
		if available_workers[i] in crew:
			continue
		if deploy_workers.size() >= total_workers_needed:
			break
		deploy_workers.append(available_workers[i])

	if deploy_workers.size() < total_workers_needed:
		return

	# Auto-refuel
	if GameState.settings.get("auto_refuel", true):
		ship.fuel = ship.fuel_capacity

	GameState.start_deploy_mission(ship, asteroid, crew, units_to_deploy, deploy_workers)

# ========== Reactive signal handlers ==========

func _on_ship_derelict(ship: Ship) -> void:
	if not enabled:
		return
	_try_rescue_ship(ship)

func _try_rescue_ship(ship: Ship) -> bool:
	if not ship.is_derelict:
		return false
	# Already being rescued or refueled
	if ship in GameState.rescue_missions or ship in GameState.refuel_missions:
		return false

	# Out of fuel: refuel is cheaper than full rescue
	if ship.derelict_reason == "out_of_fuel":
		var fuel_amount := ship.get_effective_fuel_capacity() * 0.5
		if GameState.start_refuel(ship, fuel_amount):
			rescues_started += 1
			return true

	# Breakdown or refuel failed: full rescue
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
	# Immediately give idle ships new orders
	_handle_idle_remote(ship)

func _on_ship_idle_colony(ship: Ship, _trade_mission: TradeMission) -> void:
	if not enabled:
		return
	# Head home after trading
	GameState.order_return_to_earth(ship)

func _on_tardiness_resolved(_worker: Worker, action: String) -> void:
	match action:
		"forgiven": forgiven_count += 1
		"docked": docked_count += 1
		"fired": fired_count += 1

# ========== State validation ==========

func _validate_state() -> void:
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
			_error("Worker '%s' loyalty=%.1f out of range" % [worker.worker_name, worker.loyalty])
		if worker.fatigue < 0.0 or worker.fatigue > 100.0:
			_error("Worker '%s' fatigue=%.1f out of range" % [worker.worker_name, worker.fatigue])

	for entry in GameState.hitchhike_pool:
		if entry["worker"] not in GameState.workers:
			_error("Hitchhike pool orphan: '%s'" % entry["worker"].worker_name)

	for entry in GameState.tardy_workers:
		if entry["worker"] not in GameState.workers:
			_error("Tardy list orphan: '%s'" % entry["worker"].worker_name)

	for ship in GameState.ships:
		if ship.fuel < -0.01:
			_error("Ship '%s' negative fuel=%.2f" % [ship.ship_name, ship.fuel])
		if ship.engine_condition < -0.01 or ship.engine_condition > 100.01:
			_error("Ship '%s' engine_condition=%.1f" % [ship.ship_name, ship.engine_condition])
		if ship.is_stationed and ship.station_colony == null:
			_error("Ship '%s' stationed but colony is null" % ship.ship_name)
		if ship.current_mission != null and ship.current_trade_mission != null:
			_error("Ship '%s' has BOTH mission types" % ship.ship_name)

	for mission in GameState.missions:
		if mission.ship == null:
			_error("Mission with null ship (status=%d)" % mission.status)

	for tm in GameState.trade_missions:
		if tm.ship == null:
			_error("TradeMission with null ship (status=%d)" % tm.status)

	# Validate mining units
	for unit in GameState.deployed_mining_units:
		if unit.deployed_at_asteroid == "":
			_error("Deployed mining unit '%s' has empty asteroid name" % unit.unit_name)
		if unit.durability < -0.01:
			_error("Mining unit '%s' negative durability=%.1f" % [unit.unit_name, unit.durability])
		for w in unit.assigned_workers:
			if w not in GameState.workers:
				_error("Mining unit '%s' has orphan worker '%s'" % [unit.unit_name, w.worker_name])

func _error(msg: String) -> void:
	error_count += 1
	printerr("ERROR: [AUTOTEST] %s" % msg)

# ========== Overlay ==========

func _update_overlay() -> void:
	var on_leave := 0
	var waiting := 0
	var tardy := 0
	var active := 0
	var idle := 0
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
				active += 1
			else:
				idle += 1
		elif s.is_stationed:
			active += 1
		elif s.is_docked:
			idle += 1

	var money_m := "%.1fM" % (GameState.money / 1_000_000.0)
	overlay_label.text = (
		"AI CORP | %dd | $%s | Err: %d\n" % [int(elapsed_days), money_m, error_count]
		+ "Ships: %d (active %d idle %d) | Workers: %d (avail %d)\n" % [GameState.ships.size(), active, idle, GameState.workers.size(), GameState.get_available_workers().size()]
		+ "Mining: %d done | Trade: %d done | Contracts: %d/%d\n" % [missions_completed, trade_missions_completed, contracts_completed, contracts_accepted]
		+ "Leave: %d | Wait: %d | Tardy: %d | Rides: %d | Tardies: %d\n" % [on_leave, waiting, tardy, rides_given, tardies_count]
		+ "Bought: %d ships %d equip %d upgr | Bkdn: %d | Resc: %d | Strgr: %d\n" % [ships_bought, equipment_bought, upgrades_bought, breakdowns_count, rescues_started, stranger_rescues]
		+ "Claims: %d inv %d deployed | Stockpiles: %d" % [GameState.mining_unit_inventory.size(), GameState.deployed_mining_units.size(), GameState.ore_stockpiles.size()]
	)
