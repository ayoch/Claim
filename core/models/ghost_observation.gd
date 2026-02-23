class_name GhostObservation
extends RefCounted

## A recorded observation of a rival ship, subject to light-speed delay and confidence decay.
## The observation represents where the ship *appeared to be* when the light left it,
## back-calculated from its known velocity. Position extrapolates forward as time passes.

const CONFIDENCE_LIFETIME: float = 86400.0 * 2.0  # 2 game-days before observation expires

## Position in AU at the moment of observation (light-speed corrected)
var observed_position_au: Vector2 = Vector2.ZERO

## Velocity in AU/tick at time of observation
var observed_velocity_au_per_tick: Vector2 = Vector2.ZERO

## GameState.total_ticks when HQ received this observation
var received_at_ticks: float = 0.0

## Visibility score at time of observation (0–1), determines initial confidence
var initial_confidence: float = 0.0

## Extrapolated position at current_ticks based on last known velocity
func get_estimated_position(current_ticks: float) -> Vector2:
	return observed_position_au + observed_velocity_au_per_tick * (current_ticks - received_at_ticks)

## Confidence decays linearly from initial_confidence to 0 over CONFIDENCE_LIFETIME
func get_current_confidence(current_ticks: float) -> float:
	var age := current_ticks - received_at_ticks
	return initial_confidence * maxf(0.0, 1.0 - age / CONFIDENCE_LIFETIME)

## Returns true when this observation is too stale/faint to bother displaying
func is_expired(current_ticks: float) -> bool:
	return get_current_confidence(current_ticks) < 0.02
