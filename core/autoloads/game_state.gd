extends Node

var money: int = 10000:
	set(value):
		money = value
		EventBus.money_changed.emit(money)

var resources: Dictionary = {} # OreType -> float (tons)
var workers: Array[Worker] = []
var ships: Array[Ship] = []
var missions: Array[Mission] = []
var equipment_inventory: Array[Equipment] = []
var asteroids: Array[AsteroidData] = []
var settings: Dictionary = {
	"auto_refuel": true,
}

func _ready() -> void:
	_init_resources()
	_init_starter_ship()
	asteroids = CelestialData.get_asteroids()

func _init_resources() -> void:
	for ore in ResourceTypes.OreType.values():
		resources[ore] = 0.0

func _init_starter_ship() -> void:
	var starter := Ship.new()
	starter.ship_name = "Prospector I"
	starter.thrust_g = 0.3
	starter.cargo_capacity = 100.0
	starter.fuel_capacity = 200.0
	starter.fuel = 200.0
	ships.append(starter)

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
	EventBus.worker_hired.emit(worker)

func fire_worker(worker: Worker) -> void:
	workers.erase(worker)
	worker.assigned_mission = null
	EventBus.worker_fired.emit(worker)

func get_available_workers() -> Array[Worker]:
	var available: Array[Worker] = []
	for w in workers:
		if w.is_available:
			available.append(w)
	return available

func get_docked_ships() -> Array[Ship]:
	var docked: Array[Ship] = []
	for s in ships:
		if s.is_docked:
			docked.append(s)
	return docked

func purchase_equipment(entry: Dictionary) -> bool:
	if money < entry.get("cost", 0):
		return false
	var equip := Equipment.from_catalog(entry)
	money -= equip.cost
	equipment_inventory.append(equip)
	EventBus.equipment_purchased.emit(equip)
	return true

func install_equipment(ship: Ship, equip: Equipment) -> void:
	equipment_inventory.erase(equip)
	ship.equipment.append(equip)
	EventBus.equipment_installed.emit(ship, equip)

func start_mission(ship: Ship, asteroid: AsteroidData, assigned_workers: Array[Worker]) -> Mission:
	var mission := Mission.new()
	mission.ship = ship
	mission.asteroid = asteroid
	mission.workers = assigned_workers
	mission.status = Mission.Status.TRANSIT_OUT

	var dist := Brachistochrone.distance_to(asteroid)
	mission.transit_time = Brachistochrone.transit_time(dist, ship.thrust_g)
	mission.elapsed_ticks = 0.0

	ship.current_mission = mission
	ship.current_cargo.clear()
	for w in assigned_workers:
		w.assigned_mission = mission

	missions.append(mission)
	EventBus.mission_started.emit(mission)
	return mission

func complete_mission(mission: Mission) -> void:
	# Transfer cargo from ship to stockpile
	for ore_type in mission.ship.current_cargo:
		add_resource(ore_type, mission.ship.current_cargo[ore_type])
	mission.ship.current_cargo.clear()
	mission.ship.current_mission = null

	for w in mission.workers:
		w.assigned_mission = null

	mission.status = Mission.Status.COMPLETED
	EventBus.mission_completed.emit(mission)
	missions.erase(mission)

# Save/Load
func save_game() -> void:
	var save_data := {
		"money": money,
		"resources": {},
		"workers": [],
		"ships": [],
	}
	for ore_type in resources:
		save_data["resources"][str(ore_type)] = resources[ore_type]
	for w in workers:
		save_data["workers"].append({
			"name": w.worker_name,
			"skill": w.skill,
			"wage": w.wage,
		})
	for s in ships:
		var ship_data := {
			"name": s.ship_name,
			"thrust_g": s.thrust_g,
			"cargo_capacity": s.cargo_capacity,
			"equipment": [],
		}
		for e in s.equipment:
			ship_data["equipment"].append({
				"name": e.equipment_name,
				"type": e.type,
				"mining_bonus": e.mining_bonus,
				"cost": e.cost,
			})
		save_data["ships"].append(ship_data)

	var file := FileAccess.open("user://save_game.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(save_data, "\t"))

func load_game() -> bool:
	if not FileAccess.file_exists("user://save_game.json"):
		return false
	var file := FileAccess.open("user://save_game.json", FileAccess.READ)
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return false
	var data: Dictionary = json.data

	money = int(data.get("money", 10000))

	_init_resources()
	var res_data: Dictionary = data.get("resources", {})
	for key in res_data:
		resources[int(key)] = float(res_data[key])

	workers.clear()
	for wd in data.get("workers", []):
		var w := Worker.new()
		w.worker_name = wd.get("name", "Unknown")
		w.skill = float(wd.get("skill", 1.0))
		w.wage = int(wd.get("wage", 100))
		workers.append(w)

	ships.clear()
	for sd in data.get("ships", []):
		var s := Ship.new()
		s.ship_name = sd.get("name", "Ship")
		s.thrust_g = float(sd.get("thrust_g", 0.3))
		s.cargo_capacity = float(sd.get("cargo_capacity", 100.0))
		for ed in sd.get("equipment", []):
			s.equipment.append(Equipment.from_catalog(ed))
		ships.append(s)

	return true
