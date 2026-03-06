class_name GameBalance
extends Object

## Game Balance Constants
## Centralized configuration for all game tuning values
## Update these to adjust game difficulty and economy

# ══════════════════════════════════════════════════════════════════════════════
# TIME & SPEED
# ══════════════════════════════════════════════════════════════════════════════

const PAYROLL_INTERVAL: float = 86400.0  # 1 game-day in seconds
const MARKET_UPDATE_INTERVAL: float = 86400.0  # Daily market price changes
const CONTRACT_CHECK_INTERVAL: float = 3600.0  # Check contracts every game-hour
const SURVEY_EVENT_INTERVAL: float = 7200.0  # Survey events every 2 game-hours

# ══════════════════════════════════════════════════════════════════════════════
# PHYSICS & NAVIGATION
# ══════════════════════════════════════════════════════════════════════════════

const DOCKING_DISTANCE_AU: float = 0.05  # Ships dock when within 0.05 AU
const INTERCEPT_THRESHOLD_AU: float = 0.2  # Combat intercept distance
const RESCUE_DISTANCE_AU: float = 0.1  # Distance to initiate rescue
const FUEL_STOP_DISTANCE_AU: float = 0.05  # Distance to refuel at waypoint
const POSITION_UPDATE_EPSILON: float = 0.0001  # Min movement for position update

# Orbital mechanics
const AU_TO_METERS: float = 149597870700.0  # 1 AU in meters
const BRACHISTOCHRONE_ACCEL_G: float = 0.3  # Default thrust acceleration in G
const HOHMANN_VELOCITY_FACTOR: float = 1000.0  # Velocity scaling for Hohmann transfers

# ══════════════════════════════════════════════════════════════════════════════
# WORKERS
# ══════════════════════════════════════════════════════════════════════════════

const WORKER_FATIGUE_CRITICAL: float = 80.0  # Workers need rest at this threshold
const WORKER_FATIGUE_WARNING: float = 60.0  # Show warning at this threshold
const WORKER_FATIGUE_RECOVERY_RATE: float = 10.0  # Recovery per game-hour when resting
const WORKER_FATIGUE_WORK_RATE: float = 5.0  # Fatigue gained per game-hour working

const WORKER_BASE_WAGE_MIN: float = 80.0  # Minimum daily wage
const WORKER_BASE_WAGE_MAX: float = 200.0  # Maximum daily wage (before skill multiplier)
const WORKER_SKILL_WAGE_MULTIPLIER: float = 0.5  # Wage increase per skill level

const WORKER_XP_BASE: float = 100.0  # XP needed for first level
const WORKER_XP_EXPONENT: float = 1.5  # XP curve steepness (exponential growth)
const WORKER_XP_PER_TASK: float = 10.0  # Base XP gained per task

# ══════════════════════════════════════════════════════════════════════════════
# MINING
# ══════════════════════════════════════════════════════════════════════════════

const BASE_MINING_RATE: float = 0.0001  # Base ore extraction rate (tons per tick)
const MINING_SKILL_BONUS: float = 0.1  # Bonus per miner skill level (10%)
const MINING_EFFICIENCY_FATIGUE_PENALTY: float = 0.5  # Efficiency reduction when fatigued

const RIG_MINING_MULTIPLIER: float = 2.0  # Rigs mine 2x faster than ships
const AMU_MINING_MULTIPLIER: float = 1.5  # AMUs mine 1.5x faster than ships

const MINING_THRESHOLD_QUICK_RETURN: float = 0.5  # 50% cargo full
const MINING_THRESHOLD_STANDARD: float = 0.75  # 75% cargo full
const MINING_THRESHOLD_MAXIMUM: float = 0.95  # 95% cargo full

# ══════════════════════════════════════════════════════════════════════════════
# COMBAT
# ══════════════════════════════════════════════════════════════════════════════

const COMBAT_DETECTION_RANGE_AU: float = 0.5  # Ships detect enemies within this range
const COMBAT_ENGAGEMENT_RANGE_AU: float = 0.2  # Combat initiates at this range

const TORPEDO_DAMAGE_MIN: float = 10.0
const TORPEDO_DAMAGE_MAX: float = 50.0
const LASER_DAMAGE_MIN: float = 5.0
const LASER_DAMAGE_MAX: float = 20.0
const RAILGUN_DAMAGE_MIN: float = 15.0
const RAILGUN_DAMAGE_MAX: float = 40.0

const EVASION_BASE_CHANCE: float = 0.3  # 30% base evasion chance
const EVASION_SKILL_BONUS: float = 0.05  # +5% per pilot skill level

const CREW_CASUALTY_BASE_CHANCE: float = 0.2  # 20% chance per combat round
const CREW_CASUALTY_DAMAGE_MULTIPLIER: float = 0.01  # Increases with damage taken

# ══════════════════════════════════════════════════════════════════════════════
# ECONOMY
# ══════════════════════════════════════════════════════════════════════════════

const MARKET_PRICE_VOLATILITY: float = 0.1  # ±10% price fluctuation
const MARKET_SUPPLY_PRICE_FACTOR: float = 0.05  # Price change per inventory unit
const MARKET_DEMAND_THRESHOLD: int = 1000  # Low inventory triggers price increase

const FUEL_COST_PER_UNIT: float = 100.0  # Cost per fuel unit
const REFUEL_SERVICE_FEE: float = 500.0  # Flat fee for refueling service

const SHIP_PURCHASE_DISCOUNT: float = 0.0  # Future: bulk purchase discount
const SHIP_SELL_VALUE_RATIO: float = 0.7  # Sell ships for 70% of purchase price

# ══════════════════════════════════════════════════════════════════════════════
# SHIPS
# ══════════════════════════════════════════════════════════════════════════════

const SHIP_IDLE_THRESHOLD: float = 0.1  # Consider ship idle if not moving much
const SHIP_DERELICT_FUEL_THRESHOLD: float = 0.01  # Ship is derelict below this fuel %
const SHIP_LOW_FUEL_WARNING: float = 0.25  # Warn at 25% fuel remaining

const SHIP_REPAIR_COST_PER_PERCENT: float = 1000.0  # Cost to repair 1% hull damage
const ENGINE_REPAIR_COST_BASE: float = 5000.0  # Base cost for engine repair

const PARTNERSHIP_MAX_DISTANCE_AU: float = 1.0  # Partners must stay within 1 AU
const PARTNERSHIP_FUEL_TRANSFER_RATE: float = 10.0  # Fuel units per transfer

# ══════════════════════════════════════════════════════════════════════════════
# COLONIES
# ══════════════════════════════════════════════════════════════════════════════

const COLONY_TRADE_FEE_PERCENT: float = 0.02  # 2% transaction fee at colonies
const COLONY_STOCKPILE_DECAY_RATE: float = 0.001  # Stockpile decay per day (0.1%)

# ══════════════════════════════════════════════════════════════════════════════
# VIOLATIONS & REPUTATION
# ══════════════════════════════════════════════════════════════════════════════

const VIOLATION_DECAY_TIME: float = 2592000.0  # 30 game-days before violation expires
const REPUTATION_LOSS_PER_VIOLATION: int = 10
const REPUTATION_GAIN_PER_DELIVERY: int = 1

const TRADING_BAN_THRESHOLD: int = 3  # Banned from trading after 3 violations
const DOCKING_BAN_THRESHOLD: int = 5  # Banned from docking after 5 violations

# ══════════════════════════════════════════════════════════════════════════════
# AI & AUTOMATION
# ══════════════════════════════════════════════════════════════════════════════

const AI_DECISION_INTERVAL: float = 10.0  # AI makes decisions every 10 game-seconds
const AI_RISK_TOLERANCE: float = 0.3  # Base risk tolerance for AI corporations

const AUTOPLAY_PURCHASE_RESERVE: float = 0.2  # Keep 20% money in reserve
const AUTOPLAY_HIRE_THRESHOLD: int = 3  # Hire worker when ships > workers * 3

# ══════════════════════════════════════════════════════════════════════════════
# UI & DISPLAY
# ══════════════════════════════════════════════════════════════════════════════

const UI_UPDATE_THROTTLE: float = 0.2  # Update UI max 5 times per second
const NOTIFICATION_DISPLAY_TIME: float = 5.0  # Show notifications for 5 seconds
const TOOLTIP_DELAY: float = 0.5  # Show tooltips after 0.5s hover

const DISTANCE_DISPLAY_PRECISION: int = 2  # Decimal places for AU display
const MONEY_DISPLAY_USE_THOUSANDS: bool = true  # Use comma separators

# ══════════════════════════════════════════════════════════════════════════════
# FOG OF WAR & MULTIPLAYER
# ══════════════════════════════════════════════════════════════════════════════

const FOG_OF_WAR_DECAY_TIME: float = 172800.0  # 2 game-days visibility lifetime
const LIGHT_SPEED_DELAY_FACTOR: float = 499.0  # Light-seconds per AU
const GHOST_CONTACT_MIN_CONFIDENCE: float = 0.1  # Don't show contacts below 10% confidence

const MULTIPLAYER_SYNC_INTERVAL: float = 2.0  # Poll server every 2 real seconds
const SSE_RECONNECT_DELAY: float = 1.0  # Reconnect SSE after 1 second
const SERVER_TIMEOUT: float = 10.0  # Consider server offline after 10s

# ══════════════════════════════════════════════════════════════════════════════
# ASTEROID RESERVES
# ══════════════════════════════════════════════════════════════════════════════

const ASTEROID_RESERVE_DISPLAY_HIGH: float = 0.75  # Green display above 75%
const ASTEROID_RESERVE_DISPLAY_MEDIUM: float = 0.25  # Yellow display 25-75%
const ASTEROID_RESERVE_DISPLAY_LOW: float = 0.10  # Orange display 10-25%
# Below 10% = Red display

const ASTEROID_DEPLETION_WARNING_THRESHOLD: float = 0.25  # Warn at 25% remaining

# ══════════════════════════════════════════════════════════════════════════════
# HELPER FUNCTIONS
# ══════════════════════════════════════════════════════════════════════════════

static func get_worker_wage(base_wage: float, skill_level: float) -> float:
	"""Calculate worker wage based on skill level"""
	return base_wage * (1.0 + skill_level * WORKER_SKILL_WAGE_MULTIPLIER)


static func get_xp_for_level(level: int) -> float:
	"""Calculate total XP needed to reach a level"""
	return WORKER_XP_BASE * pow(level, WORKER_XP_EXPONENT)


static func is_worker_fatigued(fatigue: float) -> bool:
	"""Check if worker needs rest"""
	return fatigue >= WORKER_FATIGUE_CRITICAL


static func get_mining_rate_with_skill(base_rate: float, skill_level: float) -> float:
	"""Calculate mining rate with skill bonus"""
	return base_rate * (1.0 + skill_level * MINING_SKILL_BONUS)


static func is_ship_in_docking_range(distance_au: float) -> bool:
	"""Check if ship is close enough to dock"""
	return distance_au < DOCKING_DISTANCE_AU


static func is_combat_range(distance_au: float) -> bool:
	"""Check if ships are in combat range"""
	return distance_au < COMBAT_ENGAGEMENT_RANGE_AU


static func format_distance(distance_au: float) -> String:
	"""Format distance for display with configured precision"""
	return ("%." + str(DISTANCE_DISPLAY_PRECISION) + "f AU") % distance_au


static func format_money(amount: float) -> String:
	"""Format money for display"""
	if MONEY_DISPLAY_USE_THOUSANDS:
		return "$%s" % _format_with_commas(int(amount))
	else:
		return "$%d" % int(amount)


static func _format_with_commas(number: int) -> String:
	"""Add thousand separators to number"""
	var s := str(number)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count == 3:
			result = "," + result
			count = 0
		result = s[i] + result
		count += 1
	return result
