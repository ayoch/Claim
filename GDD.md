# GAME DESIGN DOCUMENT

## Claim
### Asteroid Mining Strategy Game

**Multiplayer Idle Strategy Simulation**
**Platform:** Mobile (iOS / Android)
**Engine:** Godot 4.6
**Version:** 0.5 — Consortia, Policies, Colony Tiers, Design Pillars
**February 2026**

---

## 1. Vision & Core Concept

### 1.1 Elevator Pitch
Build a deep-space mining empire across the real solar system. Stake claims on asteroids by deploying automated mining units, manage supply lines to keep remote workers fed and equipment running, and haul ore back to market — all while competing with rival corporations (AI or human) for finite resources. The player who contributes the most materials to a collective endgame project earns a reward that carries into the next epoch.

### 1.2 Genre & Tone
Idle/incremental management meets hard science fiction simulation. Draws from Dope Wars (economic arbitrage), idle tycoons (long-horizon strategy), and hard sci-fi (grounded realism). Combat exists but is rare, costly, and desperate — especially early on. The real conflicts are economic, logistical, and informational. Violence becomes more common as scarcity intensifies and territorial disputes escalate.

### 1.3 Design Pillars
- **Grounded realism:** All physics, distances, travel times, and resource quantities are based on real or plausible extrapolated numbers. If a ship accelerates at 0.3g, we calculate real transit times.
- **Low attention, high engagement:** A meaningful play session is five minutes. The game runs while you're away. Decisions matter more than time spent.
- **Incomplete information:** You never know exactly what competitors are doing. Intelligence is partial, sometimes unreliable, and interpreting it is a core skill.
- **Economic depth over action:** This is a numbers game with a beautiful skin, not an action game. Strategy emerges from resource allocation, market timing, and logistics planning.
- **Worker autonomy:** You are the CEO, not the foreman. Workers make their own decisions in the field based on their personalities. You set direction; they execute — sometimes not the way you'd prefer.
- **Narrative consequence over numerical feedback:** The game communicates the effects of player actions through the world, not through UI meters. A rescue operator is curt because your reputation is low. Workers decline your offers with "I've heard things." Colony traders quietly show you their worst prices. The player who pays attention connects the dots. The player who doesn't may never understand why things aren't going well — and that's fine.
- **Playstyle ecosystem, not morality system:** The game does not judge aggressive or peaceful play. It simulates consequences. An aggressive player pays different costs (worse prices, rougher crew, becoming a target) and reaps different rewards (seized claims, salvaged equipment, intimidated rivals). A peaceful player builds compounding advantages (colony relationships, skilled crew, reliable rescue) but risks losing developed claims they won't defend. The interesting space is in between — and the game supports every arc. The tutorial warns that "actions have consequences" without prescribing which actions are right.

### 1.4 Player Experience
The player opens the app and is greeted with a summary of events since their last session: ships that arrived at destinations, mining output from deployed units across the belt, market price changes, contract opportunities, territorial disputes between workers, rumors, and observed activity from competitors. They make a series of quick decisions — accept a contract, redirect a ship, hire a worker, deploy mining units to a new asteroid — each requiring a tap or two. Then they close the app. The simulation continues. Next time they check in, they see the results.

The rhythm is like checking a command dashboard, not playing an action game. Think of it as being a CEO who reviews reports and signs off on decisions, rather than an engineer tweaking parameters.

### 1.5 Game Modes
The game supports two modes with identical mechanics:

- **Single Player:** The player competes against AI-controlled rival corporations that follow the same rules, stake claims, trade, and may contest asteroids. Includes leaderboards tracking total revenue, claims held, ore extracted, and endgame project contributions.
- **Multiplayer:** All players share a persistent solar system on a **named server**. Each server is an independent world with its own economy, claims, and endgame project. The first server is named **Euterpe**. Additional servers can be spun up as population grows — the definition of "too crowded" is an open design question. AI corporations may still fill the competitive landscape when player counts are low. Leaderboards are per-server.

---

## 2. Setting & Lore

### 2.1 Time Period
The game begins on **February 18, 2026** (the real launch date). The game world uses real calendar dates computed from the simulation clock, displayed in the player's preferred format (US, UK, EU, or ISO).

> **STATUS: IMPLEMENTED.** Game clock starts at today's date with full calendar math (leap years, proper month lengths). Date display in the speed bar with format options in settings.

Humanity has expanded into the solar system. Colonies exist on Mars, orbital stations, and among the moons of the outer planets. The asteroid belt and Kuiper Belt are the frontier — rich in resources but largely lawless.

### 2.2 Technology Level
Technology has advanced significantly but remains grounded. Fusion power is mature and provides the primary propulsion for serious mining operations. Solar sails exist as a cheap, slow alternative. Fabrication is faster than today but still requires time and raw materials. Stasis or inertial dampening technology exists to allow human survival during sustained high-acceleration burns.

An in-lore explanation exists for why AI does not run these operations autonomously. Plausible options include regulatory restrictions following a historical incident, AI limitations in strategic judgment, or economic structures that evolved around human decision-making.

### 2.3 The Solar System
The actual solar system with real distances, asteroid belt parameters, and orbital mechanics. Players operate primarily in the asteroid belt (2–3.5 AU), with trade routes extending to colonies throughout the inner and outer system. The Kuiper Belt may become relevant in late-game play.

> **STATUS: IMPLEMENTED.** The solar system uses **Keplerian orbital mechanics** based on JPL orbital elements for all 8 planets. Positions are computed from the game's Julian Date using Kepler's equation (Newton-Raphson solver). An automated **Ephemeris Verification** service periodically compares computed positions against JPL Horizons API data to confirm accuracy. 200+ named asteroids are tracked with proper orbital positions. The solar map renders the full system with a procedural starfield background, planet glow effects, ship trajectories, and colony markers.

---

## 3. Core Gameplay Loop

### 3.1 Overview
The player manages a mining corporation that stakes claims on asteroids by deploying automated mining units. Ships are logistics vessels — they haul equipment out, deliver food and supplies, collect accumulated ore, and bring it to market. The simulation runs continuously whether the player is engaged or not.

The core loop is:
1. **Scout** — Identify promising asteroids based on composition, distance, orbital position, and competition.
2. **Claim** — Dispatch a ship carrying mining units, workers, and supplies. First to deploy units on a body stakes a claim on those mining slots.
3. **Supply** — Keep remote claims running by sending regular supply ships with food and replacement parts. Workers consume food and produce waste.
4. **Collect** — Send ships to retrieve accumulated ore from mining sites.
5. **Sell** — Sell ore on the open market, to colonies, or through contracts. Or contribute materials to the endgame project.
6. **Expand** — Use profits to buy more ships, hire more workers, deploy more mining units, and spread across the belt.

> **STATUS: PARTIALLY IMPLEMENTED.** The mine-haul-sell loop is functional but uses the older model where ships stay at the asteroid during mining. The transition to deployable autonomous mining units, supply logistics, and claim staking is a major upcoming refactor (see Section 8.3).

### 3.2 The Decision Cycle
Key decisions:
- **Where to stake claims:** Which asteroids to target — composition, distance, fuel cost, available slots, competitive risk.
- **How to equip:** Mining units to deploy (mass/volume constraints), ship selection, fuel and food loading.
- **How to sustain:** Supply route planning to keep remote workers fed and equipment maintained.
- **When to sell:** Lock in a contract at guaranteed price or gamble on the open market.
- **What to sell vs. contribute:** Operating cash vs. endgame project contributions.
- **Who to hire:** Named crew with varying skills, personalities, and pay expectations. Personality determines field encounters.
- **Where to trade:** Colony relationships for equipment, fuel, and manufactured goods.
- **Whether to arm:** Weapons cost cargo capacity and money. Using them damages reputation. But sometimes you need to defend what's yours.

### 3.3 Time & The Simulation Tick
**1 tick = 1 game-second** at 1x speed, scaled by `TimeScale.speed_multiplier`. Transit times from Brachistochrone physics (1 AU at 0.3g ≈ 5.2 game-days). Mining units produce continuously. Market prices shift on supply, demand, and events.

> **STATUS: IMPLEMENTED.** Up to 30 batched steps/frame × 500 ticks/step = 200,000x without framerate issues. Speed presets: 1x, 5x, 20x, 50x, 100x (200,000x for testing).

### 3.4 Communication Delay
Light-speed delay is real. An order at 2 AU takes ~17 minutes; at 5 AU, nearly an hour. This physically prevents micromanagement — by the time you learn about a situation and respond, your workers have already handled it their way.

> **STATUS: NOT YET IMPLEMENTED.**

### 3.5 Policy System
**Policies** are broad strategic directives governing crew behavior across the operation, set in the HQ tab. This is the core idle mechanism: set policy, check in occasionally, handle the rare situation that needs a personal decision.

**Company-wide policies** apply as defaults to all operations:
- **Supply policy** — how aggressively to resupply remote sites (frequency, stockpile targets)
- **Collection policy** — when to send ore pickup runs (threshold, scheduled, opportunistic)
- **Encounter policy** — how workers handle rival crews (avoid, coexist, confront)
- **Thrust policy** — transit speed vs fuel efficiency tradeoff (already implemented: Conservative/Balanced/Aggressive/Economical)

**Per-site overrides** allow the player to set different policies for specific claims. A high-value platinum site might get aggressive defense and frequent resupply, while a low-yield carbon site runs on minimal support.

Per-site overrides surface naturally: the HQ tab shows **advisory alerts** when site conditions conflict with company-wide policy — "Rival crew spotted at Psyche, your encounter policy is set to Coexist" — with quick action to override or dismiss.

**Play style progression:**
- **Early game (manual):** The player dispatches every mission by hand. Policies exist but there's not much to automate with one ship. The player learns the mechanics.
- **Mid game (mixed):** The player has enough sites that manual management becomes tedious. They start relying on policies and auto-routes. Manual dispatch is still available for special situations.
- **Late game (strategic):** The operation runs on policy. The player's role is strategic — where to expand, how to respond to rivals, when to upgrade. The phone buzzes with strategic alerts, not routine logistics.

Both manual and auto play styles are always available from the start. A player who wants a fully passive experience can set policies immediately. This won't be competitive in multiplayer, but it's allowed.

> **STATUS: NOT YET IMPLEMENTED.** Company thrust policy exists. All other policies, per-site overrides, and the advisory alert system are not yet built.

### 3.6 Alert System
The HQ tab divides incoming information into two tiers:

**Strategic alerts** — situations that require or strongly suggest a player decision. These persist until resolved or dismissed. They are visually distinct (pinned, different color, badge count). Examples:
- Rival crew arrived at your claim
- Supply critically low at a site
- Equipment failing, mining unit going offline
- Ship breakdown
- Worker conflict escalating

**News feed** — informational events that require no action. These scroll by and age out naturally. Examples:
- Contract available
- Market price shift
- Survey results
- Mission completed
- Worker hired

Strategic alerts interact with **worker personality** and **communication delay**. When a situation arises at a remote site:
- A crew led by a **cautious leader** buys time — the alert arrives as "this is happening, you have a window to respond."
- A crew led by a **hotheaded leader** acts immediately — the alert arrives as "this already happened, here's what your crew did."
- **Light-speed delay** further constrains the window. A site at 5 AU has ~45 minutes of one-way delay. By the time you hear about a situation and send a response, 90 minutes have passed. Your workers may have already acted.

The player influences which type of alert they get by **who they hire and where they assign them** — but can never fully predict outcomes. Hiring decisions have consequences.

> **STATUS: NOT YET IMPLEMENTED.**

---

## 4. Physics & Realism

### 4.1 Core Principle
All distances, travel times, fuel consumption, and resource quantities derive from real or plausible values. Future technology proposes specific performance characteristics and uses those consistently.

> **STATUS: IMPLEMENTED.** AU-based coordinates. JPL Keplerian elements. Brachistochrone/Hohmann transit. Mass-aware fuel consumption.

### 4.2 Propulsion Systems
Ships use one of several drive types (cost/speed tradeoff). Travel follows brachistochrone trajectory: constant acceleration to midpoint, flip and decelerate.

| Drive Type | Acceleration | Fuel Cost | Use Case |
|---|---|---|---|
| Solar Sail | ~0.001g (variable) | Effectively free | Bulk cargo, non-urgent repositioning. Very slow. Transit times measured in weeks to months. |
| Ion Drive | ~0.01g sustained | Low | Budget operations. Transit times in weeks. Efficient but uncompetitive for time-sensitive missions. |
| Fusion Drive | ~0.1-0.5g sustained | Moderate to high | The workhorse. Transit times in days across belt distances. Competitive standard. |
| Advanced Fusion (late game) | ~1g+ sustained | Very high | Fast transit, hours to a day. Expensive. Strategic advantage for critical missions. |

> **STATUS: PARTIALLY IMPLEMENTED.** The Fusion Drive is the only propulsion system currently modeled. The starter Prospector operates at 0.3g with a thrust setting slider (0-100%). Hohmann transfers are implemented as a fuel-efficient alternative (25% fuel, 3x time). **Solar Sail, Ion Drive, and Advanced Fusion are not yet implemented** as distinct drive types.

### 4.3 Asteroid Types & Composition
Asteroids are classified by spectral type, which determines their composition and economic value. These are based on real asteroid taxonomy.

| Type | Composition | Primary Value | Approximate Abundance |
|---|---|---|---|
| S-type (Silicaceous) | Silicates, some iron and nickel | Moderate — structural metals | ~17% of belt |
| M-type (Metallic) | Iron, nickel, platinum group metals | High — precious and industrial metals | ~8% of belt |
| C-type (Carbonaceous) | Carbon compounds, water ice, organics | Variable — water/volatiles for colonies and fuel; organics | ~75% of belt |

Each asteroid has a finite number of **mining slots** determined by its size and surface area. A small asteroid might support 2-3 mining units. A large one might support 10+. This caps how many corporations can operate on any given body simultaneously.

> **STATUS: PARTIALLY IMPLEMENTED.** 200+ named asteroids with body types (ASTEROID, COMET, NEO, TROJAN, CENTAUR, KBO) and ore yields per type. Five ore types: Iron ($50 base), Nickel ($120), Platinum ($800), Water/Ice ($200), Carbon/Organics ($150). Survey events periodically shift individual asteroid yields by -30% to +50%. **Mining slot limits are not yet implemented.**

### 4.4 Orbital Mechanics
Distances between objects change over time — an asteroid 0.5 AU away today might be 2 AU away in six months. Strategic opportunities shift continuously.

> **STATUS: IMPLEMENTED.** Full Keplerian elements with JPL data. All bodies orbit each tick. Solar map reflects orbital motion in real time. Transit calculations use current positions.

### 4.5 Gravity Assist Routes
Planetary gravity assists reduce fuel at the cost of longer travel time.

> **STATUS: IMPLEMENTED.** Checks all 8 planets as flyby waypoints. Must save ≥15% fuel, add ≤60% time. Multi-leg trajectories rendered as dashed lines. Thrust policy determines direct vs. slingshot preference.

---

## 5. Economy & Market

### 5.1 Dual Currency System
Two forms of value, and the tension between them drives strategy:

**Money** — earned by selling ore, spent on payroll, fuel, equipment, food, repairs. Keeps your corporation alive but doesn't win the game.

**Materials** — mined ore that can be sold for money or contributed to the endgame project. Contributions determine who benefits from project completion. The central tension: sell to fund operations, or contribute to advance your position.

> **STATUS: PARTIALLY IMPLEMENTED.** Money is functional. Material contribution to endgame project **not yet implemented** (see Section 7).

### 5.2 The Open Market
Prices fluctuate on supply and demand. Events drive shifts — construction booms raise metal prices, tech announcements crash rare earths (which may recover if the announcement proves false). In multiplayer, the market responds to all players collectively.

> **STATUS: IMPLEMENTED.** Random walk (±3%/tick) with 1% mean reversion, clamped 0.3x–3.0x base. Eight event types (SHORTAGE, SURPLUS, DISASTER, BOOM, RECESSION, DISCOVERY, STRIKE, TECH_ADVANCE) with 0.5x–3.5x multipliers. System-wide or colony-specific. Up to 3 concurrent events. **Player-driven market effects not yet implemented** (multiplayer).

### 5.3 Contracts
Guaranteed sale price for a specific material over a defined period. Income stability at the cost of flexibility — if market spikes above your rate, you lose potential profit.

> **STATUS: IMPLEMENTED.** Random generation with ore types, quantities, deadlines, fictional issuers (12 companies). 1.3x–2.0x premium. 60% specify delivery colony (+20% bonus). 80% allow partial fulfillment. Up to 5 available, unlimited active. Fulfillable from cargo or stockpile.

### 5.4 Colony Trade
Colonies have specific needs and products. Players trade with them, selling what they need and purchasing what the corporation can't produce internally. A player who is a colony's primary supplier may receive priority pricing or early access to manufactured goods.

Colonies also serve as **supply chain hubs** — sources of food, fuel, and replacement parts. A well-positioned colony relationship dramatically reduces supply line costs.

### 5.5 Colony Tiers
Colonies are divided into two tiers:

**Major colonies** (HQ-capable, 5-6 total) — full repair facilities, large markets, deep worker hiring pools, equipment fabrication. These are the only locations where a player can establish their headquarters.
- **Earth orbit** — most connected, most competitive, best markets
- **Mars** — gateway to the inner belt
- **Ceres** — heart of the asteroid belt, closest to the action
- **Callisto** (Jupiter) — access to Trojans, outer belt, Hildas
- **Titan** (Saturn) — frontier outpost, access to Centaurs and outer system

**Minor colonies** — can trade there, buy fuel, hire a worker or two. Limited repair facilities — they can do the work, but part availability is a problem and repairs take longer. There are only so many hands. Smaller markets with more volatile prices. Good targets for supply contracts — they need materials and will pay for deliveries.

**Colony growth and decline:**
- Heavy trade traffic grows a colony — population, facilities, market depth. Minor colonies can eventually become major.
- Lost traffic causes stagnation — longer repairs, thinner market, workers leaving. They don't disappear, but slide back.
- **Players can invest directly** in minor colony facilities (repair bay, warehouse, fuel depot, worker housing). Accelerates growth but is a semi-public good in multiplayer.

> **STATUS: PARTIALLY IMPLEMENTED.** 9 colonies exist with unique pricing. Colony tier system, growth/decline, player investment, and expanded colony count are **not yet implemented.** Current colonies:
> - **Lunar Base** (Moon) — needs Water/Ice (1.8x), Iron (1.2x)
> - **Mars Colony** (Mars) — needs Iron (1.3x), Carbon (1.4x)
> - **Ceres Station** (asteroid belt) — balanced pricing, Water premium (1.5x)
> - **Vesta Refinery** (asteroid belt) — Nickel premium (1.4x), Platinum (1.3x)
> - **Europa Lab** (Jupiter) — extreme Water premium (2.0x), Platinum (1.5x)
> - **Ganymede Port** (Jupiter) — Iron demand (1.3x), Carbon (1.5x)
> - **Titan Outpost** (Saturn) — Carbon premium (1.8x), Water (1.6x)
> - **Callisto Base** (Jupiter) — balanced, mild premiums
> - **Triton Station** (Neptune) — remote, highest premiums across the board
>
> Colony prices also scale with distance from Earth (+20%/AU scarcity premium) and are modified by active market events. Fuel pricing is location-aware: Earth base $5/unit, colony base $6.50/unit, +$1.20/unit/AU shipping. **Colony relationship mechanics (priority pricing, supplier status) are not yet implemented.** Colony count should expand to 15-20 total.

### 5.6 The Information Layer
Not all market information is reliable. A report that a competitor developed a new synthesis process might crash prices — but the report might be false. Players may spread misinformation deliberately. Evaluating information under uncertainty is a core skill.

> **STATUS: NOT YET IMPLEMENTED.** Deferred to Phase 4.

---

## 6. Claims, Competition & Combat

### 6.1 Staking a Claim
The game's title: **claiming mineable bodies**. Deploy mining units on asteroid surface slots (finite, based on size). A unit on a slot = your claim until removed, destroyed, or abandoned.

Claims are not registered or protected by authority. They are defended by presence, reputation, and — when necessary — force.

> **STATUS: NOT YET IMPLEMENTED.** Currently mining uses a ship-present model. The claim staking system is a core upcoming feature.

### 6.2 Asteroid Contention
When rival workers meet at the same asteroid, the **workers themselves** decide what happens based on personality. The player cannot directly intervene due to communication delay — they set policy and hire accordingly.

Worker personality types affect outcomes:
- **Cautious** — yield slots or leave to avoid confrontation
- **Aggressive** — seize slots, intimidate rivals, may start unnecessary fights
- **Loyal** — follow corporate policy closely, predictable
- **Leaders** — influence other workers at the same site

Possible outcomes: peaceful coexistence, intimidation, negotiation, sabotage, or violence (rare, severe reputation consequences).

> **STATUS: NOT YET IMPLEMENTED.** Worker personality traits and autonomous decision-making are deferred to Phase 2b.

### 6.3 Combat
Combat is possible but carries heavy costs.

**Early game:** Weapons are expensive, heavy, consume cargo space. Fighting over an asteroid when dozens are unclaimed is obviously wasteful.

**Late game:** Rich asteroids become scarce. Defense investments, raids on productive claims, armed escorts — combat becomes a calculated business decision.

**Consequences:** Worker injury/death (permanent loss), equipment damage/destruction, reputation damage (worse colony pricing, higher worker pay demands, becoming a multiplayer target).

### 6.4 Ship Weapons
Weapons are ship upgrades with mass and volume. Every weapon mounted is cargo capacity sacrificed. A ship loaded with weapons is a poor hauler. A ship loaded with cargo is a poor fighter. This creates meaningful fleet composition decisions:

- Run lean cargo ships and accept the risk of losing a shipment?
- Arm every ship and eat the logistics penalty?
- Dedicate one ship as an armed escort while others haul?

Weapon types (to be designed in detail):
- **Point defense** — Light, cheap, defensive. Deters opportunistic raiders.
- **Laser turret** — Moderate. Effective against equipment and small ships.
- **Kinetic launcher** — Heavy, expensive. Can threaten larger ships but has mass penalties.

> **STATUS: NOT YET IMPLEMENTED.** Ship upgrades exist (fuel tanks, engines, cargo bays, hull) but weapon upgrades are not yet defined.

### 6.5 AI Corporations
AI corporations follow all the same rules: stake claims, deploy units, trade, hire, and contest. They make strategic decisions, react to expansion, and occasionally make mistakes. Present in single player; fill gaps in low-population multiplayer servers.

> **STATUS: NOT YET IMPLEMENTED.**

### 6.6 Fog of War
Limited visibility into competitor activity:
- **Engine flares** — fusion burns visible across great distances
- **Activity signatures** — mining energy output detectable, but not who or at what scale
- **Market signals** — supply/pricing shifts hint at competitor actions

Better sensors extend range. Stealth technology reduces visibility.

> **STATUS: NOT YET IMPLEMENTED.**

---

## 7. The Endgame Project

### 7.1 Overview
Each epoch has a large-scale collective project (interstellar ship, space station, terraforming, etc.) that all corporations contribute materials toward. Provides the win condition and drives late-game scarcity as materials leave the economy.

### 7.2 Material Requirements
Massive quantities of diverse materials. Construction phases demand different materials at different times, creating market waves. Diverted materials tighten the economy — prices rise, scarcity intensifies, competition heats up.

### 7.3 Rewards
Multiple players benefit, not just the top contributor. Top contributors get the greatest benefit (head start, technology, capital). Mid-tier contributors receive lesser but meaningful rewards. Non-contributors are left behind. Exact structure is an open design question.

### 7.4 Epochs
Project completion starts a new epoch. Seasonal structure: early expansion → mid-game competition → late-game scarcity → transition. What carries over between epochs is to be designed.

> **STATUS: NOT YET IMPLEMENTED.** Deferred to Phase 4-5.

---

## 8. Player Operations & Management

### 8.1 Home Base
Each player operates from a **major colony**, chosen at game start. The base serves as the hub for storage, fabrication, crew housing, and ship docking. Its location relative to the belt affects transit times, light-speed communication delay, and strategic positioning.

**Starting location matters.** Earth is central and well-connected but competitive. Mars gives better access to the inner belt. Ceres is the heart of the belt. Callisto puts you near the Trojans and outer belt but far from inner system markets.

**Relocation is possible** but expensive and disruptive. Moving HQ means rebasing all ships, recalculating all light-delay windows, and potentially losing colony relationships. Supply lines must be rebuilt. You'd only do it if the strategic landscape shifted enough to justify it — a region dominated by a rival consortium, or a new opportunity opening up elsewhere.

> **STATUS: IMPLICIT.** Earth serves as the implicit home base. Ships dock at Earth, workers are hired there, equipment is purchased/fabricated there. No explicit base selection, relocation mechanic, or colony tier system exists yet.

### 8.2 Fleet
Players own ships of varying size and capability. Ships are defined by their drive type, cargo capacity (mass and volume), fuel capacity, and upgrade slots. Fleet composition is a strategic choice:
- **Haulers** carry maximum cargo but are slow and vulnerable.
- **Couriers** are fast but carry little.
- **Explorers** have long range for deep-space prospecting.
- **Armed escorts** sacrifice cargo space for weapons.

Ships require maintenance and fuel, representing ongoing operational costs. Fleet expansion is a critical investment — a logistics empire cannot run on one ship.

**All units are real:** mass in tonnes (t), volume in cubic meters (m³), fuel in tonnes of propellant (which has mass and affects acceleration), thrust in g-force.

#### Ship Class Base Specifications

| Stat | Courier | Prospector | Hauler | Explorer |
|---|---|---|---|---|
| Dry mass | 73.4t | 214.8t | 488.2t | 141.6t |
| Cargo capacity (mass) | 38t | 107t | 412t | 63t |
| Cargo capacity (volume) | 54 m³ | 143 m³ | 584 m³ | 91 m³ |
| Fuel capacity | 46.5t | 118t | 237t | 192t |
| Max thrust | 0.38g | 0.31g | 0.19g | 0.47g |
| Crew | 2 | 3 | 5 | 2 |
| Upgrade slots | 3 | 4 | 5 | 4 |

**Fuel has mass.** A fully loaded Prospector masses 439.8t (214.8t dry + 118t fuel + 107t cargo). An empty return is far lighter and faster. Outbound trips are always slower than returns.

#### Per-Ship Variation
Each generated ship varies from its class baseline:

| Stat | Variation | Justification |
|---|---|---|
| Dry mass | ±5% | Manufacturing tolerances, aftermarket hull work |
| Cargo mass capacity | ±10% | Reinforced floors, removed bulkheads |
| Cargo volume | ±10% | Internal partitioning choices |
| Fuel capacity | ±8% | Additional or reduced tankage |
| Max thrust | ±5% | Engine tuning, wear history |
| Upgrade slots | ±1 slot | Hardpoints welded on or sealed off |

Example: a generated Prospector at 208.1t dry, 0.29g thrust, 112t cargo, 136 m³, 122t fuel, 3 slots — lighter with more cargo but weaker engines.

> **STATUS: NEEDS UPDATE.** Four ship classes exist in code but use old placeholder values (round numbers, no volume, no variation). Ship data needs to be updated to these specifications. Ship purchasing UI is not yet implemented.

### 8.3 Mining Equipment (Autonomous Mining Units)
**Autonomous mining units** are cargo items deployed on asteroid surfaces. They require workers to operate — a unit without workers is inert. Once deployed and staffed, they extract ore continuously without a ship present. Ships periodically collect stockpiled ore and deliver food/supplies/parts.

Mining units have mass/volume (constrain transport capacity), require a mining slot, degrade over time (need maintenance parts), and can be retrieved, relocated, upgraded, or abandoned.

#### Mining Unit Specifications (Generation 1)

| Unit Type | Mass | Volume | Workers Required | Notes |
|---|---|---|---|---|
| Basic Mining Unit | 7.6t | 11.4 m³ | 1 | Entry-level extraction |
| Advanced Mining Unit | 13.2t | 16.8 m³ | 2 | Higher yield, more maintenance |
| Refinery Unit | 21.5t | 27.3 m³ | 3 | On-site ore processing, highest output |

A Prospector (107t / 143 m³ cargo) can carry roughly 8 Basic Mining Units by volume, or 14 by mass — volume is the constraint. After accounting for food and repair parts for the workers, a typical deployment run might deliver 4-5 units plus supplies.

> **STATUS: NOT YET IMPLEMENTED.** Current system uses ship-mounted equipment that provides mining bonuses while the ship is present. Three equipment types exist (Basic Processor, Advanced Processor, Refinery) but function as ship buffs, not deployable units. This is a fundamental architectural change.

### 8.4 Cargo: Mass and Volume
Cargo holds are constrained by both **mass** (tonnes) and **volume** (m³). Heavy-but-compact items (platinum, weapons) vs. light-but-bulky items (food, organics, mining units). Supply runs are volume-constrained; ore hauling is mass-constrained.

#### Supply & Weapon Specs

| Item | Mass | Volume | Notes |
|---|---|---|---|
| Food (per worker/day) | 2.8 kg | 0.0044 m³ | Compact rations, water recycled on-site |
| Repair parts (per maintenance cycle) | 0.45t | 0.28 m³ | Filters, lubricants, replacement components |
| Point defense turret | 1.7t | 0.9 m³ | Light, defensive, deters opportunistic raids |
| Laser turret | 4.3t | 2.6 m³ | Moderate offense, effective vs equipment and small ships |
| Kinetic launcher | 11.8t | 7.4 m³ | Heavy, serious threat to large ships |

**Example:** Resupplying 5 workers for 60 days = 840 kg food (0.264 m³) plus repair parts — lightweight, leaving room for ore pickup. But deploying 4 mining units (30.4t / 45.6 m³) plus supplies fills the hold quickly.

> **STATUS: NOT YET IMPLEMENTED.** Currently only mass (tonnes) is tracked for cargo. Volume constraints, food, and supply items do not yet exist.

### 8.5 Crew
Named individuals with skills, personalities, and pay expectations.

**Skills:** pilot (transit time), engineer (maintenance), mining (extraction rate).

**Personalities** determine autonomous field behavior:
- **Aggressive** — confront rivals, defend forcefully, may start unnecessary fights
- **Cautious** — avoid conflict, may yield claims, keeps workers alive
- **Loyal** — follow corporate policy closely, predictable
- **Greedy** — motivated by bonuses, may cut corners for personal gain
- **Leader** — influences other workers at the same site

Workers consume **food** (carried as cargo, resupplied at remote sites). Running out is a serious logistics failure.

> **STATUS: PARTIALLY IMPLEMENTED.** Workers have random names (40 first x 40 last), skill levels (0.7-1.5), and daily wages ($80-200). Workers are hired/fired and assigned to missions. Payroll deducts wages every game-day.
>
> **NOT YET IMPLEMENTED:** Personality traits, autonomous decision-making, distinct roles, skill progression, food consumption, waste management.

### 8.6 Fuel & Logistics
Fuel consumption scales with distance, mass, and thrust. Fuel has weight that affects acceleration. Running out mid-transit = derelict.

With units deployed across the belt, logistics is the core challenge: supply route planning, fuel budgets, cargo allocation between food/parts/ore, and resupply frequency.

> **STATUS: IMPLEMENTED (basic).** Fuel consumption scales with distance, mass, and thrust. Derelict state on fuel depletion. Location-aware fuel pricing from nearest source.
>
> **NOT YET IMPLEMENTED:** Supply route planning, food as cargo, fuel processor equipment (extracting fuel from water-ice asteroids), player-owned fuel depots.

### 8.7 Ship Upgrades
Modules with mass, occupying upgrade slots. Categories: speed, efficiency, capacity, weapons (see Section 6.4).

> **STATUS: PARTIALLY IMPLEMENTED.** 9 types across fuel, engine, cargo, and hull. **Weapon upgrades not yet implemented.**

### 8.8 Mining Unit Generations
New models release periodically within an epoch — better extraction, durability, or maintenance at higher cost.

Upgrade decisions: replace working units (expensive, better output), keep old and expand instead (more claims, lower per-unit), or mix generations by asteroid value. Units can also be upgraded in place via improvement kits (cheaper but less effective than replacement).

> **STATUS: NOT YET IMPLEMENTED.**

---

## 9. Consortia & Alliances

Corporations can form **consortia** — goal-oriented alliances with explicit shared objectives. A consortium is defined by what its members are cooperating TO DO, not just who they are. Players can join or leave freely. A player can belong to multiple consortia simultaneously.

### 9.1 What Consortia Are For
Consortia are flexible. Some examples:
- A **mining cooperative** that shares supply routes and defends a region of the belt
- A **trade cartel** that coordinates pricing to control a commodity market
- A **defense pact** against a specific aggressor or pirate group
- An **endgame push** pooling contributions toward the collective project
- A **raider syndicate** sharing intel on vulnerable targets and coordinating attacks
- A **colony development group** jointly investing in a minor colony's infrastructure
- A **protection racket** that "offers security services" to independents in their territory

The mechanics don't care about intent. Shared supply routes work the same whether you're hauling ore or weapons. Pooled intelligence is useful whether you're scouting mining targets or raid targets.

### 9.2 Mechanical Benefits
Cooperation comes with real in-game advantages, not just social convenience:
- **Shared claim visibility:** Members can see each other's claims, supply status, and ore stockpiles.
- **Shared supply routes:** Members can share supply infrastructure, reducing logistics costs for all.
- **Pooled ore stockpiles:** Collective storage and coordinated selling for market leverage.
- **Joint colony investment:** Pool funds to develop colony facilities faster.
- **Coordinated contract fulfillment:** Multiple members contribute to large contracts no single player could fill.
- **Non-aggression:** Members' workers will not initiate conflict with each other at contested sites.
- **Mutual defense:** When a non-member threatens a member's claim, nearby member workers may respond.
- **Coordinated territory:** Divide a region — "you take that sector, we'll take this one" — reducing wasteful competition.

### 9.3 Agreements & Governance
Consortia can set shared agreements that the game makes visible but does not enforce. Enforcement is social — members see who's complying and deal with violators themselves.

**Agreement types:**
- **Price floors:** Set a minimum sale price per commodity. Members are warned when selling below the floor. The consortium log shows who violated it.
- **Territory claims:** Mark asteroids or regions on the map as consortium territory. No mechanical enforcement — just visibility. Everyone sees if someone's mining where they shouldn't be.
- **Quotas:** Set a target tonnage per member per period. Dashboard shows who's hitting it and who's not.
- **Protected zones:** Flag a region as defended. Members in the area get alerts when non-members enter.

**Governance is minimal:**
- **Founder** — whoever created the consortium. Can unilaterally kick members. If members don't like how the founder runs things, they leave and form a new one.
- **Removal** — any member can propose a kick. It goes to all other members as a strategic alert ("Remove PlayerX? Reason: undercutting platinum floor"). Majority vote wins.
- **Joining** — any player can request to join. Founder approves or denies.
- **Leaving** — any member can leave at any time, no penalty.

The game provides transparency (shared dashboards, compliance logs). Players provide consequences.

### 9.4 Consortium Risks
- **Betrayal:** A member could defect, taking shared intelligence about claim locations and supply schedules.
- **Free riding:** A weak member benefits from the consortium's resources without contributing proportionally.
- **Reputation by association:** If one member behaves aggressively, it may taint the reputation of the group.
- **Power imbalance:** A dominant member may effectively control the consortium, turning allies into dependents.
- **Conflicting memberships:** A player in two consortia with opposing goals creates tension.

### 9.5 Consortium vs. Consortium
As the game progresses and territory becomes scarce, conflicts may escalate from individual disputes to consortium-level territorial wars. A mining cooperative defending their claims against a raider syndicate. Two trade cartels competing to control the platinum market. These large-scale conflicts are the most dramatic events in the game — and the most costly. Cooperation is likely more decisive than firepower.

> **STATUS: NOT YET IMPLEMENTED.** Consortia are a Phase 4 multiplayer feature but should also be available in single-player against AI corporations.

---

## 10. Leaderboards

Categories: total revenue, claims held, ore extracted, project contributions, net worth, reputation.

**Single player:** tracked against AI corporations.

**Multiplayer:** per-server, real-time, with historical rankings and consortium aggregates. Climbing the rankings signals success but paints a target.

> **STATUS: NOT YET IMPLEMENTED.**

---

## 11. Ship Hazards & Rescue

> **STATUS: IMPLEMENTED.** A full ship hazard and rescue system has been built:

### 11.1 Engine Wear & Breakdowns
Engines degrade at 0.00003/tick (~6% per 200,000-tick trip). Below 50% condition, breakdown probability increases. Baseline chance exists even on well-maintained ships. Typical frequency: once every 2-30 trips. Breakdowns and fuel depletion both trigger derelict state.

### 11.2 Professional Rescue
Dispatched from the **nearest rescue-capable source** (Earth, Ceres Station, Ganymede Port, Mars Colony, Lunar Base, Europa Lab).

- **Rescue:** $15,000 base + $8,000/AU. Ship returned at 50% condition, 10% worker loss chance.
- **Refuel:** $5,000 base + $4,000/AU.

### 11.3 Benevolent Stranger Rescue
~1/500,000 chance per tick (~once per 6 game-days). 3x near populated areas, 0.5x deep space.

- **Immediate** (no transit). Restores 25% fuel, 40% engine. Preserves cargo, no worker loss.
- Offers expire after 12 game-hours. Accept free, tip ($2,000-5,000), or decline.
- Not tipping: -10 reputation. Tipping: +5.

### 11.4 Breakdown Alerts
Breakdowns, rescues, refuels, and stranger offers are logged as color-coded events in the HQ dashboard. Desktop breakdowns trigger window attention request.

---

## 12. Reputation System

> **STATUS: PARTIALLY IMPLEMENTED.** A foundation reputation system tracks the player's standing.

### 12.1 Score & Tiers
Score: -100 to +100, starting at 0. Five tiers:
- **Notorious** (< -50) — red
- **Shady** (< -15) — red
- **Unknown** (< 15) — white
- **Respected** (< 50) — green
- **Renowned** (>= 50) — green

### 12.2 Modifiers
| Action | Reputation Change |
|---|---|
| Not tipping a stranger rescuer | -10 |
| Tipping a stranger rescuer | +5 |
| Not paying professional rescue | -3 |
| Workers initiating violence at a contested claim | -8 to -15 (scales with severity) |
| Workers defending a claim without escalating | +2 |
| Completing contracts on time | +2 |
| Failing contracts | -5 |
| Sustained peaceful coexistence at shared bodies | +1 (periodic) |

### 12.3 Consequences
- **Colony pricing:** notorious pay more, renowned get discounts
- **Contracts:** better offers for reputable corporations
- **Worker hiring:** skilled workers refuse notorious employers; aggressive workers gravitate to shady ones
- **Stranger rescue:** more likely for reputable corporations
- **Multiplayer:** others see your tier (not exact score)
- **AI behavior:** more likely to contest notorious, coexist with respected

> **STATUS: PARTIALLY IMPLEMENTED.** Score, tiers, and stranger rescue modifiers work. **All other consequences not yet implemented.**

---

## 13. User Interface

### 13.1 Dashboard, Not Game Screen
Corporate command dashboard, not traditional game UI. High information density, fast navigation.

> **STATUS: IMPLEMENTED.** Tabbed dashboard, 720x1280 portrait, canvas_items stretch.

### 13.2 UI Tabs

**HQ Dashboard** — The player's primary interface. Two-tier alert system: **strategic alerts** (pinned, persistent, require decisions) and **news feed** (informational, scrolling, ages out). Policy controls for company-wide directives (supply, collection, encounter, thrust). Reputation display, mission summaries, claim overview. Per-site policy overrides accessible from strategic alerts.

**Fleet & Market** — Combined fleet management and market view. Ship cards showing status, fuel, engine condition, cargo (mass and volume). Dispatch controls with destination picker, transit mode selection (Brachistochrone/Hohmann), cargo loading (mining units, food, supplies, ore). Market prices and contract management.

**Workers** — Hire/fire workers, view skills, wages, and personality traits. Assign to missions. View worker reports from remote sites.

**Ship Outfitting** — Purchase and install equipment and upgrades (fuel tanks, engines, cargo bays, hull, weapons). View fabrication queue.

**Claims Map** — Overview of all staked claims across the belt: which asteroids have your mining units, how many slots remain, current ore stockpile levels, supply status, and time since last resupply.

**Solar Map** — Interactive 2D map of the solar system. Procedural starfield. Planet and asteroid markers. Colony markers. Ship positions with trajectory lines. Claim indicators on asteroids. Rival activity signatures (fog of war permitting).

**Leaderboards** — Rankings across multiple categories (revenue, claims, ore extracted, project contributions, net worth). In single player, tracks the player against AI corporations. In multiplayer, shows per-server rankings. Consortium aggregate scores when applicable.

### 13.3 Speed Controls
Speed bar with preset buttons (1x, 5x, 20x, 50x, 100x) plus keyboard shortcuts (1/2/3/0). Maximum speed 200,000x for testing. Game date displayed in the speed bar with configurable format (US/UK/EU/ISO).

### 13.4 Responsive Layout
All UI uses `HFlowContainer` for button rows and `autowrap_mode` on text labels to prevent horizontal overflow on narrow screens.

---

## 14. Technical Architecture

### 14.1 Overview
Godot client (mobile) communicating with a cloud backend. Currently runs entirely client-side as a single-player prototype.

### 14.2 Client Architecture (Current)
Four autoload singletons:
- **EventBus** — 33+ signals for decoupled communication between all systems
- **GameState** — Central data store for all game state (money, ships, missions, workers, claims, etc.)
- **Simulation** — Tick-based game loop processing all subsystems per tick
- **TimeScale** — Speed control and time formatting

Additional services:
- **HTTPFetcher** — HTTP request manager with timeouts
- **EphemerisVerifier** — Periodic JPL Horizons API verification of orbital computations

Signal flow: UI → GameState methods → EventBus signals → all UI tabs refresh.

### 14.3 Simulation Subsystems
The simulation processes these systems each tick:
1. Orbital advancement (planets, asteroids, colonies)
2. Ship missions (transit, deployment, supply, collection, return)
3. Trade missions (transit to colony, selling, return)
4. Ship position interpolation (S-curve Brachistochrone or linear Hohmann)
5. Engine wear and breakdown checks
6. Rescue mission timers
7. Refuel mission timers
8. Equipment fabrication queue
9. Stranger rescue chance rolls
10. Payroll deduction (daily)
11. Asteroid survey events (yield mutations)
12. Market price drift and event generation
13. Contract generation, countdown, and expiry
14. Autonomous mining unit production (ore accumulation at claimed sites)
15. Mining unit degradation and maintenance
16. Worker food consumption and supply tracking
17. Worker encounter resolution (when rival workers meet at contested sites)

### 14.4 Performance
At high simulation speeds, ticks are processed in batches: up to 30 steps per frame, each advancing up to 500 ticks. This allows 15,000 ticks per frame at 60fps, supporting speeds up to 200,000x without framerate degradation.

### 14.5 Server Architecture (Multiplayer)
**Named servers** — independent worlds (separate economies, claims, markets, leaderboards, endgame projects). First server: **Euterpe**. Players cannot transfer between servers.

**Stack:** Python + PostgreSQL on Linux. Godot client is a thin display layer — sends decisions, receives state. All simulation/RNG/state mutation runs server-side.

**Development:** Local server (`localhost`) first, then deploy to remote Linux. Catches client-server issues without deployment complexity.

**Server authority required for:** simulation loop, all RNG, all state mutations, market/contract generation, worker encounter resolution, consortium coordination, leaderboards, anti-cheat (TimeScale, positions, money, fuel, engine condition, mining, claims).

### 14.6 Save System
**Saved:** money, resources, workers, equipment, upgrades, ships (basic), settings, date format.

**Not yet saved:** missions, trade missions, contracts, market events/state, fabrication queue, game clock, reputation, stranger offers, rescue/refuel missions, yield mutations, claims, mining units, food/supply.

---

## 15. Development Roadmap

### Phase 1: Economic Core (Single-Player Prototype)
Build the fundamental game loop in Godot with no networking.

| Feature | Status |
|---|---|
| Basic resource model (money, ore types, fuel) | **DONE** |
| Worker hiring and payroll | **DONE** |
| Equipment purchasing and fabrication | **DONE** |
| Mission dispatch and transit time calculation | **DONE** |
| Mining output over time | **DONE** |
| Selling at market prices | **DONE** |
| Ship upgrades (speed, efficiency, capacity) | **DONE** |
| Ship purchasing (multiple ship classes) | NOT STARTED |

### Phase 2: Simulation Depth
Add the systems that make the single-player experience strategically rich.

| Feature | Status |
|---|---|
| Multiple asteroid types with varying compositions | **DONE** |
| Orbital mechanics affecting distances over time | **DONE** (Keplerian orbits, JPL data) |
| Fuel consumption and logistics constraints | **DONE** (mass-aware, location-aware pricing) |
| Contract system (fixed-price vs. spot market) | **DONE** |
| Colony trade network | **DONE** (9 colonies with unique pricing) |
| Market price fluctuations driven by events | **DONE** (8 event types, random walk) |
| Equipment wear, maintenance, and fabrication time | **DONE** |
| Gravity assist / slingshot routes | **DONE** |
| Ship hazards, rescue, and reputation | **DONE** |
| Company thrust policies | **DONE** |

### Phase 2b: Claim Staking & Logistics Overhaul
Refactor the mining system from ship-present to deployable autonomous units.

| Feature | Status |
|---|---|
| Autonomous mining units (deployable cargo items with workers) | NOT STARTED |
| Cargo volume constraints (mass + volume) | NOT STARTED |
| Mining slots per asteroid | NOT STARTED |
| Claim staking (first to deploy owns slots) | NOT STARTED |
| Passive ore accumulation at claimed sites | NOT STARTED |
| Separate mission types (deploy, supply, collect) | NOT STARTED |
| Worker food consumption and waste | NOT STARTED |
| Mining unit degradation and maintenance | NOT STARTED |
| Mining unit generations (periodic tech upgrades) | NOT STARTED |
| Worker personality traits | NOT STARTED |
| Worker autonomous encounter resolution | NOT STARTED |
| Communication delay (light-speed) | NOT STARTED |
| Policy system (company-wide + per-site overrides) | NOT STARTED |
| Two-tier alert system (strategic + news feed) | NOT STARTED |
| Colony tier system (major/minor) | NOT STARTED |
| Colony growth/decline from trade activity | NOT STARTED |
| Player investment in colony facilities | NOT STARTED |
| HQ location selection and relocation | NOT STARTED |
| Manual/auto play style toggle (per-ship) | NOT STARTED |
| Ship weapons (upgrade category) | NOT STARTED |
| Claim map UI tab | NOT STARTED |
| Single-player leaderboards | NOT STARTED |
| AI rival corporations (single-player opponents) | NOT STARTED |
| Complete save/load system | NOT STARTED |

### Phase 3: Networking & Multiplayer Foundation
Move the simulation to a cloud backend and connect the Godot client to it.

| Feature | Status |
|---|---|
| Named server infrastructure (first: Euterpe) | NOT STARTED |
| Python/PostgreSQL server on Linux | NOT STARTED |
| Local server testing (localhost) before remote deployment | NOT STARTED |
| Player authentication and accounts | NOT STARTED |
| Server-side simulation tick | NOT STARTED (reference doc prepared) |
| Client-server communication (HTTP requests) | NOT STARTED |
| Shared world state with multiple players | NOT STARTED |
| Per-server multiplayer leaderboards | NOT STARTED |
| Server scaling (spin up new servers when crowded) | NOT STARTED |

### Phase 4: Multiplayer Dynamics
Add the systems that make multiplayer competitive and engaging.

| Feature | Status |
|---|---|
| Shared asteroids with contention mechanics | NOT STARTED |
| Fog of war and observation | NOT STARTED |
| Market prices affected by all players' actions | NOT STARTED |
| Information layer with events and misinformation | NOT STARTED |
| Endgame project and contribution system | NOT STARTED |
| Reputation consequences (colony pricing, contracts, hiring) | NOT STARTED |
| Consortia and alliances (formation, coordination, betrayal) | NOT STARTED |
| Consortium leaderboards | NOT STARTED |

### Phase 5: Polish & Depth
Add deferred systems and refine the experience.

| Feature | Status |
|---|---|
| Worker skill progression | NOT STARTED |
| Additional propulsion systems (solar sail, ion, advanced fusion) | NOT STARTED |
| Fuel processor equipment (extract from ice) | NOT STARTED |
| Player fuel depots | NOT STARTED |
| Sensor and stealth upgrades | NOT STARTED |
| Artist-created scene illustrations | NOT STARTED |
| Mobile push notifications | NOT STARTED |
| Epoch transitions | NOT STARTED |
| Colony relationship mechanics | NOT STARTED |
| Offline progression | NOT STARTED |

---

## 16. Performance & Architectural Patterns

### 16.1 Performance Principles

- **Throttle expensive operations** to wall-clock intervals (label overlap 2x/sec, orbitals 2x/sec, dashboard 5x/sec). Not everything runs at full tick rate.
- **Analytical over numerical.** Patched conics (30 lines, 1/sec) replaced forward simulation (180 lines, 30/sec) with 10-100x improvement.
- **Sun-only gravity** for drifting ships. Full N-body is unnecessary for visually correct orbital behavior.
- **Mobile-first.** Target 60fps on mid-range phones. Single-threaded. Profile early.

### 16.2 Industry-Standard Solutions

Prefer proven approaches (KSP-style patched conics, Keplerian elements) over custom implementations. Custom solutions only when standard approaches don't fit.

### 16.3 Technical Debt

- **Label overlap:** O(N²) on all visible labels. Consider spatial partitioning.
- **Subsystem organization:** Ad-hoc addition of simulation systems. Consider formalizing registration and throttling.
- **Save gaps:** Many active state elements not persisted (see Section 14.6).

### 16.4 Collaborative Pattern

User describes WHAT/WHY; assistant determines HOW. Proactively suggest industry-standard alternatives rather than only optimizing the proposed approach.

---

## 17. Open Design Questions

The following questions are identified but not yet resolved:

- **AI lore:** In-universe explanation for human-driven corporate management rather than AI automation?
- **Combat resolution:** Equipment, crew, personalities, or combination? Any player input, or fully autonomous?
- **Endgame project variety:** What projects besides an interstellar ship? How does project type affect gameplay?
- **Reward structure:** How many players benefit? Concrete rewards (head start, technology, capital)?
- **Epoch transitions:** What carries over? What resets?
- **Monetization:** Premium purchase, IAP, or other?
- **Player communication:** In-game diplomacy, trade negotiation?
- **Balancing scarcity:** Belt depletion rate → epoch length and combat escalation timing.
- **Scouting:** Pre-mission intelligence detail? Investment in surveys before committing equipment?
- **Misinformation:** Limits and costs of spreading false information?
- **Ship purchasing:** Price points relative to income? Available from start or unlocked?
- **Mining unit scale:** Units per ship, productivity per unit, units for profitable claim?
- **Mining unit generations:** Release frequency, power curve, retrofit capability?
- **Food logistics:** Consumption rate, bulk, resupply interval?
- **Server capacity:** What defines "too crowded"? Player count, contention density, performance?
- **Cross-server:** Shared leaderboards? Any inter-server interaction?
- **Consortium stability:** Kicking balance (too easy = unstable, too hard = freeloaders). Founder + majority vote as starting point, needs playtesting.
- **Consortium monopoly:** Natural limits: internal disagreements at scale, coordination overhead, member poaching, being a giant target.
- **Offline catch-up:** Process all ticks on reconnect, or summary approximation?
- **Save system priority:** Order of addressing unsaved state?
- **Piracy balance:** If raiding is more profitable than mining, economy collapses. Natural checks: armed ships haul less, pirates depend on producers, colonies refuse trade, consortia form against raiders. Needs playtesting.
- **Black market & bombs:** Unexplored. Who sells, what's available, how it differs from legitimate trade, what bombs do, consequences of use. Needs design conversation.
