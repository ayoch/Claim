class_name MarketState
extends RefCounted

## LOCAL ECONOMY SYSTEM
## Each major trading hub has its own prices and inventory
## Prices adjust based on local supply and demand

# Major trading hubs (10 locations total)
const HUB_EARTH := "Earth"
const TRADING_HUBS := [
	"Earth",
	"Lunar Base",
	"Mars Colony",
	"Ceres Station",
	"Vesta Refinery",
	"Europa Lab",
	"Ganymede Port",
	"Titan Outpost",
	"Callisto Base",
	"Triton Station",
]

## Per-location market data
var location_prices: Dictionary = {}      # location -> (OreType -> float)
var location_inventory: Dictionary = {}   # location -> (OreType -> float tons)
var _base_prices: Dictionary = {}         # OreType -> float (copy of MarketData.ORE_PRICES)

const PRICE_MIN_MULT: float = 0.3
const PRICE_MAX_MULT: float = 3.0
const DRIFT_STRENGTH: float = 0.03      # max % change per drift tick
const MEAN_REVERSION: float = 0.01      # pull toward base price

# Supply/demand pricing
const INVENTORY_PRICE_SENSITIVITY: float = 0.02  # price change per 100 tons
const IDEAL_INVENTORY_PER_ORE: float = 500.0     # balanced inventory level

# Scripted event types
enum EventType { GLUT, SHORTAGE, DEMAND_SPIKE, DISCOVERY }

const EVENT_NAMES: Dictionary = {
	EventType.GLUT: "Market Glut",
	EventType.SHORTAGE: "Supply Shortage",
	EventType.DEMAND_SPIKE: "Demand Spike",
	EventType.DISCOVERY: "New Discovery",
}

func _init() -> void:
	# Initialize base prices
	for ore_type in MarketData.ORE_PRICES:
		var base: float = float(MarketData.ORE_PRICES[ore_type])
		_base_prices[ore_type] = base

	# Initialize per-location markets
	for hub in TRADING_HUBS:
		location_prices[hub] = {}
		location_inventory[hub] = {}

		for ore_type in MarketData.ORE_PRICES:
			var base: float = _base_prices[ore_type]
			# Add slight regional variation (±10%) to starting prices
			var variance: float = randf_range(0.9, 1.1)
			location_prices[hub][ore_type] = base * variance

			# Initialize inventory with random starting levels
			location_inventory[hub][ore_type] = randf_range(300.0, 700.0)

## Get price at a specific location (defaults to Earth if location not found)
func get_price(ore_type: ResourceTypes.OreType, location: String = HUB_EARTH) -> float:
	if not location_prices.has(location):
		location = HUB_EARTH
	return location_prices[location].get(ore_type, 0.0)

func get_base_price(ore_type: ResourceTypes.OreType) -> float:
	return _base_prices.get(ore_type, 0.0)

## Get inventory at a specific location
func get_inventory(ore_type: ResourceTypes.OreType, location: String = HUB_EARTH) -> float:
	if not location_inventory.has(location):
		location = HUB_EARTH
	return location_inventory[location].get(ore_type, 0.0)

## Player sells ore to a location (increases inventory, decreases price)
func sell_ore(ore_type: ResourceTypes.OreType, amount: float, location: String = HUB_EARTH) -> void:
	if not location_inventory.has(location):
		location = HUB_EARTH

	location_inventory[location][ore_type] += amount
	_update_supply_demand_price(ore_type, location)

## Player buys ore from a location (decreases inventory, increases price)
func buy_ore(ore_type: ResourceTypes.OreType, amount: float, location: String = HUB_EARTH) -> void:
	if not location_inventory.has(location):
		location = HUB_EARTH

	location_inventory[location][ore_type] = maxf(0.0, location_inventory[location][ore_type] - amount)
	_update_supply_demand_price(ore_type, location)

## Update price based on supply/demand at a location
func _update_supply_demand_price(ore_type: ResourceTypes.OreType, location: String) -> void:
	var inventory: float = location_inventory[location][ore_type]
	var base: float = _base_prices[ore_type]

	# Price decreases when inventory is high, increases when low
	var inventory_diff: float = inventory - IDEAL_INVENTORY_PER_ORE
	var price_adjustment: float = -(inventory_diff / 100.0) * INVENTORY_PRICE_SENSITIVITY * base

	var current: float = location_prices[location][ore_type]
	var new_price: float = current + price_adjustment
	location_prices[location][ore_type] = _clamp_price(ore_type, new_price)

## Apply small random drift with mean reversion to all ore prices at all locations
func apply_drift() -> void:
	for hub in TRADING_HUBS:
		for ore_type in location_prices[hub]:
			var base: float = _base_prices[ore_type]
			var current: float = location_prices[hub][ore_type]

			# Random walk
			var drift := randf_range(-DRIFT_STRENGTH, DRIFT_STRENGTH) * base

			# Mean reversion toward base price
			var reversion := (base - current) * MEAN_REVERSION

			var new_price := current + drift + reversion
			location_prices[hub][ore_type] = _clamp_price(ore_type, new_price)

## Apply a multiplier to a specific ore at a specific location (for scripted events)
func apply_event_multiplier(ore_type: ResourceTypes.OreType, multiplier: float, location: String = "") -> void:
	if location == "":
		# Apply to all locations
		for hub in TRADING_HUBS:
			var current: float = location_prices[hub].get(ore_type, 0.0)
			location_prices[hub][ore_type] = _clamp_price(ore_type, current * multiplier)
	else:
		# Apply to specific location
		if location_prices.has(location):
			var current: float = location_prices[location].get(ore_type, 0.0)
			location_prices[location][ore_type] = _clamp_price(ore_type, current * multiplier)

func _clamp_price(ore_type: ResourceTypes.OreType, price: float) -> float:
	var base: float = _base_prices.get(ore_type, 1.0)
	return clampf(price, base * PRICE_MIN_MULT, base * PRICE_MAX_MULT)

## Get price direction compared to base: -1, 0, or 1
func get_price_trend(ore_type: ResourceTypes.OreType, location: String = HUB_EARTH) -> int:
	if not location_prices.has(location):
		location = HUB_EARTH
	var base: float = _base_prices.get(ore_type, 0.0)
	var current: float = location_prices[location].get(ore_type, 0.0)
	var ratio := current / base if base > 0 else 1.0
	if ratio > 1.05:
		return 1
	elif ratio < 0.95:
		return -1
	return 0

## Find best price for selling (highest price across all hubs)
func find_best_sell_price(ore_type: ResourceTypes.OreType) -> Dictionary:
	var best_price: float = 0.0
	var best_location: String = HUB_EARTH

	for hub in TRADING_HUBS:
		var price: float = location_prices[hub].get(ore_type, 0.0)
		if price > best_price:
			best_price = price
			best_location = hub

	return {"price": best_price, "location": best_location}

## Find best price for buying (lowest price across all hubs)
func find_best_buy_price(ore_type: ResourceTypes.OreType) -> Dictionary:
	var best_price: float = INF
	var best_location: String = HUB_EARTH

	for hub in TRADING_HUBS:
		var price: float = location_prices[hub].get(ore_type, 0.0)
		if price < best_price:
			best_price = price
			best_location = hub

	return {"price": best_price, "location": best_location}
