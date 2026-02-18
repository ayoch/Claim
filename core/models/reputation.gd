class_name Reputation
extends RefCounted

enum Tier { NOTORIOUS, SHADY, UNKNOWN, RESPECTED, RENOWNED }

static var score: float = 0.0  # -100 to +100, starts at 0

static func get_tier() -> Tier:
	if score <= -50:
		return Tier.NOTORIOUS
	elif score <= -15:
		return Tier.SHADY
	elif score < 15:
		return Tier.UNKNOWN
	elif score < 50:
		return Tier.RESPECTED
	else:
		return Tier.RENOWNED

static func get_tier_name() -> String:
	match get_tier():
		Tier.NOTORIOUS:
			return "Notorious"
		Tier.SHADY:
			return "Shady"
		Tier.UNKNOWN:
			return "Unknown"
		Tier.RESPECTED:
			return "Respected"
		Tier.RENOWNED:
			return "Renowned"
	return "Unknown"

static func modify(amount: float) -> void:
	score = clampf(score + amount, -100.0, 100.0)
	EventBus.reputation_changed.emit(score, get_tier())
