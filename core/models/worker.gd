class_name Worker
extends Resource

@export var worker_name: String = ""
@export var pilot_skill: float = 0.0    # 0.0–1.5, affects transit speed
@export var engineer_skill: float = 0.0 # 0.0–1.5, reduces wear/breakdowns
@export var mining_skill: float = 0.0   # 0.0–1.5, affects ore output
@export var wage: int = 100      # cost per payroll interval (per game-day)
@export var assigned_mission: Mission = null
@export var assigned_trade_mission: TradeMission = null
@export var assigned_station_ship: Ship = null  # Set when crew on a stationed ship
@export var fatigue: float = 0.0           # 0–100, accumulates while on mission
@export var days_deployed: float = 0.0     # Game-days away from a station
@export var is_injured: bool = false       # Set by breakdowns, combat
@export var home_colony: String = ""       # Colony name or "Earth"
@export var loyalty: float = 50.0          # 0–100
@export var hired_at: float = 0.0          # total_ticks at hire
@export var leave_status: int = 0          # 0=active, 1=on_leave, 2=waiting_for_ride, 3=tardy
@export var assigned_mining_unit: MiningUnit = null
@export var pilot_xp: float = 0.0
@export var engineer_xp: float = 0.0
@export var mining_xp: float = 0.0

const BASE_XP: float = 86400.0  # 1 game-day at skill 0.0
const SKILL_CAP: float = 2.0

## Backward-compat: returns best skill across all specialties
var skill: float:
	get:
		return maxf(pilot_skill, maxf(engineer_skill, mining_skill))

var is_available: bool:
	get:
		return assigned_mission == null and assigned_trade_mission == null and assigned_station_ship == null and assigned_mining_unit == null and leave_status == 0

var days_at_company: float:
	get: return (GameState.total_ticks - hired_at) / 86400.0

var loyalty_modifier: float:
	get: return 0.9 + (loyalty / 1000.0)  # 0 loyalty=0.9x, 50=0.95x, 100=1.0x

var needs_rotation: bool:
	get:
		return fatigue >= 80.0 or is_injured

static var _first_names: Array[String] = [
	"Chen", "Olga", "James", "Yuki", "Priya", "Lars", "Fatima", "Marco",
	"Ada", "Dmitri", "Sana", "Tomás", "Ingrid", "Kofi", "Elena", "Raj",
	"Amara", "Hassan", "Sofia", "Kenji", "Aisha", "Niklas", "Mei", "Carlos",
	"Leila", "Viktor", "Jin", "Lucia", "Kwame", "Zara", "Anders", "Nadia",
	"Miguel", "Fatou", "Akira", "Ivan", "Chioma", "Omar", "Linnea", "Wei",
]

static var _last_names: Array[String] = [
	"Wei", "Petrov", "Otieno", "Tanaka", "Sharma", "Eriksson", "Al-Rashid", "Silva",
	"Okafor", "Volkov", "Park", "Herrera", "Haugen", "Mensah", "Vasquez", "Patel",
	"Mwangi", "Chen", "Kovacs", "Nakamura", "Santos", "Johansson", "Khan", "Rodriguez",
	"Kimura", "Novak", "Diallo", "Andersen", "Martinez", "Ivanov", "N'Dour", "Jensen",
	"Okonkwo", "Sato", "Kowalski", "Morales", "Hassan", "Olsen", "Adeyemi", "Lee",
]

static var _used_names: Dictionary = {}  # Track used names to avoid duplicates

static var _home_weights: Array[Dictionary] = [
	{"name": "Earth", "weight": 0.40},
	{"name": "Lunar Base", "weight": 0.20},
	{"name": "Mars Colony", "weight": 0.15},
	{"name": "Ceres Station", "weight": 0.10},
	{"name": "Europa Lab", "weight": 0.03},
	{"name": "Ganymede Port", "weight": 0.03},
	{"name": "Vesta Refinery", "weight": 0.03},
	{"name": "Titan Outpost", "weight": 0.02},
	{"name": "Callisto Base", "weight": 0.02},
	{"name": "Triton Station", "weight": 0.02},
]

static func _pick_home_colony() -> String:
	var roll := randf()
	var cumulative := 0.0
	for entry in _home_weights:
		cumulative += entry["weight"]
		if roll <= cumulative:
			return entry["name"]
	return "Earth"

static func generate_random() -> Worker:
	var w := Worker.new()

	# Generate unique name (try up to 100 times)
	var attempts := 0
	while attempts < 100:
		var first := _first_names[randi() % _first_names.size()]
		var last := _last_names[randi() % _last_names.size()]
		var full_name := "%s %s" % [first, last]

		if not _used_names.has(full_name):
			w.worker_name = full_name
			_used_names[full_name] = true
			break
		attempts += 1

	# Fallback if somehow all names exhausted
	if w.worker_name == "":
		w.worker_name = "Worker %d" % randi()

	# Assign specialties: primary (high), secondary (medium), third (low)
	var skills := [0, 1, 2]  # 0=pilot, 1=engineer, 2=mining
	skills.shuffle()
	var primary: int = skills[0]
	var secondary: int = skills[1]
	var tertiary: int = skills[2]

	var primary_val := snappedf(randf_range(0.8, 1.5), 0.05)
	var secondary_val := snappedf(randf_range(0.4, 0.9), 0.05)
	var tertiary_val := snappedf(randf_range(0.0, 0.3), 0.05)

	# Rare generalist: ~5% chance all skills are decent
	if randf() < 0.05:
		primary_val = snappedf(randf_range(0.7, 1.2), 0.05)
		secondary_val = snappedf(randf_range(0.6, 1.0), 0.05)
		tertiary_val = snappedf(randf_range(0.4, 0.8), 0.05)

	var vals := [0.0, 0.0, 0.0]
	vals[primary] = primary_val
	vals[secondary] = secondary_val
	vals[tertiary] = tertiary_val

	w.pilot_skill = vals[0]
	w.engineer_skill = vals[1]
	w.mining_skill = vals[2]

	# Wages correlate with total skill
	var total_skill := w.pilot_skill + w.engineer_skill + w.mining_skill
	w.wage = int(80 + total_skill * 40)
	w.home_colony = _pick_home_colony()
	w.hired_at = GameState.total_ticks
	return w

## Generate a worker with a guaranteed primary specialty (0=pilot, 1=engineer, 2=mining)
static func generate_with_primary(primary_index: int) -> Worker:
	var w := generate_random()
	# Swap so the desired specialty is highest
	var current_vals := [w.pilot_skill, w.engineer_skill, w.mining_skill]
	# Find which index currently has the highest value
	var max_idx := 0
	if current_vals[1] > current_vals[max_idx]:
		max_idx = 1
	if current_vals[2] > current_vals[max_idx]:
		max_idx = 2
	# Swap the desired primary with the current highest
	if max_idx != primary_index:
		var tmp: float = current_vals[primary_index]
		current_vals[primary_index] = current_vals[max_idx]
		current_vals[max_idx] = tmp
		w.pilot_skill = current_vals[0]
		w.engineer_skill = current_vals[1]
		w.mining_skill = current_vals[2]
	return w

## Returns display text like "Pilot 1.2 / Miner 0.7"
func get_specialties_text() -> String:
	var parts: Array[String] = []
	if pilot_skill >= 0.3:
		parts.append("Pilot %.1f" % pilot_skill)
	if engineer_skill >= 0.3:
		parts.append("Eng %.1f" % engineer_skill)
	if mining_skill >= 0.3:
		parts.append("Miner %.1f" % mining_skill)
	if parts.is_empty():
		return "Unskilled"
	return " / ".join(parts)

static func release_name(name: String) -> void:
	# Call this when a worker is fired to free up their name
	_used_names.erase(name)

## Get XP needed for next level based on current skill
## skill_type: 0=pilot, 1=engineer, 2=mining
func get_xp_for_next_level(skill_type: int) -> float:
	var current_skill := 0.0
	match skill_type:
		0: current_skill = pilot_skill
		1: current_skill = engineer_skill
		2: current_skill = mining_skill
	if current_skill >= SKILL_CAP:
		return 0.0
	return BASE_XP * pow(current_skill + 1.0, 2.0)

## Add XP to a skill and check for level-up
## skill_type: 0=pilot, 1=engineer, 2=mining
func add_xp(skill_type: int, amount: float) -> void:
	if amount <= 0.0:
		return

	# Get current skill and XP
	var current_skill := 0.0
	var current_xp := 0.0
	match skill_type:
		0:
			current_skill = pilot_skill
			current_xp = pilot_xp
		1:
			current_skill = engineer_skill
			current_xp = engineer_xp
		2:
			current_skill = mining_skill
			current_xp = mining_xp

	# Cap at max skill
	if current_skill >= SKILL_CAP:
		return

	# Add XP
	current_xp += amount

	# Check for level-up
	var xp_needed := get_xp_for_next_level(skill_type)
	while current_xp >= xp_needed and xp_needed > 0.0 and current_skill < SKILL_CAP:
		current_xp -= xp_needed
		current_skill += 0.05  # Increment skill by 0.05 per level
		current_skill = minf(current_skill, SKILL_CAP)

		# Update skill value
		match skill_type:
			0: pilot_skill = current_skill
			1: engineer_skill = current_skill
			2: mining_skill = current_skill

		# Recalculate XP needed for next level
		xp_needed = get_xp_for_next_level(skill_type)

		# Recalculate wage based on new total skill
		var total_skill := pilot_skill + engineer_skill + mining_skill
		wage = int(80 + total_skill * 40)

		# Small loyalty boost for career development
		loyalty = minf(loyalty + 2.0, 100.0)

		# Emit signal
		EventBus.worker_skill_leveled.emit(self, skill_type, current_skill)

	# Store updated XP
	match skill_type:
		0: pilot_xp = current_xp
		1: engineer_xp = current_xp
		2: mining_xp = current_xp

## Get progress to next level (0.0-1.0) for UI bars
## skill_type: 0=pilot, 1=engineer, 2=mining
func get_xp_progress(skill_type: int) -> float:
	var current_skill := 0.0
	var current_xp := 0.0
	match skill_type:
		0:
			current_skill = pilot_skill
			current_xp = pilot_xp
		1:
			current_skill = engineer_skill
			current_xp = engineer_xp
		2:
			current_skill = mining_skill
			current_xp = mining_xp

	if current_skill >= SKILL_CAP:
		return 0.0

	var xp_needed := get_xp_for_next_level(skill_type)
	if xp_needed <= 0.0:
		return 0.0

	return current_xp / xp_needed
