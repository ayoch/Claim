extends Node2D

var asteroid: AsteroidData = null

# Modulate colors approximating real asteroid spectral types
# C-type (dark carbon), S-type (stony), M-type (metallic), D-type (red-brown),
# V-type (basaltic), E-type (pale/high albedo), B-type (blue-grey)
const ASTEROID_TINTS: Array[Color] = [
	Color(0.55, 0.52, 0.50),  # C-type: dark grey-brown
	Color(0.80, 0.68, 0.52),  # S-type: warm tan
	Color(0.88, 0.88, 0.92),  # M-type: silvery
	Color(0.75, 0.52, 0.38),  # D-type: reddish-brown
	Color(0.82, 0.72, 0.58),  # V-type: basalt, warm grey
	Color(0.95, 0.93, 0.88),  # E-type: pale/bright
	Color(0.58, 0.62, 0.68),  # B-type: cool blue-grey
]

const ASTEROID_TEXTURES: Array[String] = [
	"res://ui/assets/asteroids/Asteroid_CType1.png",
	"res://ui/assets/asteroids/Asteroid_CType_2.png",
	"res://ui/assets/asteroids/Asteroid_CType3.png",
	"res://ui/assets/asteroids/Asteroid_CType4.png",
	"res://ui/assets/asteroids/AsteroidCtype4_bigger.png",
	"res://ui/assets/asteroids/Asteroid_Ctype_Yshape2.png",
	"res://ui/assets/asteroids/Asteroid_SType1.png",
	"res://ui/assets/asteroids/Asteroid_SType2.png",
	"res://ui/assets/asteroids/Asteroid_SType3.png",
	"res://ui/assets/asteroids/Asteroid_SType4.png",
]

const _LABEL_BASE_OFFSET := Vector2(8.0, -10.0)

func update_zoom(zoom_level: float) -> void:
	var inv := 1.0 / zoom_level
	$Label.scale = Vector2(inv, inv)
	$Label.position = _LABEL_BASE_OFFSET * inv

func _ready() -> void:
	if asteroid:
		$Label.text = asteroid.asteroid_name
		var h := absi(asteroid.asteroid_name.hash())
		var idx := h % ASTEROID_TEXTURES.size()
		var tex := load(ASTEROID_TEXTURES[idx]) as Texture2D
		if tex:
			$Sprite2D.texture = tex
		# Deterministic rotation and scale from name hash
		var angle := (h >> 4) % 360
		$Sprite2D.rotation_degrees = angle
		var scale_factor := 0.035 + ((h >> 8) % 40) * 0.001  # 0.035 – 0.074
		$Sprite2D.scale = Vector2(scale_factor, scale_factor)
		var tint_idx := (h >> 12) % ASTEROID_TINTS.size()
		$Sprite2D.modulate = ASTEROID_TINTS[tint_idx]
