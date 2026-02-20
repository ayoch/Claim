class_name Contract
extends Resource

enum Status { AVAILABLE, ACCEPTED, COMPLETED, EXPIRED, FAILED }

@export var ore_type: ResourceTypes.OreType = ResourceTypes.OreType.IRON
@export var quantity: float = 10.0       # tons required
@export var quantity_delivered: float = 0.0  # tons delivered so far
@export var reward: int = 1000           # credits paid on completion
@export var deadline_ticks: float = 300.0 # ticks remaining
@export var status: Status = Status.AVAILABLE
@export var issuer_name: String = "Unknown Corp"
@export var delivery_colony: Colony = null  # If set, must deliver to this colony
@export var allows_partial: bool = true  # Can fulfill partially for partial payment

const PREMIUM_MIN: float = 1.3
const PREMIUM_MAX: float = 2.0

static var _issuer_names: Array[String] = [
	"Terran Mining Co.", "Sol Logistics", "Orbital Corp",
	"Deep Space Industries", "Planetary Resources", "AstroForge",
	"Ceres Trading", "Belt Haulers Inc.", "Jovian Exports",
	"Frontier Minerals", "Nova Extraction", "Kuiper Commerce",
]

static func generate_random() -> Contract:
	var c := Contract.new()
	var ore_values := ResourceTypes.OreType.values()
	c.ore_type = ore_values[randi() % ore_values.size()]

	# Quantity scales with ore value (cheaper ores need more tons)
	var base_price: float = float(MarketData.ORE_PRICES.get(c.ore_type, 100))
	var target_value := randf_range(2000.0, 20000.0)
	c.quantity = snappedf(target_value / base_price, 0.1)
	c.quantity = maxf(c.quantity, 1.0)

	# Premium over spot price
	var premium := randf_range(PREMIUM_MIN, PREMIUM_MAX)
	c.reward = int(c.quantity * base_price * premium)

	# Deadline: 3-10 game-days (1 game-day = 86400 ticks)
	c.deadline_ticks = randf_range(3.0, 10.0) * 86400.0

	c.issuer_name = _issuer_names[randi() % _issuer_names.size()]
	c.status = Status.AVAILABLE
	c.quantity_delivered = 0.0

	# 60% chance of colony-specific delivery requirement
	if randf() < 0.6 and not GameState.colonies.is_empty():
		c.delivery_colony = GameState.colonies[randi() % GameState.colonies.size()]
		# Colony-specific contracts pay higher premium
		c.reward = int(c.reward * 1.2)

	# 80% allow partial fulfillment
	c.allows_partial = randf() < 0.8

	return c

func get_premium_percent() -> float:
	var base_price: float = float(MarketData.ORE_PRICES.get(ore_type, 100))
	var spot_value := quantity * base_price
	if spot_value <= 0:
		return 0.0
	return ((reward / spot_value) - 1.0) * 100.0

func get_status_text() -> String:
	match status:
		Status.AVAILABLE: return "Available"
		Status.ACCEPTED: return "Active"
		Status.COMPLETED: return "Completed"
		Status.EXPIRED: return "Expired"
		Status.FAILED: return "Failed"
	return "Unknown"

func get_progress() -> float:
	# Returns 0.0 to 1.0
	if quantity <= 0:
		return 0.0
	return quantity_delivered / quantity

func get_remaining_quantity() -> float:
	return maxf(0.0, quantity - quantity_delivered)

func is_completed() -> bool:
	return quantity_delivered >= quantity

func can_fulfill_partial(amount: float) -> bool:
	if status != Status.ACCEPTED:
		return false
	if amount <= 0:
		return false
	if not allows_partial and amount < get_remaining_quantity():
		return false
	return true

func get_partial_payment(amount: float) -> int:
	# Calculate payment for partial delivery
	var price_per_ton := float(reward) / quantity
	var delivered_value := amount * price_per_ton
	return int(delivered_value)

func get_delivery_location_text() -> String:
	if delivery_colony:
		return delivery_colony.colony_name
	return "Any Colony"

func get_display_text() -> String:
	var ore_name := ResourceTypes.get_ore_name(ore_type)
	var location := get_delivery_location_text()
	var progress_text := ""
	if quantity_delivered > 0:
		progress_text = " (%.1ft/%.1ft)" % [quantity_delivered, quantity]
	var days_left := deadline_ticks / 86400.0
	return "%s: %s %.1ft%s to %s - $%s - %.1f days" % [
		issuer_name, ore_name, quantity, progress_text, location,
		_format_number(reward), days_left
	]

func _format_number(n: int) -> String:
	var s := str(abs(n))
	var result := ""
	for i in range(s.length()):
		if i > 0 and (s.length() - i) % 3 == 0:
			result += ","
		result += s[i]
	if n < 0:
		result = "-" + result
	return result
