extends VBoxContainer
class_name DestinationSelector

## Destination Selector Component
## Choose mining asteroid or trading colony destination
## Extracted from fleet_market_tab.gd

# Signals emitted to coordinator
signal asteroid_selected(asteroid: AsteroidData)
signal colony_selected(colony: Colony)
signal selection_cancelled()

# Selection state
var _selected_asteroid: AsteroidData = null
var _selected_colony: Colony = null

# Sorting/filtering
var _sort_by: String = "profit"
var _filter_type: int = -1
var _market_sort_by: String = "profit"
var _market_search: String = ""
var _mining_search: String = ""

# Destination lists
var _colony_dest_buttons: Dictionary = {}  # Colony -> Button
var _mining_dest_buttons: Dictionary = {}  # AsteroidData -> Button
var _colony_dest_data: Array = []
var _mining_dest_data: Array = []

# Section expansion
var _colonies_section_expanded: int = -1  # -1 = auto, 0 = collapsed, 1 = expanded
var _mining_section_expanded: int = -1

# Scroll preservation
var _saved_colonies_scroll: float = 0.0
var _saved_mining_scroll: float = 0.0

# UI references
var _mining_scroll: ScrollContainer = null
var _colonies_scroll: ScrollContainer = null
var _mining_header_label: Label = null
var _colonies_header_label: Label = null
var _mining_controls: HFlowContainer = null


func _ready() -> void:
	pass


## Show asteroid selection screen
func show_asteroid_selection(ship: Ship, estimated_workers: Array[Worker]) -> void:
	# TODO: Extract from fleet_market_tab.gd
	pass


## Get sorted asteroids by profit/distance
func _get_sorted_asteroids(est_workers: Array[Worker]) -> Array[AsteroidData]:
	# TODO: Extract from fleet_market_tab.gd
	return []


## Calculate adjusted profit for an asteroid
func _calculate_adjusted_profit(asteroid: AsteroidData, est_workers: Array[Worker]) -> float:
	# TODO: Extract from fleet_market_tab.gd
	return 0.0


## Get ore summary text for an asteroid
func _get_ore_summary(asteroid: AsteroidData) -> String:
	# TODO: Extract from fleet_market_tab.gd
	return ""


## Toggle colonies section
func _toggle_colonies_section() -> void:
	_colonies_section_expanded = 1 if _colonies_section_expanded != 1 else 0
	# TODO: Rebuild UI


## Toggle mining section
func _toggle_mining_section() -> void:
	_mining_section_expanded = 1 if _mining_section_expanded != 1 else 0
	# TODO: Rebuild UI


## Update destination labels
func _update_destination_labels() -> void:
	# TODO: Extract from fleet_market_tab.gd
	pass


## Select an asteroid
func _select_asteroid(asteroid: AsteroidData) -> void:
	_selected_asteroid = asteroid
	asteroid_selected.emit(asteroid)


## Select a colony for trading
func _select_colony_trade(colony: Colony) -> void:
	_selected_colony = colony
	colony_selected.emit(colony)


## Apply mining search filter
func _apply_mining_search(query: String) -> void:
	_mining_search = query
	_update_destination_labels()


## Apply market search filter
func _apply_market_search(query: String) -> void:
	_market_search = query
	_update_destination_labels()
