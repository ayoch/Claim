extends Node

var money: int = 10000:
	set(value):
		money = value
		EventBus.money_changed.emit(money)

var resources: Dictionary = {} # OreType -> float (tons)
var workers: Array[Worker] = []
var ships: Array[Ship] = []
var missions: Array[Mission] = []
var equipment_inventory: Array[Equipment] = []
var upgrade_inventory: Array[ShipUpgrade] = []  # Purchased but not yet installed
var fabrication_queue: Array[Equipment] = []  # Equipment being fabricated
var asteroids: Array[AsteroidData] = []
var settings: Dictionary = {
	"auto_refuel": true,
	"show_unreachable_destinations": false,
}

# Phase 2: Market
var market: MarketState = null

# Phase 2: Contracts
var available_contracts: Array[Contract] = []
var active_contracts: Array[Contract] = []
const MAX_AVAILABLE_CONTRACTS: int = 5

# Phase 2: Market Events
var active_market_events: Array[MarketEvent] = []
const MAX_ACTIVE_EVENTS: int = 3

# Phase 2: Colonies & Trade
var colonies: Array[Colony] = []
var trade_missions: Array[TradeMission] = []

# Rescue missions: ship -> {elapsed_ticks, transit_time, workers}
var rescue_missions: Dictionary = {}

# Refuel missions: ship -> {elapsed_ticks, transit_time, fuel_amount}
var refuel_missions: Dictionary = {}

func _ready() -> void:
	_init_resources()
	_init_starter_ship()
	_init_starter_crew()
	asteroids = CelestialData.get_asteroids()
	market = MarketState.new()
	colonies = ColonyData.get_colonies()

func _init_resources() -> void:
	for ore in ResourceTypes.OreType.values():
		resources[ore] = 0.0

func _init_starter_ship() -> void:
	var starter := Ship.new()
	starter.ship_name = "Prospector I"
	starter.thrust_g = 0.3
	starter.cargo_capacity = 100.0
	starter.fuel_capacity = 300.0  # Increased for early game viability
	starter.fuel = 300.0
	starter.min_crew = 3
	starter.position_au = CelestialData.get_earth_position_au()
	starter.base_mass = starter.cargo_capacity * 2.0  # 200t for baseline ship
	ships.append(starter)

func _init_starter_crew() -> void:
	# Hire starter crew equal to first ship's min_crew requirement
	var starter_ship := ships[0] if ships.size() > 0 else null
	var crew_needed := starter_ship.min_crew if starter_ship else 3

	for i in range(crew_needed):
		var worker := Worker.generate_random()
		workers.append(worker)

func add_resource(ore_type: ResourceTypes.OreType, amount: float) -> void:
	resources[ore_type] = resources.get(ore_type, 0.0) + amount
	EventBus.resource_changed.emit(ore_type, resources[ore_type])

func remove_resource(ore_type: ResourceTypes.OreType, amount: float) -> bool:
	var current: float = resources.get(ore_type, 0.0)
	if current < amount:
		return false
	resources[ore_type] = current - amount
	EventBus.resource_changed.emit(ore_type, resources[ore_type])
	return true

func hire_worker(worker: Worker) -> void:
	workers.append(worker)
	EventBus.worker_hired.emit(worker)

func fire_worker(worker: Worker) -> void:
	Worker.release_name(worker.worker_name)
	workers.erase(worker)
	worker.assigned_mission = null
	EventBus.worker_fired.emit(worker)

func get_available_workers() -> Array[Worker]:
	var available: Array[Worker] = []
	for w in workers:
		if w.is_available:
			available.append(w)
	return available

func get_docked_ships() -> Array[Ship]:
	var docked: Array[Ship] = []
	for s in ships:
		if s.is_docked:
			docked.append(s)
	return docked

func get_idle_remote_ships() -> Array[Ship]:
	var idle: Array[Ship] = []
	for s in ships:
		if s.is_idle_remote:
			idle.append(s)
	return idle

func purchase_equipment(entry: Dictionary) -> bool:
	if money < entry.get("cost", 0):
		return false
	var equip := Equipment.from_catalog(entry)
	money -= equip.cost

	# Add to fabrication queue instead of instant delivery
	fabrication_queue.append(equip)
	EventBus.equipment_purchased.emit(equip)
	return true

func install_equipment(ship: Ship, equip: Equipment) -> void:
	equipment_inventory.erase(equip)
	ship.equipment.append(equip)
	EventBus.equipment_installed.emit(ship, equip)

func purchase_upgrade(entry: Dictionary) -> bool:
	if money < entry.get("cost", 0):
		return false
	var upgrade := ShipUpgrade.from_catalog(entry)
	money -= upgrade.cost
	upgrade_inventory.append(upgrade)
	EventBus.upgrade_purchased.emit(upgrade)
	return true

func install_upgrade(ship: Ship, upgrade: ShipUpgrade) -> void:
	# Ship must be docked to install upgrades
	if not ship.is_docked:
		return
	upgrade_inventory.erase(upgrade)
	ship.upgrades.append(upgrade)
	EventBus.upgrade_installed.emit(ship, upgrade)

func jettison_all_cargo(ship: Ship) -> float:
	# Dump all cargo into space (lost forever)
	var total_jettisoned := 0.0
	for ore_type in ship.current_cargo:
		total_jettisoned += ship.current_cargo[ore_type]
	ship.current_cargo.clear()
	EventBus.cargo_jettisoned.emit(ship, total_jettisoned)
	return total_jettisoned

func jettison_cargo_for_trip(ship: Ship, distance_au: float, return_cargo_mass: float) -> float:
	# Jettison minimum cargo needed to make trip viable with current fuel
	var current_cargo := ship.get_cargo_total()

	# Binary search for minimum jettison amount
	var low := 0.0
	var high := current_cargo
	var needed_jettison := current_cargo  # Worst case: dump everything

	# Try to find minimum jettison in 10 iterations (precise enough)
	for _i in range(10):
		var mid := (low + high) / 2.0
		var remaining_cargo := current_cargo - mid

		# Calculate fuel needed with this amount of cargo
		var fuel_out := ship.calc_fuel_for_distance(distance_au, remaining_cargo)
		var fuel_ret := ship.calc_fuel_for_distance(distance_au, return_cargo_mass)
		var total_fuel := fuel_out + fuel_ret

		if total_fuel <= ship.fuel:
			# This works! Try jettisoning less
			needed_jettison = mid
			high = mid
		else:
			# Still not enough, need to jettison more
			low = mid

	# Actually jettison the cargo proportionally from all ore types
	if needed_jettison > 0:
		var jettison_ratio := needed_jettison / current_cargo
		for ore_type in ship.current_cargo.keys():
			var amount: float = ship.current_cargo[ore_type]
			ship.current_cargo[ore_type] = amount * (1.0 - jettison_ratio)
		ship.cleanup_cargo()  # Clean up zero-value entries
		EventBus.cargo_jettisoned.emit(ship, needed_jettison)

	return needed_jettison

func repair_equipment(ship: Ship, equip: Equipment) -> bool:
	var cost := equip.repair_cost()
	if cost <= 0:
		return false
	if money < cost:
		return false
	money -= cost
	equip.durability = equip.max_durability
	EventBus.equipment_repaired.emit(ship, equip)
	return true

func repair_engine(ship: Ship) -> bool:
	var cost := ship.get_engine_repair_cost()
	if cost <= 0:
		return false
	if money < cost:
		return false
	money -= cost
	ship.engine_condition = 100.0
	return true

func start_mission(ship: Ship, asteroid: AsteroidData, assigned_workers: Array[Worker], transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE) -> Mission:
	var mission := Mission.new()
	mission.ship = ship
	mission.asteroid = asteroid
	mission.workers = assigned_workers
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ship.position_au
	mission.return_position_au = ship.position_au  # default return to origin
	mission.transit_mode = transit_mode

	var dist := ship.position_au.distance_to(asteroid.get_position_au())

	# Calculate transit time based on mode
	if transit_mode == Mission.TransitMode.HOHMANN:
		mission.transit_time = Brachistochrone.hohmann_time(dist)
	else:
		mission.transit_time = Brachistochrone.transit_time(dist, ship.thrust_g)

	mission.elapsed_ticks = 0.0

	# Calculate fuel burn rate: account for different cargo mass outbound vs return
	var current_cargo_mass := ship.get_cargo_total()
	# Conservative estimate: assume full capacity on return
	var fuel_outbound := ship.calc_fuel_for_distance(dist, current_cargo_mass)
	var fuel_return := ship.calc_fuel_for_distance(dist, ship.cargo_capacity)
	var total_fuel := fuel_outbound + fuel_return

	# Apply Hohmann fuel savings
	if transit_mode == Mission.TransitMode.HOHMANN:
		total_fuel *= Brachistochrone.hohmann_fuel_multiplier()

	var total_transit_ticks := mission.transit_time * 2.0
	mission.fuel_per_tick = total_fuel / total_transit_ticks if total_transit_ticks > 0 else 0.0

	ship.current_mission = mission
	ship.current_cargo.clear()
	for w in assigned_workers:
		w.assigned_mission = mission

	missions.append(mission)
	EventBus.mission_started.emit(mission)
	return mission

func complete_mission(mission: Mission) -> void:
	# Transfer cargo from ship to stockpile (only if returning to Earth)
	if mission.ship.is_at_earth:
		for ore_type in mission.ship.current_cargo:
			add_resource(ore_type, mission.ship.current_cargo[ore_type])
		mission.ship.current_cargo.clear()

	mission.ship.current_mission = null

	for w in mission.workers:
		w.assigned_mission = null

	mission.status = Mission.Status.COMPLETED
	EventBus.mission_completed.emit(mission)
	missions.erase(mission)

func order_return_to_earth(ship: Ship) -> void:
	# Start a transit-back mission from current idle position to Earth
	if not ship.is_idle_remote:
		return

	var earth_pos := CelestialData.get_earth_position_au()
	var dist := ship.position_au.distance_to(earth_pos)

	if ship.current_mission:
		# Reuse existing mission for return
		ship.current_mission.return_position_au = earth_pos
		ship.current_mission.transit_time = Brachistochrone.transit_time(dist, ship.thrust_g)
		ship.current_mission.elapsed_ticks = 0.0
		var cargo_mass := ship.get_cargo_total()
		var total_fuel := ship.calc_fuel_for_distance(dist, cargo_mass)
		ship.current_mission.fuel_per_tick = total_fuel / ship.current_mission.transit_time if ship.current_mission.transit_time > 0 else 0.0
		ship.current_mission.status = Mission.Status.TRANSIT_BACK
		EventBus.mission_phase_changed.emit(ship.current_mission)
	elif ship.current_trade_mission:
		ship.current_trade_mission.return_position_au = earth_pos
		ship.current_trade_mission.transit_time = Brachistochrone.transit_time(dist, ship.thrust_g)
		ship.current_trade_mission.elapsed_ticks = 0.0
		var cargo_mass := ship.get_cargo_total()
		var total_fuel := ship.calc_fuel_for_distance(dist, cargo_mass)
		ship.current_trade_mission.fuel_per_tick = total_fuel / ship.current_trade_mission.transit_time if ship.current_trade_mission.transit_time > 0 else 0.0
		ship.current_trade_mission.status = TradeMission.Status.TRANSIT_BACK
		EventBus.trade_mission_phase_changed.emit(ship.current_trade_mission)
	else:
		# Create a new mission just for the return trip
		var mission := Mission.new()
		mission.ship = ship
		mission.status = Mission.Status.TRANSIT_BACK
		mission.origin_position_au = ship.position_au
		mission.return_position_au = earth_pos
		mission.transit_time = Brachistochrone.transit_time(dist, ship.thrust_g)
		mission.elapsed_ticks = 0.0
		var cargo_mass := ship.get_cargo_total()
		var total_fuel := ship.calc_fuel_for_distance(dist, cargo_mass)
		mission.fuel_per_tick = total_fuel / mission.transit_time if mission.transit_time > 0 else 0.0
		ship.current_mission = mission
		missions.append(mission)
		EventBus.mission_started.emit(mission)

func dispatch_idle_ship(ship: Ship, asteroid: AsteroidData, assigned_workers: Array[Worker], transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE) -> Mission:
	# End idle state and start new mission from current position
	if ship.current_mission:
		# Clean up the idle mission
		ship.current_mission.ship = null
		missions.erase(ship.current_mission)
		ship.current_mission = null
	if ship.current_trade_mission:
		ship.current_trade_mission.ship = null
		trade_missions.erase(ship.current_trade_mission)
		ship.current_trade_mission = null

	for w in ship.last_crew:
		w.assigned_mission = null

	return start_mission(ship, asteroid, assigned_workers, transit_mode)

func dispatch_idle_ship_trade(ship: Ship, colony_target: Colony, assigned_workers: Array[Worker], cargo_to_load: Dictionary, transit_mode: int = TradeMission.TransitMode.BRACHISTOCHRONE) -> TradeMission:
	# End idle state and start new trade mission from current position
	if ship.current_mission:
		ship.current_mission.ship = null
		missions.erase(ship.current_mission)
		ship.current_mission = null
	if ship.current_trade_mission:
		ship.current_trade_mission.ship = null
		trade_missions.erase(ship.current_trade_mission)
		ship.current_trade_mission = null

	for w in ship.last_crew:
		w.assigned_mission = null

	return start_trade_mission(ship, colony_target, assigned_workers, cargo_to_load, transit_mode)

const RESCUE_COST_PER_AU: int = 2000
const REFUEL_COST_PER_AU: int = 1000  # Cheaper than rescue, just delivers fuel

func start_rescue(ship: Ship) -> bool:
	if not ship.is_derelict:
		return false
	if ship in rescue_missions:
		return false

	var earth_pos := CelestialData.get_earth_position_au()
	var dist := ship.position_au.distance_to(earth_pos)
	var cost := int(dist * RESCUE_COST_PER_AU)

	if money < cost:
		return false

	money -= cost

	# Rescue transit uses a slow 0.5g ship
	var transit := Brachistochrone.transit_time(dist, 0.5) * 2.0  # round trip for rescue vessel
	rescue_missions[ship] = {
		"elapsed_ticks": 0.0,
		"transit_time": transit,
		"workers": ship.last_crew.duplicate(),
	}

	EventBus.rescue_mission_started.emit(ship, cost)
	return true

func start_refuel(ship: Ship, fuel_amount: float) -> bool:
	# Can refuel ships that are out of fuel, but not broken down ships (those need rescue)
	if ship.is_derelict and ship.derelict_reason != "out_of_fuel":
		return false  # Broken ships need rescue, not just refuel
	if ship in refuel_missions:
		return false  # Already has refuel in progress

	var earth_pos := CelestialData.get_earth_position_au()
	var dist := ship.position_au.distance_to(earth_pos)

	# Cost: distance charge + fuel cost
	var distance_cost := int(dist * REFUEL_COST_PER_AU)
	var fuel_cost := int(fuel_amount * Ship.FUEL_COST_PER_UNIT)
	var total_cost := distance_cost + fuel_cost

	if money < total_cost:
		return false

	money -= total_cost

	# Refuel tanker uses 0.5g transit (one-way, it doesn't need to return)
	var transit := Brachistochrone.transit_time(dist, 0.5)
	refuel_missions[ship] = {
		"elapsed_ticks": 0.0,
		"transit_time": transit,
		"fuel_amount": fuel_amount,
	}

	EventBus.refuel_mission_started.emit(ship, total_cost, fuel_amount)
	return true

# --- Contract methods ---

func accept_contract(contract: Contract) -> void:
	if contract.status != Contract.Status.AVAILABLE:
		return
	contract.status = Contract.Status.ACCEPTED
	available_contracts.erase(contract)
	active_contracts.append(contract)
	EventBus.contract_accepted.emit(contract)

func fulfill_contract(contract: Contract) -> bool:
	if contract.status != Contract.Status.ACCEPTED:
		return false
	var current_amount: float = resources.get(contract.ore_type, 0.0)
	if current_amount < contract.quantity:
		return false
	remove_resource(contract.ore_type, contract.quantity)
	money += contract.reward
	contract.status = Contract.Status.COMPLETED
	active_contracts.erase(contract)
	EventBus.contract_completed.emit(contract)
	return true

func fulfill_contract_from_ship(contract: Contract, ship: Ship, amount: float) -> Dictionary:
	# Fulfill contract (partial or full) from ship cargo
	# Returns { "success": bool, "amount_delivered": float, "payment": int, "completed": bool }
	var result := {
		"success": false,
		"amount_delivered": 0.0,
		"payment": 0,
		"completed": false
	}

	if contract.status != Contract.Status.ACCEPTED:
		return result

	# Check ship has the ore
	var ship_cargo: float = ship.current_cargo.get(contract.ore_type, 0.0)
	if ship_cargo <= 0:
		return result

	# Calculate how much to deliver
	var remaining := contract.get_remaining_quantity()
	var to_deliver := minf(ship_cargo, minf(amount, remaining))

	if to_deliver <= 0:
		return result

	# Check if partial fulfillment is allowed
	if not contract.allows_partial and to_deliver < remaining:
		return result

	# Remove from ship cargo
	ship.current_cargo[contract.ore_type] -= to_deliver
	ship.cleanup_cargo()  # Clean up zero-value entries

	# Update contract
	contract.quantity_delivered += to_deliver
	var payment := contract.get_partial_payment(to_deliver)
	money += payment

	result["success"] = true
	result["amount_delivered"] = to_deliver
	result["payment"] = payment

	# Check if contract is complete
	if contract.is_completed():
		contract.status = Contract.Status.COMPLETED
		active_contracts.erase(contract)
		EventBus.contract_completed.emit(contract)
		result["completed"] = true
	else:
		EventBus.contract_progress.emit(contract, to_deliver)

	return result

# --- Trade mission methods ---

func start_trade_mission(ship: Ship, colony_target: Colony, assigned_workers: Array[Worker], cargo_to_load: Dictionary, transit_mode: int = TradeMission.TransitMode.BRACHISTOCHRONE) -> TradeMission:
	var tm := TradeMission.new()
	tm.ship = ship
	tm.colony = colony_target
	tm.workers = assigned_workers
	tm.status = TradeMission.Status.TRANSIT_TO_COLONY
	tm.origin_position_au = ship.position_au
	tm.return_position_au = ship.position_au  # default return to origin
	tm.transit_mode = transit_mode

	# Load cargo from stockpile onto ship (only if at Earth with stockpile access)
	tm.cargo = {}
	for ore_type in cargo_to_load:
		var amount: float = cargo_to_load[ore_type]
		if amount > 0:
			if ship.is_at_earth:
				if remove_resource(ore_type, amount):
					tm.cargo[ore_type] = amount
			else:
				# Remote ship: use cargo already on board
				var on_board: float = ship.current_cargo.get(ore_type, 0.0)
				var to_load := minf(amount, on_board)
				if to_load > 0:
					tm.cargo[ore_type] = to_load

	# Calculate distance and transit from ship's current position
	var colony_pos := colony_target.get_position_au()
	var dist := ship.position_au.distance_to(colony_pos)

	# Calculate transit time based on mode
	if transit_mode == TradeMission.TransitMode.HOHMANN:
		tm.transit_time = Brachistochrone.hohmann_time(dist)
	else:
		tm.transit_time = Brachistochrone.transit_time(dist, ship.thrust_g)

	tm.elapsed_ticks = 0.0

	# Fuel calculation: loaded outbound (with cargo), empty return
	var cargo_mass := ship.get_cargo_total()
	var fuel_outbound := ship.calc_fuel_for_distance(dist, cargo_mass)
	# Empty on return from trade
	var fuel_return := ship.calc_fuel_for_distance(dist, 0.0)
	var total_fuel := fuel_outbound + fuel_return

	# Apply Hohmann fuel savings
	if transit_mode == TradeMission.TransitMode.HOHMANN:
		total_fuel *= Brachistochrone.hohmann_fuel_multiplier()

	var total_transit_ticks := tm.transit_time * 2.0
	tm.fuel_per_tick = total_fuel / total_transit_ticks if total_transit_ticks > 0 else 0.0

	ship.current_trade_mission = tm
	ship.current_cargo = tm.cargo.duplicate()
	for w in assigned_workers:
		w.assigned_mission = null  # Trade missions don't lock workers via assigned_mission for simplicity

	trade_missions.append(tm)
	EventBus.trade_mission_started.emit(tm)
	return tm

func complete_trade_mission(tm: TradeMission) -> void:
	tm.ship.current_cargo.clear()
	tm.ship.current_trade_mission = null
	tm.status = TradeMission.Status.COMPLETED
	EventBus.trade_mission_completed.emit(tm)
	trade_missions.erase(tm)

# Save/Load
func save_game() -> void:
	var save_data := {
		"money": money,
		"resources": {},
		"workers": [],
		"ships": [],
		"market_prices": {},
	}
	for ore_type in resources:
		save_data["resources"][str(ore_type)] = resources[ore_type]
	if market:
		for ore_type in market.current_prices:
			save_data["market_prices"][str(ore_type)] = market.current_prices[ore_type]
	for w in workers:
		save_data["workers"].append({
			"name": w.worker_name,
			"skill": w.skill,
			"wage": w.wage,
		})
	for s in ships:
		var ship_data := {
			"name": s.ship_name,
			"thrust_g": s.thrust_g,
			"cargo_capacity": s.cargo_capacity,
			"position_au_x": s.position_au.x,
			"position_au_y": s.position_au.y,
			"engine_condition": s.engine_condition,
			"is_derelict": s.is_derelict,
			"fuel": s.fuel,
			"fuel_capacity": s.fuel_capacity,
			"equipment": [],
		}
		for e in s.equipment:
			ship_data["equipment"].append({
				"name": e.equipment_name,
				"type": e.type,
				"mining_bonus": e.mining_bonus,
				"cost": e.cost,
				"durability": e.durability,
				"max_durability": e.max_durability,
				"wear_per_tick": e.wear_per_tick,
			})
		# Save cargo if ship has any
		if not s.current_cargo.is_empty():
			var cargo_data := {}
			for ore_type in s.current_cargo:
				cargo_data[str(ore_type)] = s.current_cargo[ore_type]
			ship_data["cargo"] = cargo_data
		save_data["ships"].append(ship_data)

	var file := FileAccess.open("user://save_game.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data, "\t"))

func load_game() -> bool:
	if not FileAccess.file_exists("user://save_game.json"):
		return false
	var file := FileAccess.open("user://save_game.json", FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return false
	var data: Dictionary = json.data

	money = int(data.get("money", 10000))

	_init_resources()
	var res_data: Dictionary = data.get("resources", {})
	for key in res_data:
		resources[int(key)] = float(res_data[key])

	# Restore market prices
	if market:
		var price_data: Dictionary = data.get("market_prices", {})
		for key in price_data:
			market.current_prices[int(key)] = float(price_data[key])

	workers.clear()
	for wd in data.get("workers", []):
		var w := Worker.new()
		w.worker_name = wd.get("name", "Unknown")
		w.skill = float(wd.get("skill", 1.0))
		w.wage = int(wd.get("wage", 100))
		workers.append(w)

	ships.clear()
	for sd in data.get("ships", []):
		var s := Ship.new()
		s.ship_name = sd.get("name", "Ship")
		s.thrust_g = float(sd.get("thrust_g", 0.3))
		s.cargo_capacity = float(sd.get("cargo_capacity", 100.0))
		s.fuel_capacity = float(sd.get("fuel_capacity", 200.0))
		s.fuel = float(sd.get("fuel", 200.0))
		s.position_au = Vector2(
			float(sd.get("position_au_x", 0.0)),
			float(sd.get("position_au_y", 0.0))
		)
		s.engine_condition = float(sd.get("engine_condition", 100.0))
		s.is_derelict = sd.get("is_derelict", false)
		# Restore cargo
		var cargo_data: Dictionary = sd.get("cargo", {})
		for key in cargo_data:
			s.current_cargo[int(key)] = float(cargo_data[key])
		for ed in sd.get("equipment", []):
			var e := Equipment.from_catalog(ed)
			e.durability = float(ed.get("durability", 100.0))
			e.max_durability = float(ed.get("max_durability", 100.0))
			e.fabrication_ticks = 0.0  # Already fabricated if saved
			s.equipment.append(e)
		ships.append(s)

	return true
