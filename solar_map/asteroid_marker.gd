extends Node2D

var asteroid: AsteroidData = null

func _ready() -> void:
	if asteroid:
		$Label.text = asteroid.asteroid_name

func _draw() -> void:
	draw_circle(Vector2.ZERO, 7, Color(0.7, 0.6, 0.4))
