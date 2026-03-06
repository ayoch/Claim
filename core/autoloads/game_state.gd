extends Node

var money: int = 10000000:
	set(value):
		money = value
		EventBus.money_changed.emit(money)

var resources: Dictionary = {} # OreType -> float (tons)

# Financial history tracking
# Each entry: { "timestamp": float, "balance": int, "change": int, "desc": String, "ship": String }
var financial_history: Array[Dictionary] = []
const MAX_FINANCIAL_HISTORY: int = 1000
var workers: Array[Worker] = []
var ships: Array[Ship] = []  # Player's own ships
var _available_workers_cache: Array[Worker] = []
var _available_workers_dirty: bool = true
var _docked_ships_cache: Array[Ship] = []
var _docked_ships_dirty: bool = true
var other_players_ships: Array[Dictionary] = []  # Other players' ships (multiplayer) - stored as dictionaries with owner info
var missions: Array[Mission] = []
var equipment_inventory: Array[Equipment] = []
var upgrade_inventory: Array[ShipUpgrade] = []  # Purchased but not yet installed
var fabrication_queue: Array[Equipment] = []  # Equipment being fabricated
var asteroids: Array[AsteroidData] = []
var rival_corps: Array[RivalCorp] = []
var ghost_contacts: Array = []  # Array[GhostContact]

# Lightspeed communication delay
const LIGHT_SECONDS_PER_AU: float = 499.0
var pending_orders: Array[Dictionary] = []  # { fires_at, ship, label, fn }

var settings: Dictionary = {
	"auto_refuel": true,
	"show_unreachable_destinations": false,
	"auto_sell_at_markets": false,
	"auto_restock_torpedoes": true,
	"auto_sell_at_earth": true,
	"auto_sell_on_return": true,  # SERVER mode: server sells cargo automatically on mission return
	"autoplay": true,
	"auto_pause_on_critical": true,  # Default ON for safety
}

# Leaderboard system
var player_name: String = "Player"  # Default player name
var local_leaderboard: Array[Dictionary] = []  # Single-player leaderboard entries
const MAX_LEADERBOARD_ENTRIES: int = 100

# ═══════════════════════════════════════════════════════════════════════════════
# POLICIES - Always-On Automation Rules (Active Regardless of Autoplay)
# ═══════════════════════════════════════════════════════════════════════════════

var thrust_policy: int = CompanyPolicy.ThrustPolicy.BALANCED
var repair_policy: int = CompanyPolicy.RepairPolicy.ALWAYS
var cargo_policy: int = CompanyPolicy.CargoPolicy.STANDARD
var collection_policy: int = CompanyPolicy.CollectionPolicy.ROUTINE
var supply_policy: int = CompanyPolicy.SupplyPolicy.ROUTINE
var encounter_policy: int = CompanyPolicy.EncounterPolicy.COEXIST
var maintenance_policy: int = CompanyPolicy.MaintenancePolicy.AS_NEEDED

func get_thrust_policy(ship: Ship) -> int:
	return ship.thrust_policy_override if ship.thrust_policy_override >= 0 else thrust_policy

func get_repair_policy(ship: Ship) -> int:
	return ship.repair_policy_override if ship.repair_policy_override >= 0 else repair_policy

func get_cargo_policy(ship: Ship) -> int:
	return ship.cargo_policy_override if ship.cargo_policy_override >= 0 else cargo_policy

func get_collection_policy(ship: Ship) -> int:
	return ship.collection_policy_override if ship.collection_policy_override >= 0 else collection_policy

func get_supply_policy(ship: Ship) -> int:
	return ship.supply_policy_override if ship.supply_policy_override >= 0 else supply_policy

func get_encounter_policy(ship: Ship) -> int:
	return ship.encounter_policy_override if ship.encounter_policy_override >= 0 else encounter_policy

func get_maintenance_policy(ship: Ship) -> int:
	return ship.maintenance_policy_override if ship.maintenance_policy_override >= 0 else maintenance_policy

# ═══════════════════════════════════════════════════════════════════════════════
# AUTOPLAY SETTINGS - AI Strategy (Only Active When Autoplay Enabled)
# ═══════════════════════════════════════════════════════════════════════════════

# Core Strategy (Sliders 0-100)
var autoplay_risk_tolerance: int = 50
var autoplay_growth_rate: int = 50
var autoplay_resource_focus: int = 50

# Operational Strategy
var autoplay_diversification: int = AutoplaySettings.DiversificationStrategy.MIXED
var autoplay_workforce: int = AutoplaySettings.WorkforcePhilosophy.ADEQUATE
var autoplay_technology: int = AutoplaySettings.TechnologyInvestment.BALANCED
var autoplay_market_timing: int = AutoplaySettings.MarketTiming.IMMEDIATE
var autoplay_territorial: int = AutoplaySettings.TerritorialStrategy.REGIONAL

# Advanced Settings
var autoplay_contract_priority: int = AutoplaySettings.ContractPriority.OPPORTUNISTIC
var autoplay_upgrade_preference: int = AutoplaySettings.UpgradePreference.BALANCED
var autoplay_debt_tolerance: int = AutoplaySettings.DebtTolerance.CONSERVATIVE
var autoplay_partnership_strategy: int = AutoplaySettings.PartnershipStrategy.CONTESTED_ONLY
var autoplay_rescue_priority: int = AutoplaySettings.RescuePriority.COST_CONSCIOUS
var autoplay_colony_preference: int = AutoplaySettings.ColonyPreference.PRICE_OPTIMIZE
var autoplay_retrofit_schedule: int = AutoplaySettings.RetrofitSchedule.BALANCED
var autoplay_exploration_focus: int = AutoplaySettings.ExplorationFocus.BALANCED

# Game clock: total elapsed game-seconds (ticks) since game start
var total_ticks: float = 0.0

# Statistics
var total_crew_deaths: int = 0

const START_YEAR: int = 2112  # Game is set in year 2112

# Game epoch: Starting date/time for new games (set dynamically at game start)
# This is stored as the real-world date when the game started, in 2112
var game_start_month: int = 0
var game_start_day: int = 0
var game_start_year: int = 2112

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
	# Calculate game date from total_ticks (allows speed multiplier to work!)
	# Game starts at today's real-world date in 2112, then advances based on ticks

	# If game just started, set start date to today's date in 2112
	if game_start_month == 0:
		var now := Time.get_datetime_dict_from_system()
		game_start_month = now["month"]
		game_start_day = now["day"]
		game_start_year = START_YEAR

	# Calculate elapsed time from total_ticks
	var elapsed_seconds: float = total_ticks
	var elapsed_days := int(elapsed_seconds / 86400.0)
	var remaining_seconds := int(elapsed_seconds) % 86400
	var hours := remaining_seconds / 3600
	var minutes := (remaining_seconds % 3600) / 60

	# Start from game_start_date and add elapsed days
	var year := game_start_year
	var month := game_start_month
	var day := game_start_day

	# Add elapsed days
	while elapsed_days > 0:
		var days_in_current_month := _days_in_month(month, year)
		var days_left_in_month := days_in_current_month - day + 1

		if elapsed_days >= days_left_in_month:
			# Move to next month
			elapsed_days -= days_left_in_month
			month += 1
			day = 1
			if month > 12:
				month = 1
				year += 1
		else:
			# Stay in current month
			day += elapsed_days
			elapsed_days = 0

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
var _colony_by_name: Dictionary = {}  # Cache for O(1) colony lookups
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
var asteroid_supplies: Dictionary = {}  # asteroid_name -> { "food": float, "water": float, "oxygen": float, "repair_parts": float }

# Security zones created by patrolling ships
# Each: { "center_au": Vector2, "radius_au": float, "ship_name": String, "expires_at": float }
var security_zones: Array[Dictionary] = []

# Hitchhiking pool: workers waiting at stations for a ride home
# Each: { "worker": Worker, "location_name": String, "location_pos": Vector2, "entered_at": float, "max_wait": float }
var hitchhike_pool: Array[Dictionary] = []

# Tardy workers awaiting player discipline decision
# Each: { "worker": Worker, "reason": String, "tardy_since": float }
var tardy_workers: Array[Dictionary] = []

# Persistent warnings system
# Each: { "id": String, "message": String, "severity": String ("warning"/"critical"), "category": String }
var active_warnings: Array[Dictionary] = []
var _next_warning_id: int = 0

func _ready() -> void:
	new_game()

func new_game() -> void:
	# Clear all state before initializing (safe to call on first launch or restart)
	ships.clear()
	workers.clear()
	missions.clear()
	trade_missions.clear()
	rescue_missions.clear()
	refuel_missions.clear()
	stranger_offers.clear()
	pending_orders.clear()
	deployed_crews.clear()
	mining_unit_inventory.clear()
	deployed_mining_units.clear()
	ore_stockpiles.clear()
	asteroid_supplies.clear()
	security_zones.clear()
	hitchhike_pool.clear()
	tardy_workers.clear()
	active_warnings.clear()
	_next_warning_id = 0
	available_contracts.clear()
	active_contracts.clear()
	active_market_events.clear()
	money = 10_000_000
	total_ticks = 0.0
	# Initialize game start date to today's date in 2112
	var now := Time.get_datetime_dict_from_system()
	game_start_month = now["month"]
	game_start_day = now["day"]
	game_start_year = START_YEAR
	Reputation.score = 0.0
	_init_resources()
	_init_starter_ship()
	_init_starter_crew()
	asteroids = CelestialData.get_asteroids()
	market = MarketState.new()
	colonies = ColonyData.get_colonies()
	_rebuild_colony_cache()
	rival_corps = RivalCorpData.create_all()

## Reset state for SERVER mode (server is source of truth, don't use LOCAL defaults)
func reset_for_server_mode() -> void:
	print("[GameState] Resetting for SERVER mode (was: money=$%d, ships=%d)" % [money, ships.size()])
	# Clear LOCAL mode state
	ships.clear()
	workers.clear()
	missions.clear()
	trade_missions.clear()
	rescue_missions.clear()
	refuel_missions.clear()
	stranger_offers.clear()
	pending_orders.clear()
	deployed_crews.clear()
	mining_unit_inventory.clear()
	deployed_mining_units.clear()
	ore_stockpiles.clear()
	asteroid_supplies.clear()
	security_zones.clear()
	hitchhike_pool.clear()
	tardy_workers.clear()
	active_warnings.clear()
	_next_warning_id = 0
	available_contracts.clear()
	active_contracts.clear()
	active_market_events.clear()

	# Reset to 0 until server sends actual value
	money = 0
	total_ticks = 0.0

	# Keep shared data (asteroids, colonies, market)
	# These are reference data, not player state
	if asteroids.is_empty():
		asteroids = CelestialData.get_asteroids()
	if colonies.is_empty():
		colonies = ColonyData.get_colonies()
		_rebuild_colony_cache()
	if market == null:
		market = MarketState.new()
	if rival_corps.is_empty():
		rival_corps = RivalCorpData.create_all()

func _init_resources() -> void:
	for ore in ResourceTypes.OreType.values():
		resources[ore] = 0.0

func _init_starter_ship() -> void:
	var classes := ShipData.ShipClass.values()
	for i in range(3):
		var ship_class: ShipData.ShipClass = classes[randi() % classes.size()]
		var new_ship := ShipData.create_ship(ship_class)
		ships.append(new_ship)
		# Provision immediately with 30 days of supplies
		var crew_size := new_ship.min_crew
		new_ship.supplies["food"] = crew_size * 30.0 * 2.8
		new_ship.supplies["water"] = crew_size * 30.0 * 0.25 / 20.0
		new_ship.supplies["oxygen"] = crew_size * 30.0 * 0.05 / 2.0

func purchase_ship(ship_class: ShipData.ShipClass) -> Ship:
	var price: int = ShipData.CLASS_PRICES[ship_class]
	if money < price:
		return null
	money -= price
	var new_ship := ShipData.create_ship(ship_class)
	ships.append(new_ship)
	_invalidate_ship_cache()
	# Provision new ship with 30 days of supplies (uses min_crew for calculation)
	var crew_size := new_ship.min_crew
	new_ship.supplies["food"] = crew_size * 30.0 * 2.8
	new_ship.supplies["water"] = crew_size * 30.0 * 0.25 / 20.0
	new_ship.supplies["oxygen"] = crew_size * 30.0 * 0.05 / 2.0
	EventBus.ship_purchased.emit(new_ship, price)
	return new_ship

## Mode-aware ship purchasing - works in both LOCAL and SERVER modes
func purchase_ship_any_mode(ship_class: ShipData.ShipClass, ship_name: String, colony_id: int = 0) -> void:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		# SERVER mode: route through BackendManager
		# Server uses int ship_class, client uses enum - convert to int
		var ship_class_int: int = int(ship_class)
		BackendManager.buy_ship(ship_class_int, ship_name, colony_id)
		# State refresh will include new ship via polling
	else:
		# LOCAL mode: use local GameState directly
		purchase_ship(ship_class)

## Mode-aware equipment purchasing - works in both LOCAL and SERVER modes
func purchase_equipment_any_mode(ship: Ship, equipment_name: String) -> void:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		# SERVER mode: route through BackendManager
		if ship.server_id == 0:
			push_warning("Ship %s has no server_id, cannot buy equipment in SERVER mode" % ship.ship_name)
			return
		BackendManager.buy_equipment(ship.server_id, equipment_name)
		# State refresh will include new equipment via polling
	else:
		# LOCAL mode: look up equipment in catalog and purchase
		# This requires the catalog entry - would need UI to pass it
		# For now, just a stub
		push_warning("purchase_equipment_any_mode() LOCAL mode not fully implemented")

## Mode-aware equipment selling - works in both LOCAL and SERVER modes
func sell_equipment_any_mode(equipment: Equipment, ship: Ship) -> void:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		# SERVER mode: equipment needs server_id
		# For now, use equipment name to find it (requires server sync)
		# TODO: Add equipment.server_id field
		push_warning("sell_equipment_any_mode() SERVER mode requires equipment.server_id field")
	else:
		# LOCAL mode: remove from ship and refund 50% of cost
		ship.equipment.erase(equipment)
		money += equipment.cost / 2
		EventBus.equipment_sold.emit(equipment, ship)

## Redirect a ship in transit to a new asteroid.
## Queues the order with lightspeed delay; returns true if order accepted/queued.
func redirect_mission(mission: Mission, new_asteroid: AsteroidData) -> bool:
	if mission.status != Mission.Status.TRANSIT_OUT and mission.status != Mission.Status.TRANSIT_BACK:
		return false
	var ship := mission.ship
	var label := "Redirect to " + new_asteroid.asteroid_name
	queue_ship_order(ship, label, func(): _apply_redirect_mission(mission, new_asteroid))
	return true

func _apply_redirect_mission(mission: Mission, new_asteroid: AsteroidData) -> void:
	# Re-validate: mission may have completed or ship state changed during signal transit
	if mission == null or mission.ship == null:
		return
	if mission.status != Mission.Status.TRANSIT_OUT and mission.status != Mission.Status.TRANSIT_BACK:
		return

	var ship := mission.ship
	var thrust := ship.get_effective_thrust()

	# Calculate intercept trajectory (predicts where asteroid will be at arrival)
	var intercept := calculate_asteroid_intercept(ship.position_au, new_asteroid, thrust, mission.transit_mode)
	var new_dest: Vector2 = intercept["intercept_position"]
	var dist: float = intercept["distance"]
	var new_transit_time: float = intercept["transit_time"]
	var avg_velocity := dist / new_transit_time if new_transit_time > 0.0 else 0.0

	# Determine if a momentum arc is needed (ship is moving at significant angle to new dest)
	var velocity_dir := ship.velocity_au_per_tick.normalized() if ship.speed_au_per_tick > 1e-8 else Vector2.ZERO
	var dest_dir := (new_dest - ship.position_au).normalized() if dist > 1e-6 else Vector2.ZERO
	var dot := velocity_dir.dot(dest_dir) if ship.speed_au_per_tick > 1e-8 else 1.0
	var speed_fraction: float = clampf(ship.speed_au_per_tick / (2.0 * avg_velocity), 0.0, 1.0) if avg_velocity > 0.0 else 0.0
	var arc_fraction: float = clampf(sqrt((1.0 - dot) * 0.5) * speed_fraction * 0.4, 0.0, 0.30)

	# Compute arc waypoint and check if it makes sense
	var waypoint := ship.position_au + velocity_dir * (arc_fraction * dist)
	var dist1 := arc_fraction * dist
	var dist2 := waypoint.distance_to(new_dest)
	var use_arc := arc_fraction >= 0.05 and ship.speed_au_per_tick > 1e-8 and dist1 > 1e-6

	# Fuel check: outbound (redirect path) + return trip
	var total_path := dist1 + dist2 if use_arc else dist
	var fuel_out := ship.calc_fuel_for_distance(total_path)
	var return_origin: Vector2
	if mission.return_to_station and ship.station_colony:
		return_origin = ship.station_colony.get_position_au()
	else:
		return_origin = CelestialData.get_earth_position_au()
	var return_dist := new_dest.distance_to(return_origin)
	var fuel_ret := ship.calc_fuel_for_distance(return_dist, ship.cargo_capacity)
	var fuel_needed := fuel_out + fuel_ret

	if fuel_needed > ship.fuel:
		EventBus.mission_redirect_failed.emit(ship, "Insufficient fuel (need %.0f for redirect + return, have %.0f)" % [fuel_needed, ship.fuel])
		return

	# Redirect costs money (2x outbound fuel cost as opportunity cost penalty)
	var redirect_cost := int(fuel_out * Ship.FUEL_COST_PER_UNIT * 2.0)
	if money < redirect_cost:
		EventBus.mission_redirect_failed.emit(ship, "Cannot afford redirect cost ($%d)" % redirect_cost)
		return

	money -= redirect_cost
	mission.asteroid = new_asteroid
	mission.origin_is_earth = false
	mission.status = Mission.Status.TRANSIT_OUT
	mission.outbound_legs.clear()
	mission.outbound_waypoint_index = 0

	var return_transit_time := Brachistochrone.transit_time(return_dist, thrust)

	if use_arc:
		# Two-leg route: arc in current direction, then turn to destination
		var time1 := Brachistochrone.transit_time(dist1, thrust)
		var time2 := Brachistochrone.transit_time(dist2, thrust)
		var avg_velocity1 := dist1 / time1 if time1 > 0.0 else 0.0
		var initial_t := 0.0
		var adjusted_origin := ship.position_au
		if avg_velocity1 > 0.0 and ship.speed_au_per_tick > 0.0:
			initial_t = clampf(ship.speed_au_per_tick / (4.0 * avg_velocity1), 0.0, 0.5)
			var dfrac := 2.0 * initial_t * initial_t
			if dfrac < 0.98:
				adjusted_origin = (ship.position_au - waypoint * dfrac) / (1.0 - dfrac)
		mission.origin_position_au = adjusted_origin
		mission.outbound_legs.append(WaypointLeg.make(waypoint, time1))
		mission.elapsed_ticks = initial_t * time1
		mission.transit_time = time2
		var total_time_arc := time1 + time2 + return_transit_time
		mission.fuel_per_tick = fuel_needed / total_time_arc if total_time_arc > 0.0 else 0.0
	else:
		# Single-leg velocity-preserving redirect
		var initial_t := 0.0
		var adjusted_origin := ship.position_au
		if avg_velocity > 0.0 and ship.speed_au_per_tick > 0.0:
			initial_t = clampf(ship.speed_au_per_tick / (4.0 * avg_velocity), 0.0, 0.5)
			var dfrac := 2.0 * initial_t * initial_t
			if dfrac < 0.98:
				adjusted_origin = (ship.position_au - new_dest * dfrac) / (1.0 - dfrac)
		mission.origin_position_au = adjusted_origin
		mission.elapsed_ticks = initial_t * new_transit_time
		mission.transit_time = new_transit_time
		var total_time_single := new_transit_time + return_transit_time
		mission.fuel_per_tick = fuel_needed / total_time_single if total_time_single > 0.0 else 0.0

	# Recalculate trajectory visualization for new path
	mission.destination_position_au = new_dest
	mission.calculate_trajectory_curves()

	EventBus.mission_redirected.emit(ship, new_asteroid, redirect_cost)

## Redirect a ship in trade mission to a new colony.
## Queues the order with lightspeed delay; returns true if order accepted/queued.
func redirect_trade_mission(trade_mission: TradeMission, new_colony: Colony) -> bool:
	if trade_mission.status != TradeMission.Status.TRANSIT_TO_COLONY and trade_mission.status != TradeMission.Status.TRANSIT_BACK:
		return false
	var ship := trade_mission.ship
	var label := "Redirect to " + new_colony.colony_name
	queue_ship_order(ship, label, func(): _apply_redirect_trade_mission(trade_mission, new_colony))
	return true

func _apply_redirect_trade_mission(trade_mission: TradeMission, new_colony: Colony) -> void:
	# Re-validate: mission may have completed or ship state changed during signal transit
	if trade_mission == null or trade_mission.ship == null:
		return
	if trade_mission.status != TradeMission.Status.TRANSIT_TO_COLONY and trade_mission.status != TradeMission.Status.TRANSIT_BACK:
		return

	var ship := trade_mission.ship
	var new_dest := new_colony.get_position_au()

	# Fuel check: outbound (redirect path) + return trip
	var dist := ship.position_au.distance_to(new_dest)
	var fuel_out_tm := ship.calc_fuel_for_distance(dist, ship.get_cargo_total())
	var tm_return_origin: Vector2
	if ship.is_stationed and ship.station_colony:
		tm_return_origin = ship.station_colony.get_position_au()
	else:
		tm_return_origin = CelestialData.get_earth_position_au()
	var tm_return_dist := new_dest.distance_to(tm_return_origin)
	var fuel_ret_tm := ship.calc_fuel_for_distance(tm_return_dist, 0.0)  # empty after selling
	var fuel_needed := fuel_out_tm + fuel_ret_tm

	if fuel_needed > ship.fuel:
		EventBus.trade_mission_redirect_failed.emit(ship, "Insufficient fuel (need %.0f for redirect + return, have %.0f)" % [fuel_needed, ship.fuel])
		return

	# Redirect cost (2x outbound fuel cost)
	var redirect_cost := int(fuel_out_tm * Ship.FUEL_COST_PER_UNIT * 2.0)
	if money < redirect_cost:
		EventBus.trade_mission_redirect_failed.emit(ship, "Cannot afford redirect cost ($%d)" % redirect_cost)
		return

	money -= redirect_cost
	trade_mission.colony = new_colony

	var thrust := ship.get_effective_thrust()
	var new_transit_time := Brachistochrone.transit_time(dist, thrust)
	var avg_velocity := dist / new_transit_time if new_transit_time > 0.0 else 0.0

	# Determine if a momentum arc is needed
	var velocity_dir := ship.velocity_au_per_tick.normalized() if ship.speed_au_per_tick > 1e-8 else Vector2.ZERO
	var dest_dir := (new_dest - ship.position_au).normalized() if dist > 1e-6 else Vector2.ZERO
	var dot := velocity_dir.dot(dest_dir) if ship.speed_au_per_tick > 1e-8 else 1.0
	var speed_fraction: float = clampf(ship.speed_au_per_tick / (2.0 * avg_velocity), 0.0, 1.0) if avg_velocity > 0.0 else 0.0
	var arc_fraction: float = clampf(sqrt((1.0 - dot) * 0.5) * speed_fraction * 0.4, 0.0, 0.30)

	var waypoint := ship.position_au + velocity_dir * (arc_fraction * dist)
	var dist1 := arc_fraction * dist
	var dist2 := waypoint.distance_to(new_dest)
	var use_arc := arc_fraction >= 0.05 and ship.speed_au_per_tick > 1e-8 and dist1 > 1e-6

	var tm_return_transit_time := Brachistochrone.transit_time(tm_return_dist, thrust)

	trade_mission.origin_is_earth = false
	trade_mission.status = TradeMission.Status.TRANSIT_TO_COLONY
	trade_mission.outbound_legs.clear()
	trade_mission.outbound_waypoint_index = 0

	if use_arc:
		var time1 := Brachistochrone.transit_time(dist1, thrust)
		var time2 := Brachistochrone.transit_time(dist2, thrust)
		var avg_velocity1 := dist1 / time1 if time1 > 0.0 else 0.0
		var initial_t := 0.0
		var adjusted_origin := ship.position_au
		if avg_velocity1 > 0.0 and ship.speed_au_per_tick > 0.0:
			initial_t = clampf(ship.speed_au_per_tick / (4.0 * avg_velocity1), 0.0, 0.5)
			var dfrac := 2.0 * initial_t * initial_t
			if dfrac < 0.98:
				adjusted_origin = (ship.position_au - waypoint * dfrac) / (1.0 - dfrac)
		trade_mission.origin_position_au = adjusted_origin
		trade_mission.outbound_legs.append(WaypointLeg.make(waypoint, time1))
		trade_mission.elapsed_ticks = initial_t * time1
		trade_mission.transit_time = time2
		var total_time_arc := time1 + time2 + tm_return_transit_time
		trade_mission.fuel_per_tick = fuel_needed / total_time_arc if total_time_arc > 0.0 else 0.0
	else:
		var initial_t := 0.0
		var adjusted_origin := ship.position_au
		if avg_velocity > 0.0 and ship.speed_au_per_tick > 0.0:
			initial_t = clampf(ship.speed_au_per_tick / (4.0 * avg_velocity), 0.0, 0.5)
			var dfrac := 2.0 * initial_t * initial_t
			if dfrac < 0.98:
				adjusted_origin = (ship.position_au - new_dest * dfrac) / (1.0 - dfrac)
		trade_mission.origin_position_au = adjusted_origin
		trade_mission.elapsed_ticks = initial_t * new_transit_time
		trade_mission.transit_time = new_transit_time
		var total_time_single := new_transit_time + tm_return_transit_time
		trade_mission.fuel_per_tick = fuel_needed / total_time_single if total_time_single > 0.0 else 0.0

	EventBus.trade_mission_redirected.emit(ship, new_colony, redirect_cost)

func _init_starter_crew() -> void:
	# Hire starter crew with guaranteed specialty coverage: pilot, engineer, miner
	# Scale total workers to staff all starting ships plus a buffer of 3 spares
	var total_min_crew := 0
	for ship in ships:
		total_min_crew += ship.min_crew
	var total_workers := total_min_crew + 3

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
	_invalidate_worker_cache()
	EventBus.worker_hired.emit(worker)

func assign_worker_to_ship(worker: Worker, ship: Ship) -> Dictionary:
	# Location validation: worker must be at same colony as ship
	if ship:
		var ship_location := ""
		if ship.docked_at_earth:
			ship_location = "Earth"
		elif ship.docked_at_colony != null:
			ship_location = ship.docked_at_colony.colony_name
		else:
			return {"success": false, "error": "Ship must be docked to assign crew"}

		if worker.home_colony != ship_location:
			return {"success": false, "error": "Worker at %s cannot crew ship at %s" % [worker.home_colony, ship_location]}

	# Proceed with assignment
	if worker.assigned_ship == ship:
		return {"success": true}
	if worker.assigned_ship:
		worker.assigned_ship.crew.erase(worker)
	worker.assigned_ship = ship
	if ship and worker not in ship.crew:
		ship.crew.append(worker)
	return {"success": true}

func remove_worker_from_ship(worker: Worker, ship: Ship) -> void:
	ship.crew.erase(worker)
	if worker.assigned_ship == ship:
		worker.assigned_ship = null

func fire_worker(worker: Worker) -> void:
	Worker.release_name(worker.worker_name)
	workers.erase(worker)
	_invalidate_worker_cache()
	# Remove from ship crew
	if worker.assigned_ship:
		worker.assigned_ship.crew.erase(worker)
	worker.assigned_ship = null
	# Remove from any mining unit — check all deployed units in case pointer is out of sync
	if worker.assigned_mining_unit and is_instance_valid(worker.assigned_mining_unit):
		worker.assigned_mining_unit.assigned_workers.erase(worker)
	for unit in deployed_mining_units:
		if worker in unit.assigned_workers:
			unit.assigned_workers.erase(worker)
	worker.assigned_mining_unit = null

	# Final cleanup to break all circular references
	worker.cleanup()
	EventBus.worker_fired.emit(worker)

## Mode-aware worker hiring - works in both LOCAL and SERVER modes
func hire_worker_any_mode(worker_id: int) -> void:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		# SERVER mode: route through BackendManager
		await BackendManager.hire_worker(worker_id)
		# Note: Worker will appear in GameState on next automatic state poll
		# UI should set dirty flag after await completes
	else:
		push_warning("hire_worker_any_mode() called in LOCAL mode - use hire_worker(worker) instead")

## Mode-aware worker firing - works in both LOCAL and SERVER modes
func fire_worker_any_mode(worker: Worker) -> void:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		# SERVER mode: route through BackendManager using server ID
		if worker.server_id > 0:
			BackendManager.fire_worker(worker.server_id)
			# State refresh will remove worker via polling
		else:
			push_warning("Worker %s has no server_id, cannot fire in SERVER mode" % worker.worker_name)
	else:
		# LOCAL mode: use local GameState directly
		fire_worker(worker)

## Criminal Ban System: Record violations at colonies
func record_worker_death_violation(worker: Worker, reason: String) -> void:
	# Record death at worker's home colony
	var colony_name: String = worker.home_colony if worker.home_colony != "" else "Earth"
	var colony: Colony = _find_colony_by_name(colony_name)
	if colony:
		colony.add_violation(reason, total_ticks)
		print("VIOLATION recorded at %s: %s" % [colony_name, reason])
		EventBus.violation_recorded.emit(colony, reason)

func record_abandonment_violation(worker: Worker, reason: String) -> void:
	# Record abandonment at worker's home colony
	var colony_name: String = worker.home_colony if worker.home_colony != "" else "Earth"
	var colony: Colony = _find_colony_by_name(colony_name)
	if colony:
		colony.add_violation(reason, total_ticks)
		print("VIOLATION recorded at %s: %s" % [colony_name, reason])
		EventBus.violation_recorded.emit(colony, reason)

func record_rescue_failure_violation(ship: Ship, reason: String) -> void:
	# Record rescue failure at ship's last known colony (or Earth if never docked)
	var colony: Colony = null
	if ship.docked_at_colony:
		colony = ship.docked_at_colony
	else:
		# Default to Earth if ship has no colony association
		colony = _find_colony_by_name("Earth")

	if colony:
		colony.add_violation(reason, total_ticks)
		print("VIOLATION recorded at %s: %s" % [colony.colony_name, reason])
		EventBus.violation_recorded.emit(colony, reason)

## NPC Violation System: Track rival corp violations at colonies
func add_corp_violation(corp: RivalCorp, colony: Colony, reason: String, timestamp: float) -> void:
	if not corp.colony_standings.has(colony.colony_name):
		corp.colony_standings[colony.colony_name] = { "violations": [], "banned": false }

	var standing: Dictionary = corp.colony_standings[colony.colony_name]
	standing["violations"].append({"timestamp": timestamp, "reason": reason})

	# Decay old violations (30 game-days)
	_decay_corp_violations(corp, colony, timestamp)

	var active_count := _get_active_corp_violations(corp, colony, timestamp)
	if active_count >= 4 and not standing["banned"]:
		standing["banned"] = true
		print("NPC BAN: %s banned from %s (%d violations)" % [corp.corp_name, colony.colony_name, active_count])
		EventBus.rival_corp_banned.emit(corp.corp_name, colony.colony_name)

func _decay_corp_violations(corp: RivalCorp, colony: Colony, current_ticks: float) -> void:
	if not corp.colony_standings.has(colony.colony_name):
		return
	var standing: Dictionary = corp.colony_standings[colony.colony_name]
	var violations: Array = standing.get("violations", [])
	var decay_threshold := current_ticks - (30.0 * 86400.0)  # 30 game-days
	standing["violations"] = violations.filter(func(v): return v["timestamp"] > decay_threshold)

func _get_active_corp_violations(corp: RivalCorp, colony: Colony, current_ticks: float) -> int:
	if not corp.colony_standings.has(colony.colony_name):
		return 0
	_decay_corp_violations(corp, colony, current_ticks)
	var standing: Dictionary = corp.colony_standings[colony.colony_name]
	return standing.get("violations", []).size()

func _is_corp_banned_from_colony(corp: RivalCorp, colony: Colony) -> bool:
	if not corp.colony_standings.has(colony.colony_name):
		return false
	var standing: Dictionary = corp.colony_standings[colony.colony_name]
	return standing.get("banned", false)

func _find_colony_by_name(name: String) -> Colony:
	return _colony_by_name.get(name, null)

func _rebuild_colony_cache() -> void:
	_colony_by_name.clear()
	for colony in colonies:
		_colony_by_name[colony.colony_name] = colony

func check_game_over_banned() -> bool:
	# Check if player is banned from ALL colonies
	var banned_count: int = 0
	for colony in colonies:
		if colony.player_banned:
			banned_count += 1

	# Game over if banned from all colonies
	if banned_count >= colonies.size():
		print("GAME OVER: Banned from all colonies (%d/%d)" % [banned_count, colonies.size()])
		EventBus.game_over.emit("Banned from all colonies")
		return true

	return false

## Warning System: Persistent, dismissible warnings with lightspeed delay
## position_au: Where the event occurred (Vector2). If null, delivered instantly (local events only).
## event_time: When the event actually occurred (game ticks). If 0, uses current time.
## ship: Optional ship reference for validation at delivery (e.g., check if ship still exists/is destroyed)
func add_warning(message: String, severity: String, category: String, position_au: Vector2 = Vector2.ZERO, event_time: float = 0.0, ship: Ship = null) -> String:
	# Use current time if no event time specified
	var actual_event_time := event_time if event_time > 0.0 else total_ticks

	# Calculate lightspeed delay if position provided (non-zero)
	var delay: float = 0.0
	if position_au != Vector2.ZERO:
		var earth_pos := CelestialData.get_earth_position_au()
		var distance := position_au.distance_to(earth_pos)
		delay = distance * LIGHT_SECONDS_PER_AU

		# Queue warning for delayed delivery
		pending_orders.append({
			"fires_at": total_ticks + delay,
			"ship": ship,  # Store ship ref for validation at delivery
			"label": "warning_delivery",
			"fn": func():
				_deliver_warning(message, severity, category, delay, actual_event_time, ship)
		})
		return "queued"  # Will be assigned real ID when delivered
	else:
		# Instant delivery (local Earth events only)
		return _deliver_warning(message, severity, category, 0.0, actual_event_time, ship)

func _deliver_warning(message: String, severity: String, category: String, delay: float, event_time: float, ship: Ship = null) -> String:
	# Check if duplicate exists using stored base message (O(1) comparison)
	for warning in active_warnings:
		if warning.get("base_message", "") == message and warning["category"] == category and warning["severity"] == severity:
			return warning["id"]  # Duplicate - don't create again

	# Format event timestamp
	var event_date := _format_game_time(event_time)
	var timestamp_prefix := "[%s]" % event_date

	# Add delay info if applicable
	var final_message := message
	if delay > 0.0:
		var delay_str := _format_delay_time(delay)
		final_message = "%s [+%s delay] %s" % [timestamp_prefix, delay_str, message]
	else:
		final_message = "%s %s" % [timestamp_prefix, message]

	# Create new warning
	var warning_id := "warning_%d" % _next_warning_id
	_next_warning_id += 1

	active_warnings.append({
		"id": warning_id,
		"message": final_message,
		"base_message": message,  # Store for O(1) deduplication
		"severity": severity,  # "warning" or "critical"
		"category": category,  # "violation", "crew", "debt", "loan", "combat"
		"delivered_at": total_ticks,  # When warning arrived at player
	})

	# Limit active warnings to prevent UI bloat (keep 50 most recent)
	const MAX_ACTIVE_WARNINGS := 50
	if active_warnings.size() > MAX_ACTIVE_WARNINGS:
		# Remove oldest warnings (first in array)
		for i in range(active_warnings.size() - MAX_ACTIVE_WARNINGS):
			EventBus.warning_dismissed.emit(active_warnings[0]["id"])
			active_warnings.remove_at(0)

	# Auto-pause on critical events if setting enabled
	if severity == "critical" and settings.get("auto_pause_on_critical", true):
		TimeScale.set_speed(1.0)

	# Send push notification for critical events
	if severity == "critical":
		send_push_notification("Critical Event", final_message)

	EventBus.warning_added.emit(warning_id, final_message, severity)
	return warning_id

func _format_delay_time(seconds: float) -> String:
	if seconds < 60.0:
		return "%.0fs" % seconds
	elif seconds < 3600.0:
		return "%.1fm" % (seconds / 60.0)
	else:
		return "%.1fh" % (seconds / 3600.0)

func _format_game_time(ticks: float) -> String:
	# Format as "Day X, HH:MM"
	var day := int(ticks / 86400.0) + 1
	var remaining_secs := int(ticks) % 86400
	var hours := remaining_secs / 3600
	var minutes := (remaining_secs % 3600) / 60
	return "D%d %02d:%02d" % [day, hours, minutes]

func dismiss_warning(warning_id: String) -> void:
	for i in range(active_warnings.size() - 1, -1, -1):
		if active_warnings[i]["id"] == warning_id:
			active_warnings.remove_at(i)
			EventBus.warning_dismissed.emit(warning_id)
			return

func dismiss_warnings_by_category(category: String) -> void:
	for i in range(active_warnings.size() - 1, -1, -1):
		if active_warnings[i]["category"] == category:
			var warning_id: String = active_warnings[i]["id"]
			active_warnings.remove_at(i)
			EventBus.warning_dismissed.emit(warning_id)

func get_warnings_by_category(category: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for warning in active_warnings:
		if warning["category"] == category:
			result.append(warning)
	return result

## Push notification system for critical events
func send_push_notification(title: String, body: String) -> void:
	var os_name := OS.get_name()

	# Desktop: flash window for attention
	if os_name in ["Windows", "macOS", "Linux"]:
		DisplayServer.window_request_attention()

	# Android: native notification via JNI
	elif os_name == "Android":
		_send_android_notification(title, body)

	# iOS: native plugin required (stub for now)
	elif os_name == "iOS":
		_send_ios_notification(title, body)

func _send_android_notification(title: String, body: String) -> void:
	# Android notifications in Godot 4 require a custom GDExtension plugin
	# This is a reference implementation that would work with a proper plugin

	# Check if custom notification plugin is available
	if Engine.has_singleton("AndroidNotifications"):
		var android_notif := Engine.get_singleton("AndroidNotifications")
		android_notif.call("send_notification", title, body, true)  # true = critical (vibrate)
		return

	# Fallback: Use JavaScriptBridge approach (requires custom Android plugin module)
	# The plugin should implement:
	# - NotificationManager access
	# - Notification.Builder for creating notifications
	# - Vibration pattern support
	# - Notification channel creation (required for Android 8+)

	# For now, log to console
	print("Android notification (plugin required): %s - %s" % [title, body])

func _send_ios_notification(title: String, body: String) -> void:
	# iOS requires a native plugin for local notifications
	# This is a stub that will be implemented via native plugin
	# The plugin should call UNUserNotificationCenter to schedule local notifications

	# Check if native plugin is available
	if Engine.has_singleton("IOSNotifications"):
		var ios_notifications := Engine.get_singleton("IOSNotifications")
		ios_notifications.call("send_local_notification", title, body)
	else:
		# Fallback: log for debugging
		print("iOS notification (plugin required): %s - %s" % [title, body])

func _invalidate_worker_cache() -> void:
	_available_workers_dirty = true

func _invalidate_ship_cache() -> void:
	_docked_ships_dirty = true

func get_available_workers() -> Array[Worker]:
	if _available_workers_dirty:
		_available_workers_cache.clear()
		for w in workers:
			if w.is_available:
				_available_workers_cache.append(w)
		_available_workers_dirty = false
	return _available_workers_cache

func get_docked_ships() -> Array[Ship]:
	if _docked_ships_dirty:
		_docked_ships_cache.clear()
		for s in ships:
			if s.is_docked:
				_docked_ships_cache.append(s)
		_docked_ships_dirty = false
	return _docked_ships_cache

func get_idle_remote_ships() -> Array[Ship]:
	var idle: Array[Ship] = []
	for s in ships:
		if s.is_idle_remote:
			idle.append(s)
	return idle

func purchase_equipment(entry: Dictionary) -> bool:
	var cost: int = entry.get("cost", 0)
	if money < cost:
		var item_name: String = entry.get("name", "Equipment")
		EventBus.insufficient_funds.emit("Purchase " + item_name, cost, money)
		EventBus.purchase_failed.emit(item_name, "Insufficient funds ($%s needed, $%s available)" % [cost, money])
		push_error("[GameState] Cannot purchase %s: Insufficient funds (need $%s, have $%s)" % [item_name, cost, money])
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
	var cost: int = entry.get("cost", 0)
	if money < cost:
		var item_name: String = entry.get("name", "Upgrade")
		EventBus.insufficient_funds.emit("Purchase " + item_name, cost, money)
		EventBus.purchase_failed.emit(item_name, "Insufficient funds ($%s needed, $%s available)" % [cost, money])
		push_error("[GameState] Cannot purchase %s: Insufficient funds (need $%s, have $%s)" % [item_name, cost, money])
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

## Commission dry dock work directly on a docked ship (no inventory step).
func commission_dry_dock(ship: Ship, entry: Dictionary) -> bool:
	var item_name: String = entry.get("name", "Dry Dock Upgrade")
	var cost: int = entry.get("cost", 0)

	if not ship.is_docked:
		EventBus.operation_failed.emit("Dry Dock", "%s must be docked at Earth to receive upgrades" % ship.ship_name)
		push_error("[GameState] Cannot apply dry dock upgrade: %s is not docked" % ship.ship_name)
		return false

	if money < cost:
		EventBus.insufficient_funds.emit("Dry Dock " + item_name, cost, money)
		EventBus.purchase_failed.emit(item_name, "Insufficient funds ($%s needed, $%s available)" % [cost, money])
		push_error("[GameState] Cannot commission dry dock: Insufficient funds (need $%s, have $%s)" % [cost, money])
		return false

	var upgrade := ShipUpgrade.from_catalog(entry)
	money -= upgrade.cost
	record_transaction(-upgrade.cost, "Dry dock: %s on %s" % [upgrade.upgrade_name, ship.ship_name])
	ship.upgrades.append(upgrade)
	EventBus.upgrade_installed.emit(ship, upgrade)
	return true

## --- Mining Unit Methods ---

func purchase_mining_unit(entry: Dictionary) -> bool:
	var cost: int = entry.get("cost", 0)
	var item_name: String = entry.get("name", "Mining Unit")

	if money < cost:
		EventBus.insufficient_funds.emit("Purchase " + item_name, cost, money)
		EventBus.purchase_failed.emit(item_name, "Insufficient funds ($%s needed, $%s available)" % [cost, money])
		push_error("[GameState] Cannot purchase %s: Insufficient funds (need $%s, have $%s)" % [item_name, cost, money])
		return false

	var unit := MiningUnit.from_catalog(entry)
	money -= unit.cost
	record_transaction(-unit.cost, "Mining unit: %s" % unit.unit_name)
	mining_unit_inventory.append(unit)
	EventBus.mining_unit_purchased.emit(unit)
	return true

func deploy_mining_unit(unit: MiningUnit, asteroid: AsteroidData, unit_workers: Array[Worker]) -> bool:
	if unit.is_deployed():
		EventBus.deployment_failed.emit(unit.unit_name, "Already deployed at %s" % unit.deployed_at_asteroid)
		push_error("[GameState] Cannot deploy %s: Already deployed at %s" % [unit.unit_name, unit.deployed_at_asteroid])
		return false

	if unit_workers.size() < unit.workers_required:
		EventBus.deployment_failed.emit(unit.unit_name, "Requires %d workers, only %d assigned" % [unit.workers_required, unit_workers.size()])
		push_error("[GameState] Cannot deploy %s: Insufficient workers (need %d, have %d)" % [unit.unit_name, unit.workers_required, unit_workers.size()])
		return false

	var occupied := get_occupied_slots(asteroid.asteroid_name)
	if occupied >= asteroid.get_max_mining_slots():
		EventBus.deployment_failed.emit(unit.unit_name, "%s has no available mining slots (%d/%d occupied)" % [asteroid.asteroid_name, occupied, asteroid.get_max_mining_slots()])
		push_error("[GameState] Cannot deploy to %s: All mining slots occupied (%d/%d)" % [asteroid.asteroid_name, occupied, asteroid.get_max_mining_slots()])
		return false
	# Move from inventory to deployed
	mining_unit_inventory.erase(unit)
	deployed_mining_units.append(unit)
	unit.deployed_at_asteroid = asteroid.asteroid_name
	unit.deployed_at_tick = total_ticks
	unit.assigned_workers = []
	for w in unit_workers:
		if w.assigned_mining_unit != null:
			print("[DEPLOY DEBUG] Worker '%s' → '%s' but already has assigned_mining_unit=%s" % [w.worker_name, unit.unit_name, str(w.assigned_mining_unit)])
		unit.assigned_workers.append(w)
		w.assigned_mining_unit = unit
	EventBus.mining_unit_deployed.emit(unit, asteroid)
	return true

func repair_mining_unit(unit: MiningUnit) -> bool:
	var base_cost := unit.repair_cost()
	if base_cost <= 0:
		EventBus.repair_failed.emit(unit.unit_name, "Unit does not need repairs")
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
		EventBus.insufficient_funds.emit("Repair " + unit.unit_name, cost, money)
		EventBus.repair_failed.emit(unit.unit_name, "Insufficient funds ($%s needed, $%s available)" % [cost, money])
		push_error("[GameState] Cannot repair %s: Insufficient funds (need $%s, have $%s)" % [unit.unit_name, cost, money])
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

## Mode-aware mining unit operations - works in both LOCAL and SERVER modes

func purchase_mining_unit_any_mode(entry: Dictionary) -> bool:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		var result = await BackendManager.purchase_rig(entry["name"])
		if result:
			# Server will return the rig; state poll will sync it
			await get_tree().create_timer(1.0).timeout  # Wait for state sync
			return true
		return false
	else:
		return purchase_mining_unit(entry)

func repair_mining_unit_any_mode(unit: MiningUnit) -> bool:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		if unit.server_id > 0:
			var success := await BackendManager.repair_rig(unit.server_id)
			if success:
				await get_tree().create_timer(1.0).timeout  # Wait for state sync
			return success
		else:
			push_error("Cannot repair unit in SERVER mode: unit has no server_id")
			return false
	else:
		return repair_mining_unit(unit)

func rebuild_mining_unit_any_mode(unit: MiningUnit) -> bool:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		if unit.server_id > 0:
			var success := await BackendManager.rebuild_rig(unit.server_id)
			if success:
				await get_tree().create_timer(1.0).timeout  # Wait for state sync
			return success
		else:
			push_error("Cannot rebuild unit in SERVER mode: unit has no server_id")
			return false
	else:
		return rebuild_mining_unit(unit)

func recall_mining_unit_any_mode(unit: MiningUnit) -> bool:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		if unit.server_id > 0:
			var success := await BackendManager.recall_rig(unit.server_id)
			if success:
				await get_tree().create_timer(1.0).timeout  # Wait for state sync
			return success
		else:
			push_error("Cannot recall unit in SERVER mode: unit has no server_id")
			return false
	else:
		recall_mining_unit(unit)
		return true

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
	# Include rival ships currently mining at this asteroid
	count += get_rival_occupied_slots(asteroid_name)
	return count

func get_rival_occupied_slots(asteroid_name: String) -> int:
	var count := 0
	for corp: RivalCorp in rival_corps:
		for ship: RivalShip in corp.ships:
			if ship.status == RivalShip.Status.MINING and ship.target_asteroid_name == asteroid_name:
				count += 1
	return count

func get_player_units_at(asteroid_name: String) -> int:
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
	return asteroid_supplies.get(asteroid_name, {"food": 0.0, "water": 0.0, "oxygen": 0.0, "repair_parts": 0.0})

func add_to_asteroid_supplies(asteroid_name: String, supply_key: String, amount: float) -> void:
	if not asteroid_supplies.has(asteroid_name):
		asteroid_supplies[asteroid_name] = {"food": 0.0, "water": 0.0, "oxygen": 0.0, "repair_parts": 0.0}
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

func start_deploy_mission(ship: Ship, asteroid: AsteroidData, units: Array[MiningUnit], deploy_workers: Array[Worker], transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
	# Validate transit mode before casting
	if transit_mode < 0 or transit_mode >= Mission.TransitMode.size():
		push_error("[GameState] Invalid transit mode %d, defaulting to BRACHISTOCHRONE" % transit_mode)
		transit_mode = Mission.TransitMode.BRACHISTOCHRONE

	var mission := Mission.new()
	mission.ship = ship
	mission.asteroid = asteroid
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
	if mission.origin_is_earth:
		mission.origin_name = "Earth"
	elif ship.docked_at_colony:
		mission.origin_name = ship.docked_at_colony.colony_name
	elif ship.current_mission and ship.current_mission.asteroid:
		mission.origin_name = ship.current_mission.asteroid.asteroid_name
	elif ship.current_trade_mission and ship.current_trade_mission.colony:
		mission.origin_name = ship.current_trade_mission.colony.colony_name
	else:
		mission.origin_name = "deep space"

	var dist := ship.position_au.distance_to(asteroid.get_position_au())

	if slingshot_route:
		mission.outbound_legs = [WaypointLeg.make(slingshot_route.waypoint_pos, slingshot_route.leg1_time, WaypointLeg.WaypointType.GRAVITY_ASSIST, slingshot_route.planet_index)]
		mission.outbound_waypoint_index = 0
		mission.transit_time = slingshot_route.leg2_time
		dist = slingshot_route.leg1_distance
	else:
		if transit_mode == Mission.TransitMode.HOHMANN:
			mission.transit_time = Brachistochrone.hohmann_time(dist)
		else:
			mission.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())

	# Apply pilot skill modifier
	var best_pilot := 0.0
	for w in ship.crew:
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

	# Clear any existing trade mission before assigning new regular mission
	ship.current_trade_mission = null
	ship.current_mission = mission

	# Provision supplies before departure (if at Earth or colony)
	var at_earth_deploy := ship.position_au.distance_to(earth_pos) < 0.05
	if at_earth_deploy or ship.docked_at_colony:
		var crew_size := ship.crew.size() if ship.crew.size() > 0 else ship.min_crew
		ship.supplies["food"] = crew_size * 30.0 * 2.8
		ship.supplies["water"] = crew_size * 30.0 * 0.25 / 20.0
		ship.supplies["oxygen"] = crew_size * 30.0 * 0.05 / 2.0

	ship.docked_at_colony = null
	ship.docked_at_earth = false
	ship.reset_life_support(ship.crew.size())

	missions.append(mission)
	EventBus.mission_started.emit(mission)
	return mission

func start_collect_mission(ship: Ship, asteroid: AsteroidData, transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
	# Validate transit mode before casting
	if transit_mode < 0 or transit_mode >= Mission.TransitMode.size():
		push_error("[GameState] Invalid transit mode %d, defaulting to BRACHISTOCHRONE" % transit_mode)
		transit_mode = Mission.TransitMode.BRACHISTOCHRONE

	# Capture origin location BEFORE clearing idle mission
	var origin_location_name: String = ""
	if ship.current_mission and ship.current_mission.asteroid:
		origin_location_name = ship.current_mission.asteroid.asteroid_name
	elif ship.current_trade_mission and ship.current_trade_mission.colony:
		origin_location_name = ship.current_trade_mission.colony.colony_name

	# Clean up any lingering idle mission so its stale worker list doesn't cause mismatches
	if ship.current_mission and ship.current_mission.status == Mission.Status.IDLE_AT_DESTINATION:
		var old_mission := ship.current_mission
		ship.current_mission = null
		old_mission.cleanup()  # Break circular references
		missions.erase(old_mission)

	var mission := Mission.new()
	mission.ship = ship
	mission.asteroid = asteroid
	mission.mission_type = Mission.MissionType.COLLECT_ORE
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ship.position_au
	mission.return_position_au = ship.position_au
	mission.transit_mode = transit_mode as Mission.TransitMode

	var earth_pos := CelestialData.get_earth_position_au()
	mission.origin_is_earth = ship.position_au.distance_to(earth_pos) < 0.05
	if mission.origin_is_earth:
		mission.origin_name = "Earth"
	elif ship.docked_at_colony:
		mission.origin_name = ship.docked_at_colony.colony_name
	elif origin_location_name != "":
		# Use captured location from before clearing idle mission
		mission.origin_name = origin_location_name
	else:
		mission.origin_name = "deep space"

	var dist := ship.position_au.distance_to(asteroid.get_position_au())

	if slingshot_route:
		mission.outbound_legs = [WaypointLeg.make(slingshot_route.waypoint_pos, slingshot_route.leg1_time, WaypointLeg.WaypointType.GRAVITY_ASSIST, slingshot_route.planet_index)]
		mission.outbound_waypoint_index = 0
		mission.transit_time = slingshot_route.leg2_time
		dist = slingshot_route.leg1_distance
	else:
		if transit_mode == Mission.TransitMode.HOHMANN:
			mission.transit_time = Brachistochrone.hohmann_time(dist)
		else:
			mission.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())

	var best_pilot := 0.0
	for w in ship.crew:
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

	# Clear any existing trade mission before assigning new regular mission
	ship.current_trade_mission = null
	ship.current_mission = mission

	# Provision supplies before departure (if at Earth or colony)
	var at_earth_collect := ship.position_au.distance_to(earth_pos) < 0.05
	if at_earth_collect or ship.docked_at_colony:
		var crew_size := ship.crew.size() if ship.crew.size() > 0 else ship.min_crew
		ship.supplies["food"] = crew_size * 30.0 * 2.8
		ship.supplies["water"] = crew_size * 30.0 * 0.25 / 20.0
		ship.supplies["oxygen"] = crew_size * 30.0 * 0.05 / 2.0

	ship.docked_at_colony = null
	ship.docked_at_earth = false
	ship.reset_life_support(ship.crew.size())

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
		EventBus.repair_failed.emit(equip.equipment_name, "Equipment does not need repairs")
		return false

	if money < cost:
		EventBus.insufficient_funds.emit("Repair " + equip.equipment_name, cost, money)
		EventBus.repair_failed.emit(equip.equipment_name, "Insufficient funds ($%s needed, $%s available)" % [cost, money])
		push_error("[GameState] Cannot repair %s on %s: Insufficient funds (need $%s, have $%s)" % [equip.equipment_name, ship.ship_name, cost, money])
		return false

	money -= cost
	record_transaction(-cost, "Equip repair: %s" % equip.equipment_name, ship.ship_name)
	equip.durability = equip.max_durability
	EventBus.equipment_repaired.emit(ship, equip)
	return true

func repair_engine(ship: Ship) -> bool:
	var cost := ship.get_engine_repair_cost()
	if cost <= 0:
		EventBus.repair_failed.emit(ship.ship_name + " Engine", "Engine does not need repairs")
		return false

	if money < cost:
		EventBus.insufficient_funds.emit("Repair " + ship.ship_name + " engine", cost, money)
		EventBus.repair_failed.emit(ship.ship_name + " Engine", "Insufficient funds ($%s needed, $%s available)" % [cost, money])
		push_error("[GameState] Cannot repair %s engine: Insufficient funds (need $%s, have $%s)" % [ship.ship_name, cost, money])
		return false

	money -= cost
	record_transaction(-cost, "Engine repair", ship.ship_name)
	ship.engine_condition = 100.0
	return true

## Restock torpedoes for all torpedo launchers on a ship
func restock_torpedoes(ship: Ship) -> bool:
	if not ship.is_docked:
		EventBus.operation_failed.emit("Restock Torpedoes", "%s must be docked to restock munitions" % ship.ship_name)
		push_error("[GameState] Cannot restock torpedoes: %s is not docked" % ship.ship_name)
		return false

	# Determine location and munitions quality
	var location_name := "Earth"
	if ship.docked_at_colony != null:
		location_name = ship.docked_at_colony.colony_name
	elif not ship.is_at_earth:
		return false  # Not docked anywhere valid

	var quality: int = MunitionsData.get_quality_at_location(location_name)
	var total_cost := 0
	var restock_list: Array[Equipment] = []

	# Calculate total cost with quality-based pricing
	for equip in ship.equipment:
		if not equip.has_ammo() or not equip.needs_reload():
			continue

		# Block fusion torpedoes at non-Mars locations or insufficient reputation
		if equip.equipment_name == "Fusion Torpedo Launcher":
			if not MunitionsData.can_buy_fusion_torpedoes(location_name, Reputation.score):
				continue  # Skip fusion torpedoes if unavailable

		var needed := equip.ammo_capacity - equip.current_ammo
		var cost_per_round := MunitionsData.get_ammo_cost(equip.ammo_cost, quality)
		total_cost += needed * cost_per_round
		restock_list.append(equip)

	if total_cost <= 0:
		return false  # Nothing to restock

	if money < total_cost:
		return false  # Can't afford

	# Deduct money and restock
	money -= total_cost
	for equip in restock_list:
		var needed := equip.ammo_capacity - equip.current_ammo
		var cost_per_round := MunitionsData.get_ammo_cost(equip.ammo_cost, quality)
		equip.current_ammo = equip.ammo_capacity
		equip.ammo_quality = quality  # Store quality of purchased ammo
		var quality_name := MunitionsData.get_quality_name(quality)
		record_transaction(-needed * cost_per_round, "Torpedoes: %s (%s)" % [equip.equipment_name, quality_name], ship.ship_name)

	return true

## Get cost to restock all torpedoes on a ship (with quality-based pricing)
func get_torpedo_restock_cost(ship: Ship) -> int:
	if not ship.is_docked:
		return 0

	# Determine location and munitions quality
	var location_name := "Earth"
	if ship.docked_at_colony != null:
		location_name = ship.docked_at_colony.colony_name
	elif not ship.is_at_earth:
		return 0

	var quality: int = MunitionsData.get_quality_at_location(location_name)
	var total_cost := 0

	for equip in ship.equipment:
		if not equip.has_ammo() or not equip.needs_reload():
			continue

		# Block fusion torpedoes at non-Mars locations or insufficient reputation
		if equip.equipment_name == "Fusion Torpedo Launcher":
			if not MunitionsData.can_buy_fusion_torpedoes(location_name, Reputation.score):
				continue

		var needed := equip.ammo_capacity - equip.current_ammo
		var cost_per_round := MunitionsData.get_ammo_cost(equip.ammo_cost, quality)
		total_cost += needed * cost_per_round

	return total_cost

## Calculate intercept trajectory to a moving asteroid
## Uses iterative prediction: estimate transit time, predict where asteroid will be, recalculate
## Returns: { intercept_position: Vector2, distance: float, transit_time: float }
func calculate_asteroid_intercept(start_pos: Vector2, asteroid: AsteroidData, thrust: float, transit_mode: int) -> Dictionary:
	var iterations := 3  # Usually converges in 2-3 iterations
	var target_pos := asteroid.get_position_au()  # Start with current position
	var transit_time := 0.0

	for i in iterations:
		var dist := start_pos.distance_to(target_pos)
		if transit_mode == Mission.TransitMode.HOHMANN:
			transit_time = Brachistochrone.hohmann_time(dist)
		else:
			transit_time = Brachistochrone.transit_time(dist, thrust)

		# Predict where asteroid will be when ship arrives
		target_pos = asteroid.get_position_at_time(transit_time)

	# Final calculation with converged position
	var final_dist := start_pos.distance_to(target_pos)
	if transit_mode == Mission.TransitMode.HOHMANN:
		transit_time = Brachistochrone.hohmann_time(final_dist)
	else:
		transit_time = Brachistochrone.transit_time(final_dist, thrust)

	return {
		"intercept_position": target_pos,
		"distance": final_dist,
		"transit_time": transit_time
	}

## Mode-aware mission dispatch - works in both LOCAL and SERVER modes
func dispatch_mission_any_mode(ship: Ship, asteroid: AsteroidData) -> void:
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		# SERVER mode: route through BackendManager using server IDs
		if ship.server_id == 0:
			push_warning("Ship %s has no server_id, cannot dispatch in SERVER mode" % ship.ship_name)
			return

		# Find asteroid ID (index in asteroids array)
		var asteroid_index: int = -1
		for i in range(asteroids.size()):
			if asteroids[i] == asteroid:
				asteroid_index = i
				break

		if asteroid_index < 0:
			push_warning("Asteroid not found: %s" % asteroid.asteroid_name)
			return

		# Server database IDs start at 1, client array indices start at 0
		var server_asteroid_id: int = asteroid_index + 1

		# Dispatch via server backend (async, but we don't await - fire and forget for autoplay)
		BackendManager.dispatch_mission(ship.server_id, server_asteroid_id, 0, 86400.0, false)
	else:
		# LOCAL mode: use local GameState directly
		start_mission(ship, asteroid)

func start_mission(ship: Ship, asteroid: AsteroidData, transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
	if ship.crew.size() < ship.min_crew:
		push_warning("start_mission: not enough crew for %s (need %d, got %d)" % [ship.ship_name, ship.min_crew, ship.crew.size()])
		return null

	# Capture origin location BEFORE clearing idle mission
	var origin_location_name: String = ""
	if ship.current_mission and ship.current_mission.asteroid:
		origin_location_name = ship.current_mission.asteroid.asteroid_name
	elif ship.current_trade_mission and ship.current_trade_mission.colony:
		origin_location_name = ship.current_trade_mission.colony.colony_name

	# Clean up any lingering idle mission so its stale worker list doesn't cause mismatches
	if ship.current_mission and ship.current_mission.status == Mission.Status.IDLE_AT_DESTINATION:
		var old_mission := ship.current_mission
		ship.current_mission = null
		old_mission.cleanup()  # Break circular references
		missions.erase(old_mission)

	var mission := Mission.new()
	mission.ship = ship
	mission.asteroid = asteroid  # Keep reference for mining/game logic
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ship.position_au
	mission.return_position_au = ship.position_au  # default return to origin

	# Validate transit mode before casting
	if transit_mode < 0 or transit_mode >= Mission.TransitMode.size():
		push_error("[GameState] Invalid transit mode %d in start_mission, defaulting to BRACHISTOCHRONE" % transit_mode)
		transit_mode = Mission.TransitMode.BRACHISTOCHRONE
	mission.transit_mode = transit_mode as Mission.TransitMode

	# Set origin flag and name based on ship's current position
	var _earth_pos := CelestialData.get_earth_position_au()
	mission.origin_is_earth = ship.position_au.distance_to(_earth_pos) < 0.05
	if mission.origin_is_earth:
		mission.origin_name = "Earth"
	elif ship.docked_at_colony:
		mission.origin_name = ship.docked_at_colony.colony_name
	elif origin_location_name != "":
		# Use captured location from before clearing idle mission
		mission.origin_name = origin_location_name
	else:
		# Ship is in deep space or unknown location
		mission.origin_name = "deep space"

	# Calculate intercept trajectory to predict where asteroid will be at arrival
	var intercept := calculate_asteroid_intercept(ship.position_au, asteroid, ship.get_effective_thrust(), transit_mode)
	var dist: float = intercept["distance"]
	var predicted_position: Vector2 = intercept["intercept_position"]

	# Store predicted position as static destination (used instead of dynamic asteroid position during transit)
	mission.destination_position_au = predicted_position

	# Setup slingshot waypoints if using gravity assist
	if slingshot_route:
		mission.outbound_legs = [WaypointLeg.make(slingshot_route.waypoint_pos, slingshot_route.leg1_time, WaypointLeg.WaypointType.GRAVITY_ASSIST, slingshot_route.planet_index)]
		mission.outbound_waypoint_index = 0
		mission.transit_time = slingshot_route.leg2_time
		dist = slingshot_route.leg1_distance
	else:
		# Direct route
		if transit_mode == Mission.TransitMode.HOHMANN:
			mission.transit_time = Brachistochrone.hohmann_time(dist)
		else:
			mission.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())

	# Check if fuel stops are needed for outbound journey (use predicted intercept position)
	var expected_cargo_out := ship.get_cargo_total()
	var outbound_fuel_route := FuelRoutePlanner.plan_route_to_position(
		ship,
		predicted_position,
		expected_cargo_out,
		3  # max stops
	)

	if outbound_fuel_route["feasible"] and outbound_fuel_route["waypoints"].size() > 0:
		var waypoints: Array = outbound_fuel_route["waypoints"]
		var colonies: Array = outbound_fuel_route["colonies"]
		var fuel_amounts: Array = outbound_fuel_route["fuel_amounts"]
		var fuel_costs: Array = outbound_fuel_route["fuel_costs"]
		var leg_times: Array = outbound_fuel_route["leg_times"]
		if slingshot_route:
			# Append fuel stops after slingshot waypoint
			for i in range(waypoints.size()):
				mission.outbound_legs.append(WaypointLeg.make(waypoints[i], leg_times[i], WaypointLeg.WaypointType.REFUEL_STOP, -1, colonies[i], fuel_amounts[i], fuel_costs[i]))
		else:
			# Fuel stops only — build legs from scratch
			mission.outbound_legs.clear()
			for i in range(waypoints.size()):
				mission.outbound_legs.append(WaypointLeg.make(waypoints[i], leg_times[i], WaypointLeg.WaypointType.REFUEL_STOP, -1, colonies[i], fuel_amounts[i], fuel_costs[i]))
			# Final leg time (from last stop to destination) stays in mission.transit_time
			if leg_times.size() > waypoints.size():
				mission.transit_time = leg_times[waypoints.size()]
			elif outbound_fuel_route.has("final_leg_time"):
				mission.transit_time = outbound_fuel_route["final_leg_time"]

		# Deduct total fuel cost upfront
		money -= outbound_fuel_route["total_cost"]

	# Calculate mining duration first (needed to predict return timing)
	var skill_total := 0.0
	for w in ship.crew:
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

	# Predict where Earth will be when ship returns (if returning to Earth)
	if mission.origin_is_earth:
		var estimated_mission_time := mission.transit_time * 2.0 + mission.mining_duration
		mission.return_position_au = CelestialData.get_earth_position_at_time(estimated_mission_time)
	# else: return_position_au already set to ship.position_au for colony returns

	# Calculate return fuel stops (assume full cargo, use predicted Earth position)
	var expected_cargo_return := ship.cargo_capacity
	var return_fuel_route := FuelRoutePlanner.plan_route_to_position(
		ship,
		mission.return_position_au,
		expected_cargo_return,
		3
	)

	if return_fuel_route["feasible"] and return_fuel_route["waypoints"].size() > 0:
		var ret_waypoints: Array = return_fuel_route["waypoints"]
		var ret_colonies: Array = return_fuel_route["colonies"]
		var ret_fuel_amounts: Array = return_fuel_route["fuel_amounts"]
		var ret_fuel_costs: Array = return_fuel_route["fuel_costs"]
		var ret_leg_times: Array = return_fuel_route["leg_times"]
		mission.return_legs.clear()
		for i in range(ret_waypoints.size()):
			mission.return_legs.append(WaypointLeg.make(ret_waypoints[i], ret_leg_times[i], WaypointLeg.WaypointType.REFUEL_STOP, -1, ret_colonies[i], ret_fuel_amounts[i], ret_fuel_costs[i]))

		# Deduct return fuel cost upfront
		money -= return_fuel_route["total_cost"]

	# Apply pilot skill modifier to transit time
	var best_pilot := 0.0
	for w in ship.crew:
		if w.pilot_skill > best_pilot:
			best_pilot = w.pilot_skill
	var pilot_factor := 1.15 - (best_pilot * 0.2)  # 0.0 = 1.15x slower, 1.0 = 0.95x, 1.5 = 0.85x
	mission.transit_time *= pilot_factor

	mission.elapsed_ticks = 0.0

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

	# Clear any existing trade mission before assigning new regular mission
	ship.current_trade_mission = null
	ship.current_mission = mission
	# Stationed ships keep existing cargo (they accumulate over multiple mining runs)
	if not ship.is_stationed:
		ship.current_cargo.clear()

	# Partnership support: create shadow mission for follower
	if ship.is_partnered() and ship.is_partnership_leader:
		var follower := ship.partner_ship
		if follower != null and follower.current_mission == null:
			# Create shadow mission for follower
			var shadow := Mission.new()
			shadow.ship = follower
			shadow.asteroid = asteroid
			shadow.status = Mission.Status.TRANSIT_OUT
			shadow.is_partnership_shadow = true
			shadow.partnership_leader_ship_name = ship.ship_name
			shadow.partnership_leader_mission = mission

			# Copy route and timing from leader
			shadow.origin_position_au = follower.position_au
			shadow.return_position_au = follower.position_au
			shadow.origin_is_earth = mission.origin_is_earth
			shadow.origin_name = mission.origin_name
			shadow.destination_position_au = mission.destination_position_au
			shadow.transit_mode = mission.transit_mode
			shadow.outbound_legs = mission.outbound_legs.duplicate(true)
			shadow.return_legs = mission.return_legs.duplicate(true)
			shadow.transit_time = mission.transit_time
			shadow.mining_duration = mission.mining_duration
			shadow.mission_type = mission.mission_type
			shadow.elapsed_ticks = 0.0

			# Calculate follower's own fuel consumption (based on follower's mass/thrust)
			var follower_cargo := follower.get_cargo_total()
			var follower_fuel_out := follower.calc_fuel_for_distance(dist, follower_cargo)
			var follower_fuel_ret := follower.calc_fuel_for_distance(dist, follower.cargo_capacity)
			var follower_total_fuel := follower_fuel_out + follower_fuel_ret
			if transit_mode == Mission.TransitMode.HOHMANN:
				follower_total_fuel *= Brachistochrone.hohmann_fuel_multiplier()
			var follower_total_transit := shadow.transit_time * 2.0
			shadow.fuel_per_tick = follower_total_fuel / follower_total_transit if follower_total_transit > 0 else 0.0

			# Provision follower's supplies
			var follower_crew_size := follower.crew.size() if follower.crew.size() > 0 else follower.min_crew
			follower.supplies["food"] = follower_crew_size * 30.0 * 2.8
			follower.supplies["water"] = follower_crew_size * 30.0 * 0.25 / 20.0
			follower.supplies["oxygen"] = follower_crew_size * 30.0 * 0.05 / 2.0
			follower.reset_life_support(follower.crew.size())

			follower.current_mission = shadow
			follower.docked_at_colony = null
			follower.docked_at_earth = false
			if not follower.is_stationed:
				follower.current_cargo.clear()

			missions.append(shadow)
			EventBus.mission_started.emit(shadow)

	# Provision supplies before departure (if at Earth or colony)
	var _earth_pos_check := CelestialData.get_earth_position_au()
	var at_earth := ship.position_au.distance_to(_earth_pos_check) < 0.05
	if at_earth or ship.docked_at_colony:
		var crew_size := ship.crew.size() if ship.crew.size() > 0 else ship.min_crew
		ship.supplies["food"] = crew_size * 30.0 * 2.8
		ship.supplies["water"] = crew_size * 30.0 * 0.25 / 20.0
		ship.supplies["oxygen"] = crew_size * 30.0 * 0.05 / 2.0

	ship.docked_at_colony = null  # Ship is departing
	ship.docked_at_earth = false
	ship.reset_life_support(ship.crew.size())

	missions.append(mission)

	# Calculate trajectory visualization (once, cached for drawing)
	mission.calculate_trajectory_curves()

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
		# Transfer cargo from ship to Earth — either sell immediately or stockpile
		if settings.get("auto_sell_at_earth", true):
			var revenue := 0
			for ore_type in mission.ship.current_cargo:
				var amount: float = mission.ship.current_cargo[ore_type]
				var price: float = MarketData.get_ore_price(ore_type)
				revenue += int(amount * price)
			if revenue > 0:
				money += revenue
				record_transaction(revenue, "Ore sold at Earth", mission.ship.ship_name)
		else:
			for ore_type in mission.ship.current_cargo:
				add_resource(ore_type, mission.ship.current_cargo[ore_type])
		mission.ship.current_cargo.clear()

	mission.ship.current_mission = null
	mission.status = Mission.Status.COMPLETED
	EventBus.mission_completed.emit(mission)
	mission.cleanup()  # Break circular references
	missions.erase(mission)

	# Stationed ships don't use queued missions — station logic handles next job
	if mission.ship.is_stationed:
		return
	# Queued missions are launched in simulation.gd after provision/repair completes

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

## Returns the light-travel delay in game-seconds to reach this ship.
## Docked ships have zero delay (direct line comms).
func calc_signal_delay(ship: Ship) -> float:
	if ship.is_docked:
		return 0.0
	return ship.position_au.distance_to(CelestialData.get_earth_position_au()) * LIGHT_SECONDS_PER_AU

## Queue an order to a ship with lightspeed delay.
## If delay == 0 (ship is docked), executes immediately.
## Returns the delay in game-seconds.
func queue_ship_order(ship: Ship, label: String, fn: Callable) -> float:
	var delay := calc_signal_delay(ship)
	if delay > 0.0:
		pending_orders.append({
			"fires_at": total_ticks + delay,
			"ship": ship,
			"label": label,
			"fn": fn,
		})
		EventBus.order_queued.emit(ship, label, delay)
	else:
		fn.call()
	return delay

## Called each tick from simulation to fire ready orders.
func process_pending_orders() -> void:
	var remaining: Array[Dictionary] = []
	for order in pending_orders:
		if total_ticks >= order["fires_at"]:
			order["fn"].call()
			# Only emit order_executed for actual ship orders (not warnings)
			if order["ship"] != null:
				EventBus.order_executed.emit(order["ship"], order["label"])
		else:
			remaining.append(order)
	pending_orders = remaining

## Partnership system - create a partnership between two ships
func create_partnership(leader: Ship, follower: Ship) -> bool:
	# Validate
	var check := leader.can_partner_with(follower)
	if not check["valid"]:
		push_warning("Cannot create partnership: %s" % check["reason"])
		return false

	# Create bidirectional partnership
	leader.partner_ship = follower
	leader.partner_ship_name = follower.ship_name
	leader.is_partnership_leader = true

	follower.partner_ship = leader
	follower.partner_ship_name = leader.ship_name
	follower.is_partnership_leader = false

	EventBus.partnership_created.emit(leader, follower)
	return true

## Partnership system - break a partnership between two ships
func break_partnership(ship1: Ship, ship2: Ship, reason: String) -> void:
	ship1.partner_ship = null
	ship1.partner_ship_name = ""
	ship1.is_partnership_leader = false

	ship2.partner_ship = null
	ship2.partner_ship_name = ""
	ship2.is_partnership_leader = false

	EventBus.partnership_broken.emit(ship1, ship2, reason)

	# Convert shadow mission to independent mission
	if ship2.current_mission and ship2.current_mission.is_partnership_shadow:
		ship2.current_mission.is_partnership_shadow = false
		ship2.current_mission.partnership_leader_mission = null

## Returns the pending order dictionary for a ship, or {} if none.
func get_pending_order(ship: Ship) -> Dictionary:
	for order in pending_orders:
		if order["ship"] == ship:
			return order
	return {}

func order_return_to_earth(ship: Ship) -> void:
	if not ship.is_idle_remote:
		return
	queue_ship_order(ship, "Return to Earth", func(): _apply_order_return_to_earth(ship))

func _apply_order_return_to_earth(ship: Ship) -> void:
	# Start a transit-back mission from current idle position to Earth
	if not ship.is_idle_remote:
		return  # State changed while signal was in transit

	# CRITICAL: Update ship position to asteroid's current position before calculating distance
	# This prevents the ancient teleporting bug where ships leave from wrong locations
	if ship.current_mission and ship.current_mission.asteroid:
		ship.position_au = ship.current_mission.asteroid.get_position_au()

	var earth_pos := CelestialData.get_earth_position_au()
	var dist := ship.position_au.distance_to(earth_pos)

	if ship.current_mission:
		# Reuse existing mission for return
		ship.current_mission.return_position_au = earth_pos
		ship.current_mission.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())
		ship.current_mission.elapsed_ticks = 0.0
		# CRITICAL: Clear return legs and reset index - prevents using stale waypoint positions
		ship.current_mission.return_legs.clear()
		ship.current_mission.return_waypoint_index = 0
		var cargo_mass := ship.get_cargo_total()
		var total_fuel := ship.calc_fuel_for_distance(dist, cargo_mass)
		ship.current_mission.fuel_per_tick = total_fuel / ship.current_mission.transit_time if ship.current_mission.transit_time > 0 else 0.0
		ship.current_mission.status = Mission.Status.TRANSIT_BACK
		EventBus.mission_phase_changed.emit(ship.current_mission)
	elif ship.current_trade_mission:
		ship.current_trade_mission.return_position_au = earth_pos
		ship.current_trade_mission.transit_time = Brachistochrone.transit_time(dist, ship.get_effective_thrust())
		ship.current_trade_mission.elapsed_ticks = 0.0
		# CRITICAL: Clear return legs and reset index - prevents using stale waypoint positions
		ship.current_trade_mission.return_legs.clear()
		ship.current_trade_mission.return_waypoint_index = 0
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
		# Clear any existing trade mission before assigning new regular mission
		ship.current_trade_mission = null
		ship.current_mission = mission
		missions.append(mission)
		EventBus.mission_started.emit(mission)

func dispatch_idle_ship(ship: Ship, asteroid: AsteroidData, transit_mode: int = Mission.TransitMode.BRACHISTOCHRONE, slingshot_route = null) -> Mission:
	var label := "Dispatch to " + asteroid.asteroid_name
	queue_ship_order(ship, label, func(): _apply_dispatch_idle_ship(ship, asteroid, transit_mode, slingshot_route))
	return null  # Callers should not rely on the return value when ship is remote

func _apply_dispatch_idle_ship(ship: Ship, asteroid: AsteroidData, transit_mode: int, slingshot_route) -> void:
	if not ship.is_idle_remote:
		return  # Ship state changed while signal was in transit
	# Capture origin name before clearing missions
	var origin_asteroid_name := ""
	if ship.current_mission and ship.current_mission.asteroid:
		origin_asteroid_name = ship.current_mission.asteroid.asteroid_name
	elif ship.current_trade_mission and ship.current_trade_mission.colony:
		origin_asteroid_name = ship.current_trade_mission.colony.colony_name

	# End idle state and start new mission from current position
	if ship.current_mission:
		var old_mission := ship.current_mission
		ship.current_mission = null
		old_mission.cleanup()  # Break circular references
		missions.erase(old_mission)
	if ship.current_trade_mission:
		var old_trade_mission := ship.current_trade_mission
		ship.current_trade_mission = null
		old_trade_mission.cleanup()  # Break circular references
		trade_missions.erase(old_trade_mission)

	var mission := start_mission(ship, asteroid, transit_mode, slingshot_route)
	if mission == null:
		return
	mission.origin_is_earth = false
	mission.origin_name = origin_asteroid_name if origin_asteroid_name != "" else "deep space"

func dispatch_idle_ship_trade(ship: Ship, colony_target: Colony, cargo_to_load: Dictionary, transit_mode: int = TradeMission.TransitMode.BRACHISTOCHRONE) -> TradeMission:
	var label := "Trade mission to " + colony_target.colony_name
	queue_ship_order(ship, label, func(): _apply_dispatch_idle_ship_trade(ship, colony_target, cargo_to_load, transit_mode))
	return null  # Callers should not rely on the return value when ship is remote

func _apply_dispatch_idle_ship_trade(ship: Ship, colony_target: Colony, cargo_to_load: Dictionary, transit_mode: int) -> void:
	if not ship.is_idle_remote:
		return  # Ship state changed while signal was in transit
	# Capture origin name before clearing missions
	var origin_loc_name := ""
	if ship.current_mission and ship.current_mission.asteroid:
		origin_loc_name = ship.current_mission.asteroid.asteroid_name
	elif ship.current_trade_mission and ship.current_trade_mission.colony:
		origin_loc_name = ship.current_trade_mission.colony.colony_name

	# End idle state and start new trade mission from current position
	if ship.current_mission:
		var old_mission := ship.current_mission
		ship.current_mission = null
		old_mission.cleanup()  # Break circular references
		missions.erase(old_mission)
	if ship.current_trade_mission:
		var old_trade_mission := ship.current_trade_mission
		ship.current_trade_mission = null
		old_trade_mission.cleanup()  # Break circular references
		trade_missions.erase(old_trade_mission)

	var tm := start_trade_mission(ship, colony_target, cargo_to_load, transit_mode)
	if tm == null:
		return
	tm.origin_is_earth = false
	tm.origin_name = origin_loc_name if origin_loc_name != "" else "deep space"

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
		EventBus.operation_failed.emit("Rescue", "%s is not derelict and does not need rescue" % ship.ship_name)
		return false

	if ship in rescue_missions:
		EventBus.operation_failed.emit("Rescue", "%s rescue already in progress" % ship.ship_name)
		return false

	# Calculate rescue feasibility and cost
	var rescue_info := calculate_rescue_info(ship)

	# Check if rescue is even possible
	if not rescue_info["feasible"]:
		# Emit event with failure reason
		EventBus.rescue_impossible.emit(ship, rescue_info["reason"])
		push_error("[GameState] Rescue of %s not feasible: %s" % [ship.ship_name, rescue_info["reason"]])
		return false

	var cost: int = rescue_info["cost"]

	if money < cost:
		EventBus.insufficient_funds.emit("Rescue " + ship.ship_name, cost, money)
		EventBus.operation_failed.emit("Rescue", "Insufficient funds for %s rescue ($%s needed, $%s available)" % [ship.ship_name, cost, money])
		push_error("[GameState] Cannot rescue %s: Insufficient funds (need $%s, have $%s)" % [ship.ship_name, cost, money])
		return false

	money -= cost

	var source := _find_nearest_rescue_source(ship.position_au)

	rescue_missions[ship] = {
		"elapsed_ticks": 0.0,
		"transit_time": rescue_info["time"],
		"workers": ship.crew.duplicate(),
		"source_name": source["name"],
		"source_pos": source["pos"],
	}

	EventBus.rescue_mission_started.emit(ship, cost)
	return true

func start_fleet_rescue(ferry_ship: Ship, target_ship: Ship, rescue_crew: Array[Worker], food_units: float, parts_units: float) -> Mission:
	# ferry_ship: the docked ship being dispatched to help
	# target_ship: the derelict fleet ship
	# rescue_crew: workers who will stay on target_ship on arrival
	# food_units, parts_units: supplies to commit from ferry_ship now and transfer on arrival

	# Build worker list from ferry's last crew + available workers.
	# Rescue missions require only 1 crew — the ship will fly understaffed
	# and head straight to the nearest crew pickup on return.
	# Use ferry's crew for the rescue mission; rescue_crew will be left on the target ship
	var all_workers: Array[Worker] = ferry_ship.crew.duplicate()
	# Add rescue crew if not already on ship (they may be from a different source)
	for w in rescue_crew:
		if w not in all_workers:
			all_workers.append(w)
	# Top up to 2 from available workers if needed (minimum for rescue: 1 stays on derelict, 1 flies back)
	if all_workers.size() < 2:
		for w in get_available_workers():
			if w not in all_workers:
				all_workers.append(w)
			if all_workers.size() >= 2:
				break
	if all_workers.size() < 2:
		push_warning("start_fleet_rescue: need at least 2 crew for %s" % ferry_ship.ship_name)
		return null

	var dist := ferry_ship.position_au.distance_to(target_ship.position_au)
	var transit_t := Brachistochrone.transit_time(dist, ferry_ship.get_effective_thrust())

	var mission := Mission.new()
	mission.mission_type = Mission.MissionType.CREW_FERRY
	mission.is_derelict_rescue = true
	mission.rescue_crew = rescue_crew.duplicate()
	mission.supplies_to_transfer = {"food": food_units, "repair_parts": parts_units}
	mission.ship = ferry_ship
	ferry_ship.crew = all_workers
	mission.status = Mission.Status.TRANSIT_OUT
	mission.origin_position_au = ferry_ship.position_au
	mission.return_position_au = ferry_ship.position_au
	mission.origin_is_earth = ferry_ship.is_at_earth
	if mission.origin_is_earth:
		mission.origin_name = "Earth"
	elif ferry_ship.docked_at_colony:
		mission.origin_name = ferry_ship.docked_at_colony.colony_name
	mission.destination_position_au = target_ship.position_au
	mission.destination_name = target_ship.ship_name
	mission.station_job_duration = 3600.0  # 1 hour for crew + supply transfer
	mission.transit_time = transit_t
	mission.fuel_per_tick = ferry_ship.calc_fuel_for_distance(dist) / transit_t if transit_t > 0 else 0.0

	ferry_ship.current_mission = mission

	# Commit supplies from ferry ship (deducted now; transferred on arrival)
	ferry_ship.supplies["food"] = maxf(0.0, ferry_ship.supplies.get("food", 0.0) - food_units)
	ferry_ship.supplies["repair_parts"] = maxf(0.0, ferry_ship.supplies.get("repair_parts", 0.0) - parts_units)

	missions.append(mission)
	EventBus.mission_started.emit(mission)
	return mission

## Find the fleet rescue ferry currently heading to a derelict ship (if any).
func find_fleet_rescue_ferry(derelict_ship: Ship) -> Ship:
	for s in ships:
		if s.current_mission == null:
			continue
		if s.current_mission.mission_type != Mission.MissionType.CREW_FERRY:
			continue
		if not s.current_mission.is_derelict_rescue:
			continue
		if s.current_mission.destination_name == derelict_ship.ship_name or \
			s.current_mission.destination_position_au.distance_to(derelict_ship.position_au) < 0.1:
			return s
	return null

## Cancel a fleet rescue in progress — recalls the ferry, workers return with it.
func cancel_fleet_rescue(derelict_ship: Ship) -> void:
	var ferry := find_fleet_rescue_ferry(derelict_ship)
	if ferry == null or ferry.current_mission == null:
		return
	var mission := ferry.current_mission
	var earth_pos := CelestialData.get_earth_position_au()
	var dist := ferry.position_au.distance_to(earth_pos)
	# Flip mission to TRANSIT_BACK to Earth, keeping current position and momentum
	mission.return_position_au = earth_pos
	mission.return_to_station = false
	mission.transit_time = Brachistochrone.transit_time(dist, ferry.get_effective_thrust())
	mission.elapsed_ticks = 0.0
	var cargo_mass := ferry.get_cargo_total()
	mission.fuel_per_tick = ferry.calc_fuel_for_distance(dist, cargo_mass) / mission.transit_time \
		if mission.transit_time > 0 else 0.0
	mission.status = Mission.Status.TRANSIT_BACK
	EventBus.mission_phase_changed.emit(mission)

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
	# Ensure ship has a crew assigned (use existing crew or auto-assign from available)
	if ship.crew.is_empty() or ship.crew.size() < ship.min_crew:
		var available := get_available_workers()
		# Filter to workers at the same colony
		var local_workers: Array[Worker] = []
		for w in available:
			if w.home_colony == colony.colony_name:
				local_workers.append(w)
		for i in range(mini(ship.min_crew - ship.crew.size(), local_workers.size())):
			var result := assign_worker_to_ship(local_workers[i], ship)
			if not result["success"]:
				push_warning("Failed to auto-assign worker to stationed ship: %s" % result["error"])
	else:
		for w in ship.crew:
			w.assigned_ship = ship
	ship.add_station_log("Stationed at %s" % colony.colony_name, "system")
	EventBus.ship_stationed.emit(ship, colony)

func unstation_ship(ship: Ship) -> void:
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
	var volume_per_unit := 0.0
	for supply_type in SupplyData.SUPPLY_INFO:
		var info: Dictionary = SupplyData.SUPPLY_INFO[supply_type]
		if info["key"] == supply_key:
			cost_per_unit = info["cost_per_unit"]
			mass_per_unit = info["mass_per_unit"]
			volume_per_unit = info.get("volume_per_unit", 0.0)
			break

	if cost_per_unit <= 0:
		return false

	var total_mass := amount * mass_per_unit
	# Check cargo capacity (supplies share space with ore)
	var available_space := ship.get_cargo_remaining() - ship.get_supplies_mass()
	if total_mass > available_space + 0.01:
		return false

	# Check cargo volume
	var total_volume := amount * volume_per_unit
	if total_volume > ship.get_cargo_volume_remaining() + 0.01:
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
		pass  # Workers assigned to mining units are tracked via assigned_mining_unit
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
	# Record abandonment violation before firing
	record_abandonment_violation(worker, "Worker %s abandoned (fired while tardy)" % worker.worker_name)

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
	var to_deliver: float = minf(ship_cargo, minf(amount, remaining))

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

func start_trade_mission(ship: Ship, colony_target: Colony, cargo_to_load: Dictionary, transit_mode: int = TradeMission.TransitMode.BRACHISTOCHRONE) -> TradeMission:
	if ship.crew.size() < ship.min_crew:
		push_warning("start_trade_mission: not enough crew for %s (need %d, got %d)" % [ship.ship_name, ship.min_crew, ship.crew.size()])
		return null
	var tm := TradeMission.new()
	tm.ship = ship
	tm.colony = colony_target
	tm.status = TradeMission.Status.TRANSIT_TO_COLONY
	tm.origin_position_au = ship.position_au
	tm.return_position_au = ship.position_au  # default return to origin
	tm.transit_mode = transit_mode as TradeMission.TransitMode

	# Set origin flag and name based on ship's current position
	var _tm_earth_pos := CelestialData.get_earth_position_au()
	tm.origin_is_earth = ship.position_au.distance_to(_tm_earth_pos) < 0.05
	if tm.origin_is_earth:
		tm.origin_name = "Earth"
	elif ship.docked_at_colony:
		tm.origin_name = ship.docked_at_colony.colony_name
	# else: left blank; dispatch_idle_ship_trade will fill it in

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
				var to_load: float = minf(amount, on_board)
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
		var tm_out_waypoints: Array = outbound_fuel_route["waypoints"]
		var tm_out_colonies: Array = outbound_fuel_route["colonies"]
		var tm_out_fuel_amounts: Array = outbound_fuel_route["fuel_amounts"]
		var tm_out_fuel_costs: Array = outbound_fuel_route["fuel_costs"]
		var tm_out_leg_times: Array = outbound_fuel_route["leg_times"]
		tm.outbound_legs.clear()
		for i in range(tm_out_waypoints.size()):
			tm.outbound_legs.append(WaypointLeg.make(tm_out_waypoints[i], tm_out_leg_times[i], WaypointLeg.WaypointType.REFUEL_STOP, -1, tm_out_colonies[i], tm_out_fuel_amounts[i], tm_out_fuel_costs[i]))
		if tm_out_leg_times.size() > tm_out_waypoints.size():
			tm.transit_time = tm_out_leg_times[tm_out_waypoints.size()]
		elif outbound_fuel_route.has("final_leg_time"):
			tm.transit_time = outbound_fuel_route["final_leg_time"]

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
		var tm_ret_waypoints: Array = return_fuel_route["waypoints"]
		var tm_ret_colonies: Array = return_fuel_route["colonies"]
		var tm_ret_fuel_amounts: Array = return_fuel_route["fuel_amounts"]
		var tm_ret_fuel_costs: Array = return_fuel_route["fuel_costs"]
		var tm_ret_leg_times: Array = return_fuel_route["leg_times"]
		tm.return_legs.clear()
		for i in range(tm_ret_waypoints.size()):
			tm.return_legs.append(WaypointLeg.make(tm_ret_waypoints[i], tm_ret_leg_times[i], WaypointLeg.WaypointType.REFUEL_STOP, -1, tm_ret_colonies[i], tm_ret_fuel_amounts[i], tm_ret_fuel_costs[i]))

		# Deduct return fuel cost upfront
		money -= return_fuel_route["total_cost"]

	# Apply pilot skill modifier to transit time
	var best_pilot := 0.0
	for w in ship.crew:
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

	# Provision supplies before departure (if at Earth or colony)
	var at_earth_trade := ship.position_au.distance_to(_tm_earth_pos) < 0.05
	if at_earth_trade or ship.docked_at_colony:
		var crew_size := ship.crew.size() if ship.crew.size() > 0 else ship.min_crew
		ship.supplies["food"] = crew_size * 30.0 * 2.8
		ship.supplies["water"] = crew_size * 30.0 * 0.25 / 20.0
		ship.supplies["oxygen"] = crew_size * 30.0 * 0.05 / 2.0

	ship.docked_at_colony = null  # Ship is departing
	ship.docked_at_earth = false
	ship.reset_life_support(ship.crew.size())

	trade_missions.append(tm)
	EventBus.trade_mission_started.emit(tm)

	# Check if any hitchhiking workers can catch this ride
	var trade_route_points: Array[Vector2] = [colony_target.get_position_au()]
	check_hitchhike_opportunities(ship, trade_route_points)

	return tm

func complete_trade_mission(tm: TradeMission) -> void:
	# If the ship still has unsold cargo (e.g. returned to Earth without selling),
	# return it to the stockpile rather than losing it.
	if not tm.cargo.is_empty():
		for ore_type in tm.cargo:
			add_resource(ore_type, tm.cargo[ore_type])
		tm.cargo.clear()
	tm.ship.current_cargo.clear()
	tm.ship.current_trade_mission = null
	tm.status = TradeMission.Status.COMPLETED
	EventBus.trade_mission_completed.emit(tm)
	tm.cleanup()  # Break circular references
	trade_missions.erase(tm)

	# Stationed ships don't use queued missions — station logic handles next job
	if tm.ship.is_stationed:
		return
	# Queued missions are launched in simulation.gd after provision/repair completes

func _start_queued_mission(ship: Ship) -> void:
	# Automatically start a player-planned mission after the current one completes.
	# Falls back to policy dispatch if the queued mission is no longer feasible.
	if not ship.has_queued_mission():
		return

	var dest = ship.queued_destination
	var mission_type = ship.queued_mission_type
	var transit_mode = ship.queued_transit_mode
	var slingshot_route = ship.queued_slingshot_route

	# Clear the queue before starting (avoids recursion if start_mission re-emits signals)
	ship.clear_queued_mission()

	if ship.crew.size() < ship.min_crew:
		# Not enough crew — fall through to policy on next tick
		return

	if dest is AsteroidData:
		var asteroid := dest as AsteroidData
		# Feasibility: enough fuel for round trip?
		var dist := ship.position_au.distance_to(asteroid.get_position_au())
		var fuel_out := ship.calc_fuel_for_distance(dist, ship.get_cargo_total())
		var fuel_back := ship.calc_fuel_for_distance(dist, ship.get_effective_cargo_capacity())
		if fuel_out + fuel_back > ship.fuel:
			# Not enough fuel — fall through to policy on next tick
			return
		match mission_type:
			Mission.MissionType.COLLECT_ORE:
				start_collect_mission(ship, asteroid, transit_mode, slingshot_route)
			Mission.MissionType.REPOSITION:
				var mission := start_mission(ship, asteroid, transit_mode, slingshot_route)
				if mission:
					mission.mission_type = Mission.MissionType.REPOSITION
			_:  # Default: MINING
				start_mission(ship, asteroid, transit_mode, slingshot_route)


# ══════════════════════════════════════════════════════════════════════════════
# LEADERBOARD SYSTEM
# ══════════════════════════════════════════════════════════════════════════════

## Calculate current net worth (money + ship values + cargo values)
func calculate_net_worth() -> int:
	var total := money

	# Add ship values (using purchase price as estimate)
	for ship in ships:
		var price: int = ShipData.CLASS_PRICES.get(ship.ship_class, 0)
		total += price

	# Add cargo value (ore in ships)
	if market:
		for ship in ships:
			for ore_type in ship.current_cargo:
				var price: float = market.get_price(ore_type)
				total += int(ship.current_cargo[ore_type] * price)

	# Add ore in storage
	if market:
		for ore_type in resources:
			var price: float = market.get_price(ore_type)
			total += int(resources[ore_type] * price)

	return total


## Submit current game state to local leaderboard
func submit_leaderboard_entry() -> void:
	var net_worth := calculate_net_worth()
	var entry := {
		"player_name": player_name,
		"net_worth": net_worth,
		"timestamp": Time.get_unix_time_from_system(),
		"game_date": get_game_date_string(),
		"ships_count": ships.size(),
		"workers_count": workers.size(),
	}

	local_leaderboard.append(entry)

	# Sort by net worth descending
	local_leaderboard.sort_custom(func(a, b): return a["net_worth"] > b["net_worth"])

	# Keep only top entries
	if local_leaderboard.size() > MAX_LEADERBOARD_ENTRIES:
		local_leaderboard = local_leaderboard.slice(0, MAX_LEADERBOARD_ENTRIES)


## Get local leaderboard sorted by net worth
func get_local_leaderboard() -> Array:
	# Return copy so UI can't modify original
	return local_leaderboard.duplicate(true)


# Save/Load
func save_game(save_name: String = "") -> void:
	# Generate file name from save name
	var file_name := "save_game.json"  # Default for backwards compatibility
	if save_name != "":
		# Create safe filename from save name
		var safe_name := save_name.to_lower().replace(" ", "_").replace("/", "_").replace("\\", "_")
		file_name = "save_%s.json" % safe_name

	var save_data := {
		"save_name": save_name if save_name != "" else "Quicksave",
		"save_timestamp": Time.get_unix_time_from_system(),
		"net_worth": calculate_net_worth(),
		"money": money,
		"total_ticks": total_ticks,
		"game_start_month": game_start_month,
		"game_start_day": game_start_day,
		"game_start_year": game_start_year,
		"total_crew_deaths": total_crew_deaths,
		# Policies (always-on automation)
		"thrust_policy": thrust_policy,
		"repair_policy": repair_policy,
		"cargo_policy": cargo_policy,
		"collection_policy": collection_policy,
		"supply_policy": supply_policy,
		"encounter_policy": encounter_policy,
		"maintenance_policy": maintenance_policy,
		# Autoplay Settings (AI strategy)
		"autoplay_risk_tolerance": autoplay_risk_tolerance,
		"autoplay_growth_rate": autoplay_growth_rate,
		"autoplay_resource_focus": autoplay_resource_focus,
		"autoplay_diversification": autoplay_diversification,
		"autoplay_workforce": autoplay_workforce,
		"autoplay_technology": autoplay_technology,
		"autoplay_market_timing": autoplay_market_timing,
		"autoplay_territorial": autoplay_territorial,
		"autoplay_contract_priority": autoplay_contract_priority,
		"autoplay_upgrade_preference": autoplay_upgrade_preference,
		"autoplay_debt_tolerance": autoplay_debt_tolerance,
		"autoplay_partnership_strategy": autoplay_partnership_strategy,
		"autoplay_rescue_priority": autoplay_rescue_priority,
		"autoplay_colony_preference": autoplay_colony_preference,
		"autoplay_retrofit_schedule": autoplay_retrofit_schedule,
		"autoplay_exploration_focus": autoplay_exploration_focus,
		"resources": {},
		"workers": [],
		"ships": [],
		"market_prices": {},
		"missions": [],
		"trade_missions": [],
		"available_contracts": [],
		"active_contracts": [],
		"market_events": [],
		"rival_corps": [],
		"autoplay": settings.get("autoplay", false),
		"auto_sell_at_earth": settings.get("auto_sell_at_earth", true),
		"auto_sell_at_markets": settings.get("auto_sell_at_markets", false),
		"auto_restock_torpedoes": settings.get("auto_restock_torpedoes", true),
		"fabrication_queue": [],
		"reputation": Reputation.score,
		"rescue_missions": {},
		"refuel_missions": {},
		"stranger_offers": {},
		"player_name": player_name,
		"local_leaderboard": local_leaderboard,
	}
	for ore_type in resources:
		save_data["resources"][str(ore_type)] = resources[ore_type]
	if market:
		# Save location-based market data
		save_data["market_locations"] = {}
		for location in market.location_prices:
			save_data["market_locations"][location] = {
				"prices": {},
				"inventory": {}
			}
			for ore_type in market.location_prices[location]:
				save_data["market_locations"][location]["prices"][str(ore_type)] = market.location_prices[location][ore_type]
			for ore_type in market.location_inventory[location]:
				save_data["market_locations"][location]["inventory"][str(ore_type)] = market.location_inventory[location][ore_type]
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
		# Crew
		ship_data["crew"] = s.crew.map(func(w: Worker) -> String: return w.worker_name)
		# Policy overrides
		ship_data["thrust_policy_override"] = s.thrust_policy_override
		ship_data["supply_policy_override"] = s.supply_policy_override
		ship_data["collection_policy_override"] = s.collection_policy_override
		ship_data["encounter_policy_override"] = s.encounter_policy_override
		ship_data["repair_policy_override"] = s.repair_policy_override
		ship_data["cargo_policy_override"] = s.cargo_policy_override
		ship_data["maintenance_policy_override"] = s.maintenance_policy_override
		ship_data["trading_policy_override"] = s.trading_policy_override
		ship_data["morale_policy_override"] = s.morale_policy_override
		ship_data["automation_policy_override"] = s.automation_policy_override
		ship_data["aggression_stance"] = s.aggression_stance
		ship_data["docked_at_earth"] = s.docked_at_earth
		# Partnership data
		if s.is_partnered():
			ship_data["partner_ship_name"] = s.partner_ship_name
			ship_data["is_partnership_leader"] = s.is_partnership_leader
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
				"weapon_power": e.weapon_power,
				"weapon_range": e.weapon_range,
				"weapon_accuracy": e.weapon_accuracy,
				"weapon_role": e.weapon_role,
				"fire_rate": e.fire_rate,
				"ammo_capacity": e.ammo_capacity,
				"current_ammo": e.current_ammo,
				"ammo_cost": e.ammo_cost,
				"ammo_quality": e.ammo_quality,
				"mining_speed_bonus": e.mining_speed_bonus,
				"mass": e.mass,
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
			"origin_name": m.origin_name,
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
			"outbound_legs": m.outbound_legs.map(func(l: WaypointLeg) -> Dictionary: return l.to_dict()),
			"outbound_waypoint_index": m.outbound_waypoint_index,
			"return_legs": m.return_legs.map(func(l: WaypointLeg) -> Dictionary: return l.to_dict()),
			"return_waypoint_index": m.return_waypoint_index,
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
			"origin_name": tm.origin_name,
			"return_position_au": {"x": tm.return_position_au.x, "y": tm.return_position_au.y},
			"transit_mode": tm.transit_mode,
			"revenue": tm.revenue,
			"outbound_legs": tm.outbound_legs.map(func(l: WaypointLeg) -> Dictionary: return l.to_dict()),
			"outbound_waypoint_index": tm.outbound_waypoint_index,
			"return_legs": tm.return_legs.map(func(l: WaypointLeg) -> Dictionary: return l.to_dict()),
			"return_waypoint_index": tm.return_waypoint_index,
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

	# Save active warnings
	save_data["active_warnings"] = active_warnings.duplicate()
	save_data["next_warning_id"] = _next_warning_id

	# Save rival corps (ship states only — corp definitions recreated from RivalCorpData)
	var rival_data: Array[Dictionary] = []
	for corp: RivalCorp in rival_corps:
		var corp_entry := { "name": corp.corp_name, "money": corp.money,
			"total_ore_mined": corp.total_ore_mined, "total_revenue": corp.total_revenue,
			"aggression": corp.aggression, "skill": corp.skill,
			"colony_standings": corp.colony_standings.duplicate(true),
			"ships": [] }
		for ship: RivalShip in corp.ships:
			corp_entry["ships"].append({
				"status": ship.status,
				"target_asteroid_name": ship.target_asteroid_name,
				"target_position_au_x": ship.target_position_au.x,
				"target_position_au_y": ship.target_position_au.y,
				"cargo_tons": ship.cargo_tons,
				"transit_time": ship.transit_time,
				"elapsed_ticks": ship.elapsed_ticks,
				"mining_elapsed": ship.mining_elapsed,
				"mining_duration": ship.mining_duration,
			})
		rival_data.append(corp_entry)
	save_data["rival_corps"] = rival_data

	# Save colony criminal ban data
	var colony_data: Array[Dictionary] = []
	for colony in colonies:
		colony_data.append({
			"name": colony.colony_name,
			"violations": colony.violations.duplicate(),
			"player_banned": colony.player_banned,
		})
	save_data["colonies"] = colony_data

	# Submit to leaderboard before saving
	submit_leaderboard_entry()

	var file := FileAccess.open("user://" + file_name, FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data, "\t"))

func load_game(file_name: String = "save_game.json") -> bool:
	# In SERVER mode, don't load local saves - server is the source of truth
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		print("[GameState] Skipping local save load in SERVER mode - using server data only")
		return false

	if not FileAccess.file_exists("user://" + file_name):
		return false
	var file := FileAccess.open("user://" + file_name, FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return false
	var data: Dictionary = json.data

	money = int(data.get("money", 10000))

	# Policies (always-on automation)
	thrust_policy = int(data.get("thrust_policy", CompanyPolicy.ThrustPolicy.BALANCED))
	repair_policy = int(data.get("repair_policy", CompanyPolicy.RepairPolicy.ALWAYS))
	cargo_policy = int(data.get("cargo_policy", CompanyPolicy.CargoPolicy.STANDARD))
	collection_policy = int(data.get("collection_policy", CompanyPolicy.CollectionPolicy.ROUTINE))
	supply_policy = int(data.get("supply_policy", CompanyPolicy.SupplyPolicy.ROUTINE))
	encounter_policy = int(data.get("encounter_policy", CompanyPolicy.EncounterPolicy.COEXIST))
	maintenance_policy = int(data.get("maintenance_policy", CompanyPolicy.MaintenancePolicy.AS_NEEDED))

	# Autoplay Settings (AI strategy) - backward compatible with old saves
	autoplay_risk_tolerance = int(data.get("autoplay_risk_tolerance", 50))
	autoplay_growth_rate = int(data.get("autoplay_growth_rate", 50))
	autoplay_resource_focus = int(data.get("autoplay_resource_focus", 50))
	autoplay_diversification = int(data.get("autoplay_diversification", AutoplaySettings.DiversificationStrategy.MIXED))
	autoplay_workforce = int(data.get("autoplay_workforce", AutoplaySettings.WorkforcePhilosophy.ADEQUATE))
	autoplay_technology = int(data.get("autoplay_technology", AutoplaySettings.TechnologyInvestment.BALANCED))
	autoplay_market_timing = int(data.get("autoplay_market_timing", AutoplaySettings.MarketTiming.IMMEDIATE))
	autoplay_territorial = int(data.get("autoplay_territorial", AutoplaySettings.TerritorialStrategy.REGIONAL))
	autoplay_contract_priority = int(data.get("autoplay_contract_priority", AutoplaySettings.ContractPriority.OPPORTUNISTIC))
	autoplay_upgrade_preference = int(data.get("autoplay_upgrade_preference", AutoplaySettings.UpgradePreference.BALANCED))
	autoplay_debt_tolerance = int(data.get("autoplay_debt_tolerance", AutoplaySettings.DebtTolerance.CONSERVATIVE))
	autoplay_partnership_strategy = int(data.get("autoplay_partnership_strategy", AutoplaySettings.PartnershipStrategy.CONTESTED_ONLY))
	autoplay_rescue_priority = int(data.get("autoplay_rescue_priority", AutoplaySettings.RescuePriority.COST_CONSCIOUS))
	autoplay_colony_preference = int(data.get("autoplay_colony_preference", AutoplaySettings.ColonyPreference.PRICE_OPTIMIZE))
	autoplay_retrofit_schedule = int(data.get("autoplay_retrofit_schedule", AutoplaySettings.RetrofitSchedule.BALANCED))
	autoplay_exploration_focus = int(data.get("autoplay_exploration_focus", AutoplaySettings.ExplorationFocus.BALANCED))
	settings["autoplay"] = data.get("autoplay", false)
	settings["auto_sell_at_earth"] = data.get("auto_sell_at_earth", true)
	settings["auto_sell_at_markets"] = data.get("auto_sell_at_markets", false)
	settings["auto_restock_torpedoes"] = data.get("auto_restock_torpedoes", true)

	_init_resources()
	var res_data: Dictionary = data.get("resources", {})
	for key in res_data:
		resources[int(key)] = float(res_data[key])

	# Restore market prices and inventory
	if market:
		# Try new format first (location-based markets)
		var location_data: Dictionary = data.get("market_locations", {})
		if not location_data.is_empty():
			for location in location_data:
				if market.location_prices.has(location):
					var prices: Dictionary = location_data[location].get("prices", {})
					for key in prices:
						market.location_prices[location][int(key)] = float(prices[key])
					var inventory: Dictionary = location_data[location].get("inventory", {})
					for key in inventory:
						market.location_inventory[location][int(key)] = float(inventory[key])
		else:
			# Fallback for old saves (global prices only) - apply to all locations
			var price_data: Dictionary = data.get("market_prices", {})
			for location in market.location_prices:
				for key in price_data:
					market.location_prices[location][int(key)] = float(price_data[key])

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
		s.ship_name = sd.get("ship_name", "Ship")
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
		# Restore policy overrides
		s.thrust_policy_override = int(sd.get("thrust_policy_override", -1))
		s.supply_policy_override = int(sd.get("supply_policy_override", -1))
		s.collection_policy_override = int(sd.get("collection_policy_override", -1))
		s.encounter_policy_override = int(sd.get("encounter_policy_override", -1))
		s.repair_policy_override = int(sd.get("repair_policy_override", -1))
		s.cargo_policy_override = int(sd.get("cargo_policy_override", -1))
		s.maintenance_policy_override = int(sd.get("maintenance_policy_override", -1))
		s.trading_policy_override = int(sd.get("trading_policy_override", -1))
		s.morale_policy_override = int(sd.get("morale_policy_override", -1))
		s.automation_policy_override = int(sd.get("automation_policy_override", -1))
		s.aggression_stance = int(sd.get("aggression_stance", Ship.AggressionStance.DEFENSIVE))
		s.docked_at_earth = bool(sd.get("docked_at_earth", true))
		# Restore partnership data (references resolved after all ships loaded)
		s.partner_ship_name = sd.get("partner_ship_name", "")
		s.is_partnership_leader = sd.get("is_partnership_leader", false)
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
			# Restore weapon ammo if saved (for torpedoes)
			if ed.has("current_ammo"):
				e.current_ammo = int(ed.get("current_ammo", e.ammo_capacity))
			# Restore ammo quality (default to STANDARD for old saves)
			e.ammo_quality = int(ed.get("ammo_quality", 1))  # 1 = MunitionsData.Quality.STANDARD
			s.equipment.append(e)
		ships.append(s)

	# Restore game clock and statistics
	total_ticks = float(data.get("total_ticks", 0.0))
	game_start_month = int(data.get("game_start_month", 0))
	game_start_day = int(data.get("game_start_day", 0))
	game_start_year = int(data.get("game_start_year", 2112))
	total_crew_deaths = int(data.get("total_crew_deaths", 0))

	# Reconnect ship crew from saved worker names
	var ship_save_array: Array = data.get("ships", [])
	for sd in ship_save_array:
		var ship_name_str: String = sd.get("name", "")
		for ship in ships:
			if ship.ship_name == ship_name_str:
				for wname in sd.get("crew", []):
					for w in workers:
						if w.worker_name == wname:
							var result := assign_worker_to_ship(w, ship)
							if not result["success"]:
								# Backward compat: relocate worker to ship's location on load
								if ship.docked_at_earth:
									w.home_colony = "Earth"
								elif ship.docked_at_colony:
									w.home_colony = ship.docked_at_colony.colony_name
								# Try assignment again
								result = assign_worker_to_ship(w, ship)
								if not result["success"]:
									push_warning("Failed to assign crew from save: %s" % result["error"])
							break
				break

	# Reconnect station colony references (colonies loaded at _ready)
	for ship in ships:
		if ship.is_stationed:
			for sd in ship_save_array:
				if sd.get("name", "") == ship.ship_name:
					var colony_name: String = sd.get("station_colony_name", "")
					if colony_name != "":
						for colony in colonies:
							if colony.colony_name == colony_name:
								ship.station_colony = colony
								break
					break

	# Resolve partnership references (like crew resolution)
	for s in ships:
		if s.partner_ship_name != "":
			var partner_arr := ships.filter(func(sh): return sh.ship_name == s.partner_ship_name)
			if not partner_arr.is_empty():
				s.partner_ship = partner_arr[0]
			else:
				push_warning("Could not resolve partner ship: %s" % s.partner_ship_name)
				s.partner_ship_name = ""

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
		m.origin_name = str(md.get("origin_name", ""))
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
		# Restore waypoint legs
		for leg_dict in md.get("outbound_legs", []):
			m.outbound_legs.append(WaypointLeg.from_dict(leg_dict, colonies))
		m.outbound_waypoint_index = int(md.get("outbound_waypoint_index", 0))
		for leg_dict in md.get("return_legs", []):
			m.return_legs.append(WaypointLeg.from_dict(leg_dict, colonies))
		m.return_waypoint_index = int(md.get("return_waypoint_index", 0))
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
		tm.origin_name = str(tmd.get("origin_name", ""))
		var return_data: Dictionary = tmd.get("return_position_au", {})
		if return_data.has("x") and return_data.has("y"):
			tm.return_position_au = Vector2(float(return_data["x"]), float(return_data["y"]))

		# Restore cargo
		var cargo_data: Dictionary = tmd.get("cargo", {})
		for key in cargo_data:
			tm.cargo[int(key)] = float(cargo_data[key])

		# Restore waypoint legs
		for leg_dict in tmd.get("outbound_legs", []):
			tm.outbound_legs.append(WaypointLeg.from_dict(leg_dict, colonies))
		tm.outbound_waypoint_index = int(tmd.get("outbound_waypoint_index", 0))
		for leg_dict in tmd.get("return_legs", []):
			tm.return_legs.append(WaypointLeg.from_dict(leg_dict, colonies))
		tm.return_waypoint_index = int(tmd.get("return_waypoint_index", 0))

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
					"workers": ship.crew.duplicate(),
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

	# Restore active warnings
	active_warnings = data.get("active_warnings", [])
	_next_warning_id = int(data.get("next_warning_id", 0))

	# Restore mining unit inventory
	const MU_VOL_DEFAULTS: Dictionary = {0: 11.4, 1: 16.8, 2: 27.3}
	mining_unit_inventory.clear()
	for mud in data.get("mining_unit_inventory", []):
		var unit := MiningUnit.new()

		# Validate unit type before casting
		var unit_type_int: int = int(mud.get("unit_type", 0))
		if unit_type_int < 0 or unit_type_int >= MiningUnit.UnitType.size():
			push_error("[GameState] Invalid mining unit type %d in save data, defaulting to RIG" % unit_type_int)
			unit_type_int = MiningUnit.UnitType.RIG
		unit.unit_type = unit_type_int as MiningUnit.UnitType
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

		# Validate unit type before casting
		var unit_type_int: int = int(mud.get("unit_type", 0))
		if unit_type_int < 0 or unit_type_int >= MiningUnit.UnitType.size():
			push_error("[GameState] Invalid deployed mining unit type %d in save data, defaulting to RIG" % unit_type_int)
			unit_type_int = MiningUnit.UnitType.RIG
		unit.unit_type = unit_type_int as MiningUnit.UnitType
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

	# Restore rival corp states — rebuild structure from RivalCorpData, then overlay saved state
	rival_corps = RivalCorpData.create_all()
	var saved_rivals: Array = data.get("rival_corps", [])
	for i in min(rival_corps.size(), saved_rivals.size()):
		var corp: RivalCorp = rival_corps[i]
		var cd: Dictionary = saved_rivals[i]
		corp.money = int(cd.get("money", corp.money))
		corp.total_ore_mined = float(cd.get("total_ore_mined", 0.0))
		corp.total_revenue = int(cd.get("total_revenue", 0))
		corp.aggression = float(cd.get("aggression", corp.aggression))
		corp.skill = float(cd.get("skill", corp.skill))
		corp.colony_standings = cd.get("colony_standings", {}).duplicate(true)
		var saved_ships: Array = cd.get("ships", [])
		for j in min(corp.ships.size(), saved_ships.size()):
			var ship: RivalShip = corp.ships[j]
			var shipd: Dictionary = saved_ships[j]
			ship.status = int(shipd.get("status", RivalShip.Status.IDLE))
			ship.target_asteroid_name = shipd.get("target_asteroid_name", "")
			ship.target_position_au = Vector2(
				float(shipd.get("target_position_au_x", 0.0)),
				float(shipd.get("target_position_au_y", 0.0)))
			ship.cargo_tons = float(shipd.get("cargo_tons", 0.0))
			ship.transit_time = float(shipd.get("transit_time", 0.0))
			ship.elapsed_ticks = float(shipd.get("elapsed_ticks", 0.0))
			ship.mining_elapsed = float(shipd.get("mining_elapsed", 0.0))
			ship.mining_duration = float(shipd.get("mining_duration", 86400.0))

	# Restore colony criminal ban data
	var saved_colonies: Array = data.get("colonies", [])
	for colony_data in saved_colonies:
		var colony_name: String = colony_data.get("name", "")
		# Find matching colony in colonies array
		for colony in colonies:
			if colony.colony_name == colony_name:
				colony.violations = colony_data.get("violations", [])
				colony.player_banned = colony_data.get("player_banned", false)
				break

	# Load leaderboard data
	player_name = data.get("player_name", "Player")
	local_leaderboard.clear()
	for entry_data in data.get("local_leaderboard", []):
		local_leaderboard.append(entry_data.duplicate())

	return true


# ══════════════════════════════════════════════════════════════════════════════
# SERVER STATE SYNC (Phase 1: Read-Only Polling)
# ══════════════════════════════════════════════════════════════════════════════

## Apply server state to local GameState
## Called periodically when in SERVER mode to sync with server simulation
func apply_server_state(server_data: Dictionary) -> void:
	if server_data.is_empty():
		return

	# Track if state changed for logging
	var old_money := money
	var old_ship_count := ships.size()
	var old_worker_count := workers.size()
	var old_rig_count := mining_unit_inventory.size() + deployed_mining_units.size()
	var state_changed := false

	# Update money (triggers money_changed signal)
	var new_money: int = int(server_data.get("money", money))
	if new_money != money:
		money = new_money
		state_changed = true

	# Update total_ticks from server (for date/time display)
	total_ticks = int(server_data.get("total_ticks", total_ticks))

	# Update speed multiplier from server (sync client display with server speed)
	var server_speed: float = float(server_data.get("speed_multiplier", 1.0))
	if TimeScale.speed_multiplier != server_speed:
		TimeScale.speed_multiplier = server_speed

	# Update player policies (always-on automation)
	repair_policy = int(server_data.get("repair_policy", repair_policy))
	cargo_policy = int(server_data.get("cargo_policy", cargo_policy))
	collection_policy = int(server_data.get("collection_policy", collection_policy))
	supply_policy = int(server_data.get("supply_policy", supply_policy))
	encounter_policy = int(server_data.get("encounter_policy", encounter_policy))
	maintenance_policy = int(server_data.get("maintenance_policy", maintenance_policy))

	# Update autoplay settings (AI strategy)
	autoplay_risk_tolerance = int(server_data.get("autoplay_risk_tolerance", autoplay_risk_tolerance))
	autoplay_growth_rate = int(server_data.get("autoplay_growth_rate", autoplay_growth_rate))
	autoplay_resource_focus = int(server_data.get("autoplay_resource_focus", autoplay_resource_focus))
	settings["auto_sell_on_return"] = bool(server_data.get("auto_sell_on_return", settings.get("auto_sell_on_return", true)))

	# Update ships (server only has: id, ship_name, fuel, cargo, position, is_stationed)
	# In SERVER mode, match by server_id and update existing ships or create new ones
	var server_ships: Array = server_data.get("ships", [])

	# Build map of existing ships by server_id for fast lookup
	var local_ships_by_id: Dictionary = {}
	for ship in ships:
		if ship.server_id > 0:
			local_ships_by_id[ship.server_id] = ship

	# Track which server_ids we've seen (to remove deleted ships later)
	var seen_server_ids: Array[int] = []

	for ship_data in server_ships:
		var ship_id: int = int(ship_data.get("id", 0))
		seen_server_ids.append(ship_id)

		var ship: Ship = null
		var is_new := false

		# Match by server_id
		if local_ships_by_id.has(ship_id):
			ship = local_ships_by_id[ship_id]
		else:
			ship = ShipData.create_ship(
				int(ship_data.get("ship_class", 0)),
				str(ship_data.get("ship_name", "Ship"))
			)
			ship.server_id = ship_id
			is_new = true
			# Ship created from server data

		# Update fields from server data (only if changed for existing ships)
		var ship_changed := is_new

		# Helper macro to update if different
		var new_fuel := float(ship_data.get("fuel", 200.0))
		if ship.fuel != new_fuel:
			ship.fuel = new_fuel
			ship_changed = true

		var new_pos_x := float(ship_data.get("position_x", 1.0))
		var new_pos_y := float(ship_data.get("position_y", 0.0))
		if ship.position_au.x != new_pos_x or ship.position_au.y != new_pos_y:
			ship.position_au.x = new_pos_x
			ship.position_au.y = new_pos_y
			ship_changed = true

		var new_condition := float(ship_data.get("engine_condition", 100.0))
		if ship.engine_condition != new_condition:
			ship.engine_condition = new_condition
			ship_changed = true

		var new_derelict := bool(ship_data.get("is_derelict", false))
		if ship.is_derelict != new_derelict:
			ship.is_derelict = new_derelict
			ship_changed = true

		var new_docked := bool(ship_data.get("is_stationed", true))
		if ship.server_docked != new_docked:
			ship.server_docked = new_docked
			ship_changed = true

		# Parse cargo and check if changed
		var server_cargo: Dictionary = ship_data.get("current_cargo", {})
		var cargo_changed := false
		var new_cargo := {}
		for ore_key in server_cargo:
			var ore_type := _parse_ore_type(ore_key)
			if ore_type >= 0:
				new_cargo[ore_type] = float(server_cargo[ore_key])

		if new_cargo != ship.current_cargo:
			ship.current_cargo = new_cargo
			cargo_changed = true
			ship_changed = true

		if ship_changed:
			state_changed = true

		# Add new ships to the array
		if is_new:
			ships.append(ship)

	# Remove ships that no longer exist on server
	for i in range(ships.size() - 1, -1, -1):
		var ship := ships[i]
		if ship.server_id > 0 and not seen_server_ids.has(ship.server_id):
			print("[GameState] Removing ship no longer on server: %s (id %d)" % [ship.ship_name, ship.server_id])
			ships.remove_at(i)

	# Update workers (server only has: id, first_name, last_name, skills, xp, wage)
	# In SERVER mode, match by server_id and update existing workers or create new ones
	var server_workers: Array = server_data.get("workers", [])

	# Build map of existing workers by server_id for fast lookup
	var local_workers_by_id: Dictionary = {}
	for worker in workers:
		if worker.server_id > 0:
			local_workers_by_id[worker.server_id] = worker

	# Track which server_ids we've seen (to remove deleted workers later)
	var seen_worker_ids: Array[int] = []

	for worker_data in server_workers:
		var worker_id: int = int(worker_data.get("id", 0))
		seen_worker_ids.append(worker_id)

		var worker: Worker = null
		var is_new := false

		# Match by server_id
		if local_workers_by_id.has(worker_id):
			worker = local_workers_by_id[worker_id]
		else:
			# Create new worker
			worker = Worker.new()
			worker.server_id = worker_id
			var first := str(worker_data.get("first_name", ""))
			var last := str(worker_data.get("last_name", ""))
			worker.worker_name = (first + " " + last).strip_edges()
			var colony_id: int = int(worker_data.get("location_colony_id", 1))
			worker.home_colony = ColonyData.get_colony_name(colony_id)
			worker.personality = int(worker_data.get("personality", 2))
			is_new = true

		# Update fields from server data (only if changed for existing workers)
		var worker_changed := is_new

		var new_xp_p := float(worker_data.get("pilot_xp", 0.0))
		var new_xp_e := float(worker_data.get("engineer_xp", 0.0))
		var new_xp_m := float(worker_data.get("mining_xp", 0.0))
		if worker.pilot_xp != new_xp_p or worker.engineer_xp != new_xp_e or worker.mining_xp != new_xp_m:
			worker.pilot_xp = new_xp_p
			worker.engineer_xp = new_xp_e
			worker.mining_xp = new_xp_m
			worker_changed = true

		var new_skill_p := float(worker_data.get("pilot_skill", 0.0))
		var new_skill_e := float(worker_data.get("engineer_skill", 0.0))
		var new_skill_m := float(worker_data.get("mining_skill", 0.0))
		if worker.pilot_skill != new_skill_p or worker.engineer_skill != new_skill_e or worker.mining_skill != new_skill_m:
			worker.pilot_skill = new_skill_p
			worker.engineer_skill = new_skill_e
			worker.mining_skill = new_skill_m
			worker_changed = true

		var new_wage := int(worker_data.get("wage", 100))
		if worker.wage != new_wage:
			worker.wage = new_wage
			worker_changed = true

		var new_fatigue := float(worker_data.get("fatigue", 0.0))
		if worker.fatigue != new_fatigue:
			worker.fatigue = new_fatigue
			worker_changed = true

		if worker_changed:
			state_changed = true

		# Add new workers to the array
		if is_new:
			workers.append(worker)

	# Remove workers that no longer exist on server
	for i in range(workers.size() - 1, -1, -1):
		var worker := workers[i]
		if worker.server_id > 0 and not seen_worker_ids.has(worker.server_id):
			workers.remove_at(i)

	# Update rigs (server has: id, unit_type, unit_name, durability, max_durability, deployed_at_asteroid_id, etc.)
	var server_rigs: Array = server_data.get("rigs", [])

	# Build map of existing rigs by server_id
	var local_rigs_by_id: Dictionary = {}
	for unit in mining_unit_inventory:
		if unit.server_id > 0:
			local_rigs_by_id[unit.server_id] = unit
	for unit in deployed_mining_units:
		if unit.server_id > 0:
			local_rigs_by_id[unit.server_id] = unit

	var seen_rig_ids: Array[int] = []

	for rig_data in server_rigs:
		var rig_id: int = int(rig_data.get("id", 0))
		seen_rig_ids.append(rig_id)

		var unit: MiningUnit = null
		var is_new := false

		# Try to find existing rig by server_id
		if local_rigs_by_id.has(rig_id):
			unit = local_rigs_by_id[rig_id]
		else:
			# Create new rig
			unit = MiningUnit.new()
			unit.server_id = rig_id
			is_new = true

		# Update fields from server
		var server_unit_type: int = int(rig_data.get("unit_type", 0))

		# Validate unit type before casting
		if server_unit_type < 0 or server_unit_type >= MiningUnit.UnitType.size():
			push_error("[GameState] Invalid server mining unit type %d, defaulting to RIG" % server_unit_type)
			server_unit_type = MiningUnit.UnitType.RIG

		if unit.unit_type != server_unit_type:
			unit.unit_type = server_unit_type as MiningUnit.UnitType
			state_changed = true

		var server_name: String = str(rig_data.get("unit_name", ""))
		if unit.unit_name != server_name:
			unit.unit_name = server_name
			state_changed = true

		var server_mass: float = float(rig_data.get("mass", 0.0))
		if abs(unit.mass - server_mass) > 0.01:
			unit.mass = server_mass
			state_changed = true

		var server_workers_req: int = int(rig_data.get("workers_required", 1))
		if unit.workers_required != server_workers_req:
			unit.workers_required = server_workers_req
			state_changed = true

		var server_mining_mult: float = float(rig_data.get("mining_multiplier", 1.0))
		if abs(unit.mining_multiplier - server_mining_mult) > 0.01:
			unit.mining_multiplier = server_mining_mult
			state_changed = true

		var server_cost: int = int(rig_data.get("cost", 0))
		if unit.cost != server_cost:
			unit.cost = server_cost
			state_changed = true

		var server_durability: float = float(rig_data.get("durability", 100.0))
		if abs(unit.durability - server_durability) > 0.01:
			unit.durability = server_durability
			state_changed = true

		var server_max_durability: float = float(rig_data.get("max_durability", 100.0))
		if abs(unit.max_durability - server_max_durability) > 0.01:
			unit.max_durability = server_max_durability
			state_changed = true

		var server_wear: float = float(rig_data.get("wear_per_day", 0.3))
		if abs(unit.wear_per_day - server_wear) > 0.01:
			unit.wear_per_day = server_wear
			state_changed = true

		# Handle deployment status
		var server_deployed_ast_id = rig_data.get("deployed_at_asteroid_id", null)
		var is_deployed := server_deployed_ast_id != null

		if is_deployed:
			# Find asteroid by server ID (1-based) - convert to 0-based array index
			var server_ast_id: int = int(server_deployed_ast_id)
			var asteroid_index := server_ast_id - 1
			var target_asteroid: AsteroidData = null

			if asteroid_index >= 0 and asteroid_index < asteroids.size():
				target_asteroid = asteroids[asteroid_index]

			if target_asteroid:
				var new_ast_name: String = target_asteroid.asteroid_name
				if unit.deployed_at_asteroid != new_ast_name:
					unit.deployed_at_asteroid = new_ast_name
					state_changed = true

				var server_deployed_tick: float = float(rig_data.get("deployed_at_tick", 0.0))
				if abs(unit.deployed_at_tick - server_deployed_tick) > 0.01:
					unit.deployed_at_tick = server_deployed_tick
					state_changed = true

				# Ensure rig is in deployed list
				if is_new:
					deployed_mining_units.append(unit)
				elif mining_unit_inventory.has(unit):
					mining_unit_inventory.erase(unit)
					deployed_mining_units.append(unit)
			else:
				push_warning("Rig %d deployed to invalid asteroid ID %d (index %d out of bounds, have %d asteroids)" % [rig_id, server_ast_id, asteroid_index, asteroids.size()])
		else:
			# Rig is in inventory
			if unit.deployed_at_asteroid != "":
				unit.deployed_at_asteroid = ""
				unit.deployed_at_tick = 0.0
				state_changed = true

				# Clear worker assignments when rig is recalled
				for worker in unit.assigned_workers:
					worker.assigned_to_ship = null
					worker.assigned_to_mining_unit = null
				unit.assigned_workers.clear()

			# Ensure rig is in inventory list
			if is_new:
				mining_unit_inventory.append(unit)
			elif deployed_mining_units.has(unit):
				deployed_mining_units.erase(unit)
				mining_unit_inventory.append(unit)

	# Remove rigs that no longer exist on server
	for i in range(mining_unit_inventory.size() - 1, -1, -1):
		var unit := mining_unit_inventory[i]
		if unit.server_id > 0 and not seen_rig_ids.has(unit.server_id):
			mining_unit_inventory.remove_at(i)
			state_changed = true

	for i in range(deployed_mining_units.size() - 1, -1, -1):
		var unit := deployed_mining_units[i]
		if unit.server_id > 0 and not seen_rig_ids.has(unit.server_id):
			deployed_mining_units.remove_at(i)
			state_changed = true

	# Update missions (server has: id, ship_id, status, elapsed_ticks, transit_time)
	var server_missions: Array = server_data.get("active_missions", [])
	# TODO: Sync mission state when server has full mission data
	# For now, client-side missions are the source of truth

	# Check if ships, workers, or rigs changed
	var new_rig_count := mining_unit_inventory.size() + deployed_mining_units.size()
	if ships.size() != old_ship_count or workers.size() != old_worker_count or new_rig_count != old_rig_count:
		state_changed = true

	# Only log and emit when state changes (less noisy)
	if state_changed:
		# State synced from server
		EventBus.server_state_synced.emit()


## Helper to map server ore names to client OreType enum
func _parse_ore_type(ore_key: String) -> ResourceTypes.OreType:
	match ore_key.to_lower():
		"iron":
			return ResourceTypes.OreType.IRON
		"nickel":
			return ResourceTypes.OreType.NICKEL
		"platinum":
			return ResourceTypes.OreType.PLATINUM
		"water_ice", "water-ice":
			return ResourceTypes.OreType.WATER_ICE
		"carbon_organics", "carbon-organics", "carbon":
			return ResourceTypes.OreType.CARBON_ORGANICS
		_:
			return -1  # Unknown ore type


# ══════════════════════════════════════════════════════════════════════════════
# SERVER EVENT HANDLERS (SSE Real-Time Updates)
# ══════════════════════════════════════════════════════════════════════════════

## Apply worker skill level-up event from server
## Event format: {type, worker_id, player_id, skill_type, new_value, worker_name}
func apply_worker_skill_event(event: Dictionary) -> void:
	var worker_name: String = event.get("worker_name", "")
	var skill_type_str: String = event.get("skill_type", "")
	var new_value: float = float(event.get("new_value", 0.0))

	# Find worker by name
	var found_worker: Worker = null
	for worker in workers:
		if worker.worker_name == worker_name:
			found_worker = worker
			break

	if not found_worker:
		push_warning("apply_worker_skill_event: Worker '%s' not found" % worker_name)
		return

	# Map skill type string to int (0=pilot, 1=engineer, 2=mining)
	var skill_type_int := -1
	match skill_type_str:
		"pilot":
			found_worker.pilot_skill = new_value
			skill_type_int = 0
		"engineer":
			found_worker.engineer_skill = new_value
			skill_type_int = 1
		"mining":
			found_worker.mining_skill = new_value
			skill_type_int = 2
		_:
			push_warning("apply_worker_skill_event: Unknown skill type '%s'" % skill_type_str)
			return

	# Recalculate wage (server does this too, but we mirror it for consistency)
	var total_skill := found_worker.pilot_skill + found_worker.engineer_skill + found_worker.mining_skill
	found_worker.wage = int(80 + total_skill * 40)

	print("[GameState] Worker skill updated via SSE: %s - %s → %.2f (wage: $%d)" % [
		worker_name, skill_type_str, new_value, found_worker.wage
	])

	# Emit signal for UI update (signal expects int for skill_type)
	EventBus.worker_skill_leveled.emit(found_worker, skill_type_int, new_value)


## Apply market price update event from server
## Event format: {type: "market_update", prices: {ore_name: new_price, ...}}
func apply_market_update_event(event: Dictionary) -> void:
	var prices: Dictionary = event.get("prices", {})

	if prices.is_empty():
		return

	# Log market updates for now
	# TODO: Integrate with local economy system (MarketState is per-instance, needs refactor)
	var updated_count := prices.size()
	if updated_count > 0:
		print("[GameState] Market prices updated via SSE: %d ore types" % updated_count)
		for ore_name in prices:
			var new_price: float = float(prices[ore_name])
			print("  - %s: $%.0f" % [ore_name, new_price])
		EventBus.market_state_changed.emit()



# ══════════════════════════════════════════════════════════════════════════════
# MULTIPLAYER WORLD STATE (All Players' Ships)
# ══════════════════════════════════════════════════════════════════════════════

## Apply shared world state from server (multiplayer)
## Shows all players' ships on solar map
## Format: {ships: [{id, player_id, owner_username, ship_name, position_x, position_y, ...}, ...]}
func apply_world_state(world_data: Dictionary) -> void:
	var all_ships: Array = world_data.get("ships", [])

	if all_ships.is_empty():
		return

	# Clear previous other players' ships
	other_players_ships.clear()

	# Current player's ID (from server backend)
	var my_player_id: int = 0
	if BackendManager.current_mode == BackendManager.BackendMode.SERVER:
		var server_backend = BackendManager.get_server_backend()
		if server_backend:
			my_player_id = server_backend.player_id

	# Separate own ships from others
	for ship_data in all_ships:
		var ship_player_id: int = int(ship_data.get("player_id", 0))

		# Skip own ships (they're already in GameState.ships via apply_server_state)
		if ship_player_id == my_player_id:
			continue

		# Store other players' ships as dictionaries
		# Extract just the fields we need for display
		var other_ship := {
			"owner_username": ship_data.get("owner_username", "Unknown"),
			"ship_name": ship_data.get("ship_name", "Ship"),
			"ship_class": int(ship_data.get("ship_class", 0)),
			"position_x": float(ship_data.get("position_x", 0.0)),
			"position_y": float(ship_data.get("position_y", 0.0)),
			"is_stationed": bool(ship_data.get("is_stationed", true)),
			"is_derelict": bool(ship_data.get("is_derelict", false)),
		}

		other_players_ships.append(other_ship)

	if other_players_ships.size() > 0:
		print("[GameState] Multiplayer: Loaded %d other players' ships" % other_players_ships.size())

		# Emit signal so solar map can update
		EventBus.world_state_updated.emit()
