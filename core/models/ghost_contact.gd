class_name GhostContact
extends RefCounted

## A persistent tracked contact on the solar map.
## Created when a new observation can't be matched to an existing contact.
## Survives across multiple observation updates as long as it stays visible.

var contact_id: int = 0
var contact_color: Color = Color.WHITE

## Corp attribution — "" = unknown, filled in as confidence builds
var inferred_corp: String = ""
## 0–1. Low = weak direction match, high = trajectory clearly points to/from a known home.
var corp_confidence: float = 0.0

## Most recent observation for this contact
var latest_obs: GhostObservation = null
var first_seen_ticks: float = 0.0

func update_obs(obs: GhostObservation, current_ticks: float = -1.0) -> void:
	if latest_obs == null or current_ticks < 0.0:
		latest_obs = obs
		return
	# Carry forward the higher of current decayed confidence vs incoming
	# This prevents visible confidence pulses when observations are continuous
	var current_conf := get_current_confidence(current_ticks)
	obs.initial_confidence = maxf(obs.initial_confidence, current_conf)
	latest_obs = obs

func get_estimated_position(current_ticks: float) -> Vector2:
	if latest_obs == null:
		return Vector2.ZERO
	return latest_obs.get_estimated_position(current_ticks)

func get_current_confidence(current_ticks: float) -> float:
	if latest_obs == null:
		return 0.0
	return latest_obs.get_current_confidence(current_ticks)

func is_expired(current_ticks: float) -> bool:
	if latest_obs == null:
		return true
	return latest_obs.is_expired(current_ticks)
