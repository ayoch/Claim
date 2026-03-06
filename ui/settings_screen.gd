extends Control

@onready var back_btn: Button = %BackButton
@onready var notifications_enabled_check: CheckBox = %NotificationsEnabledCheck
@onready var critical_check: CheckBox = %CriticalCheck
@onready var important_check: CheckBox = %ImportantCheck
@onready var optional_check: CheckBox = %OptionalCheck

# Category checkboxes
@onready var combat_check: CheckBox = %CombatCheck
@onready var ship_health_check: CheckBox = %ShipHealthCheck
@onready var crew_check: CheckBox = %CrewCheck
@onready var equipment_check: CheckBox = %EquipmentCheck
@onready var missions_check: CheckBox = %MissionsCheck
@onready var economy_check: CheckBox = %EconomyCheck
@onready var colonies_check: CheckBox = %ColoniesCheck
@onready var mining_check: CheckBox = %MiningCheck
@onready var general_check: CheckBox = %GeneralCheck

func _ready() -> void:
	back_btn.pressed.connect(_on_back)

	# Load current settings
	_load_settings()

	# Connect checkboxes
	notifications_enabled_check.toggled.connect(_on_notifications_enabled_toggled)
	critical_check.toggled.connect(func(on: bool) -> void: _on_priority_toggled(NotificationManager.Priority.CRITICAL, on))
	important_check.toggled.connect(func(on: bool) -> void: _on_priority_toggled(NotificationManager.Priority.IMPORTANT, on))
	optional_check.toggled.connect(func(on: bool) -> void: _on_priority_toggled(NotificationManager.Priority.OPTIONAL, on))

	combat_check.toggled.connect(func(on: bool) -> void: _on_category_toggled(NotificationManager.Category.COMBAT, on))
	ship_health_check.toggled.connect(func(on: bool) -> void: _on_category_toggled(NotificationManager.Category.SHIP_HEALTH, on))
	crew_check.toggled.connect(func(on: bool) -> void: _on_category_toggled(NotificationManager.Category.CREW, on))
	equipment_check.toggled.connect(func(on: bool) -> void: _on_category_toggled(NotificationManager.Category.EQUIPMENT, on))
	missions_check.toggled.connect(func(on: bool) -> void: _on_category_toggled(NotificationManager.Category.MISSIONS, on))
	economy_check.toggled.connect(func(on: bool) -> void: _on_category_toggled(NotificationManager.Category.ECONOMY, on))
	colonies_check.toggled.connect(func(on: bool) -> void: _on_category_toggled(NotificationManager.Category.COLONIES, on))
	mining_check.toggled.connect(func(on: bool) -> void: _on_category_toggled(NotificationManager.Category.MINING, on))
	general_check.toggled.connect(func(on: bool) -> void: _on_category_toggled(NotificationManager.Category.GENERAL, on))

func _load_settings() -> void:
	# Master toggle
	notifications_enabled_check.button_pressed = GameState.settings.get("notifications_enabled", true)

	# Priority filters
	critical_check.button_pressed = NotificationManager.priority_settings.get(NotificationManager.Priority.CRITICAL, true)
	important_check.button_pressed = NotificationManager.priority_settings.get(NotificationManager.Priority.IMPORTANT, true)
	optional_check.button_pressed = NotificationManager.priority_settings.get(NotificationManager.Priority.OPTIONAL, true)

	# Category filters
	combat_check.button_pressed = NotificationManager.category_settings.get(NotificationManager.Category.COMBAT, true)
	ship_health_check.button_pressed = NotificationManager.category_settings.get(NotificationManager.Category.SHIP_HEALTH, true)
	crew_check.button_pressed = NotificationManager.category_settings.get(NotificationManager.Category.CREW, true)
	equipment_check.button_pressed = NotificationManager.category_settings.get(NotificationManager.Category.EQUIPMENT, true)
	missions_check.button_pressed = NotificationManager.category_settings.get(NotificationManager.Category.MISSIONS, true)
	economy_check.button_pressed = NotificationManager.category_settings.get(NotificationManager.Category.ECONOMY, true)
	colonies_check.button_pressed = NotificationManager.category_settings.get(NotificationManager.Category.COLONIES, true)
	mining_check.button_pressed = NotificationManager.category_settings.get(NotificationManager.Category.MINING, true)
	general_check.button_pressed = NotificationManager.category_settings.get(NotificationManager.Category.GENERAL, true)

	# Disable critical (always enabled)
	critical_check.disabled = true

func _on_notifications_enabled_toggled(on: bool) -> void:
	GameState.settings["notifications_enabled"] = on
	print("Notifications globally: ", "ENABLED" if on else "DISABLED")

func _on_priority_toggled(priority: int, on: bool) -> void:
	NotificationManager.set_priority_enabled(priority, on)
	print("Priority %s: %s" % [NotificationManager.PRIORITY_NAMES[priority], "ENABLED" if on else "DISABLED"])

func _on_category_toggled(category: int, on: bool) -> void:
	NotificationManager.set_category_enabled(category, on)
	print("Category %s: %s" % [NotificationManager.CATEGORY_NAMES[category], "ENABLED" if on else "DISABLED"])

func _on_back() -> void:
	get_tree().change_scene_to_file("res://ui/title_screen.tscn")
