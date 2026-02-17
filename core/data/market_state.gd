class_name MarketState
extends RefCounted

## Mutable market prices that drift over time
var current_prices: Dictionary = {}  # OreType -> float
var _base_prices: Dictionary = {}    # OreType -> float (copy of MarketData.ORE_PRICES)

const PRICE_MIN_MULT: float = 0.3
const PRICE_MAX_MULT: float = 3.0
const DRIFT_STRENGTH: float = 0.03      # max % change per drift tick
const MEAN_REVERSION: float = 0.01      # pull toward base price

# Scripted event types
enum EventType { GLUT, SHORTAGE, DEMAND_SPIKE, DISCOVERY }

const EVENT_NAMES: Dictionary = {
	EventType.GLUT: "Market Glut",
	EventType.SHORTAGE: "Supply Shortage",
	EventType.DEMAND_SPIKE: "Demand Spike",
	EventType.DISCOVERY: "New Discovery",
}

func _init() -> void:
	for ore_type in MarketData.ORE_PRICES:
		var base: float = float(MarketData.ORE_PRICES[ore_type])
		_base_prices[ore_type] = base
		current_prices[ore_type] = base

func get_price(ore_type: ResourceTypes.OreType) -> float:
	return current_prices.get(ore_type, 0.0)

func get_base_price(ore_type: ResourceTypes.OreType) -> float:
	return _base_prices.get(ore_type, 0.0)

## Apply small random drift with mean reversion to all ore prices
func apply_drift() -> void:
	for ore_type in current_prices:
		var base: float = _base_prices[ore_type]
		var current: float = current_prices[ore_type]

		# Random walk
		var drift := randf_range(-DRIFT_STRENGTH, DRIFT_STRENGTH) * base

		# Mean reversion toward base price
		var reversion := (base - current) * MEAN_REVERSION

		var new_price := current + drift + reversion
		current_prices[ore_type] = _clamp_price(ore_type, new_price)

## Apply a multiplier to a specific ore (for scripted events)
func apply_event_multiplier(ore_type: ResourceTypes.OreType, multiplier: float) -> void:
	var current: float = current_prices.get(ore_type, 0.0)
	current_prices[ore_type] = _clamp_price(ore_type, current * multiplier)

func _clamp_price(ore_type: ResourceTypes.OreType, price: float) -> float:
	var base: float = _base_prices.get(ore_type, 1.0)
	return clampf(price, base * PRICE_MIN_MULT, base * PRICE_MAX_MULT)

## Get price direction compared to base: -1, 0, or 1
func get_price_trend(ore_type: ResourceTypes.OreType) -> int:
	var base: float = _base_prices.get(ore_type, 0.0)
	var current: float = current_prices.get(ore_type, 0.0)
	var ratio := current / base if base > 0 else 1.0
	if ratio > 1.05:
		return 1
	elif ratio < 0.95:
		return -1
	return 0
