# GAME DESIGN DOCUMENT

## Claim
### Asteroid Mining Strategy Game

**Multiplayer Idle Strategy Simulation**
**Platform:** Mobile (iOS / Android)
**Engine:** Godot 4.6
**Version:** 0.4 -- Added Servers, Leaderboards, Unions, Mining Unit Generations
**February 2026**

---

## 1. Vision & Core Concept

### 1.1 Elevator Pitch
Build a deep-space mining empire across the real solar system. Stake claims on asteroids by deploying automated mining units, manage supply lines to keep remote workers fed and equipment running, and haul ore back to market — all while competing with rival corporations (AI or human) for finite resources. The player who contributes the most materials to a collective endgame project earns a reward that carries into the next epoch.

### 1.2 Genre & Tone
The game sits at the intersection of idle/incremental management and hard science fiction simulation. It draws from the economic arbitrage loop of classic games like Dope Wars, the long-horizon strategy of idle tycoon games, and the grounded realism of hard sci-fi. Combat exists but is rare, costly, and desperate — especially early on. The real conflicts are economic, logistical, and informational. Violence becomes more common as scarcity intensifies and territorial disputes escalate.

### 1.3 Design Pillars
- **Grounded realism:** All physics, distances, travel times, and resource quantities are based on real or plausible extrapolated numbers. If a ship accelerates at 0.3g, we calculate real transit times.
- **Low attention, high engagement:** A meaningful play session is five minutes. The game runs while you're away. Decisions matter more than time spent.
- **Incomplete information:** You never know exactly what competitors are doing. Intelligence is partial, sometimes unreliable, and interpreting it is a core skill.
- **Economic depth over action:** This is a numbers game with a beautiful skin, not an action game. Strategy emerges from resource allocation, market timing, and logistics planning.
- **Worker autonomy:** You are the CEO, not the foreman. Workers make their own decisions in the field based on their personalities. You set direction; they execute — sometimes not the way you'd prefer.

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

An in-lore explanation exists for why AI does not run these operations autonomously. The specifics are to be determined, but plausible options include regulatory restrictions following a historical incident, AI limitations in strategic judgment, or economic and legal structures that evolved around human decision-making. This explanation should feel natural to the setting rather than contrived.

### 2.3 The Solar System
The game world is the actual solar system with real distances, real asteroid belt parameters, and real orbital mechanics. Players operate primarily in the asteroid belt, roughly 2 to 3.5 AU from the Sun, with trade routes extending to colonies throughout the inner and outer system. The Kuiper Belt may become relevant in late-game play.

> **STATUS: IMPLEMENTED.** The solar system uses **Keplerian orbital mechanics** based on JPL orbital elements for all 8 planets. Positions are computed from the game's Julian Date using Kepler's equation (Newton-Raphson solver). An automated **Ephemeris Verification** service periodically compares computed positions against JPL Horizons API data to confirm accuracy. 200+ named asteroids are tracked with proper orbital positions. The solar map renders the full system with a procedural starfield background, planet glow effects, ship trajectories, and colony markers.

---

## 3. Core Gameplay Loop

### 3.1 Overview
The player manages a mining corporation that stakes claims on asteroids by deploying automated mining units. Ships are logistics vessels — they haul mining equipment out, deliver food and supplies to remote workers, collect accumulated ore, and bring it to market. The game runs in real time, with the simulation progressing whether the player is actively engaged or not.

The core loop is:
1. **Scout** — Identify promising asteroids based on composition, distance, orbital position, and competition.
2. **Claim** — Dispatch a ship carrying mining units, workers, and supplies. First to deploy units on a body stakes a claim on those mining slots.
3. **Supply** — Keep remote claims running by sending regular supply ships with food and replacement parts. Workers consume food and produce waste.
4. **Collect** — Send ships to retrieve accumulated ore from mining sites.
5. **Sell** — Sell ore on the open market, to colonies, or through contracts. Or contribute materials to the endgame project.
6. **Expand** — Use profits to buy more ships, hire more workers, deploy more mining units, and spread across the belt.

> **STATUS: PARTIALLY IMPLEMENTED.** The mine-haul-sell loop is functional but uses the older model where ships stay at the asteroid during mining. The transition to deployable autonomous mining units, supply logistics, and claim staking is a major upcoming refactor (see Section 8.3).

### 3.2 The Decision Cycle
Every interaction with the game involves reviewing new information and making decisions based on it. The key decisions are:
- **Where to stake claims:** Which asteroids to target, based on composition, distance, fuel cost, available mining slots, and competitive risk.
- **How to equip:** How many mining units to deploy (mass and volume constraints), what ship to use, how much fuel and food to load.
- **How to sustain:** Planning supply routes to keep remote workers fed and equipment maintained.
- **When to sell:** Whether to lock in a contract at a guaranteed price or gamble on the open market.
- **What to sell vs. contribute:** Balancing the need for operating cash against contributing materials to the endgame project.
- **Who to hire and how to pay:** Managing a named crew with varying skills, personalities, and pay expectations. Personality determines how workers handle encounters with rivals in the field.
- **Where to trade:** Which colonies to build relationships with for equipment, fuel, and manufactured goods.
- **Whether to arm:** Mounting weapons on ships costs cargo capacity and money. Using them damages reputation. But sometimes you need to defend what's yours.

### 3.3 Time & The Simulation Tick
**1 tick = 1 game-second** at 1x speed. The simulation advances in real time, scaled by `TimeScale.speed_multiplier`. Ships travel at speeds determined by their drive type and acceleration profile. Deployed mining units produce output continuously. Market prices shift based on supply, demand, and events.

> **STATUS: IMPLEMENTED.** The simulation processes up to 30 batched steps per frame, each up to 500 ticks, allowing speeds up to 200,000x without framerate issues. Transit times are computed from real Brachistochrone physics: 1 AU at 0.3g takes ~450,000 seconds (~5.2 game-days). Speed presets: 1x, 5x, 20x, 50x, 100x, with a maximum of 200,000x for testing.

### 3.4 Communication Delay
Light-speed communication delay is real at solar system distances. An order sent to workers at 2 AU takes ~17 minutes to arrive. At 5 AU, nearly an hour. This physically prevents micromanagement and reinforces worker autonomy — by the time you learn about a situation and respond, your workers have already handled it their way.

> **STATUS: NOT YET IMPLEMENTED.**

---

## 4. Physics & Realism

### 4.1 Core Principle
All distances, travel times, fuel consumption, and resource quantities are derived from real or plausible values. Where the game assumes future technology, it proposes specific performance characteristics and uses those consistently. The numbers should be internally coherent even if the technology is speculative.

> **STATUS: IMPLEMENTED.** All physics use consistent AU-based coordinate system. Planet positions from JPL Keplerian elements. Transit times from Brachistochrone or Hohmann calculations. Fuel consumption scales with distance, mass, and thrust setting.

### 4.2 Propulsion Systems
Ships use one of several drive types, each representing a different cost/speed tradeoff. Travel follows a brachistochrone trajectory: constant acceleration to the midpoint, then flip and decelerate. Transit time is calculated from distance and acceleration rate.

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
Asteroids follow orbits, meaning distances between objects change over time. An asteroid that is 0.5 AU away today might be 2 AU away in six months. This creates a dynamic geography where strategic opportunities shift continuously.

> **STATUS: IMPLEMENTED.** All celestial bodies orbit using Kepler's third law. Planet positions use full Keplerian orbital elements with JPL data. Asteroid and colony orbital positions advance each tick. The solar map reflects all orbital motion in real time. Transit calculations use current orbital positions for accurate distance computation.

### 4.5 Gravity Assist Routes
Ships can use planetary gravity assists (slingshot maneuvers) to reduce fuel consumption at the cost of longer travel time.

> **STATUS: IMPLEMENTED.** The `gravity_assist.gd` system checks all 8 planets as potential flyby waypoints. A slingshot must save at least 15% fuel and add no more than 60% extra travel time. Planet gravitational parameters are calibrated for game units. Multi-leg trajectories are rendered on the solar map as dashed waypoint lines. Company thrust policy (Conservative/Balanced/Aggressive/Economical) determines whether the AI prefers direct or slingshot routes.

---

## 5. Economy & Market

### 5.1 Dual Currency System
The game has two forms of value, and the tension between them drives strategy.

**Money** is earned by selling ore and materials to colonies or on the open market. Money is spent on payroll, fuel, equipment purchases, food, repairs, and other operational costs. Money keeps your corporation alive but does not directly win the game.

**Materials** are what you mine. They can be sold for money or contributed to the endgame project. Materials contributed are what determine who benefits from the project's completion. The central strategic tension is between selling materials to fund operations and contributing them to advance your position.

> **STATUS: PARTIALLY IMPLEMENTED.** Money is fully functional as the primary currency. Material contribution to the endgame project is **not yet implemented** (see Section 7).

### 5.2 The Open Market
Material prices fluctuate based on supply and demand across the solar system. Prices are influenced by events — a construction boom on a Mars colony drives up structural metal prices; a new refining technology announcement crashes rare earth values (which may later recover if the announcement proves false). In multiplayer, the market responds to what all players collectively do: if everyone floods the market with iron, the price drops.

> **STATUS: IMPLEMENTED.** Market prices use a random walk (±3% per tick) with 1% mean reversion toward base prices, clamped between 0.3x and 3.0x base price. Eight scripted event types generate dynamic market conditions: SHORTAGE, SURPLUS, DISASTER, BOOM, RECESSION, DISCOVERY, STRIKE, TECH_ADVANCE. Events apply multipliers ranging from 0.5x to 3.5x on affected ore types. Events can be system-wide or colony-specific. Up to 3 concurrent market events. **Player-driven market effects are not yet implemented** (multiplayer feature).

### 5.3 Contracts
Players can enter into contracts that guarantee a sale price for a specific material over a defined period. Contracts provide income stability but lock you into commitments. If market prices spike above your contract rate, you lose potential profit. If prices crash, you're protected.

> **STATUS: IMPLEMENTED.** Contracts are generated with random ore types, quantities, deadlines, and fictional issuer names (12 companies). Premium pricing: 1.3x-2.0x over spot price. 60% of contracts specify a delivery colony (with 20% bonus). 80% allow partial fulfillment. Up to 5 available contracts and unlimited active contracts. Contracts expire if not accepted, and fail if deadlines pass unfulfilled. Players can fulfill contracts from ship cargo or from stockpile.

### 5.4 Colony Trade
Colonies throughout the solar system have specific needs and specific products. A Mars colony might need water ice and volatiles but can manufacture mining equipment. An orbital station might need structural metals but produces refined fuel. Players trade with colonies, selling them what they need and purchasing what the corporation cannot produce internally.

These relationships have strategic value beyond individual transactions. A player who is a colony's primary supplier may receive priority pricing or early access to manufactured goods.

Colonies also serve as **supply chain hubs** — sources of food, fuel, and replacement parts for remote mining operations. A well-positioned colony relationship can dramatically reduce supply line costs.

> **STATUS: IMPLEMENTED.** 9 colonies with unique price multipliers per ore type:
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
> Colony prices also scale with distance from Earth (+20%/AU scarcity premium) and are modified by active market events. Fuel pricing is location-aware: Earth base $5/unit, colony base $6.50/unit, +$1.20/unit/AU shipping. **Colony relationship mechanics (priority pricing, supplier status) are not yet implemented.**

### 5.5 The Information Layer
Not all market information is reliable. Events, rumors, and announcements enter the game's information feed, and the player must judge what is trustworthy. A report that a competitor has developed a new synthesis process might crash material prices — but the report might be false.

Players may be able to spread misinformation deliberately. Evaluating information and maintaining composure under uncertainty is a core skill.

> **STATUS: NOT YET IMPLEMENTED.** The information/intelligence layer, fog of war on market data, and misinformation mechanics are deferred to Phase 4.

---

## 6. Claims, Competition & Combat

### 6.1 Staking a Claim
The game's title refers to its central mechanic: **claiming mineable bodies**. When a player's ship arrives at an asteroid and deploys mining units, those units occupy mining slots on the body's surface. Each asteroid has a finite number of slots based on its size. Deploying a unit on an open slot stakes a claim to that slot — it belongs to that player's corporation until the unit is removed, destroyed, or abandoned.

Claims are not registered or protected by any authority. They are defended by presence, reputation, and — when necessary — force.

> **STATUS: NOT YET IMPLEMENTED.** Currently mining uses a ship-present model. The claim staking system is a core upcoming feature.

### 6.2 Asteroid Contention
When workers from two corporations arrive at the same asteroid simultaneously, there is no automated resolution. The **workers themselves** decide what happens based on their personalities.

- **Cautious workers** may yield the best slots or leave entirely.
- **Aggressive workers** may attempt to seize occupied slots or intimidate rivals.
- **Loyal workers** follow corporate policy more closely but still exercise judgment.
- **Leaders** influence the behavior of other workers at the same site.

The player/CEO cannot directly intervene in these encounters due to communication delay. They set policy and hire the kind of people who will execute it — but the details play out autonomously.

Possible outcomes when workers from rival corporations encounter each other:
- **Peaceful coexistence** — Both parties claim different slots and mine separately.
- **Intimidation** — One crew's presence (numbers, equipment, personality) causes the other to relocate.
- **Negotiation** — Workers may agree to share a body or establish informal boundaries.
- **Sabotage** — A desperate or aggressive worker might damage rival equipment.
- **Violence** — Rare, especially early game. Injures or kills workers. Severe reputation consequences.

> **STATUS: NOT YET IMPLEMENTED.** Worker personality traits and autonomous decision-making are deferred to Phase 2b.

### 6.3 Combat
Combat is possible but carries heavy costs:

**Early game:** Violence is rare and risky. Weapons are expensive, heavy, and consume cargo space that could carry ore. Most workers won't fight unless cornered. Starting a fight over an asteroid when dozens of others are unclaimed is irrational — and the game's systems should make this feel obviously wasteful.

**Late game:** As the belt is carved up and rich asteroids become scarce, the calculus changes. Corporations with established territories invest in defense. Raiders attempt to seize productive claims. Armed escorts protect ore haulers. Combat becomes a calculated business decision — costly, but sometimes cheaper than finding a new source.

**Consequences of aggression:**
- Workers can be injured or killed (permanent loss, expensive to replace)
- Equipment can be damaged or destroyed
- Reputation damage: colonies may raise prices or refuse trade, workers may demand higher pay or refuse to work for aggressive corporations, other players may form alliances against the aggressor
- In multiplayer, aggression makes you a target

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
In single-player mode, AI-controlled corporations provide competition. They follow all the same rules as the player: they stake claims, deploy mining units, trade with colonies, hire workers, and may contest asteroids. Their behavior should feel like competing with real opponents — they make strategic decisions, react to the player's expansion, and occasionally make mistakes.

In multiplayer, AI corporations may still fill the competitive landscape when player counts are low.

> **STATUS: NOT YET IMPLEMENTED.**

### 6.6 Fog of War
Players have limited visibility into what competitors are doing:
- **Engine flares:** A fusion burn is visible across great distances. You might see that someone is heading toward a body you're interested in.
- **Activity signatures:** Energy output from mining operations on an asteroid might be detectable, indicating that a rock is already being worked, but not by whom or at what scale.
- **Market signals:** A sudden change in supply or pricing can indicate that a competitor has made a major sale or shifted strategy.

Better sensor equipment could extend observation range. Stealth technology could reduce visibility.

> **STATUS: NOT YET IMPLEMENTED.**

---

## 7. The Endgame Project

### 7.1 Overview
Each game epoch has a large-scale collective project that all corporations can contribute materials toward. The nature of this project may vary — it could be an interstellar ship, a massive space station, a terraforming initiative, or something else. The project provides the game's win condition and drives late-game scarcity as materials are diverted from the economy.

### 7.2 Material Requirements
The project requires massive quantities of diverse materials. Its construction phases demand different materials at different times, shifting demand and creating market waves. As materials are diverted to the project, the broader economy tightens — prices rise, scarcity intensifies, and competition for remaining resources heats up.

### 7.3 Rewards
Multiple players can benefit from the project's completion, not just the single top contributor. The reward structure is flexible:
- Top contributors may receive the greatest benefit (e.g., a head start in a new system, exclusive access to advanced technology, bonus starting capital for the next epoch).
- Mid-tier contributors receive lesser but still meaningful rewards.
- Non-contributors are left behind but can continue operating in the current system.

The exact reward structure is an open design question that should be tuned based on playtesting.

### 7.4 Epochs
When the project completes, a new epoch begins. The specifics of epoch transitions — what carries over, what resets, how the new environment differs — are to be designed. The goal is a seasonal structure where each epoch has a clear arc: early expansion, mid-game competition, late-game scarcity and desperation, then transition.

> **STATUS: NOT YET IMPLEMENTED.** The endgame project, contribution system, rewards, and epochs are all deferred to Phase 4-5.

---

## 8. Player Operations & Management

### 8.1 Home Base
Each player operates from a home facility, likely an orbital station. The base serves as the hub for storage, fabrication, crew housing, and ship docking. Its location relative to the belt affects transit times and strategic positioning.

> **STATUS: IMPLICIT.** Earth serves as the implicit home base. Ships dock at Earth, workers are hired there, equipment is purchased/fabricated there. No explicit base facility, upgrade system, or relocation mechanic exists yet.

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

**Fuel has mass.** A fully loaded Prospector (214.8t dry + 118t fuel + 107t cargo) masses 439.8t. An empty one returning with depleted tanks is far lighter and accelerates faster. This means outbound trips (heavy with fuel, cargo, mining units, food) are slower than return trips.

#### Per-Ship Variation
No two ships are identical. Each generated ship varies from its class baseline, reflecting manufacturing tolerances, aftermarket modifications, and wear history:

| Stat | Variation | Justification |
|---|---|---|
| Dry mass | ±5% | Manufacturing tolerances, aftermarket hull work |
| Cargo mass capacity | ±10% | Reinforced floors, removed bulkheads |
| Cargo volume | ±10% | Internal partitioning choices |
| Fuel capacity | ±8% | Additional or reduced tankage |
| Max thrust | ±5% | Engine tuning, wear history |
| Upgrade slots | ±1 slot | Hardpoints welded on or sealed off |

A generated Prospector might come out at 208.1t dry mass, 0.29g thrust, 112t cargo, 136 m³ volume, 122t fuel, 3 upgrade slots — a slightly lighter ship with more cargo room but weaker engines. Every ship has its own personality in the numbers.

> **STATUS: NEEDS UPDATE.** Four ship classes exist in code but use old placeholder values (round numbers, no volume, no variation). Ship data needs to be updated to these specifications. Ship purchasing UI is not yet implemented.

### 8.3 Mining Equipment (Autonomous Mining Units)
Mining is performed by **autonomous mining units** deployed on asteroid surfaces. These are not ship components — they are cargo items with mass and volume that ships transport and deploy. **Mining units require workers to operate and maintain them.** A unit without workers is inert. Workers stationed at a mining site consume food, produce waste, and handle encounters with rival crews autonomously.

Once deployed on an asteroid's mining slot with assigned workers, a unit operates continuously without a ship present. It extracts ore and stockpiles it at the mining site. Ships periodically visit to collect accumulated ore and deliver food, supplies, and replacement parts.

Mining units:
- Have mass and volume (constrain how many a ship can carry)
- Require a mining slot on the asteroid's surface
- **Require assigned workers to operate** (more skilled workers = higher output)
- Operate continuously once deployed and staffed
- Require periodic maintenance (repair parts delivered by supply ships)
- Degrade over time; neglected units eventually go offline
- Can be retrieved, relocated, or abandoned
- Can be upgraded (see Section 8.8)

#### Mining Unit Specifications (Generation 1)

| Unit Type | Mass | Volume | Workers Required | Notes |
|---|---|---|---|---|
| Basic Mining Unit | 7.6t | 11.4 m³ | 1 | Entry-level extraction |
| Advanced Mining Unit | 13.2t | 16.8 m³ | 2 | Higher yield, more maintenance |
| Refinery Unit | 21.5t | 27.3 m³ | 3 | On-site ore processing, highest output |

A Prospector (107t / 143 m³ cargo) can carry roughly 8 Basic Mining Units by volume, or 14 by mass — volume is the constraint. After accounting for food and repair parts for the workers, a typical deployment run might deliver 4-5 units plus supplies.

> **STATUS: NOT YET IMPLEMENTED.** Current system uses ship-mounted equipment that provides mining bonuses while the ship is present. Three equipment types exist (Basic Processor, Advanced Processor, Refinery) but function as ship buffs, not deployable units. This is a fundamental architectural change.

### 8.4 Cargo: Mass and Volume
Ship cargo holds are constrained by both **mass** (tonnes) and **volume** (cubic meters). Some items are heavy but compact (platinum ore, weapons). Others are light but bulky (food supplies, carbon organics, mining units). A ship might fill its volume before reaching its mass limit, or vice versa.

This creates packing optimization decisions: a supply run carrying food and mining units is volume-constrained; an ore hauling run is mass-constrained. Ship upgrades can expand mass capacity, volume capacity, or both.

#### Supply & Weapon Specs

| Item | Mass | Volume | Notes |
|---|---|---|---|
| Food (per worker/day) | 2.8 kg | 0.0044 m³ | Compact rations, water recycled on-site |
| Repair parts (per maintenance cycle) | 0.45t | 0.28 m³ | Filters, lubricants, replacement components |
| Point defense turret | 1.7t | 0.9 m³ | Light, defensive, deters opportunistic raids |
| Laser turret | 4.3t | 2.6 m³ | Moderate offense, effective vs equipment and small ships |
| Kinetic launcher | 11.8t | 7.4 m³ | Heavy, serious threat to large ships |

**Example supply run:** A Prospector resupplying a site with 5 workers for 60 days needs 840 kg of food (0.264 m³) plus repair parts. That's lightweight and compact — leaving most cargo space for collecting stockpiled ore on the return trip. But a deployment run carrying 4 mining units (30.4t / 45.6 m³) plus food plus repair parts fills the hold quickly.

> **STATUS: NOT YET IMPLEMENTED.** Currently only mass (tonnes) is tracked for cargo. Volume constraints, food, and supply items do not yet exist.

### 8.5 Crew
Workers are named individuals with skills, personalities, and pay expectations.

**Skills** determine productivity: better miners extract more ore, better pilots reduce transit time, better engineers maintain equipment more effectively.

**Personalities** determine autonomous behavior in the field:
- **Aggressive** — Will confront rivals, defend claims forcefully, but may start fights unnecessarily.
- **Cautious** — Avoids conflict, may yield claims to avoid confrontation, but keeps workers alive.
- **Loyal** — Follows corporate policy closely, predictable behavior.
- **Greedy** — Motivated by bonuses, may cut corners or take risks for personal gain.
- **Leader** — Influences other workers at the same site. A strong leader shapes the group's response to encounters.

Workers consume **food** and produce **waste**. Food must be carried as cargo on every mission and resupplied at remote mining sites. Waste is jettisoned in space or at mining sites. Food consumption is calculated based on crew size and mission duration. Running out of food is a serious logistics failure.

> **STATUS: PARTIALLY IMPLEMENTED.** Workers have random names (40 first x 40 last), skill levels (0.7-1.5), and daily wages ($80-200). Workers are hired/fired and assigned to missions. Payroll deducts wages every game-day.
>
> **NOT YET IMPLEMENTED:** Personality traits, autonomous decision-making, distinct roles, skill progression, food consumption, waste management.

### 8.6 Fuel & Logistics
Fuel is a critical constraint. Every mission requires fuel calculated from distance, ship mass (including cargo weight), and thrust setting. Fuel has weight that affects acceleration. Running out of fuel in transit is a serious operational failure.

With autonomous mining units deployed across the belt, logistics becomes the core challenge: planning supply routes, managing fuel budgets, balancing cargo space between food, repair parts, and ore, and deciding how often to resupply versus how much food to send each time.

> **STATUS: IMPLEMENTED (basic).** Fuel consumption scales with distance, mass, and thrust. Derelict state on fuel depletion. Location-aware fuel pricing from nearest source.
>
> **NOT YET IMPLEMENTED:** Supply route planning, food as cargo, fuel processor equipment (extracting fuel from water-ice asteroids), player-owned fuel depots.

### 8.7 Ship Upgrades
Ships can be upgraded with modules that improve their capabilities. Each upgrade has mass and occupies an upgrade slot. Upgrade categories:

- **Speed:** Improved engines, thrust nozzles — faster transit, higher fuel consumption.
- **Efficiency:** High-efficiency engines, lightweight hull — less fuel per trip, more net cargo.
- **Capacity:** Extended fuel tanks, expanded cargo bays — carry more per trip.
- **Weapons:** Point defense, laser turrets, kinetic launchers — combat capability at the cost of cargo capacity (see Section 6.4).

> **STATUS: PARTIALLY IMPLEMENTED.** 9 upgrade types across fuel, engine, cargo, and hull categories. **Weapon upgrades are not yet implemented.**

### 8.8 Mining Unit Generations
Mining units are not static technology. New, more capable models are released periodically — not frequently, but as meaningful technological milestones within an epoch. Each generation offers greater extraction rates, better durability, or lower maintenance requirements, but at significantly higher cost.

This creates upgrade decisions:
- **Replace** working units with newer models (expensive up front, better long-term output)
- **Keep** older units running and invest in expansion instead (more claims, lower per-unit output)
- **Mix** generations across sites based on asteroid value (best units on the richest bodies)

Older units continue to function but become increasingly outclassed. A corporation running first-generation units in the late game is at a competitive disadvantage — but they're not worthless.

Mining units can also be upgraded in place (workers install improvement kits delivered by supply ships) rather than fully replaced, offering a cheaper but less effective middle path.

> **STATUS: NOT YET IMPLEMENTED.**

---

## 9. Unions & Alliances

Corporations can form **unions** — formal alliances of mining firms that coordinate operations and present a unified front.

### 9.1 Union Mechanics
- **Formation:** Any corporation can propose a union. Others accept or decline. A union needs at least 2 members.
- **Shared claim visibility:** Union members can see each other's claims, supply status, and ore stockpiles.
- **Non-aggression:** Union members' workers will not initiate conflict with each other at contested sites.
- **Mutual defense:** If a non-union corporation's workers threaten a union member's claim, nearby union workers may respond.
- **Coordinated territory:** Unions can informally divide the belt — "you take that region, we'll take this one" — reducing wasteful competition.
- **Shared supply routes:** Union members may share supply infrastructure, reducing logistics costs for all members.

### 9.2 Union Risks
- **Betrayal:** A union member could defect, seizing shared intelligence about claim locations and supply schedules.
- **Free riding:** A weak member benefits from the union's protection without contributing proportionally.
- **Reputation by association:** If one union member behaves aggressively, it may taint the reputation of the entire union.
- **Power imbalance:** A dominant member may effectively control the union, turning allies into dependents.

### 9.3 Union vs. Union
As the game progresses and territory becomes scarce, conflicts may escalate from individual corporation disputes to union-level territorial wars. These large-scale conflicts are the most dramatic events in the game — and the most costly.

> **STATUS: NOT YET IMPLEMENTED.** Unions are a Phase 4 multiplayer feature but should also be available in single-player against AI corporations.

---

## 10. Leaderboards

### 10.1 Single Player Leaderboards
Track the player's performance against AI corporations:
- **Total Revenue** — Lifetime earnings from ore sales and contracts
- **Claims Held** — Number of active mining operations across the belt
- **Ore Extracted** — Total tonnes mined across all sites
- **Project Contributions** — Materials contributed to the endgame project
- **Net Worth** — Money + estimated value of assets (ships, mining units, stockpiled ore)
- **Reputation** — Current reputation score and tier

### 10.2 Multiplayer Leaderboards
Per-server leaderboards visible to all players on that server:
- Same categories as single player
- Updated in real time
- Historical rankings (how positions changed over time)
- Union leaderboards (aggregate scores for allied corporations)

Leaderboards create strategic information: a player climbing the rankings signals success but also paints a target. A player who stays off the top of the board attracts less attention.

> **STATUS: NOT YET IMPLEMENTED.**

---

## 11. Ship Hazards & Rescue

> **STATUS: IMPLEMENTED.** A full ship hazard and rescue system has been built:

### 11.1 Engine Wear & Breakdowns
Ship engines degrade during transit at a rate of 0.00003 condition per tick (~6% loss per 200,000-tick trip). When condition drops below 50%, breakdown probability increases. Even well-maintained ships have a tiny baseline breakdown chance (manufacturing defects, worker misuse). Typical breakdown frequency: once every 2-30 trips depending on maintenance.

Breakdowns cause engine failure and trigger a derelict state. Fuel depletion also causes derelict status.

### 11.2 Professional Rescue
When a ship becomes derelict, the player can dispatch a rescue mission. The system finds the **nearest rescue-capable source** — Earth or any colony with `has_rescue_ops` (Ceres Station, Ganymede Port, Mars Colony, Lunar Base, Europa Lab). Rescue from the nearest source minimizes transit time and cost.

- **Base rescue cost:** $15,000 (crew, equipment, opportunity cost) + $8,000/AU from source
- **Base refuel cost:** $5,000 + $4,000/AU from source
- Rescued ships are returned to the source colony at 50% engine condition with a 10% chance of losing a worker

### 11.3 Benevolent Stranger Rescue
There is a very rare chance (~1 in 500,000 per tick, ~once per 6 game-days) that a passing ship offers to help a derelict vessel. Ships near populated areas (within 1 AU of Earth or colonies) have 3x the chance; deep space ships have 0.5x.

- Stranger rescue is **immediate** (no transit wait — they're already there)
- Restores fuel to 25%, engine to 40%, preserves cargo, no worker loss risk
- Offers expire after 12 game-hours (43,200 ticks)
- The player can accept free, accept and tip ($2,000-5,000 suggested), or decline
- **Not tipping severely damages reputation** (-10). Tipping improves it (+5)

### 11.4 Breakdown Alerts
Ship breakdowns, rescues, refuels, and stranger offers are logged as color-coded events in the HQ dashboard tab. On desktop, breakdowns trigger a window attention request.

---

## 12. Reputation System

> **STATUS: PARTIALLY IMPLEMENTED.** A foundation reputation system tracks the player's standing.

### 12.1 Score & Tiers
Reputation is a numeric score from -100 to +100, starting at 0. Five tiers:
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
Reputation affects the game world's response to the player:
- **Colony trade pricing:** Notorious corporations pay more, renowned ones get discounts.
- **Contract availability:** Better contracts offered to reputable corporations.
- **Worker hiring:** Skilled workers refuse to work for notorious employers. Aggressive workers gravitate toward shady corporations.
- **Stranger assistance:** Strangers are more likely to help reputable corporations.
- **Multiplayer diplomacy:** Other players can see your reputation tier (not exact score).
- **AI corporation behavior:** AI rivals are more likely to contest claims of notorious corporations and more likely to coexist peacefully with respected ones.

> **STATUS: PARTIALLY IMPLEMENTED.** Score and tiers exist. Stranger rescue modifiers work. **All other consequences are not yet implemented.**

---

## 13. User Interface

### 13.1 Dashboard, Not Game Screen
The interface should feel like a corporate command dashboard, not a traditional game UI. Information density is high. Navigation is fast.

> **STATUS: IMPLEMENTED.** The UI is a tabbed dashboard (720x1280 viewport, portrait orientation, canvas_items stretch).

### 13.2 UI Tabs

**HQ Dashboard** — Event log with color-coded entries (breakdowns, rescues, market events, missions, territorial encounters), reputation display, mission summaries, claim overview.

**Fleet & Market** — Combined fleet management and market view. Ship cards showing status, fuel, engine condition, cargo (mass and volume). Dispatch controls with destination picker, transit mode selection (Brachistochrone/Hohmann), cargo loading (mining units, food, supplies, ore). Market prices and contract management.

**Workers** — Hire/fire workers, view skills, wages, and personality traits. Assign to missions. View worker reports from remote sites.

**Ship Outfitting** — Purchase and install equipment and upgrades (fuel tanks, engines, cargo bays, hull, weapons). View fabrication queue.

**Claims Map** — Overview of all staked claims across the belt: which asteroids have your mining units, how many slots remain, current ore stockpile levels, supply status, and time since last resupply.

**Solar Map** — Interactive 2D map of the solar system. Procedural starfield. Planet and asteroid markers. Colony markers. Ship positions with trajectory lines. Claim indicators on asteroids. Rival activity signatures (fog of war permitting).

**Leaderboards** — Rankings across multiple categories (revenue, claims, ore extracted, project contributions, net worth). In single player, tracks the player against AI corporations. In multiplayer, shows per-server rankings. Union aggregate scores when applicable.

### 13.3 Speed Controls
Speed bar with preset buttons (1x, 5x, 20x, 50x, 100x) plus keyboard shortcuts (1/2/3/0). Maximum speed 200,000x for testing. Game date displayed in the speed bar with configurable format (US/UK/EU/ISO).

### 13.4 Responsive Layout
All UI uses `HFlowContainer` for button rows and `autowrap_mode` on text labels to prevent horizontal overflow on narrow screens.

---

## 14. Technical Architecture

### 14.1 Overview
The game consists of a Godot client (mobile) that will eventually communicate with a cloud backend. The current build runs entirely client-side as a single-player prototype.

### 14.2 Client Architecture (Current)
Four autoload singletons form the backbone:
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
Each multiplayer game world runs on a **named server**. Servers are independent — separate economies, claims, markets, leaderboards, and endgame projects.

- **First server:** Euterpe
- **Scaling:** Additional servers are spun up when an existing server becomes too crowded. The threshold for "too crowded" is an open design question — it may relate to player count, asteroid contention density, or server performance.
- **Server names** are chosen by the operator (not auto-generated).
- Each server runs the full simulation loop authoritatively. Clients send decisions and receive state updates.
- Players cannot transfer between servers (their progress is server-specific).

The recommended starting backend is a Backend-as-a-Service platform such as Firebase or Supabase. A server-side reference document identifies all systems requiring server authority:
- The entire simulation loop (all subsystems)
- All RNG calls (currently unseeded)
- All state mutations (money, resources, positions, fuel, engine condition, claims)
- Market price generation and event creation
- Contract generation and validation
- Worker encounter resolution
- Union membership and coordination
- Leaderboard computation
- Key anti-cheat surfaces: TimeScale, ship positions, money, fuel, engine condition, mining multipliers, claim ownership

### 14.6 Save System
Current save persistence: money, resources, workers, equipment inventory, upgrade inventory, ships (basic properties), settings, date format.

**Not yet saved (gaps):** Active missions, trade missions, contracts, market events, market state, fabrication queue, game clock (total_ticks), reputation score, stranger offers, rescue/refuel missions, asteroid yield mutations, claims, deployed mining units, food/supply state.

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
| Communication delay | NOT STARTED |
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
| Backend setup (Firebase/Supabase) | NOT STARTED |
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
| Unions and alliances (formation, coordination, betrayal) | NOT STARTED |
| Union leaderboards | NOT STARTED |

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

## 16. Open Design Questions

The following questions are identified but not yet resolved:

- **Home base specifics:** What does the player's base look like? What facilities does it contain? Can it be upgraded or relocated?
- **AI lore:** What is the in-universe explanation for human-driven corporate management rather than AI automation?
- **Combat resolution:** How is combat mechanically resolved? Based on equipment, crew numbers, worker personalities, or some combination? Is there any player input, or is it fully autonomous?
- **Endgame project variety:** What projects besides an interstellar ship could serve as epoch goals? How does the project type affect gameplay?
- **Reward structure:** How many players benefit from project completion? What do rewards look like concretely (head start, technology, capital)?
- **Epoch transitions:** What carries over between epochs? What resets? How different is the new environment?
- **Monetization:** Premium purchase, optional in-app purchases, or another model?
- **Player communication:** Can players communicate in-game? Diplomacy, alliances, trade negotiation?
- **Balancing scarcity:** How quickly should the asteroid belt deplete? This determines epoch length and when combat escalation begins.
- **Scouting and surveying:** How detailed is pre-mission intelligence? Can players invest in surveys before committing equipment?
- **Misinformation mechanics:** If players can spread false information, what are the limits and costs?
- **Ship purchasing:** Price points relative to mining income? Available from the start or unlocked?
- **Mining unit scale:** How many units per ship? How productive is one unit? How many units make a profitable claim?
- **Mining unit generations:** How often do new models release? What's the power curve between generations? Can old units be retrofit?
- **Food logistics:** How much food per worker per day? How bulky is it? How long can a remote site last between resupply?
- **Worker autonomy granularity:** How much detail does the player see about autonomous encounters? Full replay, summary report, or just outcomes?
- **Server capacity:** What defines "too crowded" for a server? Player count, asteroid contention, performance metrics?
- **Cross-server features:** Can players on different servers see each other's leaderboards? Any interaction between servers?
- **Union mechanics:** How formal are unions? Can they enforce agreements? What prevents a union from becoming a single dominant entity?
- **Offline catch-up:** How should the simulation handle hours/days of offline time? Process all ticks on reconnect, or use a summary approximation?
- **Save system priority:** What order should unsaved state be addressed in?
