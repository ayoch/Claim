extends VBoxContainer
class_name FleetListPanel

## Fleet List Panel Component
## Displays list of all ships with status, cargo, location, crew, policies
## Extracted from fleet_market_tab.gd

# Signals emitted to coordinator
signal ship_selected(ship: Ship)
signal dispatch_requested(ship: Ship)
signal rescue_requested(target_ship: Ship)
signal supply_shop_requested(ship: Ship)
signal partnership_requested(ship: Ship)
signal station_jobs_requested(ship: Ship)

# Ship display caching
var _progress_bars: Dictionary = {}  # Ship -> ProgressBar
var _status_labels: Dictionary = {}  # Ship -> Label
var _detail_labels: Dictionary = {}  # Ship -> Label
var _location_labels: Dictionary = {}  # Ship -> Label
var _cargo_labels: Dictionary = {}  # Ship -> Label
var _signal_labels: Dictionary = {}  # Ship -> Label (pending order countdown)

# Expansion state (persists across rebuilds)
var _crew_expanded: Dictionary = {}  # Ship -> bool
var _policy_overrides_expanded: Dictionary = {}  # Ship -> bool
var _ship_stats_expanded: Dictionary = {}  # Ship -> bool

# References
@onready var ships_list: VBoxContainer = %ShipsList
@onready var ships_scroll: ScrollContainer = %ShipsScroll

const PROGRESS_LERP_SPEED: float = 8.0  # How fast progress bars catch up


func _ready() -> void:
	# Connect to EventBus for ship-related events
	EventBus.mission_started.connect(_on_mission_event)
	EventBus.mission_completed.connect(_on_mission_event)
	EventBus.mission_phase_changed.connect(_on_mission_event)
	EventBus.trade_mission_started.connect(_on_trade_event)
	EventBus.trade_mission_completed.connect(_on_trade_event)
	EventBus.ship_breakdown.connect(_on_ship_event)
	EventBus.ship_derelict.connect(_on_ship_event)
	# TODO: Add remaining ship event connections


func _process(delta: float) -> void:
	_update_ship_progress_bars(delta)


## Rebuild entire ship list
func rebuild_ships() -> void:
	# TODO: Extract from fleet_market_tab.gd
	pass


## Update progress bars smoothly
func _update_ship_progress_bars(delta: float) -> void:
	for ship in GameState.ships:
		if _progress_bars.has(ship):
			var bar: ProgressBar = _progress_bars[ship]
			# TODO: Smooth progress update logic
	pass


## Get location text for a ship
func _get_location_text(ship: Ship) -> String:
	# TODO: Extract from fleet_market_tab.gd
	return ""


## Get wrench texture for repair status
func _get_wrench_texture(ship: Ship) -> Texture2D:
	# TODO: Extract from fleet_market_tab.gd
	return null


## Build detailed status text for a ship
func _build_details_text(ship: Ship) -> String:
	# TODO: Extract from fleet_market_tab.gd
	return ""


## Format cargo display text
func _format_cargo_text(ship: Ship) -> String:
	# TODO: Extract from fleet_market_tab.gd
	return ""


## Event handlers
func _on_mission_event(_mission: Mission) -> void:
	rebuild_ships()


func _on_trade_event(_trade_mission: TradeMission) -> void:
	rebuild_ships()


func _on_ship_event(_ship: Ship, _reason: String = "") -> void:
	rebuild_ships()


## Toggle crew section expansion
func _toggle_crew_section(ship: Ship) -> void:
	_crew_expanded[ship] = not _crew_expanded.get(ship, false)
	rebuild_ships()


## Toggle policy overrides section expansion
func _toggle_policy_section(ship: Ship) -> void:
	_policy_overrides_expanded[ship] = not _policy_overrides_expanded.get(ship, false)
	rebuild_ships()


## Toggle ship stats section expansion
func _toggle_stats_section(ship: Ship) -> void:
	_ship_stats_expanded[ship] = not _ship_stats_expanded.get(ship, false)
	rebuild_ships()
