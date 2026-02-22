class_name CompanyPolicy
extends RefCounted

enum ThrustPolicy {
	CONSERVATIVE,  # Ensure safe return with margin, slower speeds
	BALANCED,      # Reasonable speed with fuel safety considerations
	AGGRESSIVE,    # Maximize speed, assume refueling available
	ECONOMICAL,    # Minimize fuel costs, accept slower speeds
}

const THRUST_POLICY_NAMES := {
	ThrustPolicy.CONSERVATIVE: "Conservative",
	ThrustPolicy.BALANCED: "Balanced",
	ThrustPolicy.AGGRESSIVE: "Aggressive",
	ThrustPolicy.ECONOMICAL: "Economical",
}

const THRUST_POLICY_DESCRIPTIONS := {
	ThrustPolicy.CONSERVATIVE: "Prioritize safety. Ensure ships can return with full cargo even if refueling unavailable.",
	ThrustPolicy.BALANCED: "Balance speed and safety. Use higher thrust near civilization, lower thrust in remote areas.",
	ThrustPolicy.AGGRESSIVE: "Maximize speed. Assume refueling will be available. Risk fuel emergencies for faster missions.",
	ThrustPolicy.ECONOMICAL: "Minimize fuel costs. Use lower thrust to maximize profit margins, accept slower completion.",
}

# --- Supply Policy ---
# Controls when stationed ships are sent to resupply remote asteroid sites.
# Threshold is expressed as days of supplies remaining at the site.
enum SupplyPolicy {
	PROACTIVE,  # Resupply when <30 days remain — always well-stocked
	ROUTINE,    # Resupply when <15 days remain — standard operations
	MINIMAL,    # Resupply when <7 days remain — lean logistics, more risk
	MANUAL,     # Never auto-resupply — player dispatches manually
}

const SUPPLY_POLICY_NAMES := {
	SupplyPolicy.PROACTIVE: "Proactive",
	SupplyPolicy.ROUTINE: "Routine",
	SupplyPolicy.MINIMAL: "Minimal",
	SupplyPolicy.MANUAL: "Manual",
}

const SUPPLY_POLICY_DESCRIPTIONS := {
	SupplyPolicy.PROACTIVE: "Resupply sites before they fall below 30 days of provisions. Higher logistics cost, no risk of starvation.",
	SupplyPolicy.ROUTINE: "Resupply when sites fall below 15 days. Balanced cost and safety.",
	SupplyPolicy.MINIMAL: "Resupply only when critically low (<7 days). Lean but risky — delays or breakdowns can strand workers.",
	SupplyPolicy.MANUAL: "Never auto-resupply. You handle all supply dispatches manually.",
}

# Threshold in days for each policy — auto-resupply when remaining days < this
const SUPPLY_POLICY_THRESHOLDS := {
	SupplyPolicy.PROACTIVE: 30.0,
	SupplyPolicy.ROUTINE: 15.0,
	SupplyPolicy.MINIMAL: 7.0,
	SupplyPolicy.MANUAL: 0.0,  # Never triggers
}

# --- Collection Policy ---
# Controls when stationed ships are sent to collect ore from remote stockpiles.
# Threshold is expressed as % of the ship's cargo capacity that the stockpile must reach.
enum CollectionPolicy {
	AGGRESSIVE,  # Collect when stockpile reaches 25% of ship cargo — frequent runs
	ROUTINE,     # Collect when stockpile reaches 50% of ship cargo — standard
	PATIENT,     # Collect when stockpile reaches 80% of ship cargo — fewer trips
	MANUAL,      # Never auto-collect — player dispatches manually
}

const COLLECTION_POLICY_NAMES := {
	CollectionPolicy.AGGRESSIVE: "Aggressive",
	CollectionPolicy.ROUTINE: "Routine",
	CollectionPolicy.PATIENT: "Patient",
	CollectionPolicy.MANUAL: "Manual",
}

const COLLECTION_POLICY_DESCRIPTIONS := {
	CollectionPolicy.AGGRESSIVE: "Collect ore when stockpile reaches 25% of ship cargo capacity. More trips, lower inventory risk.",
	CollectionPolicy.ROUTINE: "Collect when stockpile reaches 50% of ship cargo. Balanced trip frequency.",
	CollectionPolicy.PATIENT: "Collect when stockpile reaches 80% of ship cargo. Fewer trips, higher stockpile risk.",
	CollectionPolicy.MANUAL: "Never auto-collect. You dispatch all collection runs manually.",
}

# Threshold as fraction of ship cargo capacity
const COLLECTION_POLICY_THRESHOLDS := {
	CollectionPolicy.AGGRESSIVE: 0.25,
	CollectionPolicy.ROUTINE: 0.50,
	CollectionPolicy.PATIENT: 0.80,
	CollectionPolicy.MANUAL: 0.0,  # Never triggers
}

# --- Encounter Policy ---
# Controls how workers behave when rival crews are present at the same asteroid.
# (Currently informational — encounter resolution activates in Phase 4.)
enum EncounterPolicy {
	AVOID,     # Yield slots or leave to avoid confrontation
	COEXIST,   # Stay but do not escalate — share if necessary
	CONFRONT,  # Assert dominance, challenge rivals, pressure them to leave
	DEFEND,    # Hold the claim; use force if threatened
}

const ENCOUNTER_POLICY_NAMES := {
	EncounterPolicy.AVOID: "Avoid",
	EncounterPolicy.COEXIST: "Coexist",
	EncounterPolicy.CONFRONT: "Confront",
	EncounterPolicy.DEFEND: "Defend",
}

const ENCOUNTER_POLICY_DESCRIPTIONS := {
	EncounterPolicy.AVOID: "Workers yield and leave rather than risk confrontation. Safest crew, lowest productivity at contested sites.",
	EncounterPolicy.COEXIST: "Workers stay but won't escalate. Peaceful coexistence where possible. Reputation benefit over time.",
	EncounterPolicy.CONFRONT: "Workers assert dominance and pressure rivals to leave. Higher productivity at contested sites; reputation risk if violence occurs.",
	EncounterPolicy.DEFEND: "Workers hold the claim at all costs. Use force if threatened. Best claim retention; significant reputation risk.",
}

# Calculate optimal thrust setting based on policy and mission parameters
static func calculate_thrust_setting(
	policy: ThrustPolicy,
	ship: Ship,
	destination_pos: Vector2,
	expected_cargo_mass: float = 0.0
) -> float:
	var ship_pos := ship.position_au
	var dist := ship_pos.distance_to(destination_pos)
	var current_fuel := ship.fuel
	var _max_fuel := ship.get_effective_fuel_capacity()

	# Calculate fuel needed for round trip with expected cargo
	var current_cargo := ship.get_cargo_total()
	var fuel_outbound := ship.calc_fuel_for_distance(dist, current_cargo)
	var fuel_return := ship.calc_fuel_for_distance(dist, current_cargo + expected_cargo_mass)
	var total_fuel_at_max := fuel_outbound + fuel_return

	# Find nearest refuel point from destination
	var nearest_refuel_dist := _find_nearest_refuel_distance(destination_pos)

	match policy:
		ThrustPolicy.CONSERVATIVE:
			# Ensure we can complete mission even at max thrust
			# If not possible at 100%, reduce thrust until it fits
			if total_fuel_at_max > current_fuel:
				# Calculate thrust reduction needed
				# fuel ∝ thrust, so if we need 80% less fuel, use 80% thrust
				var thrust_ratio := current_fuel / total_fuel_at_max
				return clampf(thrust_ratio * 0.9, 0.1, 1.0)  # 90% of calculated for safety margin
			else:
				# We can do max thrust safely, but stay conservative near max capacity
				return 0.8  # 80% thrust for fuel safety

		ThrustPolicy.BALANCED:
			# Use higher thrust if close to refuel points, lower if remote
			if nearest_refuel_dist < 2.0:  # Within 2 AU of civilization
				# Close to refueling - can use more thrust
				if total_fuel_at_max <= current_fuel * 0.8:
					return 1.0  # Plenty of fuel, go fast
				else:
					return 0.85  # Moderate thrust
			else:
				# Remote area - be more careful
				if total_fuel_at_max > current_fuel:
					var thrust_ratio := current_fuel / total_fuel_at_max
					return clampf(thrust_ratio * 0.85, 0.1, 1.0)
				else:
					return 0.7  # Moderate thrust for safety

		ThrustPolicy.AGGRESSIVE:
			# Always max thrust, assume we can refuel
			return 1.0

		ThrustPolicy.ECONOMICAL:
			# Use minimum thrust that still completes mission in reasonable time
			# Target 50-60% thrust for fuel savings
			if total_fuel_at_max > current_fuel:
				# Must reduce thrust
				var thrust_ratio := current_fuel / total_fuel_at_max
				return clampf(thrust_ratio * 0.9, 0.1, 1.0)
			else:
				# Could go faster, but prefer fuel economy
				return 0.5  # 50% thrust for maximum fuel efficiency

	return 1.0  # Fallback

# Select preferred route (direct or slingshot) based on policy
static func calculate_preferred_route(
	policy: ThrustPolicy,
	available_routes: Array  # Array of GravityAssist.SlingshotRoute
):
	# Returns null for direct route, or a SlingshotRoute if slingshot is preferred

	if available_routes.is_empty():
		return null  # No slingshots available, use direct

	# Get best slingshot option (already sorted by fuel savings)
	var best_slingshot = available_routes[0]  # GravityAssist.SlingshotRoute
	var fuel_savings_pct: float = best_slingshot.fuel_savings_percent
	var time_penalty_pct: float = (best_slingshot.time_penalty / best_slingshot.transit_time) * 100.0

	match policy:
		ThrustPolicy.CONSERVATIVE:
			# Use slingshot if it saves fuel (>15%) - safety first
			if fuel_savings_pct >= 15.0:
				return best_slingshot
			return null

		ThrustPolicy.BALANCED:
			# Use slingshot if good fuel savings AND reasonable time penalty
			if fuel_savings_pct >= 25.0:
				return best_slingshot
			elif fuel_savings_pct >= 15.0 and time_penalty_pct < 30.0:
				return best_slingshot
			return null

		ThrustPolicy.AGGRESSIVE:
			# Only use slingshot if massive fuel savings (>40%)
			# Time is more valuable than fuel for aggressive policy
			if fuel_savings_pct >= 40.0:
				return best_slingshot
			return null

		ThrustPolicy.ECONOMICAL:
			# Always use slingshot if ANY fuel savings
			if fuel_savings_pct > 0.0:
				return best_slingshot
			return null

	return null  # Fallback

static func _find_nearest_refuel_distance(from_pos: Vector2) -> float:
	var nearest := 999999.0

	# Check Earth
	var earth_dist := from_pos.distance_to(CelestialData.get_earth_position_au())
	nearest = minf(nearest, earth_dist)

	# Check colonies (they have refueling)
	for colony in GameState.colonies:
		var colony_dist := from_pos.distance_to(colony.get_position_au())
		nearest = minf(nearest, colony_dist)

	return nearest
