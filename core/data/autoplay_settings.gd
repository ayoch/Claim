class_name AutoplaySettings
extends RefCounted

## Autoplay Settings - High-level AI strategy controls
## These settings ONLY affect behavior when autoplay is enabled
## They do NOT affect manual play or always-on automation (see CompanyPolicy)

# ═══════════════════════════════════════════════════════════════════════════════
# CORE STRATEGY (Sliders 0-100)
# ═══════════════════════════════════════════════════════════════════════════════

## Risk Tolerance (0-100)
## How much risk the AI will take
## 0-33: Conservative (safe asteroids, avoid combat, maintain reserves)
## 34-66: Balanced (calculated risks, defend assets, grow steadily)
## 67-100: Aggressive (high-value targets, seek combat, rapid expansion)
static func get_risk_category(value: int) -> String:
	if value < 34:
		return "Conservative"
	elif value < 67:
		return "Balanced"
	else:
		return "Aggressive"

## Growth Rate (0-100)
## How aggressively to expand operations
## 0-33: Slow (accumulate profits, buy only when safe)
## 34-66: Moderate (balanced reinvestment, grow with income)
## 67-100: Rapid (spend aggressively, hire proactively)
static func get_growth_category(value: int) -> String:
	if value < 34:
		return "Slow"
	elif value < 67:
		return "Moderate"
	else:
		return "Rapid"

## Resource Focus (0-100)
## Balance between consolidating and expanding
## 0-33: Consolidate (build reserves, strengthen existing assets)
## 34-66: Balanced (mix of stockpiling and expansion)
## 67-100: Expand (reinvest everything into new territory)
static func get_resource_focus_category(value: int) -> String:
	if value < 34:
		return "Consolidate"
	elif value < 67:
		return "Balanced"
	else:
		return "Expand"

# ═══════════════════════════════════════════════════════════════════════════════
# OPERATIONAL STRATEGY (Dropdowns)
# ═══════════════════════════════════════════════════════════════════════════════

enum DiversificationStrategy {
	SPECIALIST,   # Focus on 1-2 ore types, similar ship classes
	MIXED,        # Balanced portfolio
	GENERALIST,   # Wide variety of ships, target all ore types
}

const DIVERSIFICATION_NAMES := {
	DiversificationStrategy.SPECIALIST: "Specialist",
	DiversificationStrategy.MIXED: "Mixed",
	DiversificationStrategy.GENERALIST: "Generalist",
}

const DIVERSIFICATION_DESCRIPTIONS := {
	DiversificationStrategy.SPECIALIST: "Focus on 1-2 ore types and similar ship classes. Maximize efficiency in narrow domain.",
	DiversificationStrategy.MIXED: "Balanced portfolio of ship types and ore targets. Moderate diversification.",
	DiversificationStrategy.GENERALIST: "Wide variety of ships targeting all ore types. Maximum diversification, lower efficiency.",
}

enum WorkforcePhilosophy {
	LEAN_CREW,       # Minimal headcount, maximize utilization
	ADEQUATE,        # Slight buffer for flexibility
	DEEP_BENCH,      # Excess capacity for rapid deployment
}

const WORKFORCE_NAMES := {
	WorkforcePhilosophy.LEAN_CREW: "Lean Crew",
	WorkforcePhilosophy.ADEQUATE: "Adequate",
	WorkforcePhilosophy.DEEP_BENCH: "Deep Bench",
}

const WORKFORCE_DESCRIPTIONS := {
	WorkforcePhilosophy.LEAN_CREW: "Minimal headcount. Low payroll costs, high utilization, but limited flexibility for emergencies.",
	WorkforcePhilosophy.ADEQUATE: "Slight buffer of available workers. Balanced cost and flexibility.",
	WorkforcePhilosophy.DEEP_BENCH: "Excess capacity. High payroll but can rapidly deploy to new opportunities or handle emergencies.",
}

enum TechnologyInvestment {
	FLEET_FIRST,     # Prioritize ship quantity over quality
	BALANCED,        # Mix of equipment and ships
	TECH_FOCUS,      # Invest heavily in equipment/upgrades before fleet expansion
}

const TECHNOLOGY_NAMES := {
	TechnologyInvestment.FLEET_FIRST: "Fleet First",
	TechnologyInvestment.BALANCED: "Balanced",
	TechnologyInvestment.TECH_FOCUS: "Tech Focus",
}

const TECHNOLOGY_DESCRIPTIONS := {
	TechnologyInvestment.FLEET_FIRST: "Prioritize buying ships over equipment. Fast expansion, lower per-ship capability.",
	TechnologyInvestment.BALANCED: "Mix of ship purchases and equipment/upgrades. Moderate growth and capability.",
	TechnologyInvestment.TECH_FOCUS: "Invest heavily in equipment and upgrades before expanding fleet. Slower growth, highly capable ships.",
}

enum MarketTiming {
	IMMEDIATE,       # Sell ore as soon as ships return
	OPPORTUNISTIC,   # Wait for favorable prices (moderate patience)
	STRATEGIC,       # Stockpile and wait for market events
}

const MARKET_TIMING_NAMES := {
	MarketTiming.IMMEDIATE: "Immediate",
	MarketTiming.OPPORTUNISTIC: "Opportunistic",
	MarketTiming.STRATEGIC: "Strategic",
}

const MARKET_TIMING_DESCRIPTIONS := {
	MarketTiming.IMMEDIATE: "Sell ore immediately upon return. Steady cash flow, never miss opportunities.",
	MarketTiming.OPPORTUNISTIC: "Wait for above-average prices. Higher revenue but delayed cash.",
	MarketTiming.STRATEGIC: "Stockpile ore for major price spikes and market events. Maximum profit potential, cash tied up.",
}

enum TerritorialStrategy {
	CONCENTRATED,    # Focus on 2-3 high-value asteroids
	REGIONAL,        # Claim a sector (similar orbital distances)
	DISTRIBUTED,     # Spread operations across inner/mid/outer belt
}

const TERRITORIAL_NAMES := {
	TerritorialStrategy.CONCENTRATED: "Concentrated",
	TerritorialStrategy.REGIONAL: "Regional",
	TerritorialStrategy.DISTRIBUTED: "Distributed",
}

const TERRITORIAL_DESCRIPTIONS := {
	TerritorialStrategy.CONCENTRATED: "Focus operations on 2-3 high-value asteroids. Easy to defend, vulnerable to depletion.",
	TerritorialStrategy.REGIONAL: "Claim a sector of similar orbital distances. Moderate travel times, regional dominance.",
	TerritorialStrategy.DISTRIBUTED: "Spread operations across inner, mid, and outer belt. Maximum diversification, high logistics cost.",
}

# ═══════════════════════════════════════════════════════════════════════════════
# ADVANCED SETTINGS (Dropdowns)
# ═══════════════════════════════════════════════════════════════════════════════

enum ContractPriority {
	IGNORE,          # Don't take contracts
	OPPORTUNISTIC,   # Only profitable contracts
	COMMITTED,       # Accept all, prioritize fulfillment
}

const CONTRACT_PRIORITY_NAMES := {
	ContractPriority.IGNORE: "Ignore",
	ContractPriority.OPPORTUNISTIC: "Opportunistic",
	ContractPriority.COMMITTED: "Committed",
}

const CONTRACT_PRIORITY_DESCRIPTIONS := {
	ContractPriority.IGNORE: "Don't accept or fulfill contracts. Focus purely on mining and trading.",
	ContractPriority.OPPORTUNISTIC: "Accept only highly profitable contracts. Fulfill when convenient.",
	ContractPriority.COMMITTED: "Accept all contracts and prioritize fulfillment. Best reputation, may sacrifice mining profit.",
}

enum UpgradePreference {
	ESSENTIAL_ONLY,  # Cargo/fuel upgrades
	BALANCED,        # Mix of upgrades
	PERFORMANCE,     # Thrust/efficiency upgrades
	COMBAT,          # Weapon/armor upgrades
}

const UPGRADE_PREFERENCE_NAMES := {
	UpgradePreference.ESSENTIAL_ONLY: "Essential Only",
	UpgradePreference.BALANCED: "Balanced",
	UpgradePreference.PERFORMANCE: "Performance",
	UpgradePreference.COMBAT: "Combat",
}

const UPGRADE_PREFERENCE_DESCRIPTIONS := {
	UpgradePreference.ESSENTIAL_ONLY: "Only buy cargo and fuel capacity upgrades. Maximize hauling capability.",
	UpgradePreference.BALANCED: "Mix of all upgrade types. Well-rounded fleet.",
	UpgradePreference.PERFORMANCE: "Prioritize thrust and efficiency upgrades. Fast, fuel-efficient fleet.",
	UpgradePreference.COMBAT: "Prioritize weapon and armor upgrades. Combat-ready fleet.",
}

enum DebtTolerance {
	NEVER,           # Never borrow money (when loan system exists)
	CONSERVATIVE,    # Borrow only for emergencies
	MODERATE,        # Leverage for growth opportunities
	AGGRESSIVE,      # Leverage heavily for rapid expansion
}

const DEBT_TOLERANCE_NAMES := {
	DebtTolerance.NEVER: "Never",
	DebtTolerance.CONSERVATIVE: "Conservative",
	DebtTolerance.MODERATE: "Moderate",
	DebtTolerance.AGGRESSIVE: "Aggressive",
}

const DEBT_TOLERANCE_DESCRIPTIONS := {
	DebtTolerance.NEVER: "Never borrow money. Grow only from profits. Slowest but safest.",
	DebtTolerance.CONSERVATIVE: "Borrow only for emergencies (rescue, critical repairs). Minimal debt.",
	DebtTolerance.MODERATE: "Leverage debt for growth opportunities. Balanced risk/reward.",
	DebtTolerance.AGGRESSIVE: "Leverage heavily for rapid expansion. High risk, high growth potential.",
}

enum PartnershipStrategy {
	ALWAYS_PAIR,     # Form partnerships whenever possible
	CONTESTED_ONLY,  # Only pair ships for contested asteroids
	HIGH_VALUE_ONLY, # Only pair for high-value targets
	NEVER,           # Never form partnerships
}

const PARTNERSHIP_STRATEGY_NAMES := {
	PartnershipStrategy.ALWAYS_PAIR: "Always Pair",
	PartnershipStrategy.CONTESTED_ONLY: "Contested Only",
	PartnershipStrategy.HIGH_VALUE_ONLY: "High-Value Only",
	PartnershipStrategy.NEVER: "Never",
}

const PARTNERSHIP_STRATEGY_DESCRIPTIONS := {
	PartnershipStrategy.ALWAYS_PAIR: "Form ship partnerships whenever possible. Maximum safety, lower fleet utilization.",
	PartnershipStrategy.CONTESTED_ONLY: "Pair ships only when going to contested asteroids. Balanced safety and efficiency.",
	PartnershipStrategy.HIGH_VALUE_ONLY: "Pair ships only for high-value targets. Minimal pairing overhead.",
	PartnershipStrategy.NEVER: "Never form partnerships. Maximum fleet utilization, highest risk.",
}

enum RescuePriority {
	IMMEDIATE,       # Rescue ASAP regardless of cost
	COST_CONSCIOUS,  # Only if rescue cost < 30% of ship value
	INSURANCE_ONLY,  # Only rescue if profitable (insurance > rescue cost)
	ABANDON,         # Let ships die, collect insurance
}

const RESCUE_PRIORITY_NAMES := {
	RescuePriority.IMMEDIATE: "Immediate",
	RescuePriority.COST_CONSCIOUS: "Cost-Conscious",
	RescuePriority.INSURANCE_ONLY: "Insurance Only",
	RescuePriority.ABANDON: "Abandon",
}

const RESCUE_PRIORITY_DESCRIPTIONS := {
	RescuePriority.IMMEDIATE: "Rescue derelict ships immediately regardless of cost. Best crew morale, highest expense.",
	RescuePriority.COST_CONSCIOUS: "Rescue only if cost < 30% of ship replacement value. Balanced approach.",
	RescuePriority.INSURANCE_ONLY: "Only rescue if insurance payout makes it profitable. Ruthless efficiency.",
	RescuePriority.ABANDON: "Never rescue ships. Collect insurance and buy new ships. Lowest morale, lowest cost.",
}

enum ColonyPreference {
	SINGLE_HUB,      # Pick one favorite colony for trading
	DIVERSIFIED,     # Spread trading across all colonies
	PRICE_OPTIMIZE,  # Always sell at highest-paying colony
}

const COLONY_PREFERENCE_NAMES := {
	ColonyPreference.SINGLE_HUB: "Single Hub",
	ColonyPreference.DIVERSIFIED: "Diversified",
	ColonyPreference.PRICE_OPTIMIZE: "Price-Optimize",
}

const COLONY_PREFERENCE_DESCRIPTIONS := {
	ColonyPreference.SINGLE_HUB: "Trade with one preferred colony. Build strong relationship, simpler logistics.",
	ColonyPreference.DIVERSIFIED: "Spread trading evenly across all colonies. Balanced relationships.",
	ColonyPreference.PRICE_OPTIMIZE: "Always trade at the colony offering best prices. Maximum profit, no loyalty.",
}

enum RetrofitSchedule {
	AGGRESSIVE,      # Upgrade ships frequently
	BALANCED,        # Upgrade when cost-effective
	ESSENTIAL_ONLY,  # Only critical upgrades
}

const RETROFIT_SCHEDULE_NAMES := {
	RetrofitSchedule.AGGRESSIVE: "Aggressive",
	RetrofitSchedule.BALANCED: "Balanced",
	RetrofitSchedule.ESSENTIAL_ONLY: "Essential Only",
}

const RETROFIT_SCHEDULE_DESCRIPTIONS := {
	RetrofitSchedule.AGGRESSIVE: "Retrofit ships with new upgrades frequently. Best fleet capability, highest cost.",
	RetrofitSchedule.BALANCED: "Upgrade ships when cost-effective. Moderate capability and cost.",
	RetrofitSchedule.ESSENTIAL_ONLY: "Only install critical upgrades. Lowest cost, fleet may fall behind.",
}

enum ExplorationFocus {
	KNOWN_ONLY,      # Mine known asteroids only
	BALANCED,        # Some scouting, mostly mining known sites
	SCOUT_HEAVY,     # Prioritize discovering new asteroids
}

const EXPLORATION_FOCUS_NAMES := {
	ExplorationFocus.KNOWN_ONLY: "Known Only",
	ExplorationFocus.BALANCED: "Balanced",
	ExplorationFocus.SCOUT_HEAVY: "Scout-Heavy",
}

const EXPLORATION_FOCUS_DESCRIPTIONS := {
	ExplorationFocus.KNOWN_ONLY: "Only mine known asteroids. Predictable, no discovery opportunities.",
	ExplorationFocus.BALANCED: "Mix of mining and scouting. Moderate discovery rate.",
	ExplorationFocus.SCOUT_HEAVY: "Prioritize discovering new asteroids. High discovery rate, lower mining output.",
}
