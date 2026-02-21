extends Node

var money: int = 14000000:
	set(value):
		money = value
		EventBus.money_changed.emit(money)

var resources: Dictionary = {} # OreType -> float (tons)

# Financial history tracking
# Each entry: { "timestamp": float, "balance": int, "change": int, "desc": String, "ship": String }
var financial_history: Array[Dictionary] = []
const MAX_FINANCIAL_HISTORY: int = 1000
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
	"auto_sell_at_markets": false,
}

# Company policies
var thrust_policy: int = CompanyPolicy.ThrustPolicy.BALANCED  # Default to balanced

# Game clock: total elapsed game-seconds (ticks) since game start
var total_ticks: float = 0.0
const START_YEAR: int = 2026
const START_MONTH: int = 2
const START_DAY: int = 18

# Days per month (non-leap)
const DAYS_IN_MONTH: Array[int] = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

func _is_leap_year(y: int) -> bool:
	return (y % 4 == 0 and y % 100 != 0) or (y % 400 == 0)

func _days_in_year(y: int) -> int:
	return 366 if _is_leap_year(y) else 365

func _days_in_month(m: int, y: int) -> int:
	if m == 2 and _is_leap_year(y):
		return 29
	return DAYS_IN_MONTH[m - 1]

func get_game_date() -> Dictionary:
	var total_days := int(total_ticks / 86400.0)
	var remaining_secs := int(total_ticks) % 86400
	var hours := remaining_secs / 3600
	var minutes := (remaining_secs % 3600) / 60.0

	var year := START_YEAR
	var month := START_MONTH
	var day := START_DAY + total_days

	# Roll forward through months/years
	while day > _days_in_month(month, year):
		day -= _days_in_month(month, year)
		month += 1
		if month > 12:
			month = 1
			year += 1

	return { "year": year, "month": month, "day": day, "hours": hours, "minutes": minutes }

func get_game_date_string() -> String:
	var d := get_game_date()
	var fmt: String = settings.get("date_format", "us")
	match fmt:
		"us":
			return "%02d/%02d/%04d  %02d:%02d" % [d["month"], d["day"], d["year"], d["hours"], d["minutes"]]
		"eu":
			return "%02d.%02d.%04d  %02d:%02d" % [d["day"], d["month"], d["year"], d["hours"], d["minutes"]]
		"iso":
			return "%04d-%02d-%02d  %02d:%02d" % [d["year"], d["month"], d["day"], d["hours"], d["minutes"]]
		"uk":
			return "%02d/%02d/%04d  %02d:%02d" % [d["day"], d["month"], d["year"], d["hours"], d["minutes"]]
		_:
			return "%02d/%02d/%04d  %02d:%02d" % [d["month"], d["day"], d["year"], d["hours"], d["minutes"]]

func record_transaction(change: int, desc: String, ship_name: String = "") -> void:
	financial_history.append({
		"timestamp": total_ticks,
		"balance": money,
		"change": change,
		"desc": desc,
		"ship": ship_name,
	})
	if financial_history.size() > MAX_FINANCIAL_HISTORY:
		financial_history.remove_at(0)  # Drop oldest — avoids allocating a new array

func get_financial_data(time_range_seconds: float) -> Array[Dictionary]:
	# Returns financial history within the time range
	var cutoff_time := total_ticks - time_range_seconds
	var result: Array[Dictionary] = []
	for entry in financial_history:
		if entry["timestamp"] >= cutoff_time:
			result.append(entry)
	return result

func calculate_profit_rate(time_range_seconds: float) -> float:
	# Calculate profit per second over the time range
	var data := get_financial_data(time_range_seconds)
	if data.is_empty():
		return 0.0
	var total_change := 0
	for entry in data:
		total_change += entry["change"]
	var actual_time: float = total_ticks - float(data[0]["timestamp"])
	if actual_time > 0:
		return float(total_change) / actual_time
	return 0.0

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

# Refuel missions: ship -> {elapsed_ticks, transit_time, fuel_amount, source_name, source_pos}
var refuel_missions: Dictionary = {}

# Stranger rescue offers: ship -> {stranger_name, expires_ticks, suggested_tip}
var stranger_offers: Dictionary = {}

# Deployed crews at remote asteroids (foundation for claims system)
var deployed_crews: Array[Dictionary] = []
# Each: { "asteroid": AsteroidData, "workers": Array[Worker], "supplies": Dictionary, "deployed_at": float }

# Mining units (deployable autonomous miners)
var mining_unit_inventory: Array[MiningUnit] = []  # Purchased, not yet deployed
var deployed_mining_units: Array[MiningUnit] = []  # On asteroids, mining autonomously
var ore_stockpiles: Dictionary = {}  # asteroid_name -> { OreType -> float }
var asteroid_supplies: Dictionary = {}  # asteroid_name -> { "food": float, "repair_parts": float }

# Security zones created by patrolling ships
# Each: { "center_au": Vector2, "radius_au": float, "ship_name": String, "expires_at": float }
var security_zones: Array[Dictionary] = []

# Hitchhiking pool: workers waiting at stations for a ride home
# Each: { "worker": Worker, "location_name": String, "location_pos": Vector2, "entered_at": float, "max_wait": float }
var hitchhike_pool: Array[Dictionary] = []

# Tardy workers awaiting player discipline decision
# Each: { "worker": Worker, "reason": String, "tardy_since": float }
var tardy_workers: Array[Dictionary] = []

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
	var classes := ShipData.ShipClass.values()
	for i in range(3):
		var ship_class: ShipData.ShipClass = classes[randi() % classes.size()]
		ships.append(ShipData.create_ship(ship_class))

func purchase_ship(ship_class: ShipData.ShipClass) -> Ship:
	var price: int = ShipData.CLASS_PRICES[ship_class]
	if money < price:
		return null
	money -= price
	var new_ship := ShipData.create_ship(ship_class)
	ships.append(new_ship)
	EventBus.ship_purchased.emit(new_ship, price)
	return new_ship

## Redirect a ship in transit to a new asteroid
## Returns true if redirect successful, false if not feasible or not enough fuel/money
func redirect_mission(mission: Mission, new_asteroid: AsteroidData) -> bool:
	if mission.status != Mission.Status.TRANSIT_OUT and mission.status != Mission.Status.TRANSIT_BACK:
		return false  # Can only redirect during transit

	var ship := mission.ship
	var new_dest := new_asteroid.get_position_au()

	# Calculate course change from current position/velocity
	var course_change := Brachistochrone.calculate_course_change(
		ship.position_au,
		ship.velocity_au_per_tick,
		ship.get_effective_thrust(),
		ship.fuel,
		new_dest
	)

	if not course_change["feasible"]:
		EventBus.mission_redirect_failed.emit(ship, course_change["reason"])
		return false

	# Redirect costs money (crew time, recalculation, opportunity cost)
	var redirect_cost := int(course_change["fuel_cost"] * Ship.FUEL_COST_PER_UNIT * 2.0)  # 2x fuel cost as penalty
	if money < redirect_cost:
		EventBus.mission_redirect_failed.emit(ship, "Cannot afford redirect cost ($%d)" % redirect_cost)
		return false

	money -= redirect_cost

	# Update mission to new destination
	mission.asteroid = new_asteroid

	# Reset transit for outbound leg
	if mission.status == Mission.Status.TRANSIT_OUT:
		mission.elapsed_ticks = 0.0
		mission.transit_time = course_change["new_transit_time"]
		# Fuel already consumed doesn't change, but update fuel_per_tick for remaining transit
		var remaining_fuel_budget := ship.fuel
		mission.fuel_per_tick = remaining_fuel_budget / mission.transit_time if mission.transit_time > 0 else 0.0

	EventBus.mission_redirected.emit(ship, new_asteroid, redirect_cost)
	return true

## Redirect a ship in trade mission to a new colony
func redirect_trade_mission(trade_mission: TradeMission, new_colony: Colony) -> bool:
	if trade_mission.status != TradeMission.Status.TRANSIT_TO_COLONY and trade_mission.status != TradeMission.Status.TRANSIT_BACK:
		return false  # Can only redirect during transit

	var ship := trade_mission.ship
	var new_dest := new_colony.get_position_au()

	# Calculate course change
	var course_change := Brachistochrone.calculate_course_change(
		ship.position_au,
		ship.velocity_au_per_tick,
		ship.get_effective_thrust(),
		ship.fuel,
		new_dest
	)

	if not course_change["feasible"]:
		EventBus.trade_mission_redirect_failed.emit(ship, course_change["reason"])
		return false

	# Redirect cost
	var redirect_cost := int(course_change["fuel_cost"] * Ship.FUEL_COST_PER_UNIT * 2.0)
	if money < redirect_cost:
		EventBus.trade_mission_redirect_failed.emit(ship, "Cannot afford redirect cost ($%d)" % redirect_cost)
		return false

	money -= redirect_cost

	# Update trade mission
	trade_mission.colony = new_colony

	# Reset transit
	if trade_mission.status == TradeMission.Status.TRANSIT_TO_COLONY:
		trade_mission.elapsed_ticks = 0.0
		trade_mission.transit_time = course_change["new_transit_time"]
		var remaining_fuel_budget := ship.fuel
		trade_mission.fuel_per_tick = remaining_fuel_budget / trade_mission.transit_time if trade_mission.transit_time > 0 else 0.0

	EventBus.trade_mission_redirected.emit(ship, new_colony, redirect_cost)
	return true

func _init_starter_crew() -> void:
	# Hire starter crew with guaranteed specialty coverage: pilot, engineer, miner
	# Extra workers for testing ship purchases (12 total allows buying multiple ships)
	var total_workers := 12

	# First 3 workers get guaranteed primary specialties
	var primaries := [0, 1, 2]  # pilot, engineer, mining
	for i in range(total_workers):
		var worker: Worker
		if i < primaries.size():
			worker = Worker.generate_with_primary(primaries[i])
		else:
			worker = Worker.generate_random()
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
	worker.assigned_trade_mission = null
	# Remove from any stationed ship's crew
	if worker.assigned_station_ship:
		worker.assigned_station_ship.last_crew.erase(worker)
	worker.assigned_station_ship = null
	# Remove from any mining unit
	if worker.assigned_mining_unit:
		worker.assigned_mining_unit.assigned_workers.erase(worker)
		worker.assigned_mining_unit = null
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
	record_transaction(-upgrade.cost, "Upgrade: %s" % upgrade.upgrade_name)
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

## --- Mining Unit Methods ---

func purchase_mining_unit(entry: Dictionary) -> bool:
	if money < entry.get("cost", 0):
		return false
	var unit := MiningUnit.from_catalog(entry)
	money -= unit.cost
	record_transaction(-unit.cost, "Mining unit: %s" % unit.unit_name)
	mining_unit_inventory.append(unit)
	EventBus.mining_unit_purchased.emit(unit)
	return true

func deploy_mining_unit(unit: MiningUnit, asteroid: AsteroidData, unit_workers: Array[Worker]) -> bool:
	if unit.is_deployed():
		return false
	if unit_workers.size() < unit.workers_required:
		return false
	var occupied := get_occupied_slots(asteroid.asteroid_name)
	if occupied >= asteroid.get_max_mining_slots():
		return false
	# Move from inventory to deployed
	mining_unit_inventory.erase(unit)
	deployed_mining_units.append(unit)
	unit.deployed_at_asteroid = asteroid.asteroid_name
	unit.deployed_at_tick = total_ticks
	unit.assigned_workers = []
	for w in unit_workers:
		unit.assigned_workers.append(w)
		w.assigned_mining_unit = unit
	EventBus.mining_unit_deployed.emit(unit, asteroid)
	return true

func repair_mining_unit(unit: MiningUnit) -> bool:
	var base_cost := unit.repair_cost()
	if base_cost <= 0:
		return false
	# Better engineers reduce repair cost (best engineer skill among assigned workers)
	var best_eng := 0.0
	for w in unit.assigned_workers:
		if w.engineer_skill > best_eng:
			best_eng = w.engineer_skill
	# 0.0 skill = full price, 1.5 skill = 55% price
	var eng_discount := 1.0 - (best_eng * 0.3)
	var cost := int(base_cost * eng_discount)
	if cost <= 0:
		cost = 1
	if money < cost:
		return false
	money -= cost
	unit.durability = unit.max_durability
	# Grant engineer XP to workers assigned to the unit
	for w in unit.assigned_workers:
		w.add_xp(1, 21600.0)  # 1 = engineer skill, quarter day per repair event
	return true

func rebuild_mining_unit(unit: MiningUnit) -> bool:
	# Must be in inventory (recalled), not deployed
	if unit.is_deployed():
		return false
	var cost := unit.rebuild_cost()
	if money < cost:
		return false
	money -= cost
	record_transaction(-cost, "Rebuild: %s" % unit.unit_name)
	unit.max_durability = 100.0
	unit.durability = 100.0
	return true

func recall_mining_unit(unit: MiningUnit) -> void:
	if not unit.is_deployed():
		return
	for w in unit.assigned_workers:
		w.assigned_mining_unit = null
	unit.assigned_workers.clear()
	unit.deployed_at_asteroid = ""
	deployed_mining_units.erase(unit)
	mining_unit_inventory.append(unit)
	EventBus.mining_unit_recalled.emit(unit)

func get_mining_units_at(asteroid_name: String) -> Array[MiningUnit]:
	var result: Array[MiningUnit] = []
	for unit in deployed_mining_units:
		if unit.deployed_at_asteroid == asteroid_name:
			result.append(unit)
	return result

func get_occupied_slots(asteroid_name: String) -> int:
	var count := 0
	for unit in deployed_mining_units:
		if unit.deployed_at_asteroid == asteroid_name:
			count += 1
	return count

func get_ore_stockpile(asteroid_name: String) -> Dictionary:
	return ore_stockpiles.get(asteroid_name, {})

func add_to_stockpile(asteroid_name: String, ore_type: ResourceTypes.OreType, amount: float) -> void:
	if not ore_stockpiles.has(asteroid_name):
		ore_stockpiles[asteroid_name] = {}
	var pile: Dictionary = ore_stockpiles[asteroid_name]
	pile[ore_type] = pile.get(ore_type, 0.0) + amount

func collect_from_stockpile(asteroid_name: String, ship: Ship) -> float:
	if not ore_stockpiles.has(asteroid_name):
		return 0.0
	var pile: Dictionary = ore_stockpiles[asteroid_name]
	var space_remaining := ship.cargo_capacity - ship.get_cargo_total()
	var total_collected := 0.0
	# Load proportionally if not enough space
	var total_available := 0.0
	for ore_type in pile:
		total_available += pile[ore_type]
	if total_available <= 0.0:
		return 0.0
	var scale := 1.0
	if total_available > space_remaining:
		scale = space_remaining / total_available
	for ore_type in pile.keys():
		var amount: float = pile[ore_type] * scale
		if amount > 0.0:
			ship.current_cargo[ore_type] = ship.current_cargo.get(ore_type, 0.0) + amount
			pile[ore_type] -= amount
			total_collected += amount
	# Clean up empty entries
	for ore_type in pile.keys():
		if pile[ore_type] <= 0.001:
			pile.erase(ore_type)
	if pile.is_empty():
		ore_stockpiles.erase(asteroid_name)
	return total_collected

func get_asteroid_supplies(asteroid_name: String) -> Dictionary:
	return asteroid_supplies.get(asteroid_name, {"food": 0.0, "repair_parts": 0.0})

func add_to_asteroid_supplies(asteroid_name: String, supply_key: String, amount: float) -> void:
	if not asteroid_supplies.has(asteroid_name):
		asteroid_supplies[asteroid_name] = {"food": 0.0, "repair_parts": 0.0}
	asteroid_supplies[asteroid_name][supply_key] = asteroid_supplies[asteroid_name].get(supply_key, 0.0) + amount

func consume_asteroid_supply(asteroid_name: String, supply_key: String, amount: float) -> float:
	## Consume up to `amount` from the supply. Returns actual amount consumed.
	if not asteroid_supplies.has(asteroid_name):
		return 0.0
	var current: float = asteroid_supplies[asteroid_name].get(supply_key, 0.0)
	var consumed: float = minf(amount, current)
	asteroid_supplies[asteroid_name][supply_key] = current - consumed
	return consumed

func get_asteroid_supply_days(asteroid_name: String, supply_key: String) -> float:
	## Returns days remaining for the given supply based on current deployed units/workers
	var supply: float = asteroid_supplies.get(asteroid_name, {}).get(supply_key, 0.0)
	if supply <= 0.0:
		return 0.0
	match supply_key:
		"food":
			var worker_count := 0
			for unit in deployed_mining_units:
				if unit.deployed_at_asteroid == asteroid_name:
					worker_count += unit.assigned_workers.size()
			if worker_count <= 0:
				return INF
			return supply / (worker_count * 0.028)
		"repair_parts":
			var unit_count := 0
			for unit in deployed_mining_units:
				if unit.deployed_at_asteroid == asteroid_name:
					unit_count += 1
			if unit_count <= 0:
				return INF
			return supply / (unit_count * 0.05)
	return INF

func start_deploy_mission(ship: Ship, asteroid: AsteroidData, crew: Array[Worker], units: Array[MiningUnit], deploy_workers: Array[Worker], transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
	var mission := Mission.new()
	mission.ship = ship
	mission.asteroid = asteroid
	mission.workers = crew
	mission.mission_type = Mission.MissionType.DEPLOY_UNIT
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ship.position_au
	mission.return_position_au = ship.position_au
	mission.transit_mode = transit_mode as Mission.TransitMode
	mission.mining_units_to_deploy = units
	mission.workers_to_deploy = deploy_workers
	mission.deploy_duration = 3600.0 * units.size()

	# Determine if departing from Earth
	var earth_pos := CelestialData.get_earth_position_au()
	mission.origin_is_earth = ship.position_au.distance_to(earth_pos) < 0.05

	var dist := ship.position_au.distance_to(asteroid.get_position_au())

	if slingshot_route:
		mission.outbound_waypoints = [slingshot_route.waypoint_pos]
		mission.outbound_waypoint_planet_ids = [slingshot_route.planet_index]
		mission.outbound_leg_times = [slingshot_route.leg1_time, slingshot_route.leg2_time]
		mission.outbound_waypoint_index = 0
		mission.transit_time = slingshot_route.leg1_time
		dist = slingshot_route.leg1_distance
	else:
		if transit_mode == Mission.TransitMode.HOHMANN:
			mission.transit_time = Brachistochrone.hohmann_time(dist)
		else:
			mission.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())

	# Apply pilot skill modifier
	var best_pilot := 0.0
	for w in crew:
		if w.pilot_skill > best_pilot:
			best_pilot = w.pilot_skill
	var pilot_factor := 1.15 - (best_pilot * 0.2)
	mission.transit_time *= pilot_factor

	mission.elapsed_ticks = 0.0

	# Calculate fuel burn rate
	var cargo_mass := ship.get_cargo_total()
	# Add unit mass to cargo for fuel calculation
	var unit_mass := 0.0
	for u in units:
		unit_mass += u.mass
	var fuel_outbound := ship.calc_fuel_for_distance(dist, cargo_mass + unit_mass)
	var fuel_return := ship.calc_fuel_for_distance(dist, cargo_mass)  # Return lighter (units deployed)
	var total_fuel := fuel_outbound + fuel_return
	if transit_mode == Mission.TransitMode.HOHMANN:
		total_fuel *= Brachistochrone.hohmann_fuel_multiplier()
	var total_transit_ticks := mission.transit_time * 2.0
	mission.fuel_per_tick = total_fuel / total_transit_ticks if total_transit_ticks > 0 else 0.0

	# Remove units from inventory immediately — they're now loaded on the ship
	for u in units:
		mining_unit_inventory.erase(u)

	ship.current_mission = mission
	ship.docked_at_colony = null
	ship.reset_life_support(crew.size())
	for w in crew:
		w.assigned_mission = mission

	missions.append(mission)
	EventBus.mission_started.emit(mission)
	return mission

func start_collect_mission(ship: Ship, asteroid: AsteroidData, crew: Array[Worker], transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
	# Clean up any lingering idle mission so its stale worker list doesn't cause mismatches
	if ship.current_mission and ship.current_mission.status == Mission.Status.IDLE_AT_DESTINATION:
		ship.current_mission.ship = null
		missions.erase(ship.current_mission)
		ship.current_mission = null
	var mission := Mission.new()
	mission.ship = ship
	mission.asteroid = asteroid
	mission.workers = crew
	mission.mission_type = Mission.MissionType.COLLECT_ORE
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ship.position_au
	mission.return_position_au = ship.position_au
	mission.transit_mode = transit_mode as Mission.TransitMode

	var earth_pos := CelestialData.get_earth_position_au()
	mission.origin_is_earth = ship.position_au.distance_to(earth_pos) < 0.05

	var dist := ship.position_au.distance_to(asteroid.get_position_au())

	if slingshot_route:
		mission.outbound_waypoints = [slingshot_route.waypoint_pos]
		mission.outbound_waypoint_planet_ids = [slingshot_route.planet_index]
		mission.outbound_leg_times = [slingshot_route.leg1_time, slingshot_route.leg2_time]
		mission.outbound_waypoint_index = 0
		mission.transit_time = slingshot_route.leg1_time
		dist = slingshot_route.leg1_distance
	else:
		if transit_mode == Mission.TransitMode.HOHMANN:
			mission.transit_time = Brachistochrone.hohmann_time(dist)
		else:
			mission.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())

	var best_pilot := 0.0
	for w in crew:
		if w.pilot_skill > best_pilot:
			best_pilot = w.pilot_skill
	var pilot_factor := 1.15 - (best_pilot * 0.2)
	mission.transit_time *= pilot_factor

	mission.elapsed_ticks = 0.0

	var cargo_mass := ship.get_cargo_total()
	var fuel_outbound := ship.calc_fuel_for_distance(dist, cargo_mass)
	var fuel_return := ship.calc_fuel_for_distance(dist, ship.cargo_capacity)  # Assume full return
	var total_fuel := fuel_outbound + fuel_return
	if transit_mode == Mission.TransitMode.HOHMANN:
		total_fuel *= Brachistochrone.hohmann_fuel_multiplier()
	var total_transit_ticks := mission.transit_time * 2.0
	mission.fuel_per_tick = total_fuel / total_transit_ticks if total_transit_ticks > 0 else 0.0

	ship.current_mission = mission
	ship.docked_at_colony = null
	ship.reset_life_support(crew.size())
	for w in crew:
		w.assigned_mission = mission

	missions.append(mission)
	EventBus.mission_started.emit(mission)
	return mission

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
	record_transaction(-cost, "Equip repair: %s" % equip.equipment_name, ship.ship_name)
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
	record_transaction(-cost, "Engine repair", ship.ship_name)
	ship.engine_condition = 100.0
	return true

func start_mission(ship: Ship, asteroid: AsteroidData, assigned_workers: Array[Worker], transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
	# Clean up any lingering idle mission so its stale worker list doesn't cause mismatches
	if ship.current_mission and ship.current_mission.status == Mission.Status.IDLE_AT_DESTINATION:
		ship.current_mission.ship = null
		missions.erase(ship.current_mission)
		ship.current_mission = null
	var mission := Mission.new()
	mission.ship = ship
	mission.asteroid = asteroid
	mission.workers = assigned_workers
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ship.position_au
	mission.return_position_au = ship.position_au  # default return to origin
	mission.transit_mode = transit_mode as Mission.TransitMode

	var dist := ship.position_au.distance_to(asteroid.get_position_au())

	# Setup slingshot waypoints if using gravity assist
	if slingshot_route:
		mission.outbound_waypoints = [slingshot_route.waypoint_pos]
		mission.outbound_waypoint_planet_ids = [slingshot_route.planet_index]
		mission.outbound_leg_times = [slingshot_route.leg1_time, slingshot_route.leg2_time]
		mission.outbound_waypoint_index = 0
		mission.transit_time = slingshot_route.leg1_time  # First leg
		dist = slingshot_route.leg1_distance
	else:
		# Direct route
		if transit_mode == Mission.TransitMode.HOHMANN:
			mission.transit_time = Brachistochrone.hohmann_time(dist)
		else:
			mission.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())

	# Check if fuel stops are needed for outbound journey
	var expected_cargo_out := ship.get_cargo_total()
	var outbound_fuel_route := FuelRoutePlanner.plan_route_to_position(
		ship,
		asteroid.get_position_au(),
		expected_cargo_out,
		3  # max stops
	)

	if outbound_fuel_route["feasible"] and outbound_fuel_route["waypoints"].size() > 0:
		# Need fuel stops - add them to waypoint arrays
		# If we already have slingshot waypoints, we need to merge them
		if slingshot_route:
			# For now, append fuel stops after slingshot (simple approach)
			# TODO: Could optimize by interleaving based on positions
			for i in range(outbound_fuel_route["waypoints"].size()):
				mission.outbound_waypoints.append(outbound_fuel_route["waypoints"][i])
				mission.outbound_waypoint_types.append(Mission.WaypointType.REFUEL_STOP)
				mission.outbound_waypoint_colony_refs.append(outbound_fuel_route["colonies"][i])
				mission.outbound_waypoint_fuel_amounts.append(outbound_fuel_route["fuel_amounts"][i])
				mission.outbound_waypoint_fuel_costs.append(outbound_fuel_route["fuel_costs"][i])
				mission.outbound_leg_times.append(outbound_fuel_route["leg_times"][i])
			# Mark slingshot waypoints
			for i in range(mission.outbound_waypoint_planet_ids.size()):
				if i < mission.outbound_waypoint_types.size():
					mission.outbound_waypoint_types[i] = Mission.WaypointType.GRAVITY_ASSIST
		else:
			# No slingshot, just fuel stops
			mission.outbound_waypoints = outbound_fuel_route["waypoints"].duplicate()
			mission.outbound_waypoint_colony_refs = outbound_fuel_route["colonies"].duplicate()
			mission.outbound_waypoint_fuel_amounts = outbound_fuel_route["fuel_amounts"].duplicate()
			mission.outbound_waypoint_fuel_costs = outbound_fuel_route["fuel_costs"].duplicate()
			mission.outbound_leg_times = outbound_fuel_route["leg_times"].duplicate()
			mission.outbound_waypoint_types = []
			for i in range(outbound_fuel_route["waypoints"].size()):
				mission.outbound_waypoint_types.append(Mission.WaypointType.REFUEL_STOP)

			# Set initial transit time to first leg
			mission.transit_time = mission.outbound_leg_times[0] if mission.outbound_leg_times.size() > 0 else mission.transit_time

		# Deduct total fuel cost upfront
		money -= outbound_fuel_route["total_cost"]

	# Calculate return fuel stops separately (assume full cargo)
	var expected_cargo_return := ship.cargo_capacity
	var return_fuel_route := FuelRoutePlanner.plan_route_to_position(
		ship,
		mission.return_position_au,
		expected_cargo_return,
		3
	)

	if return_fuel_route["feasible"] and return_fuel_route["waypoints"].size() > 0:
		mission.return_waypoints = return_fuel_route["waypoints"].duplicate()
		mission.return_waypoint_colony_refs = return_fuel_route["colonies"].duplicate()
		mission.return_waypoint_fuel_amounts = return_fuel_route["fuel_amounts"].duplicate()
		mission.return_waypoint_fuel_costs = return_fuel_route["fuel_costs"].duplicate()
		mission.return_leg_times = return_fuel_route["leg_times"].duplicate()
		mission.return_waypoint_types = []
		for i in range(return_fuel_route["waypoints"].size()):
			mission.return_waypoint_types.append(Mission.WaypointType.REFUEL_STOP)

		# Deduct return fuel cost upfront
		money -= return_fuel_route["total_cost"]

	# Apply pilot skill modifier to transit time
	var best_pilot := 0.0
	for w in assigned_workers:
		if w.pilot_skill > best_pilot:
			best_pilot = w.pilot_skill
	var pilot_factor := 1.15 - (best_pilot * 0.2)  # 0.0 = 1.15x slower, 1.0 = 0.95x, 1.5 = 0.85x
	mission.transit_time *= pilot_factor

	mission.elapsed_ticks = 0.0

	# Calculate mining duration: time to fill cargo hold (uses mining_skill)
	var skill_total := 0.0
	for w in assigned_workers:
		skill_total += w.mining_skill
	if skill_total < 0.1:
		skill_total = 0.1
	var equip_mult := ship.get_mining_multiplier()
	var total_yield_per_tick := 0.0
	for ore_type in asteroid.ore_yields:
		var base_yield: float = asteroid.ore_yields[ore_type]
		total_yield_per_tick += base_yield * skill_total * equip_mult * Simulation.BASE_MINING_RATE
	if total_yield_per_tick > 0:
		mission.mining_duration = ship.cargo_capacity / total_yield_per_tick
	else:
		mission.mining_duration = 86400.0  # Fallback: 1 day

	# Calculate fuel burn rate
	if slingshot_route:
		# Use pre-calculated fuel cost from slingshot route
		var total_fuel: float = slingshot_route.fuel_cost
		var total_transit_ticks: float = slingshot_route.transit_time * 2.0  # Outbound + return
		mission.fuel_per_tick = total_fuel / total_transit_ticks if total_transit_ticks > 0 else 0.0
	else:
		# Standard fuel calculation
		var current_cargo_mass := ship.get_cargo_total()
		var fuel_outbound := ship.calc_fuel_for_distance(dist, current_cargo_mass)
		var fuel_return := ship.calc_fuel_for_distance(dist, ship.cargo_capacity)
		var total_fuel := fuel_outbound + fuel_return

		# Apply Hohmann fuel savings
		if transit_mode == Mission.TransitMode.HOHMANN:
			total_fuel *= Brachistochrone.hohmann_fuel_multiplier()

		var total_transit_ticks := mission.transit_time * 2.0
		mission.fuel_per_tick = total_fuel / total_transit_ticks if total_transit_ticks > 0 else 0.0

	ship.current_mission = mission
	# Stationed ships keep existing cargo (they accumulate over multiple mining runs)
	if not ship.is_stationed:
		ship.current_cargo.clear()
	ship.docked_at_colony = null  # Ship is departing
	ship.reset_life_support(assigned_workers.size())  # Reset life support based on crew
	for w in assigned_workers:
		w.assigned_mission = mission

	missions.append(mission)
	EventBus.mission_started.emit(mission)

	# Check if any hitchhiking workers can catch this ride
	var route_points: Array[Vector2] = [asteroid.get_position_au()]
	check_hitchhike_opportunities(ship, route_points)

	return mission

func complete_mission(mission: Mission) -> void:
	# Stationed ships keep cargo (they sell via trade mission autonomously)
	if mission.ship.is_stationed:
		# Don't transfer cargo, ship keeps it for trading
		pass
	elif mission.ship.is_at_earth:
		# Transfer cargo from ship to stockpile (only if returning to Earth)
		for ore_type in mission.ship.current_cargo:
			add_resource(ore_type, mission.ship.current_cargo[ore_type])
		mission.ship.current_cargo.clear()

	mission.ship.current_mission = null

	for w in mission.workers:
		w.assigned_mission = null

	mission.status = Mission.Status.COMPLETED
	EventBus.mission_completed.emit(mission)
	missions.erase(mission)

	# Stationed ships don't use queued missions — station logic handles next job
	if mission.ship.is_stationed:
		return

	# Check for queued mission and auto-start it
	if mission.ship.has_queued_mission():
		_start_queued_mission(mission.ship)

func _name_for_position(pos: Vector2) -> String:
	# Find nearest colony
	var best_name := ""
	var best_dist := 0.2  # Must be within 0.2 AU to count
	for colony in colonies:
		var d := pos.distance_to(colony.get_position_au())
		if d < best_dist:
			best_dist = d
			best_name = colony.colony_name
	if best_name != "":
		return best_name
	# Check near Earth
	if pos.distance_to(CelestialData.get_earth_position_au()) < 0.1:
		return "Earth"
	# Check near planets
	for i in range(CelestialData.PLANETS.size()):
		var planet_pos := CelestialData.get_planet_position_au(i)
		if pos.distance_to(planet_pos) < 0.3:
			return CelestialData.PLANETS[i]["name"]
	return "deep space"

func order_return_to_earth(ship: Ship) -> void:
	# Start a transit-back mission from current idle position to Earth
	if not ship.is_idle_remote:
		return

	var earth_pos := CelestialData.get_earth_position_au()
	var dist := ship.position_au.distance_to(earth_pos)

	if ship.current_mission:
		# Reuse existing mission for return
		ship.current_mission.return_position_au = earth_pos
		ship.current_mission.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())
		ship.current_mission.elapsed_ticks = 0.0
		var cargo_mass := ship.get_cargo_total()
		var total_fuel := ship.calc_fuel_for_distance(dist, cargo_mass)
		ship.current_mission.fuel_per_tick = total_fuel / ship.current_mission.transit_time if ship.current_mission.transit_time > 0 else 0.0
		ship.current_mission.status = Mission.Status.TRANSIT_BACK
		EventBus.mission_phase_changed.emit(ship.current_mission)
	elif ship.current_trade_mission:
		ship.current_trade_mission.return_position_au = earth_pos
		ship.current_trade_mission.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())
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
		mission.origin_is_earth = false  # Ship is stranded somewhere, not at Earth
		mission.return_position_au = earth_pos
		mission.destination_name = _name_for_position(ship.position_au)
		mission.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())
		mission.elapsed_ticks = 0.0
		var cargo_mass := ship.get_cargo_total()
		var total_fuel := ship.calc_fuel_for_distance(dist, cargo_mass)
		mission.fuel_per_tick = total_fuel / mission.transit_time if mission.transit_time > 0 else 0.0
		ship.current_mission = mission
		missions.append(mission)
		EventBus.mission_started.emit(mission)

func dispatch_idle_ship(ship: Ship, asteroid: AsteroidData, assigned_workers: Array[Worker], transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
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
		w.assigned_trade_mission = null

	var mission := start_mission(ship, asteroid, assigned_workers, transit_mode, slingshot_route)
	mission.origin_is_earth = false  # Ship is dispatched from a remote location, not Earth
	return mission

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
		w.assigned_trade_mission = null

	var tm := start_trade_mission(ship, colony_target, assigned_workers, cargo_to_load, transit_mode)
	tm.origin_is_earth = false  # Ship is dispatched from a remote location, not Earth
	return tm

const RESCUE_COST_BASE: int = 20000  # Crew wages, equipment, opportunity cost — even nearby rescues are expensive
const RESCUE_COST_PER_AU: int = 8000  # Fuel + extended crew time for distance
const RESCUE_COST_PER_KMS: int = 5000  # Velocity-matching difficulty
const REFUEL_COST_BASE: int = 5000  # Base dispatch cost for a tanker
const REFUEL_COST_PER_AU: int = 4000  # Tanker fuel + crew time

func _find_nearest_rescue_source(ship_pos: Vector2) -> Dictionary:
	# Returns { "name": String, "pos": Vector2, "dist": float }
	var earth_pos := CelestialData.get_earth_position_au()
	var best_name := "Earth"
	var best_pos := earth_pos
	var best_dist := ship_pos.distance_to(earth_pos)

	for colony in colonies:
		if not colony.has_rescue_ops:
			continue
		var colony_pos := colony.get_position_au()
		var d := ship_pos.distance_to(colony_pos)
		if d < best_dist:
			best_dist = d
			best_pos = colony_pos
			best_name = colony.colony_name

	return { "name": best_name, "pos": best_pos, "dist": best_dist }

## Calculate rescue feasibility and cost
## Returns: { "feasible": bool, "cost": int, "time": float, "reason": String, "crew_survives": bool }
func calculate_rescue_info(ship: Ship) -> Dictionary:
	var source := _find_nearest_rescue_source(ship.position_au)

	# Rescue ship specs: upgraded hauler for rescue operations
	var rescue_accel_g := 0.45  # Upgraded engines
	var rescue_fuel_capacity := 550.0  # Most cargo space converted to fuel

	# Calculate intercept
	var intercept := Brachistochrone.calculate_rescue_intercept(
		source["pos"],           # Rescue starting position
		rescue_accel_g,          # Rescue ship acceleration
		rescue_fuel_capacity,    # Rescue ship fuel capacity
		ship.position_au,        # Derelict position
		ship.velocity_au_per_tick  # Derelict velocity
	)

	# Check if crew will survive the rescue time
	var crew_survives: bool = ship.life_support_remaining >= intercept["time"]

	# Calculate cost based on fuel used, time, and risk
	var fuel_cost_for_rescue := int(intercept["fuel"] * Ship.FUEL_COST_PER_UNIT)
	var crew_time_cost := int(intercept["time"] / 3600.0 * 500.0)  # $500/hour crew time
	var risk_premium := int(intercept.get("velocity_match_km_s", 0.0) * 100.0)  # High velocity = risky
	var fuel_transfer := ship.get_effective_fuel_capacity() * 0.5
	var fuel_transfer_cost := int(fuel_transfer * Ship.FUEL_COST_PER_UNIT)

	var total_cost := RESCUE_COST_BASE + fuel_cost_for_rescue + crew_time_cost + risk_premium + fuel_transfer_cost

	# Determine final feasibility and reason
	var feasible: bool = intercept["feasible"] and crew_survives
	var reason: String = intercept["reason"]

	if intercept["feasible"] and not crew_survives:
		var hours_short := int((intercept["time"] - ship.life_support_remaining) / 3600.0)
		reason = "Crew will run out of life support %d hours before rescue arrives" % hours_short
		feasible = false

	return {
		"feasible": feasible,
		"cost": total_cost,
		"time": intercept["time"],
		"reason": reason,
		"crew_survives": crew_survives,
		"intercept_info": intercept
	}

func get_rescue_cost(ship: Ship) -> int:
	var info := calculate_rescue_info(ship)
	return info["cost"]

func get_refuel_cost(ship: Ship, fuel_amount: float) -> int:
	var source := _find_nearest_rescue_source(ship.position_au)
	var distance_cost := REFUEL_COST_BASE + int(source["dist"] * REFUEL_COST_PER_AU)
	var fuel_cost := int(fuel_amount * Ship.FUEL_COST_PER_UNIT)
	return distance_cost + fuel_cost

func start_rescue(ship: Ship) -> bool:
	if not ship.is_derelict:
		return false
	if ship in rescue_missions:
		return false

	# Calculate rescue feasibility and cost
	var rescue_info := calculate_rescue_info(ship)

	# Check if rescue is even possible
	if not rescue_info["feasible"]:
		# Emit event with failure reason
		EventBus.rescue_impossible.emit(ship, rescue_info["reason"])
		return false

	var cost: int = rescue_info["cost"]

	if money < cost:
		return false

	money -= cost

	var source := _find_nearest_rescue_source(ship.position_au)

	rescue_missions[ship] = {
		"elapsed_ticks": 0.0,
		"transit_time": rescue_info["time"],
		"workers": ship.last_crew.duplicate(),
		"source_name": source["name"],
		"source_pos": source["pos"],
	}

	EventBus.rescue_mission_started.emit(ship, cost)
	return true

func start_refuel(ship: Ship, fuel_amount: float) -> bool:
	# Can refuel ships that are out of fuel, but not broken down ships (those need rescue)
	if ship.is_derelict and ship.derelict_reason != "out_of_fuel":
		return false  # Broken ships need rescue, not just refuel
	if ship in refuel_missions:
		return false  # Already has refuel in progress

	var source := _find_nearest_rescue_source(ship.position_au)
	var dist: float = source["dist"]

	# Cost: base dispatch + distance charge + fuel cost
	var distance_cost := REFUEL_COST_BASE + int(dist * REFUEL_COST_PER_AU)
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
		"source_name": source["name"],
		"source_pos": source["pos"],
	}

	EventBus.refuel_mission_started.emit(ship, total_cost, fuel_amount)
	return true

# --- Stranger rescue methods ---

func accept_stranger_rescue(ship: Ship, pay_tip: bool) -> void:
	if ship not in stranger_offers:
		return
	var offer: Dictionary = stranger_offers[ship]
	var stranger_name: String = offer["stranger_name"]

	# Restore ship in place — stranger matched course, ship keeps velocity
	ship.is_derelict = false
	ship.derelict_reason = ""
	ship.engine_condition = 40.0
	ship.fuel = ship.get_effective_fuel_capacity() * 0.25
	# Cargo preserved, no worker loss

	if pay_tip:
		var tip: int = offer["suggested_tip"]
		money -= tip
		Reputation.modify(5.0)
	else:
		Reputation.modify(-10.0)

	stranger_offers.erase(ship)
	EventBus.stranger_rescue_completed.emit(ship, stranger_name)

func decline_stranger_rescue(ship: Ship) -> void:
	if ship not in stranger_offers:
		return
	var offer: Dictionary = stranger_offers[ship]
	var stranger_name: String = offer["stranger_name"]
	stranger_offers.erase(ship)
	EventBus.stranger_rescue_declined.emit(ship, stranger_name)

# --- Station management ---

func station_ship(ship: Ship, colony: Colony, jobs: Array[String]) -> void:
	ship.is_stationed = true
	ship.station_colony = colony
	ship.station_jobs = jobs.duplicate()
	ship.station_log.clear()
	# Ensure ship has a crew assigned (use last_crew or auto-assign from available)
	if ship.last_crew.is_empty() or ship.last_crew.size() < ship.min_crew:
		var available := get_available_workers()
		ship.last_crew.clear()
		for i in range(mini(ship.min_crew, available.size())):
			available[i].assigned_station_ship = ship
			ship.last_crew.append(available[i])
	else:
		for w in ship.last_crew:
			w.assigned_station_ship = ship
	ship.add_station_log("Stationed at %s" % colony.colony_name, "system")
	EventBus.ship_stationed.emit(ship, colony)

func unstation_ship(ship: Ship) -> void:
	for w in ship.last_crew:
		w.assigned_station_ship = null
	ship.is_stationed = false
	ship.add_station_log("Unstationed", "system")
	ship.station_colony = null
	ship.station_jobs.clear()
	EventBus.ship_unstationed.emit(ship)

func update_station_jobs(ship: Ship, jobs: Array[String]) -> void:
	ship.station_jobs = jobs.duplicate()
	ship.add_station_log("Jobs updated: %s" % ", ".join(jobs), "system")

func buy_supplies(ship: Ship, supply_key: String, amount: float) -> bool:
	# Find supply type from key
	var cost_per_unit := 0
	var mass_per_unit := 0.0
	for supply_type in SupplyData.SUPPLY_INFO:
		var info: Dictionary = SupplyData.SUPPLY_INFO[supply_type]
		if info["key"] == supply_key:
			cost_per_unit = info["cost_per_unit"]
			mass_per_unit = info["mass_per_unit"]
			break

	if cost_per_unit <= 0:
		return false

	var total_mass := amount * mass_per_unit
	# Check cargo capacity (supplies share space with ore)
	var available_space := ship.get_cargo_remaining() - ship.get_supplies_mass()
	if total_mass > available_space + 0.01:
		return false

	var total_cost := int(amount * cost_per_unit)
	if money < total_cost:
		return false

	money -= total_cost
	record_transaction(-total_cost, "Supplies: %s ×%.1f" % [supply_key, amount], ship.ship_name)
	ship.supplies[supply_key] = ship.supplies.get(supply_key, 0.0) + amount
	return true

# --- Deployed crew methods ---

func deploy_crew(asteroid: AsteroidData, crew_workers: Array[Worker], initial_supplies: Dictionary) -> void:
	# Remove workers from available pool
	for w in crew_workers:
		w.assigned_mission = null  # They're deployed, not on a mission
	var entry: Dictionary = {
		"asteroid": asteroid,
		"workers": crew_workers.duplicate(),
		"supplies": initial_supplies.duplicate(),
		"deployed_at": total_ticks,
	}
	deployed_crews.append(entry)
	EventBus.crew_deployed.emit(asteroid, crew_workers)

func recall_crew(asteroid: AsteroidData) -> void:
	for i in range(deployed_crews.size() - 1, -1, -1):
		var entry: Dictionary = deployed_crews[i]
		if entry["asteroid"] == asteroid:
			var crew_workers: Array = entry["workers"]
			EventBus.crew_recalled.emit(asteroid, crew_workers)
			deployed_crews.remove_at(i)
			break

func get_deployed_crew_at(asteroid: AsteroidData) -> Dictionary:
	for entry in deployed_crews:
		if entry["asteroid"] == asteroid:
			return entry
	return {}

# --- Hitchhike & discipline methods ---

func _get_colony_position(colony_name: String) -> Vector2:
	if colony_name == "Earth":
		return CelestialData.get_earth_position_au()
	for colony in colonies:
		if colony.colony_name == colony_name:
			return colony.get_position_au()
	return CelestialData.get_earth_position_au()  # Fallback

func add_to_hitchhike_pool(worker: Worker, location_name: String, location_pos: Vector2) -> void:
	# 35% chance worker stays put (doesn't want to go home)
	if randf() < 0.35:
		worker.leave_status = 1  # Just on leave, no ride wanted
		return
	# Skip if worker's home IS this location
	if worker.home_colony == location_name:
		worker.leave_status = 1
		return
	# Skip duplicates
	for entry in hitchhike_pool:
		if entry["worker"] == worker:
			return
	worker.leave_status = 2
	var max_wait := randf_range(7.0, 14.0) * 86400.0  # 7-14 game-days in ticks
	hitchhike_pool.append({
		"worker": worker,
		"location_name": location_name,
		"location_pos": location_pos,
		"entered_at": total_ticks,
		"max_wait": max_wait,
	})
	EventBus.worker_waiting_for_ride.emit(worker, location_name)

func check_hitchhike_opportunities(ship: Ship, route_positions: Array[Vector2]) -> void:
	var matched: Array[Dictionary] = []
	for entry in hitchhike_pool:
		var worker: Worker = entry["worker"]
		var worker_pos: Vector2 = entry["location_pos"]
		# Must be at ship's current location (within 0.05 AU)
		if ship.position_au.distance_to(worker_pos) > 0.05:
			continue
		# Check if any route waypoint passes within 0.1 AU of worker's home colony
		var home_pos := _get_colony_position(worker.home_colony)
		for route_pos in route_positions:
			if route_pos.distance_to(home_pos) < 0.1:
				matched.append(entry)
				break
	for entry in matched:
		var worker: Worker = entry["worker"]
		hitchhike_pool.erase(entry)
		worker.leave_status = 1  # On leave (riding home)
		worker.loyalty = minf(worker.loyalty + 3.0, 100.0)
		EventBus.worker_hitched_ride.emit(worker, ship)

func forgive_tardy_worker(worker: Worker) -> void:
	for i in range(tardy_workers.size() - 1, -1, -1):
		if tardy_workers[i]["worker"] == worker:
			tardy_workers.remove_at(i)
			break
	worker.leave_status = 0
	worker.fatigue = 0.0
	worker.loyalty = minf(worker.loyalty + 5.0, 100.0)
	EventBus.worker_tardiness_resolved.emit(worker, "forgiven")

func dock_pay_tardy_worker(worker: Worker) -> void:
	for i in range(tardy_workers.size() - 1, -1, -1):
		if tardy_workers[i]["worker"] == worker:
			tardy_workers.remove_at(i)
			break
	worker.leave_status = 0
	worker.fatigue = 0.0
	worker.loyalty = maxf(worker.loyalty - 8.0, 0.0)
	# Dock 3 days wages
	money += worker.wage * 3
	EventBus.worker_tardiness_resolved.emit(worker, "docked")

func fire_tardy_worker(worker: Worker) -> void:
	for i in range(tardy_workers.size() - 1, -1, -1):
		if tardy_workers[i]["worker"] == worker:
			tardy_workers.remove_at(i)
			break
	worker.leave_status = 0
	EventBus.worker_tardiness_resolved.emit(worker, "fired")
	fire_worker(worker)

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
	tm.transit_mode = transit_mode as TradeMission.TransitMode

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
		tm.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())

	# Check if fuel stops are needed for outbound journey
	var cargo_mass := ship.get_cargo_total()
	var outbound_fuel_route := FuelRoutePlanner.plan_route_to_position(
		ship,
		colony_pos,
		cargo_mass,
		3  # max stops
	)

	if outbound_fuel_route["feasible"] and outbound_fuel_route["waypoints"].size() > 0:
		# Need fuel stops
		tm.outbound_waypoints = outbound_fuel_route["waypoints"].duplicate()
		tm.outbound_waypoint_colony_refs = outbound_fuel_route["colonies"].duplicate()
		tm.outbound_waypoint_fuel_amounts = outbound_fuel_route["fuel_amounts"].duplicate()
		tm.outbound_waypoint_fuel_costs = outbound_fuel_route["fuel_costs"].duplicate()
		tm.outbound_leg_times = outbound_fuel_route["leg_times"].duplicate()
		tm.outbound_waypoint_types = []
		for i in range(outbound_fuel_route["waypoints"].size()):
			tm.outbound_waypoint_types.append(TradeMission.WaypointType.REFUEL_STOP)

		# Set initial transit time to first leg
		tm.transit_time = tm.outbound_leg_times[0] if tm.outbound_leg_times.size() > 0 else tm.transit_time

		# Deduct total fuel cost upfront
		money -= outbound_fuel_route["total_cost"]

	# Calculate return fuel stops (empty cargo after selling)
	var return_fuel_route := FuelRoutePlanner.plan_route_to_position(
		ship,
		tm.return_position_au,
		0.0,  # Empty after selling
		3
	)

	if return_fuel_route["feasible"] and return_fuel_route["waypoints"].size() > 0:
		tm.return_waypoints = return_fuel_route["waypoints"].duplicate()
		tm.return_waypoint_colony_refs = return_fuel_route["colonies"].duplicate()
		tm.return_waypoint_fuel_amounts = return_fuel_route["fuel_amounts"].duplicate()
		tm.return_waypoint_fuel_costs = return_fuel_route["fuel_costs"].duplicate()
		tm.return_leg_times = return_fuel_route["leg_times"].duplicate()
		tm.return_waypoint_types = []
		for i in range(return_fuel_route["waypoints"].size()):
			tm.return_waypoint_types.append(TradeMission.WaypointType.REFUEL_STOP)

		# Deduct return fuel cost upfront
		money -= return_fuel_route["total_cost"]

	# Apply pilot skill modifier to transit time
	var best_pilot := 0.0
	for w in assigned_workers:
		if w.pilot_skill > best_pilot:
			best_pilot = w.pilot_skill
	# Also check last_crew for trade missions (workers aren't locked)
	for w in ship.last_crew:
		if w.pilot_skill > best_pilot:
			best_pilot = w.pilot_skill
	var pilot_factor := 1.15 - (best_pilot * 0.2)
	tm.transit_time *= pilot_factor

	tm.elapsed_ticks = 0.0

	# Fuel calculation: loaded outbound (with cargo), empty return
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
	ship.docked_at_colony = null  # Ship is departing
	ship.reset_life_support(assigned_workers.size())  # Reset life support based on crew
	for w in assigned_workers:
		w.assigned_trade_mission = tm

	trade_missions.append(tm)
	EventBus.trade_mission_started.emit(tm)

	# Check if any hitchhiking workers can catch this ride
	var trade_route_points: Array[Vector2] = [colony_target.get_position_au()]
	check_hitchhike_opportunities(ship, trade_route_points)

	return tm

func complete_trade_mission(tm: TradeMission) -> void:
	tm.ship.current_cargo.clear()
	tm.ship.current_trade_mission = null
	for w in tm.workers:
		w.assigned_trade_mission = null
	tm.status = TradeMission.Status.COMPLETED
	EventBus.trade_mission_completed.emit(tm)
	trade_missions.erase(tm)

	# Stationed ships don't use queued missions — station logic handles next job
	if tm.ship.is_stationed:
		return

	# Check for queued mission and auto-start it
	if tm.ship.has_queued_mission():
		_start_queued_mission(tm.ship)

func _start_queued_mission(ship: Ship) -> void:
	# Automatically start a queued mission
	if not ship.has_queued_mission():
		return

	var dest = ship.queued_destination
	var workers_array = ship.queued_workers
	var transit_mode = ship.queued_transit_mode
	var slingshot_route = ship.queued_slingshot_route

	# Clear the queue before starting (to avoid recursion)
	ship.clear_queued_mission()

	# Start the appropriate mission type based on destination
	if dest is AsteroidData:
		# Mining mission
		start_mission(ship, dest, workers_array, transit_mode, slingshot_route)
	elif dest is Colony:
		# Trade mission (if ship has cargo)
		if ship.get_cargo_total() > 0:
			start_trade_mission(ship, dest, workers_array, transit_mode, slingshot_route)
		else:
			# No cargo, can't trade - mission cancelled
			print("Queued trade mission cancelled: ship has no cargo")

# Save/Load
func save_game() -> void:
	var save_data := {
		"money": money,
		"total_ticks": total_ticks,
		"thrust_policy": thrust_policy,
		"resources": {},
		"workers": [],
		"ships": [],
		"market_prices": {},
		"missions": [],
		"trade_missions": [],
		"available_contracts": [],
		"active_contracts": [],
		"market_events": [],
		"fabrication_queue": [],
		"reputation": Reputation.score,
		"rescue_missions": {},
		"refuel_missions": {},
		"stranger_offers": {},
	}
	for ore_type in resources:
		save_data["resources"][str(ore_type)] = resources[ore_type]
	if market:
		for ore_type in market.current_prices:
			save_data["market_prices"][str(ore_type)] = market.current_prices[ore_type]
	for w in workers:
		save_data["workers"].append({
			"name": w.worker_name,
			"pilot_skill": w.pilot_skill,
			"engineer_skill": w.engineer_skill,
			"mining_skill": w.mining_skill,
			"pilot_xp": w.pilot_xp,
			"engineer_xp": w.engineer_xp,
			"mining_xp": w.mining_xp,
			"wage": w.wage,
			"fatigue": w.fatigue,
			"days_deployed": w.days_deployed,
			"is_injured": w.is_injured,
			"home_colony": w.home_colony,
			"loyalty": w.loyalty,
			"hired_at": w.hired_at,
			"leave_status": w.leave_status,
			"personality": w.personality,
		})
	for s in ships:
		var ship_data := {
			"name": s.ship_name,
			"max_thrust_g": s.max_thrust_g,
			"thrust_setting": s.thrust_setting,
			"ship_class": s.ship_class,
			"cargo_capacity": s.cargo_capacity,
			"cargo_volume": s.cargo_volume,
			"position_au_x": s.position_au.x,
			"position_au_y": s.position_au.y,
			"engine_condition": s.engine_condition,
			"is_derelict": s.is_derelict,
			"derelict_reason": s.derelict_reason,
			"velocity_au_x": s.velocity_au_per_tick.x,
			"velocity_au_y": s.velocity_au_per_tick.y,
			"fuel": s.fuel,
			"fuel_capacity": s.fuel_capacity,
			"equipment": [],
		}
		# Station data
		if s.is_stationed:
			ship_data["is_stationed"] = true
			ship_data["station_colony_name"] = s.station_colony.colony_name if s.station_colony else ""
			ship_data["station_jobs"] = s.station_jobs.duplicate()
			ship_data["station_log"] = s.station_log.duplicate()
		# Supplies
		if not s.supplies.is_empty():
			ship_data["supplies"] = s.supplies.duplicate()
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

	# Save missions
	for m in missions:
		save_data["missions"].append({
			"ship_name": m.ship.ship_name,
			"asteroid_name": m.asteroid.asteroid_name if m.asteroid else "",
			"status": m.status,
			"mission_type": m.mission_type,
			"return_to_station": m.return_to_station,
			"origin_is_earth": m.origin_is_earth,
			"elapsed_ticks": m.elapsed_ticks,
			"transit_time": m.transit_time,
			"mining_duration": m.mining_duration,
			"fuel_per_tick": m.fuel_per_tick,
			"station_job_duration": m.station_job_duration,
			"destination_position_au_x": m.destination_position_au.x,
			"destination_position_au_y": m.destination_position_au.y,
			"destination_name": m.destination_name,
			"return_position_au_x": m.return_position_au.x,
			"return_position_au_y": m.return_position_au.y,
			"workers": m.workers.map(func(w): return w.worker_name),
			"outbound_waypoint_types": m.outbound_waypoint_types,
			"outbound_waypoint_fuel_amounts": m.outbound_waypoint_fuel_amounts,
			"outbound_waypoint_fuel_costs": m.outbound_waypoint_fuel_costs,
			"outbound_waypoint_colony_names": m.outbound_waypoint_colony_refs.map(func(c): return c.colony_name if c else ""),
			"return_waypoint_types": m.return_waypoint_types,
			"return_waypoint_fuel_amounts": m.return_waypoint_fuel_amounts,
			"return_waypoint_fuel_costs": m.return_waypoint_fuel_costs,
			"return_waypoint_colony_names": m.return_waypoint_colony_refs.map(func(c): return c.colony_name if c else ""),
		})

	# Save trade missions
	for tm in trade_missions:
		var cargo_data := {}
		for ore_type in tm.cargo:
			cargo_data[str(ore_type)] = tm.cargo[ore_type]
		save_data["trade_missions"].append({
			"ship_name": tm.ship.ship_name,
			"colony_name": tm.colony.colony_name if tm.colony else "",
			"status": tm.status,
			"elapsed_ticks": tm.elapsed_ticks,
			"transit_time": tm.transit_time,
			"fuel_per_tick": tm.fuel_per_tick,
			"cargo": cargo_data,
			"origin_position_au": {"x": tm.origin_position_au.x, "y": tm.origin_position_au.y},
			"origin_is_earth": tm.origin_is_earth,
			"return_position_au": {"x": tm.return_position_au.x, "y": tm.return_position_au.y},
			"transit_mode": tm.transit_mode,
			"revenue": tm.revenue,
			"workers": tm.workers.map(func(w): return w.worker_name),
			"outbound_waypoint_types": tm.outbound_waypoint_types,
			"outbound_waypoint_fuel_amounts": tm.outbound_waypoint_fuel_amounts,
			"outbound_waypoint_fuel_costs": tm.outbound_waypoint_fuel_costs,
			"outbound_waypoint_colony_names": tm.outbound_waypoint_colony_refs.map(func(c): return c.colony_name if c else ""),
			"return_waypoint_types": tm.return_waypoint_types,
			"return_waypoint_fuel_amounts": tm.return_waypoint_fuel_amounts,
			"return_waypoint_fuel_costs": tm.return_waypoint_fuel_costs,
			"return_waypoint_colony_names": tm.return_waypoint_colony_refs.map(func(c): return c.colony_name if c else ""),
		})

	# Save contracts
	for c in available_contracts:
		save_data["available_contracts"].append({
			"ore_type": c.ore_type,
			"quantity": c.quantity,
			"reward": c.reward,
			"deadline_ticks": c.deadline_ticks,
			"issuer": c.issuer_name,
			"colony_name": c.delivery_colony.colony_name if c.delivery_colony else "",
			"allows_partial": c.allows_partial,
		})
	for c in active_contracts:
		save_data["active_contracts"].append({
			"ore_type": c.ore_type,
			"quantity": c.quantity,
			"quantity_delivered": c.quantity_delivered,
			"reward": c.reward,
			"deadline_ticks": c.deadline_ticks,
			"issuer": c.issuer_name,
			"colony_name": c.delivery_colony.colony_name if c.delivery_colony else "",
			"allows_partial": c.allows_partial,
		})

	# Save market events
	for e in active_market_events:
		save_data["market_events"].append({
			"type": e.type,
			"ore_types": e.affected_ore_types.map(func(ot): return int(ot)),
			"multiplier": e.price_multiplier,
			"remaining": e.remaining_ticks,
			"message": e.message,
			"colony_name": e.affected_colony.colony_name if e.affected_colony else "",
		})

	# Save fabrication queue
	for eq in fabrication_queue:
		save_data["fabrication_queue"].append({
			"name": eq.equipment_name,
			"type": eq.type,
			"bonus": eq.mining_bonus,
			"cost": eq.cost,
			"durability": eq.durability,
		})

	# Save rescue/refuel missions (ship name -> data)
	for ship in rescue_missions:
		var rm_data = rescue_missions[ship]
		save_data["rescue_missions"][ship.ship_name] = {
			"elapsed": rm_data["elapsed_ticks"],
			"transit": rm_data["transit_time"],
			"source": rm_data["source_name"],
		}
	for ship in refuel_missions:
		var rf_data = refuel_missions[ship]
		save_data["refuel_missions"][ship.ship_name] = {
			"elapsed": rf_data["elapsed_ticks"],
			"transit": rf_data["transit_time"],
			"fuel": rf_data["fuel_amount"],
			"source": rf_data["source_name"],
		}

	# Save stranger offers
	for ship in stranger_offers:
		var so_data = stranger_offers[ship]
		save_data["stranger_offers"][ship.ship_name] = {
			"name": so_data["stranger_name"],
			"expires": so_data["expires_ticks"],
			"tip": so_data["suggested_tip"],
		}

	# Save deployed crews
	var deployed_crews_data: Array[Dictionary] = []
	for entry in deployed_crews:
		var asteroid: AsteroidData = entry["asteroid"]
		var worker_names: Array[String] = []
		for w in entry["workers"]:
			worker_names.append(w.worker_name)
		deployed_crews_data.append({
			"asteroid_name": asteroid.asteroid_name,
			"worker_names": worker_names,
			"supplies": entry["supplies"].duplicate(),
			"deployed_at": entry["deployed_at"],
		})
	save_data["deployed_crews"] = deployed_crews_data

	# Save mining unit inventory
	var mu_inventory_data: Array[Dictionary] = []
	for unit in mining_unit_inventory:
		mu_inventory_data.append({
			"unit_type": unit.unit_type,
			"unit_name": unit.unit_name,
			"mass": unit.mass,
			"volume": unit.volume,
			"workers_required": unit.workers_required,
			"mining_multiplier": unit.mining_multiplier,
			"durability": unit.durability,
			"max_durability": unit.max_durability,
			"wear_per_day": unit.wear_per_day,
			"cost": unit.cost,
		})
	save_data["mining_unit_inventory"] = mu_inventory_data

	# Save deployed mining units
	var mu_deployed_data: Array[Dictionary] = []
	for unit in deployed_mining_units:
		var worker_names: Array[String] = []
		for w in unit.assigned_workers:
			worker_names.append(w.worker_name)
		mu_deployed_data.append({
			"unit_type": unit.unit_type,
			"unit_name": unit.unit_name,
			"mass": unit.mass,
			"volume": unit.volume,
			"workers_required": unit.workers_required,
			"mining_multiplier": unit.mining_multiplier,
			"durability": unit.durability,
			"max_durability": unit.max_durability,
			"wear_per_day": unit.wear_per_day,
			"cost": unit.cost,
			"deployed_at_asteroid": unit.deployed_at_asteroid,
			"deployed_at_tick": unit.deployed_at_tick,
			"worker_names": worker_names,
		})
	save_data["deployed_mining_units"] = mu_deployed_data

	# Save ore stockpiles
	var stockpile_data := {}
	for asteroid_name in ore_stockpiles:
		var pile: Dictionary = ore_stockpiles[asteroid_name]
		var serialized_pile := {}
		for ore_type in pile:
			serialized_pile[str(ore_type)] = pile[ore_type]
		stockpile_data[asteroid_name] = serialized_pile
	save_data["ore_stockpiles"] = stockpile_data

	# Save asteroid supplies
	save_data["asteroid_supplies"] = asteroid_supplies.duplicate(true)

	# Save hitchhike pool
	var hitchhike_data: Array[Dictionary] = []
	for entry in hitchhike_pool:
		var w: Worker = entry["worker"]
		hitchhike_data.append({
			"worker_name": w.worker_name,
			"location_name": entry["location_name"],
			"location_pos_x": entry["location_pos"].x,
			"location_pos_y": entry["location_pos"].y,
			"entered_at": entry["entered_at"],
			"max_wait": entry["max_wait"],
		})
	save_data["hitchhike_pool"] = hitchhike_data

	# Save tardy workers
	var tardy_data: Array[Dictionary] = []
	for entry in tardy_workers:
		var w: Worker = entry["worker"]
		tardy_data.append({
			"worker_name": w.worker_name,
			"reason": entry["reason"],
			"tardy_since": entry["tardy_since"],
		})
	save_data["tardy_workers"] = tardy_data

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
	thrust_policy = int(data.get("thrust_policy", CompanyPolicy.ThrustPolicy.BALANCED))

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
		# Backward compat: old saves have single "skill" → assign to mining_skill
		if wd.has("pilot_skill"):
			w.pilot_skill = float(wd.get("pilot_skill", 0.0))
			w.engineer_skill = float(wd.get("engineer_skill", 0.0))
			w.mining_skill = float(wd.get("mining_skill", 0.0))
		else:
			w.mining_skill = float(wd.get("skill", 1.0))
			w.pilot_skill = 0.0
			w.engineer_skill = 0.0
		# Load XP (default to 0.0 for old saves)
		w.pilot_xp = float(wd.get("pilot_xp", 0.0))
		w.engineer_xp = float(wd.get("engineer_xp", 0.0))
		w.mining_xp = float(wd.get("mining_xp", 0.0))
		w.wage = int(wd.get("wage", 100))
		w.fatigue = float(wd.get("fatigue", 0.0))
		w.days_deployed = float(wd.get("days_deployed", 0.0))
		w.is_injured = wd.get("is_injured", false)
		w.home_colony = wd.get("home_colony", "Earth")
		w.loyalty = float(wd.get("loyalty", 50.0))
		w.hired_at = float(wd.get("hired_at", 0.0))
		w.leave_status = int(wd.get("leave_status", 0))
		w.personality = int(wd.get("personality", Worker.Personality.LOYAL))
		workers.append(w)

	ships.clear()
	for sd in data.get("ships", []):
		var s := Ship.new()
		s.ship_name = sd.get("name", "Ship")
		# Backward compatibility: old saves have thrust_g, new saves have max_thrust_g
		if sd.has("max_thrust_g"):
			s.max_thrust_g = float(sd.get("max_thrust_g", 0.3))
			s.thrust_setting = float(sd.get("thrust_setting", 1.0))
		else:
			# Old save: convert thrust_g to max_thrust_g at 100%
			s.max_thrust_g = float(sd.get("thrust_g", 0.3))
			s.thrust_setting = 1.0
		s.ship_class = int(sd.get("ship_class", -1))
		s.cargo_capacity = float(sd.get("cargo_capacity", 100.0))
		# Default cargo_volume from class stats for backward compatibility with old saves
		var _class_vol: float = ShipData.CLASS_STATS.get(s.ship_class, {}).get("cargo_volume", 143.0)
		s.cargo_volume = float(sd.get("cargo_volume", _class_vol))
		s.fuel_capacity = float(sd.get("fuel_capacity", 200.0))
		s.fuel = float(sd.get("fuel", 200.0))
		s.position_au = Vector2(
			float(sd.get("position_au_x", 0.0)),
			float(sd.get("position_au_y", 0.0))
		)
		s.engine_condition = float(sd.get("engine_condition", 100.0))
		s.is_derelict = sd.get("is_derelict", false)
		s.derelict_reason = sd.get("derelict_reason", "")
		# Restore velocity for drifting derelicts
		s.velocity_au_per_tick = Vector2(
			float(sd.get("velocity_au_x", 0.0)),
			float(sd.get("velocity_au_y", 0.0))
		)
		s.speed_au_per_tick = s.velocity_au_per_tick.length()
		# Restore cargo
		var cargo_data: Dictionary = sd.get("cargo", {})
		for key in cargo_data:
			s.current_cargo[int(key)] = float(cargo_data[key])
		# Restore supplies
		var supplies_data: Dictionary = sd.get("supplies", {})
		for key in supplies_data:
			s.supplies[key] = float(supplies_data[key])
		# Restore station data (colony ref reconnected after colonies are loaded)
		s.is_stationed = sd.get("is_stationed", false)
		if s.is_stationed:
			s.station_jobs = []
			var saved_jobs: Array = sd.get("station_jobs", [])
			for job in saved_jobs:
				s.station_jobs.append(str(job))
			s.station_log = []
			var saved_log: Array = sd.get("station_log", [])
			for entry in saved_log:
				s.station_log.append(entry)
		for ed in sd.get("equipment", []):
			var e := Equipment.from_catalog(ed)
			e.durability = float(ed.get("durability", 100.0))
			e.max_durability = float(ed.get("max_durability", 100.0))
			e.fabrication_ticks = 0.0  # Already fabricated if saved
			s.equipment.append(e)
		ships.append(s)

	# Restore game clock
	total_ticks = float(data.get("total_ticks", 0.0))

	# Reconnect station colony references (colonies loaded at _ready)
	for ship in ships:
		if ship.is_stationed:
			var sd_array: Array = data.get("ships", [])
			for sd in sd_array:
				if sd.get("name", "") == ship.ship_name:
					var colony_name: String = sd.get("station_colony_name", "")
					if colony_name != "":
						for colony in colonies:
							if colony.colony_name == colony_name:
								ship.station_colony = colony
								break
					break
			# Mark stationed crew as assigned to this ship
			for w in ship.last_crew:
				w.assigned_station_ship = ship

	# Restore reputation
	if data.has("reputation"):
		Reputation.score = float(data.get("reputation", 0.0))

	# Restore missions (need to reconnect ship and asteroid references)
	missions.clear()
	for md in data.get("missions", []):
		var m := Mission.new()
		# Find ship by name
		for ship in ships:
			if ship.ship_name == md.get("ship_name", ""):
				m.ship = ship
				ship.current_mission = m
				break
		# Find asteroid by name
		for asteroid in asteroids:
			if asteroid.asteroid_name == md.get("asteroid_name", ""):
				m.asteroid = asteroid
				break
		m.status = int(md.get("status", Mission.Status.TRANSIT_OUT))
		m.mission_type = int(md.get("mission_type", Mission.MissionType.MINING))
		m.return_to_station = md.get("return_to_station", false)
		m.origin_is_earth = md.get("origin_is_earth", true)
		m.elapsed_ticks = float(md.get("elapsed_ticks", 0.0))
		m.transit_time = float(md.get("transit_time", 0.0))
		m.mining_duration = float(md.get("mining_duration", 86400.0))
		m.fuel_per_tick = float(md.get("fuel_per_tick", 0.0))
		m.station_job_duration = float(md.get("station_job_duration", 0.0))
		m.destination_position_au = Vector2(
			float(md.get("destination_position_au_x", 0.0)),
			float(md.get("destination_position_au_y", 0.0))
		)
		m.destination_name = str(md.get("destination_name", ""))
		m.return_position_au = Vector2(
			float(md.get("return_position_au_x", m.return_position_au.x)),
			float(md.get("return_position_au_y", m.return_position_au.y))
		)
		# Reconnect workers
		var worker_names: Array = md.get("workers", [])
		for wname in worker_names:
			for w in workers:
				if w.worker_name == wname:
					m.workers.append(w)
					w.assigned_mission = m
					break
		# Load waypoint metadata
		m.outbound_waypoint_types = md.get("outbound_waypoint_types", [])
		m.outbound_waypoint_fuel_amounts = md.get("outbound_waypoint_fuel_amounts", [])
		m.outbound_waypoint_fuel_costs = md.get("outbound_waypoint_fuel_costs", [])
		m.return_waypoint_types = md.get("return_waypoint_types", [])
		m.return_waypoint_fuel_amounts = md.get("return_waypoint_fuel_amounts", [])
		m.return_waypoint_fuel_costs = md.get("return_waypoint_fuel_costs", [])
		# Reconnect colony references
		var outbound_colony_names: Array = md.get("outbound_waypoint_colony_names", [])
		for colony_name in outbound_colony_names:
			var found_colony: Colony = null
			for colony in colonies:
				if colony.colony_name == colony_name:
					found_colony = colony
					break
			m.outbound_waypoint_colony_refs.append(found_colony)
		var return_colony_names: Array = md.get("return_waypoint_colony_names", [])
		for colony_name in return_colony_names:
			var found_colony: Colony = null
			for colony in colonies:
				if colony.colony_name == colony_name:
					found_colony = colony
					break
			m.return_waypoint_colony_refs.append(found_colony)
		# Mining missions require an asteroid; other types may not have one
		if m.ship and (m.asteroid or m.mission_type != Mission.MissionType.MINING):
			missions.append(m)

	# Restore trade missions
	trade_missions.clear()
	for tmd in data.get("trade_missions", []):
		var tm := TradeMission.new()
		# Find ship
		for ship in ships:
			if ship.ship_name == tmd.get("ship_name", ""):
				tm.ship = ship
				ship.current_trade_mission = tm
				break
		# Find colony
		var colony_name: String = tmd.get("colony_name", "")
		if colony_name != "":
			for colony in colonies:
				if colony.colony_name == colony_name:
					tm.colony = colony
					break
		tm.status = int(tmd.get("status", TradeMission.Status.TRANSIT_TO_COLONY))
		tm.elapsed_ticks = float(tmd.get("elapsed_ticks", 0.0))
		tm.transit_time = float(tmd.get("transit_time", 0.0))
		tm.fuel_per_tick = float(tmd.get("fuel_per_tick", 0.0))
		tm.revenue = int(tmd.get("revenue", 0))
		tm.transit_mode = int(tmd.get("transit_mode", TradeMission.TransitMode.BRACHISTOCHRONE)) as TradeMission.TransitMode

		# Restore positions
		var origin_data: Dictionary = tmd.get("origin_position_au", {})
		if origin_data.has("x") and origin_data.has("y"):
			tm.origin_position_au = Vector2(float(origin_data["x"]), float(origin_data["y"]))
		tm.origin_is_earth = tmd.get("origin_is_earth", true)
		var return_data: Dictionary = tmd.get("return_position_au", {})
		if return_data.has("x") and return_data.has("y"):
			tm.return_position_au = Vector2(float(return_data["x"]), float(return_data["y"]))

		# Restore cargo
		var cargo_data: Dictionary = tmd.get("cargo", {})
		for key in cargo_data:
			tm.cargo[int(key)] = float(cargo_data[key])

		# Restore workers
		var worker_names: Array = tmd.get("workers", [])
		for worker_name in worker_names:
			for w in workers:
				if w.worker_name == worker_name:
					tm.workers.append(w)
					w.assigned_trade_mission = tm
					break

		# Load waypoint metadata
		tm.outbound_waypoint_types = tmd.get("outbound_waypoint_types", [])
		tm.outbound_waypoint_fuel_amounts = tmd.get("outbound_waypoint_fuel_amounts", [])
		tm.outbound_waypoint_fuel_costs = tmd.get("outbound_waypoint_fuel_costs", [])
		tm.return_waypoint_types = tmd.get("return_waypoint_types", [])
		tm.return_waypoint_fuel_amounts = tmd.get("return_waypoint_fuel_amounts", [])
		tm.return_waypoint_fuel_costs = tmd.get("return_waypoint_fuel_costs", [])
		# Reconnect colony references
		var tm_outbound_colony_names: Array = tmd.get("outbound_waypoint_colony_names", [])
		for tm_colony_name in tm_outbound_colony_names:
			var tm_found_colony: Colony = null
			for colony in colonies:
				if colony.colony_name == tm_colony_name:
					tm_found_colony = colony
					break
			tm.outbound_waypoint_colony_refs.append(tm_found_colony)
		var tm_return_colony_names: Array = tmd.get("return_waypoint_colony_names", [])
		for tm_colony_name in tm_return_colony_names:
			var tm_found_colony: Colony = null
			for colony in colonies:
				if colony.colony_name == tm_colony_name:
					tm_found_colony = colony
					break
			tm.return_waypoint_colony_refs.append(tm_found_colony)

		if tm.ship:
			trade_missions.append(tm)

	# Restore contracts
	available_contracts.clear()
	for cd in data.get("available_contracts", []):
		var c := Contract.new()
		c.ore_type = int(cd.get("ore_type", 0)) as ResourceTypes.OreType
		c.quantity = float(cd.get("quantity", cd.get("amount", 100.0)))
		c.reward = int(cd.get("reward", 1000))
		c.deadline_ticks = float(cd.get("deadline_ticks", 86400.0))
		c.issuer_name = cd.get("issuer", "Unknown")
		c.allows_partial = cd.get("allows_partial", true)
		var colony_name = cd.get("colony_name", "")
		if colony_name != "":
			for colony in colonies:
				if colony.colony_name == colony_name:
					c.delivery_colony = colony
					break
		available_contracts.append(c)

	active_contracts.clear()
	for cd in data.get("active_contracts", []):
		var c := Contract.new()
		c.ore_type = int(cd.get("ore_type", 0)) as ResourceTypes.OreType
		c.quantity = float(cd.get("quantity", cd.get("amount", 100.0)))
		c.quantity_delivered = float(cd.get("quantity_delivered", cd.get("fulfilled", 0.0)))
		c.reward = int(cd.get("reward", 1000))
		c.deadline_ticks = float(cd.get("deadline_ticks", 86400.0))
		c.issuer_name = cd.get("issuer", "Unknown")
		c.allows_partial = cd.get("allows_partial", true)
		var colony_name = cd.get("colony_name", "")
		if colony_name != "":
			for colony in colonies:
				if colony.colony_name == colony_name:
					c.delivery_colony = colony
					break
		active_contracts.append(c)

	# Restore market events
	active_market_events.clear()
	for ed in data.get("market_events", []):
		var e := MarketEvent.new()
		e.type = int(ed.get("type", 0))
		var ore_types_arr: Array = ed.get("ore_types", [])
		for ot_int in ore_types_arr:
			e.affected_ore_types.append(int(ot_int))
		e.price_multiplier = float(ed.get("multiplier", 1.0))
		e.remaining_ticks = float(ed.get("remaining", 0.0))
		e.message = ed.get("message", "")
		var colony_name = ed.get("colony_name", "")
		if colony_name != "":
			for colony in colonies:
				if colony.colony_name == colony_name:
					e.affected_colony = colony
					break
		active_market_events.append(e)

	# Restore fabrication queue
	fabrication_queue.clear()
	for eqd in data.get("fabrication_queue", []):
		var eq := Equipment.new()
		eq.equipment_name = eqd.get("name", "Equipment")
		eq.type = eqd.get("type", "processor")
		eq.mining_bonus = float(eqd.get("bonus", 1.2))
		eq.cost = int(eqd.get("cost", 1000))
		eq.durability = float(eqd.get("durability", 100.0))
		eq.max_durability = eq.durability
		fabrication_queue.append(eq)

	# Restore rescue missions
	rescue_missions.clear()
	var rescue_data: Dictionary = data.get("rescue_missions", {})
	for ship_name in rescue_data:
		var rd: Dictionary = rescue_data[ship_name]
		# Find ship
		for ship in ships:
			if ship.ship_name == ship_name:
				rescue_missions[ship] = {
					"elapsed_ticks": float(rd.get("elapsed", 0.0)),
					"transit_time": float(rd.get("transit", 0.0)),
					"workers": ship.last_crew.duplicate(),
					"source_name": rd.get("source", "Earth"),
					"source_pos": CelestialData.get_earth_position_au(),  # Approximate
				}
				break

	# Restore refuel missions
	refuel_missions.clear()
	var refuel_data: Dictionary = data.get("refuel_missions", {})
	for ship_name in refuel_data:
		var rfd: Dictionary = refuel_data[ship_name]
		for ship in ships:
			if ship.ship_name == ship_name:
				refuel_missions[ship] = {
					"elapsed_ticks": float(rfd.get("elapsed", 0.0)),
					"transit_time": float(rfd.get("transit", 0.0)),
					"fuel_amount": float(rfd.get("fuel", 0.0)),
					"source_name": rfd.get("source", "Earth"),
					"source_pos": CelestialData.get_earth_position_au(),
				}
				break

	# Restore stranger offers
	stranger_offers.clear()
	var stranger_data: Dictionary = data.get("stranger_offers", {})
	for ship_name in stranger_data:
		var sod: Dictionary = stranger_data[ship_name]
		for ship in ships:
			if ship.ship_name == ship_name:
				stranger_offers[ship] = {
					"stranger_name": sod.get("name", "Unknown"),
					"expires_ticks": float(sod.get("expires", 0.0)),
					"suggested_tip": int(sod.get("tip", 3000)),
				}
				break

	# Restore deployed crews
	deployed_crews.clear()
	for dc_data in data.get("deployed_crews", []):
		var asteroid_name: String = dc_data.get("asteroid_name", "")
		var asteroid: AsteroidData = null
		for a in asteroids:
			if a.asteroid_name == asteroid_name:
				asteroid = a
				break
		if asteroid == null:
			continue
		var crew_workers: Array[Worker] = []
		for wname in dc_data.get("worker_names", []):
			for w in workers:
				if w.worker_name == wname:
					crew_workers.append(w)
					break
		deployed_crews.append({
			"asteroid": asteroid,
			"workers": crew_workers,
			"supplies": dc_data.get("supplies", {}).duplicate(),
			"deployed_at": float(dc_data.get("deployed_at", 0.0)),
		})

	# Restore hitchhike pool
	hitchhike_pool.clear()
	for hp_data in data.get("hitchhike_pool", []):
		var hp_worker_name: String = hp_data.get("worker_name", "")
		var hp_worker: Worker = null
		for w in workers:
			if w.worker_name == hp_worker_name:
				hp_worker = w
				break
		if hp_worker:
			hitchhike_pool.append({
				"worker": hp_worker,
				"location_name": hp_data.get("location_name", ""),
				"location_pos": Vector2(float(hp_data.get("location_pos_x", 0.0)), float(hp_data.get("location_pos_y", 0.0))),
				"entered_at": float(hp_data.get("entered_at", 0.0)),
				"max_wait": float(hp_data.get("max_wait", 604800.0)),
			})

	# Restore tardy workers
	tardy_workers.clear()
	for td_data in data.get("tardy_workers", []):
		var td_worker_name: String = td_data.get("worker_name", "")
		var td_worker: Worker = null
		for w in workers:
			if w.worker_name == td_worker_name:
				td_worker = w
				break
		if td_worker:
			tardy_workers.append({
				"worker": td_worker,
				"reason": td_data.get("reason", "Unknown"),
				"tardy_since": float(td_data.get("tardy_since", 0.0)),
			})

	# Restore mining unit inventory
	const MU_VOL_DEFAULTS: Dictionary = {0: 11.4, 1: 16.8, 2: 27.3}
	mining_unit_inventory.clear()
	for mud in data.get("mining_unit_inventory", []):
		var unit := MiningUnit.new()
		unit.unit_type = int(mud.get("unit_type", 0)) as MiningUnit.UnitType
		unit.unit_name = mud.get("unit_name", "")
		unit.mass = float(mud.get("mass", 7.6))
		unit.volume = float(mud.get("volume", MU_VOL_DEFAULTS.get(unit.unit_type, 11.4)))
		unit.workers_required = int(mud.get("workers_required", 1))
		unit.mining_multiplier = float(mud.get("mining_multiplier", 1.0))
		unit.durability = float(mud.get("durability", 100.0))
		unit.max_durability = float(mud.get("max_durability", 100.0))
		unit.wear_per_day = float(mud.get("wear_per_day", 0.3))
		unit.cost = int(mud.get("cost", 50000))
		mining_unit_inventory.append(unit)

	# Restore deployed mining units
	deployed_mining_units.clear()
	for mud in data.get("deployed_mining_units", []):
		var unit := MiningUnit.new()
		unit.unit_type = int(mud.get("unit_type", 0)) as MiningUnit.UnitType
		unit.unit_name = mud.get("unit_name", "")
		unit.mass = float(mud.get("mass", 7.6))
		unit.volume = float(mud.get("volume", MU_VOL_DEFAULTS.get(unit.unit_type, 11.4)))
		unit.workers_required = int(mud.get("workers_required", 1))
		unit.mining_multiplier = float(mud.get("mining_multiplier", 1.0))
		unit.durability = float(mud.get("durability", 100.0))
		unit.max_durability = float(mud.get("max_durability", 100.0))
		unit.wear_per_day = float(mud.get("wear_per_day", 0.3))
		unit.cost = int(mud.get("cost", 50000))
		unit.deployed_at_asteroid = mud.get("deployed_at_asteroid", "")
		unit.deployed_at_tick = float(mud.get("deployed_at_tick", 0.0))
		# Reconnect workers
		var mu_worker_names: Array = mud.get("worker_names", [])
		for wname in mu_worker_names:
			for w in workers:
				if w.worker_name == wname:
					unit.assigned_workers.append(w)
					w.assigned_mining_unit = unit
					break
		deployed_mining_units.append(unit)

	# Restore ore stockpiles
	ore_stockpiles.clear()
	var stockpile_data: Dictionary = data.get("ore_stockpiles", {})
	for asteroid_name in stockpile_data:
		var pile_data: Dictionary = stockpile_data[asteroid_name]
		var pile := {}
		for key in pile_data:
			pile[int(key)] = float(pile_data[key])
		ore_stockpiles[asteroid_name] = pile

	# Restore asteroid supplies
	asteroid_supplies.clear()
	var supplies_data: Dictionary = data.get("asteroid_supplies", {})
	for asteroid_name in supplies_data:
		var sd: Dictionary = supplies_data[asteroid_name]
		asteroid_supplies[asteroid_name] = {
			"food": float(sd.get("food", 0.0)),
			"repair_parts": float(sd.get("repair_parts", 0.0)),
		}

	return true
