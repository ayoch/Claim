class_name Worker
extends Resource

@export var worker_name: String = ""
@export var skill: float = 1.0   # multiplier on mining output
@export var wage: int = 100      # cost per payroll tick
@export var assigned_mission: Mission = null

var is_available: bool:
	get:
		return assigned_mission == null

static var _name_pool: Array[String] = [
	"Chen Wei", "Olga Petrov", "James Otieno", "Yuki Tanaka",
	"Priya Sharma", "Lars Eriksson", "Fatima Al-Rashid", "Marco Silva",
	"Ada Okafor", "Dmitri Volkov", "Sana Park", "Tomás Herrera",
	"Ingrid Haugen", "Kofi Mensah", "Elena Vasquez", "Raj Patel",
]

static func generate_random() -> Worker:
	var w := Worker.new()
	w.worker_name = _name_pool[randi() % _name_pool.size()]
	w.skill = snappedf(randf_range(0.7, 1.5), 0.05)
	w.wage = int(randi_range(80, 200))
	return w
