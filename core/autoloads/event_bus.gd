extends Node

# All signals in this file are emitted from other scripts and connected elsewhere.
# GDScript cannot see cross-file usage, so we suppress the false-positive warning.
@warning_ignore_start("unused_signal")

# Money & resources
signal money_changed(new_amount: int)
signal resource_changed(ore_type: ResourceTypes.OreType, new_amount: float)

# Workers
signal worker_hired(worker: Worker)
signal worker_fired(worker: Worker)
signal worker_assigned(worker: Worker, target)  # target can be Ship or MiningUnit
signal worker_unassigned(worker: Worker)
signal worker_skill_leveled(worker: Worker, skill_type: int, new_value: float)
signal worker_wage_increased(worker: Worker, amount: int)

# Ships & equipment
signal ship_purchased(ship: Ship, cost: int)
signal equipment_purchased(equipment: Equipment)
signal equipment_installed(ship: Ship, equipment: Equipment)
signal equipment_broken(ship: Ship, equipment: Equipment)
signal equipment_repaired(ship: Ship, equipment: Equipment)
signal equipment_fabricated(equipment: Equipment)

# Ship upgrades
signal upgrade_purchased(upgrade: ShipUpgrade)
signal upgrade_installed(ship: Ship, upgrade: ShipUpgrade)

# Cargo management
signal cargo_jettisoned(ship: Ship, tons_jettisoned: float)

# Missions
signal mission_started(mission: Mission)
signal mission_phase_changed(mission: Mission)
signal mission_completed(mission: Mission)
signal mission_redirected(ship: Ship, new_destination: AsteroidData, cost: int)
signal mission_redirect_failed(ship: Ship, reason: String)
signal mission_preview_started(ship: Ship, destination_pos: Vector2, slingshot_route)  # Show planned route (slingshot_route is GravityAssist.SlingshotRoute or null)
signal mission_preview_cancelled()  # Hide planned route

# Trade missions
signal trade_mission_started(trade_mission: TradeMission)
signal trade_mission_completed(trade_mission: TradeMission)
signal trade_mission_phase_changed(trade_mission: TradeMission)
signal trade_mission_redirected(ship: Ship, new_colony: Colony, cost: int)
signal trade_mission_redirect_failed(ship: Ship, reason: String)

# Simulation
signal tick(delta_ticks: float)
signal game_speed_changed(new_speed: float)

# Multiplayer
signal world_state_updated()  # Other players' ships updated

# Random events
signal survey_update(asteroid: AsteroidData, message: String)

# Market
signal market_event(ore_type: ResourceTypes.OreType, old_price: float, new_price: float, message: String)
signal market_event_started(event: MarketEvent)
signal market_event_ended(event: MarketEvent)
signal market_state_changed()  # General market update (prices or inventory changed)
signal arbitrage_opportunity(ore_name: String, low_hub: String, high_hub: String, gap_pct: float)

# Contracts
signal contract_offered(contract: Contract)
signal contract_accepted(contract: Contract)
signal contract_completed(contract: Contract)
signal contract_expired(contract: Contract)
signal contract_failed(contract: Contract)
signal contract_progress(contract: Contract, amount: float)

# Waypoint dispatching & breakdowns
signal ship_idle_at_destination(ship: Ship, mission: Mission)
signal ship_idle_at_colony(ship: Ship, trade_mission: TradeMission)
signal ship_breakdown(ship: Ship, reason: String)
signal ship_food_depleted(ship: Ship, workers_killed: int)
signal ship_derelict(ship: Ship)
signal ship_destroyed(ship: Ship, body_name: String)
signal life_support_warning(ship: Ship, percent_remaining: float)
signal rescue_mission_started(ship: Ship, cost: int)
signal rescue_mission_completed(ship: Ship)
signal rescue_impossible(ship: Ship, reason: String)
signal refuel_mission_started(ship: Ship, cost: int, fuel_amount: float)
signal refuel_mission_completed(ship: Ship, fuel_amount: float)

# Stranger rescue
signal stranger_rescue_offered(ship: Ship, stranger_name: String)
signal stranger_rescue_completed(ship: Ship, stranger_name: String)
signal stranger_rescue_declined(ship: Ship, stranger_name: String)

# Reputation
signal reputation_changed(new_score: float, tier: int)

# Station system
signal ship_stationed(ship: Ship, colony: Colony)
signal ship_unstationed(ship: Ship)
signal station_job_started(ship: Ship, job: String, destination: String)
signal station_job_completed(ship: Ship, job: String, summary: String)
signal crew_deployed(asteroid: AsteroidData, workers: Array)
signal crew_recalled(asteroid: AsteroidData, workers: Array)
signal worker_fatigued(worker: Worker)
signal worker_injured(worker: Worker)

# Hitchhiking & tardiness
signal worker_waiting_for_ride(worker: Worker, location: String)
signal worker_hitched_ride(worker: Worker, ship: Ship)
signal worker_tardy(worker: Worker, reason: String)
signal worker_tardiness_resolved(worker: Worker, action: String)

# Solar map dispatch
signal map_dispatch_to_asteroid(ship: Ship, asteroid: AsteroidData)
signal map_dispatch_to_colony(ship: Ship, colony: Colony)
signal map_ship_selected(ship: Ship)  # Emitted when player selects a ship on the solar map

# Lightspeed communication delay
signal order_queued(ship: Ship, label: String, delay_secs: float)
signal order_executed(ship: Ship, label: String)

# Rival corporations
signal rival_corp_dispatched(corp_name: String, asteroid_name: String)
signal rival_corp_arrived(corp_name: String, asteroid_name: String)
signal rival_corp_departed(corp_name: String, asteroid_name: String, tons: float)
signal rival_corps_contested(corp_name: String, asteroid_name: String)

# Mining units
signal mining_unit_purchased(unit: MiningUnit)
signal mining_unit_deployed(unit: MiningUnit, asteroid: AsteroidData)
signal mining_unit_recalled(unit: MiningUnit)
signal mining_unit_broken(unit: MiningUnit)
signal stockpile_collected(asteroid: AsteroidData, tons: float)
signal asteroid_supplies_low(asteroid_name: String, supply_key: String, days_remaining: float)

# Backend mode (single-player vs multiplayer)
signal backend_mode_changed(mode: int)  # BackendManager.BackendMode enum
signal server_state_synced()  # Emitted after server state is applied (SERVER mode only)
signal ship_sold(ship_id: int)

# Criminal ban system
signal violation_recorded(colony: Colony, reason: String)
signal colony_banned_player(colony: Colony)
signal game_over(reason: String)

# Warning system
signal warning_added(warning_id: String, message: String, severity: String)
signal warning_dismissed(warning_id: String)

# Combat system
signal combat_initiated(attacker: Ship, defender: Ship, distance: float)
signal combat_resolved(result: Dictionary)
signal torpedo_fired(attacker: Ship, weapon_name: String, target: Ship)
signal torpedo_intercepted(defender: Ship, weapon_name: String)
signal torpedo_evaded(defender: Ship, weapon_name: String)
signal fusion_weapon_used(attacker: Ship)
signal ship_disabled_combat(ship: Ship, damage: float)
signal crew_casualty_combat(ship: Ship, worker: Worker)

# NPC violations & consequences
signal rival_corp_banned(corp_name: String, colony_name: String)
signal colony_militia_intervened(corp_name: String, colony_name: String)

# Partnership system
signal partnership_created(leader: Ship, follower: Ship)
signal partnership_broken(ship1: Ship, ship2: Ship, reason: String)
signal partnership_aid_provided(leader_name: String, follower_name: String, aid_type: String, details: Dictionary)

# Notification system
signal notification_received(notification: Dictionary)
signal notification_read(notification: Dictionary)
signal notifications_cleared()

# Loan system
signal loan_taken(amount: int, total_debt: int)
signal loan_repaid(amount: int, total_debt: int)
signal loan_interest_charged(amount: int, total_debt: int)
signal debt_warning(total_debt: int, daily_interest: int)

# Salvage system
signal salvage_target_appeared(target: SalvageTarget)
signal salvage_target_expired(target: SalvageTarget)
signal salvage_mission_started(mission: Mission)
signal salvage_mission_completed(mission: Mission, credits: int, equipment_count: int)

# Fuel production system
signal power_source_purchased(ps: PowerSource)
signal power_source_deployed(ps: PowerSource, asteroid: AsteroidData)
signal power_source_recalled(ps: PowerSource)
signal power_source_broken(ps: PowerSource)
signal fuel_processor_purchased(fp: FuelProcessor)
signal fuel_processor_deployed(fp: FuelProcessor, asteroid: AsteroidData)
signal fuel_processor_recalled(fp: FuelProcessor)
signal fuel_processor_broken(fp: FuelProcessor)
signal fuel_stockpile_collected(asteroid: AsteroidData, fuel_amount: float)
signal reactor_exploded(ps: PowerSource, asteroid_name: String)

# Error notifications - Operation failures
signal operation_failed(operation: String, reason: String)  # Generic operation failure
signal purchase_failed(item_name: String, reason: String)  # Purchase operations
signal repair_failed(item_name: String, reason: String)  # Repair operations
signal deployment_failed(item_name: String, reason: String)  # Deployment operations
signal insufficient_funds(operation: String, cost: int, available: int)  # Not enough money

@warning_ignore_restore("unused_signal")
