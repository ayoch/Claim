class_name Contract
extends Resource

enum Status { AVAILABLE, ACCEPTED, COMPLETED, EXPIRED, FAILED }

@export var ore_type: ResourceTypes.OreType = ResourceTypes.OreType.IRON
@export var quantity: float = 10.0       # tons required
@export var reward: int = 1000           # credits paid on completion
@export var deadline_ticks: float = 300.0 # ticks remaining
@export var status: Status = Status.AVAILABLE
@export var issuer_name: String = "Unknown Corp"

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

	# Deadline: 200-600 ticks
	c.deadline_ticks = randf_range(200.0, 600.0)

	c.issuer_name = _issuer_names[randi() % _issuer_names.size()]
	c.status = Status.AVAILABLE
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
