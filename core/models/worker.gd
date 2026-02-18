class_name Worker
extends Resource

@export var worker_name: String = ""
@export var skill: float = 1.0   # multiplier on mining output
@export var wage: int = 100      # cost per payroll tick
@export var assigned_mission: Mission = null

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

	w.skill = snappedf(randf_range(0.7, 1.5), 0.05)
	w.wage = int(randi_range(80, 200))
	return w

static func release_name(name: String) -> void:
	# Call this when a worker is fired to free up their name
	_used_names.erase(name)
