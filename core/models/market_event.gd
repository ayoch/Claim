extends Resource
class_name MarketEvent

# Types of market events
enum EventType {
	SHORTAGE,      # Supply shortage - prices increase
	SURPLUS,       # Oversupply - prices decrease
	DISASTER,      # Colony disaster - specific ore prices spike
	BOOM,          # Economic boom - all prices increase
	RECESSION,     # Economic recession - all prices decrease
	DISCOVERY,     # New deposits found - specific ore prices drop
	STRIKE,        # Worker strike - mining slows, prices rise
	TECH_ADVANCE   # Technology breakthrough - specific ore demand spikes
}

@export var event_type: EventType = EventType.SHORTAGE
@export var affected_ore: ResourceTypes.OreType = ResourceTypes.OreType.IRON
@export var affected_colony: Colony = null  # If null, affects all colonies
@export var price_multiplier: float = 1.0  # Applied to base prices
@export var duration_ticks: float = 0.0  # How long event lasts (0 = permanent)
@export var remaining_ticks: float = 0.0  # Time remaining
@export var event_name: String = ""
@export var event_description: String = ""
@export var is_active: bool = true

static var _event_names: Dictionary = {
	EventType.SHORTAGE: ["Iron Shortage", "Platinum Scarcity", "Nickel Deficit"],
	EventType.SURPLUS: ["Market Glut", "Oversupply Crisis", "Warehouse Full"],
	EventType.DISASTER: ["Colony Emergency", "Habitat Breach", "Life Support Failure"],
	EventType.BOOM: ["Economic Boom", "Market Rally", "Bull Market"],
	EventType.RECESSION: ["Market Crash", "Economic Downturn", "Bear Market"],
	EventType.DISCOVERY: ["New Deposit Found", "Rich Vein Discovered", "Motherlode Located"],
	EventType.STRIKE: ["Worker Strike", "Labor Dispute", "Union Action"],
	EventType.TECH_ADVANCE: ["Tech Breakthrough", "New Application Found", "Demand Spike"]
}

static func generate_random() -> MarketEvent:
	var event := MarketEvent.new()

	# Pick random event type
	var types := EventType.values()
	event.event_type = types[randi() % types.size()]

	# Pick affected ore (except for economy-wide events)
	if event.event_type in [EventType.BOOM, EventType.RECESSION]:
		event.affected_ore = ResourceTypes.OreType.IRON  # Placeholder, affects all
	else:
		var ore_types := ResourceTypes.OreType.values()
		event.affected_ore = ore_types[randi() % ore_types.size()]

	# Pick affected colony (50% chance of being colony-specific)
	if randf() < 0.5 and not GameState.colonies.is_empty():
		event.affected_colony = GameState.colonies[randi() % GameState.colonies.size()]

	# Set price multiplier based on event type
	match event.event_type:
		EventType.SHORTAGE:
			event.price_multiplier = randf_range(1.3, 1.8)
			event.duration_ticks = randf_range(150.0, 400.0)
		EventType.SURPLUS:
			event.price_multiplier = randf_range(0.5, 0.8)
			event.duration_ticks = randf_range(150.0, 400.0)
		EventType.DISASTER:
			event.price_multiplier = randf_range(2.0, 3.5)
			event.duration_ticks = randf_range(100.0, 250.0)
		EventType.BOOM:
			event.price_multiplier = randf_range(1.2, 1.5)
			event.duration_ticks = randf_range(300.0, 600.0)
		EventType.RECESSION:
			event.price_multiplier = randf_range(0.7, 0.9)
			event.duration_ticks = randf_range(300.0, 600.0)
		EventType.DISCOVERY:
			event.price_multiplier = randf_range(0.6, 0.8)
			event.duration_ticks = randf_range(200.0, 500.0)
		EventType.STRIKE:
			event.price_multiplier = randf_range(1.4, 1.9)
			event.duration_ticks = randf_range(100.0, 300.0)
		EventType.TECH_ADVANCE:
			event.price_multiplier = randf_range(1.5, 2.2)
			event.duration_ticks = randf_range(250.0, 500.0)

	event.remaining_ticks = event.duration_ticks
	event.is_active = true

	# Generate name and description
	event.event_name = _generate_event_name(event)
	event.event_description = _generate_event_description(event)

	return event

static func _generate_event_name(event: MarketEvent) -> String:
	var templates: Array = _event_names.get(event.event_type, ["Market Event"])
	var template: String = templates[randi() % templates.size()]

	# For ore-specific events, prepend ore name
	if event.event_type not in [EventType.BOOM, EventType.RECESSION]:
		var ore_name := ResourceTypes.get_ore_name(event.affected_ore)
		return "%s %s" % [ore_name, template]

	return template

static func _generate_event_description(event: MarketEvent) -> String:
	var ore_name := ResourceTypes.get_ore_name(event.affected_ore)
	var location := ""
	if event.affected_colony:
		location = " at %s" % event.affected_colony.colony_name
	else:
		location = " system-wide"

	var price_change := ""
	if event.price_multiplier > 1.0:
		var increase := (event.price_multiplier - 1.0) * 100.0
		price_change = "up %.0f%%" % increase
	else:
		var decrease := (1.0 - event.price_multiplier) * 100.0
		price_change = "down %.0f%%" % decrease

	match event.event_type:
		EventType.SHORTAGE:
			return "Supply shortage%s drives %s prices %s" % [location, ore_name, price_change]
		EventType.SURPLUS:
			return "Oversupply%s pushes %s prices %s" % [location, ore_name, price_change]
		EventType.DISASTER:
			return "Emergency%s creates urgent demand for %s, prices %s" % [location, ore_name, price_change]
		EventType.BOOM:
			return "Economic boom%s lifts all ore prices %s" % [location, price_change]
		EventType.RECESSION:
			return "Market downturn%s reduces all ore prices %s" % [location, price_change]
		EventType.DISCOVERY:
			return "New %s deposits discovered%s, prices %s" % [ore_name, location, price_change]
		EventType.STRIKE:
			return "Mining strike%s reduces %s supply, prices %s" % [location, ore_name, price_change]
		EventType.TECH_ADVANCE:
			return "New tech increases %s demand%s, prices %s" % [ore_name, location, price_change]

	return "Market conditions changed"

func advance_time(dt: float) -> void:
	if duration_ticks > 0:
		remaining_ticks -= dt
		if remaining_ticks <= 0:
			is_active = false

func applies_to_ore(ore_type: ResourceTypes.OreType) -> bool:
	# Economy-wide events affect all ores
	if event_type in [EventType.BOOM, EventType.RECESSION]:
		return true
	return ore_type == affected_ore

func applies_to_colony(colony: Colony) -> bool:
	if not affected_colony:
		return true  # Applies to all colonies
	return colony == affected_colony

func get_price_modifier(ore_type: ResourceTypes.OreType, colony: Colony) -> float:
	if not is_active:
		return 1.0
	if not applies_to_ore(ore_type):
		return 1.0
	if not applies_to_colony(colony):
		return 1.0
	return price_multiplier

func get_display_text() -> String:
	var time_text := ""
	if duration_ticks > 0:
		time_text = " (%s remaining)" % _format_time(remaining_ticks)
	return "%s%s" % [event_name, time_text]

func _format_time(ticks: float) -> String:
	var total_seconds := int(ticks)
	var hours := total_seconds / 3600
	var minutes := (total_seconds % 3600) / 60
	if hours > 0:
		return "%dh %dm" % [hours, minutes]
	elif minutes > 0:
		return "%dm" % minutes
	return "%ds" % total_seconds
