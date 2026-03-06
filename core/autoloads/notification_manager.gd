extends Node

## NotificationManager — manages mobile push notifications
## Activity log/alerts ALWAYS show events (handled by hq_tab.gd)
## Push notifications controlled by user settings (Settings menu)
## Priority levels: CRITICAL (red, always shown), IMPORTANT (yellow, configurable), OPTIONAL (blue, configurable)

enum Priority {
	CRITICAL,   # Ship destruction, life support failure, game over, violations
	IMPORTANT,  # Combat, breakdowns, equipment failures, contract deadlines
	OPTIONAL,   # Mining complete, arrivals, market events, level ups
}

enum Category {
	COMBAT,           # Combat encounters, damage taken, weapons fired
	SHIP_HEALTH,      # Breakdowns, derelict ships, life support warnings
	CREW,             # Worker issues (tardy, injuries, quit), skill level ups
	EQUIPMENT,        # Equipment broken, repairs needed
	MISSIONS,         # Mission complete, arrivals at destinations
	ECONOMY,          # Market events, contract deadlines, low funds
	COLONIES,         # Violations, bans, reputation changes
	MINING,           # MUD stockpiles ready, mining complete, ore collected
	GENERAL,          # Misc notifications
}

const PRIORITY_COLORS := {
	Priority.CRITICAL: Color(1.0, 0.2, 0.2),    # Red
	Priority.IMPORTANT: Color(1.0, 0.8, 0.2),   # Yellow
	Priority.OPTIONAL: Color(0.4, 0.8, 1.0),    # Blue
}

const PRIORITY_NAMES := {
	Priority.CRITICAL: "Critical",
	Priority.IMPORTANT: "Important",
	Priority.OPTIONAL: "Optional",
}

const CATEGORY_NAMES := {
	Category.COMBAT: "Combat",
	Category.SHIP_HEALTH: "Ship Health",
	Category.CREW: "Crew",
	Category.EQUIPMENT: "Equipment",
	Category.MISSIONS: "Missions",
	Category.ECONOMY: "Economy",
	Category.COLONIES: "Colonies",
	Category.MINING: "Mining",
	Category.GENERAL: "General",
}

# Notification history (most recent first)
var notifications: Array[Dictionary] = []
const MAX_NOTIFICATIONS: int = 100

# Settings (which notification types are enabled)
# Separated into priority and category to avoid enum key collisions
var priority_settings: Dictionary = {
	Priority.CRITICAL: true,   # Always enabled
	Priority.IMPORTANT: true,  # Enabled by default
	Priority.OPTIONAL: true,   # Enabled by default
}

var category_settings: Dictionary = {
	Category.COMBAT: true,
	Category.SHIP_HEALTH: true,
	Category.CREW: true,
	Category.EQUIPMENT: true,
	Category.MISSIONS: true,
	Category.ECONOMY: true,
	Category.COLONIES: true,
	Category.MINING: true,
	Category.GENERAL: true,
}

# Mobile push notification support (Firebase Cloud Messaging)
var fcm_enabled: bool = false
var fcm_token: String = ""
var fcm_device_id: String = ""

func _ready() -> void:
	_load_settings()
	_setup_event_listeners()

func _setup_event_listeners() -> void:
	# Only send notifications when autoplay is OFF
	# When autoplay is ON, the AI handles everything automatically

	# CRITICAL notifications
	EventBus.ship_destroyed.connect(_on_ship_destroyed)
	EventBus.life_support_warning.connect(_on_life_support_warning)
	EventBus.game_over.connect(_on_game_over)
	EventBus.violation_recorded.connect(_on_violation_recorded)

	# IMPORTANT notifications
	EventBus.ship_breakdown.connect(_on_ship_breakdown)
	EventBus.equipment_broken.connect(_on_equipment_broken)
	EventBus.worker_tardy.connect(_on_worker_tardy)
	EventBus.worker_injured.connect(_on_worker_injured)
	EventBus.mining_unit_broken.connect(_on_mining_unit_broken)
	EventBus.contract_failed.connect(_on_contract_failed)

	# OPTIONAL notifications
	EventBus.mission_completed.connect(_on_mission_completed)
	EventBus.trade_mission_completed.connect(_on_trade_mission_completed)
	EventBus.stockpile_collected.connect(_on_stockpile_collected)
	EventBus.worker_skill_leveled.connect(_on_worker_skill_leveled)
	EventBus.market_event.connect(_on_market_event)
	EventBus.asteroid_supplies_low.connect(_on_asteroid_supplies_low)

# ══════════════════════════════════════════════════════════════════════════════
# PUBLIC API
# ══════════════════════════════════════════════════════════════════════════════

func send_notification(
	title: String,
	message: String,
	priority: Priority,
	category: Category,
	metadata: Dictionary = {}
) -> void:
	"""Send a notification (mobile push notifications based on user settings)
	Note: Activity log/alerts always show events regardless of these settings"""

	# Check if notifications are globally enabled
	if not GameState.settings.get("notifications_enabled", true):
		return

	# Check if this priority/category is enabled
	if not _is_notification_enabled(priority, category):
		return

	# Create notification record
	var notification := {
		"title": title,
		"message": message,
		"priority": priority,
		"category": category,
		"metadata": metadata,
		"timestamp": GameState.total_ticks,
		"real_time": Time.get_unix_time_from_system(),
		"read": false,
	}

	# Add to history
	notifications.push_front(notification)
	if notifications.size() > MAX_NOTIFICATIONS:
		notifications.resize(MAX_NOTIFICATIONS)

	# Emit signal for UI update
	EventBus.notification_received.emit(notification)

	# Send mobile push notification if enabled
	if fcm_enabled and OS.has_feature("mobile"):
		_send_push_notification(title, message, priority, category, metadata)

	# Desktop: flash window/taskbar for critical/important
	if priority <= Priority.IMPORTANT and OS.get_name() in ["Windows", "macOS", "Linux"]:
		DisplayServer.window_request_attention()

func mark_as_read(notification: Dictionary) -> void:
	"""Mark notification as read"""
	notification["read"] = true
	EventBus.notification_read.emit(notification)

func clear_all() -> void:
	"""Clear all notifications"""
	notifications.clear()
	EventBus.notifications_cleared.emit()

func get_unread_count() -> int:
	"""Get count of unread notifications"""
	var count := 0
	for n in notifications:
		if not n.get("read", false):
			count += 1
	return count

func get_unread_count_by_priority(priority: Priority) -> int:
	"""Get count of unread notifications by priority"""
	var count := 0
	for n in notifications:
		if not n.get("read", false) and n.get("priority") == priority:
			count += 1
	return count

# ══════════════════════════════════════════════════════════════════════════════
# EVENT HANDLERS (CRITICAL)
# ══════════════════════════════════════════════════════════════════════════════

func _on_ship_destroyed(ship: Ship, body_name: String) -> void:
	var msg := ""
	if body_name == "Life support failure":
		msg = "%s — life support failure, all hands lost" % ship.ship_name
	else:
		msg = "%s crashed into %s — all hands lost" % [ship.ship_name, body_name]
	send_notification("Ship Destroyed", msg, Priority.CRITICAL, Category.SHIP_HEALTH, {
		"ship_name": ship.ship_name,
		"body_name": body_name,
	})

func _on_life_support_warning(ship: Ship, pct: float) -> void:
	var pct_int := int(pct * 100)
	send_notification("Life Support Critical", "%s at %d%% — send rescue!" % [ship.ship_name, pct_int], Priority.CRITICAL, Category.SHIP_HEALTH, {
		"ship_name": ship.ship_name,
		"life_support_pct": pct,
	})

func _on_game_over(reason: String) -> void:
	send_notification("Game Over", reason, Priority.CRITICAL, Category.GENERAL, {
		"reason": reason,
	})

func _on_violation_recorded(colony: Colony, reason: String) -> void:
	var active_count := colony.get_active_violation_count(GameState.total_ticks)
	send_notification("Violation Recorded", "%s: %s (%d/%d violations)" % [
		colony.colony_name, reason, active_count, Colony.VIOLATION_THRESHOLD
	], Priority.CRITICAL, Category.COLONIES, {
		"colony_name": colony.colony_name,
		"reason": reason,
		"violation_count": active_count,
	})

# ══════════════════════════════════════════════════════════════════════════════
# EVENT HANDLERS (IMPORTANT)
# ══════════════════════════════════════════════════════════════════════════════

func _on_ship_breakdown(ship: Ship, reason: String) -> void:
	send_notification("Ship Breakdown", "%s — %s" % [ship.ship_name, reason], Priority.IMPORTANT, Category.SHIP_HEALTH, {
		"ship_name": ship.ship_name,
		"reason": reason,
	})

func _on_equipment_broken(ship: Ship, equip: Equipment) -> void:
	send_notification("Equipment Broken", "%s on %s has broken!" % [equip.equipment_name, ship.ship_name], Priority.IMPORTANT, Category.EQUIPMENT, {
		"ship_name": ship.ship_name,
		"equipment_name": equip.equipment_name,
	})

func _on_worker_tardy(worker: Worker, reason: String) -> void:
	send_notification("Worker Tardy", "%s — %s" % [worker.worker_name, reason], Priority.IMPORTANT, Category.CREW, {
		"worker_name": worker.worker_name,
		"reason": reason,
	})

func _on_worker_injured(worker: Worker) -> void:
	var location := "unknown location"
	if worker.assigned_mining_unit:
		location = "%s mining unit" % worker.assigned_mining_unit.deployed_at_asteroid
	send_notification("Worker Injured", "%s injured at %s" % [worker.worker_name, location], Priority.IMPORTANT, Category.CREW, {
		"worker_name": worker.worker_name,
		"location": location,
	})

func _on_mining_unit_broken(unit: MiningUnit) -> void:
	send_notification("Mining Unit Broken", "%s at %s needs repair" % [unit.unit_name, unit.deployed_at_asteroid], Priority.IMPORTANT, Category.MINING, {
		"unit_name": unit.unit_name,
		"asteroid_name": unit.deployed_at_asteroid,
	})

func _on_contract_failed(contract: Contract) -> void:
	send_notification("Contract Failed", "%s — %.1f t %s not delivered" % [
		contract.issuer_name, contract.quantity, ResourceTypes.get_ore_name(contract.ore_type)
	], Priority.IMPORTANT, Category.ECONOMY, {
		"issuer_name": contract.issuer_name,
		"quantity": contract.quantity,
		"ore_type": contract.ore_type,
	})

# ══════════════════════════════════════════════════════════════════════════════
# EVENT HANDLERS (OPTIONAL)
# ══════════════════════════════════════════════════════════════════════════════

func _on_mission_completed(mission: Mission) -> void:
	var location := mission.asteroid.asteroid_name if mission.asteroid else "remote location"
	send_notification("Mission Complete", "%s returned from %s" % [mission.ship.ship_name, location], Priority.OPTIONAL, Category.MISSIONS, {
		"ship_name": mission.ship.ship_name,
		"location": location,
	})

func _on_trade_mission_completed(tm: TradeMission) -> void:
	send_notification("Trade Complete", "%s returned from %s (+$%d)" % [
		tm.ship.ship_name, tm.colony.colony_name, tm.revenue
	], Priority.OPTIONAL, Category.ECONOMY, {
		"ship_name": tm.ship.ship_name,
		"colony_name": tm.colony.colony_name,
		"revenue": tm.revenue,
	})

func _on_stockpile_collected(asteroid: AsteroidData, tons: float) -> void:
	send_notification("Stockpile Collected", "Collected %.1ft from %s" % [tons, asteroid.asteroid_name], Priority.OPTIONAL, Category.MINING, {
		"asteroid_name": asteroid.asteroid_name,
		"tons": tons,
	})

func _on_worker_skill_leveled(worker: Worker, skill_type: int, new_value: float) -> void:
	var skill_name := ""
	match skill_type:
		0: skill_name = "Pilot"
		1: skill_name = "Engineer"
		2: skill_name = "Mining"
	send_notification("Skill Level Up", "%s's %s skill increased to %.2f" % [worker.worker_name, skill_name, new_value], Priority.OPTIONAL, Category.CREW, {
		"worker_name": worker.worker_name,
		"skill_name": skill_name,
		"skill_value": new_value,
	})

func _on_market_event(_ore: ResourceTypes.OreType, _old: float, _new: float, msg: String) -> void:
	send_notification("Market Event", msg, Priority.OPTIONAL, Category.ECONOMY, {
		"ore_type": _ore,
		"old_price": _old,
		"new_price": _new,
	})

func _on_asteroid_supplies_low(asteroid_name: String, supply_key: String, days_remaining: float) -> void:
	var supply_label := "food" if supply_key == "food" else "repair parts"
	send_notification("Low Supplies", "%.1f days of %s remaining at %s" % [days_remaining, supply_label, asteroid_name], Priority.OPTIONAL, Category.MINING, {
		"asteroid_name": asteroid_name,
		"supply_type": supply_label,
		"days_remaining": days_remaining,
	})

# ══════════════════════════════════════════════════════════════════════════════
# SETTINGS & FILTERS
# ══════════════════════════════════════════════════════════════════════════════

func _is_notification_enabled(priority: Priority, category: Category) -> bool:
	"""Check if this notification type is enabled in settings"""
	# Critical always enabled
	if priority == Priority.CRITICAL:
		return true

	# Check priority filter
	if not priority_settings.get(priority, true):
		return false

	# Check category filter
	if not category_settings.get(category, true):
		return false

	return true

func set_priority_enabled(priority: Priority, enabled: bool) -> void:
	"""Enable/disable a priority level"""
	if priority == Priority.CRITICAL:
		return  # Can't disable critical
	priority_settings[priority] = enabled
	_save_settings()

func set_category_enabled(category: Category, enabled: bool) -> void:
	"""Enable/disable a category"""
	category_settings[category] = enabled
	_save_settings()

func _load_settings() -> void:
	"""Load notification settings from GameState"""
	if GameState.settings.has("notification_priority_settings"):
		var saved: Dictionary = GameState.settings["notification_priority_settings"]
		for key in saved:
			priority_settings[key] = saved[key]

	if GameState.settings.has("notification_category_settings"):
		var saved: Dictionary = GameState.settings["notification_category_settings"]
		for key in saved:
			category_settings[key] = saved[key]

func _save_settings() -> void:
	"""Save notification settings to GameState"""
	GameState.settings["notification_priority_settings"] = priority_settings.duplicate()
	GameState.settings["notification_category_settings"] = category_settings.duplicate()

# ══════════════════════════════════════════════════════════════════════════════
# MOBILE PUSH NOTIFICATIONS (Firebase Cloud Messaging)
# ══════════════════════════════════════════════════════════════════════════════

func _send_push_notification(
	title: String,
	message: String,
	priority: Priority,
	category: Category,
	metadata: Dictionary
) -> void:
	"""Send mobile push notification via FCM (placeholder for future implementation)"""
	# TODO: Implement FCM integration when mobile builds are ready
	# This will require:
	# 1. Firebase project setup
	# 2. FCM plugin for Godot (or custom Java/Swift bridge)
	# 3. Server endpoint to send FCM messages
	# 4. Deep linking to open game at specific screen

	print("PUSH NOTIFICATION: [%s] %s - %s" % [PRIORITY_NAMES[priority], title, message])

func enable_push_notifications(device_token: String) -> void:
	"""Enable mobile push notifications with FCM token"""
	fcm_enabled = true
	fcm_token = device_token
	print("Push notifications enabled with token: %s" % device_token)

func disable_push_notifications() -> void:
	"""Disable mobile push notifications"""
	fcm_enabled = false
	fcm_token = ""
	print("Push notifications disabled")
