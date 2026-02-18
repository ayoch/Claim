class_name Worker
extends Resource

@export var worker_name: String = ""
@export var pilot_skill: float = 0.0    # 0.0–1.5, affects transit speed
@export var engineer_skill: float = 0.0 # 0.0–1.5, reduces wear/breakdowns
@export var mining_skill: float = 0.0   # 0.0–1.5, affects ore output
@export var wage: int = 100      # cost per payroll interval (per game-day)
@export var assigned_mission: Mission = null

## Backward-compat: returns best skill across all specialties
var skill: float:
	get:
		return maxf(pilot_skill, maxf(engineer_skill, mining_skill))

var is_available: bool:
	get:
		return assigned_mission == null

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
