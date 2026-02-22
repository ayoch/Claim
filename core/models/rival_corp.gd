class_name RivalCorp
extends Resource

enum Personality {
	AGGRESSIVE,    # High risk, targets richest asteroids regardless of competition
	SYSTEMATIC,    # Methodical, prefers less-contested bodies, full runs
	OPPORTUNISTIC, # Follows player — targets whatever's profitable right now
	CONSERVATIVE,  # Sticks to safe, nearby bodies; avoids conflict
	EXPANSIONIST,  # Sends many ships simultaneously; quantity over quality
}

@export var corp_name: String = ""
@export var tagline: String = ""
@export var personality: Personality = Personality.SYSTEMATIC
@export var home_position_au: Vector2 = Vector2.ZERO  # Approximate colony position
@export var ships: Array[RivalShip] = []
@export var money: int = 0
@export var total_ore_mined: float = 0.0
@export var total_revenue: int = 0
