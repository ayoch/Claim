# Claim - Feature List

Complete list of implemented and planned features for the asteroid mining tycoon game.

**Legend:**
- ✅ **Implemented** - Feature is complete and functional
- 🚧 **Partial** - Feature is partially implemented or backend-only
- ❌ **Planned** - Feature is designed but not yet implemented

---

## Core Gameplay Systems

### Ships & Fleet Management
- ✅ **Ship Classes** - 4 classes (Courier, Hauler, Prospector, Explorer) with distinct stats
- ✅ **Ship Purchasing** - Buy ships at colonies with cost validation
- ✅ **Ship Positioning** - Real-time orbital position tracking
- ✅ **Ship Partnerships** - Leader/follower pairs, mutual aid (fuel transfer, engineer repair), combined combat
- ✅ **Docking System** - Ships dock at Earth or colonies
- ✅ **Derelict State** - Ships become derelict from fuel/breakdown, require rescue
- ✅ **Engine Condition** - Degrades over time, affects thrust, can break down
- ✅ **Stationed Ships** - Automated operations at assigned colonies
- ✅ **Life Support** - Food, water, oxygen consumption with crew survival mechanics
- ✅ **Cargo Management** - Per-ore-type tracking with capacity limits
- ✅ **Supplies System** - Food, repair parts, fuel management

### Equipment & Upgrades
- ✅ **Equipment Types** - 6 types (mining drill, refinery, scanner, laser, railgun, torpedo launcher)
- ✅ **Weapon Systems** - 7 weapon types with power/range/accuracy/role stats
- ✅ **Durability System** - Equipment degrades, requires maintenance
- ✅ **Ammunition Tracking** - Torpedoes auto-restock at colonies/Earth
- ✅ **Equipment Slots** - Ships have max equipment capacity based on class
- 🚧 **Ship Upgrades** - Dry dock vs modular upgrades (system exists, limited content)
- ✅ **Fuel Processor** - Deploy at water-ice asteroids to produce propellant; requires Solar Array or Fusion Reactor power source; fuel stockpiles collected on ship arrival or via policy dispatch
- ❌ **Technology Research** - Unlock better equipment/ship improvements

### Workers & Crew
- ✅ **Worker Hiring/Firing** - Labor pool system with available workers
- ✅ **Skill System** - Pilot, engineer, mining skills (0.0 to 2.0 range)
- ✅ **XP & Leveling** - Exponential XP curve, skills increase in 0.05 increments
- ✅ **Wage Scaling** - Wages increase with total skill level
- ✅ **Personality Traits** - 5 personalities affecting behavior (Cautious, Greedy, Loyal, Leader, Slacker)
- ✅ **Fatigue System** - Rest requirements, performance degradation
- ✅ **Loyalty System** - Affects performance, can quit if too low
- ✅ **Leave System** - Workers take time off periodically
- ✅ **Crew Specialization** - Best pilot flies, best engineer repairs, all mine
- ✅ **Worker Assignment** - Assign to ships or rigs
- ✅ **Payroll System** - Daily wage deduction (1 game-day intervals)
- ✅ **Worker Location System** - Workers have home colonies; can only board ships docked at their location

---

## Mission Systems

### Mission Types
- ✅ **Mining Missions** - Travel to asteroid, mine ore, return
- ✅ **Trade Missions** - Sell ore at colonies, calculate revenue
- ✅ **Collection Missions** - Pick up ore from rig stockpiles
- ✅ **Deploy Unit Missions** - Deploy rigs to asteroids with crew
- ✅ **Rescue Missions** - Physics-based crew/fuel transfer to derelict ships
- ✅ **Reposition Missions** - Move ship to location and idle
- 🚧 **Survey Missions** - Exploration (system exists, limited implementation)
- 🚧 **Patrol Missions** - Security zones (system exists, limited implementation)
- ✅ **Salvage Missions** - Board and strip derelict ships (rival kills + random spawns); scrap credits, equipment recovery, cargo/fuel transfer; 2hr salvage phase, auto-returns to Earth

### Mission Mechanics
- ✅ **Mission Redirect** - Change destination mid-flight with full dispatch UI
- ✅ **Transit Mode Selection** - Brachistochrone (fast) or Hohmann (economical)
- ✅ **Fuel Routing** - Automatic waypoint calculation for fuel stops
- ✅ **Gravity Assists** - Slingshot routes via planetary flybys
- ✅ **Return Routing** - Auto-return to station or Earth
- ✅ **Multi-leg Journeys** - Waypoint system for complex routes
- ✅ **Mission Abort** - Cancel missions, ships return
- ✅ **Intercept Trajectories** - Predict moving target positions (3-iteration convergence)
- ✅ **Mining Threshold Policy** - Ships return at 50%, 75%, or 95% cargo full
- ✅ **Trajectory Visualization** - Curved paths showing Brachistochrone/Hohmann transfers

---

## Physics & Orbital Mechanics

### Core Physics
- ✅ **Brachistochrone Trajectories** - Constant thrust, fast transit
- ✅ **Hohmann Transfers** - Economical orbits, minimal fuel
- ✅ **Orbital Positions** - 200+ bodies with Keplerian elements
- ✅ **Gravity Assists** - Planet flybys for fuel savings
- ✅ **Fuel Calculations** - Distance-based with cargo mass
- ✅ **Thrust Settings** - Per-ship thrust policy (Conservative/Balanced/Aggressive/Economical)
- ✅ **Velocity Preservation** - Ships maintain velocity during redirects
- ✅ **Collision Detection** - Derelict ships can crash into celestial bodies
- ✅ **Time Scale** - 1 tick = 1 game-second at 1x speed

### Celestial Bodies
- ✅ **200+ Bodies** - Planets, moons, asteroids with real orbital data
- ✅ **Orbital Motion** - Bodies move along elliptical orbits
- ✅ **Position Prediction** - Calculate future positions for intercepts
- ✅ **Asteroid Database** - NEOs, main belt, trojans, centaurs

---

## Economy & Resources

### Mining & Production
- ✅ **12 Ore Types** - Nickel, iron, platinum, gold, water ice, etc.
- ✅ **Asteroid Ore Yields** - Per-asteroid composition and mining rates
- ✅ **Base Mining Rate** - 0.0001 scaling factor (fills cargo in ~1 game-day)
- ✅ **Skill-based Mining** - Crew skill affects mining speed
- ✅ **Equipment Bonuses** - Drills/refineries boost mining
- ✅ **Cargo Thresholds** - Policy-based return triggers
- ✅ **Rigs (AMUs)** - Deployable autonomous mining units
- ✅ **Rig Types** - Basic, Advanced, Refinery (3 types)
- ✅ **Stockpile System** - Ore accumulation at asteroids
- ✅ **Rig Degradation** - Durability and max durability decay over time
- ✅ **Worker Assignment to Rigs** - Crew operate rigs for increased productivity

### Market & Trading
- ✅ **Dynamic Pricing** - Market prices drift over time
- ✅ **Base Ore Prices** - 12 ore types with established values
- ✅ **Local Economies** - 10 trading hubs (Earth + 9 colonies) with independent prices
- ✅ **Supply/Demand** - Inventory levels affect prices (oversupply lowers, shortage raises)
- ✅ **Arbitrage Opportunities** - Price differences between locations
- ✅ **Trade Missions** - Sell ore at colonies for revenue
- ✅ **Arbitrage Trading UI** - Price comparison across colonies with route recommendations
- ❌ **Market Events** - Crashes, booms, shortages that cascade (e.g. Trojan belt depletion → Nickel price spike at all hubs)
- ✅ **Contracts with Deadlines** - Deliver ore to colony by deadline; 20% early bonus if >50% time remains; auto-fulfilled on trade mission return; accept button in HQ

### Economy Management
- ✅ **Money System** - Track credits, expenses, income
- ✅ **Fuel Costs** - Per-unit fuel pricing
- ✅ **Redirect Costs** - 2x fuel cost penalty for mid-flight course changes
- ✅ **Payroll System** - Daily wage deduction for workers
- ✅ **Equipment Costs** - Purchase/sell equipment
- ✅ **Ship Costs** - Purchase ships with class-based pricing
- ✅ **Loan System** - Borrow in $500K–$5M tiers, 9%/yr daily interest (capitalises if unpaid), repay anytime; HQ Loans panel with borrow/repay buttons and debt capacity bar
- ✅ **Insurance** - Company policy: None / Hull (50% payout) / Comprehensive (75% hull + 50% cargo); daily premium deducted from payroll

---

## Colonies & Infrastructure

### Colony System
- ✅ **Colony Locations** - 9 major colonies at planets/moons
- ✅ **Docking at Colonies** - Ships can dock and refuel
- ✅ **Colony Markets** - Independent pricing and inventory per colony
- ✅ **Station Assignment** - Ships can be stationed at colonies
- ✅ **Rescue Operations** - Colonies with rescue capability
- ✅ **Price Multipliers** - Colony-specific price adjustments
- ❌ **Colony Tiers** - Growth levels affecting services/prices
- ❌ **Colony Growth/Decline** - Population and economy changes over time
- ❌ **Colony Construction** - Build new colonies or expand existing
- ❌ **Colony Resources** - Resource needs and production

### Player Infrastructure
- ✅ **Rig Deployment** - Place autonomous mining units at asteroids
- ✅ **Stockpile Management** - Ore storage at remote locations
- ❌ **Fuel Depots** - Player-deployed fuel caches at strategic locations
- ❌ **Outposts** - Small stations for crew rest/resupply

---

## Combat & Conflict

### Combat System
- ✅ **7 Weapon Types** - Mining laser, railgun, pulse laser, beam laser, plasma cannon, missile launcher, torpedo launcher
- ✅ **Combat Phases** - Torpedoes → Lasers → Evasion (multi-phase resolution)
- ✅ **Aggression Stances** - Avoid, Coexist, Confront, Defend
- ✅ **Threat Assessment** - Rival corps evaluate firepower before attacking
- ✅ **Damage Distribution** - Ship damage, crew casualties, equipment degradation
- ✅ **Partnership Combat** - Partnered ships combine firepower, split damage
- ✅ **Mining Laser Bonus** - Mining lasers provide small combat bonus
- ✅ **Ammunition System** - Torpedoes require restocking
- ✅ **Criminal Violations** - Attacking non-aggressive ships triggers penalties
- ✅ **Militia Intervention** - Armed colonies respond to violations
- ✅ **Trading Penalties** - Criminal status affects market access
- ✅ **Docking Bans** - Violators banned from colony docking

### Rival Corporations
- ✅ **NPC Corporations** - AI-controlled competing mining companies
- ✅ **Rival Ships** - NPCs operate ships with same mechanics as player
- ✅ **Rival Strategies** - Different aggression levels and behaviors
- ✅ **Resource Competition** - NPCs mine same asteroids
- ✅ **Rival Partnerships** - NPCs form partnerships for contested targets
- ✅ **NPC Violations** - Rivals face same criminal consequences as player
- ✅ **Combat Encounters** - Rival ships can attack player ships
- ❌ **Piracy** - Set ships to intercept and raid trade routes rather than mine
- ❌ **Diplomacy** - Negotiations, alliances, trade agreements
- ❌ **Alliances** - Formal player groups; optional sub-features: shared ship location visibility, no-attack pacts
- ❌ **Corporate Espionage** - Intel gathering, sabotage

---

## Company Management

### Policy System
- ✅ **6 Company Policies** - Company-wide behavioral settings
  - Thrust Policy (Conservative/Balanced/Aggressive/Economical)
  - Resupply Policy (Proactive/Routine/Minimal/Manual)
  - Pickup Threshold (Aggressive/Routine/Patient/Manual)
  - Encounter Policy (Avoid/Coexist/Confront/Defend)
  - Repair Policy (Always/As Needed/Never)
  - Mining Threshold (50%/75%/95%)
- ✅ **Per-Ship Policy Overrides** - Individual ship settings override company defaults
- ❌ **Equipment Maintenance Policy** - When to repair broken equipment; thrust-linked wear (aggressive thrust = faster degradation)
- ❌ **Trading Policy** - When/how to sell ore
- ❌ **Crew Morale Policy** - Rest vs productivity balance; fatigue/morale affecting skill rolls
- ❌ **Automation Policy** - Ship autonomy level

### Automation & AI
- ✅ **Autoplay Toggle** - Full AI corporation mode
- ✅ **AI Decision Making** - Hiring, purchasing, dispatching, contracts, combat
- ✅ **Policy-based AI** - AI respects company policy settings
- ✅ **Stationed Ship Automation** - Ships execute jobs automatically
- ✅ **Auto-refuel** - Automatic refueling at Earth/colonies
- ✅ **Auto-provision** - Automatic food/supply restocking
- ✅ **Auto-speed Control** - Autoplay sets max speed, manual disables
- ❌ **Custom AI Scripts** - Player-defined automation rules

---

## UI & Visualization

### Main Interface
- ✅ **7 Main Tabs** - Dashboard, Fleet/Market, Workers, Ship Outfitting, Solar Map, MUD (Mining Units), HQ
- ✅ **Dashboard** - Overview, activity log, alerts, key metrics
- ✅ **Fleet Management** - Ship cards with status, missions, crew, equipment
- ✅ **Market Integration** - Fleet + Market combined in single tab
- ✅ **Worker Management** - Hire/fire, skill progression, assignment; grouped by colony location
- ✅ **Ship Outfitting** - Equipment purchase/sale, torpedo restocking
- ✅ **Solar Map** - 2D orbital view with ship/asteroid positions
- ✅ **MUD Tab** - Manage deployed mining units: status, worker assignment, degradation, stockpiles
- ✅ **Dispatch Panel** - Full journey details, transit mode selection, worker assignment
- ✅ **Redirect Panel** - Same as dispatch panel for mid-flight course changes
- ✅ **Search & Sort** - Alphabetical sort and name search for destinations
- ✅ **Expandable Sections** - Collapsible crew/stats/policy sections per ship
- ✅ **Settings Screen** - Graphics, audio, and gameplay settings
- ✅ **Registration Screen** - Separate account creation screen (distinct from login)
- ✅ **Bug Report Dialog** - In-game issue reporting

### Notifications & Automation
- ✅ **Notification Log Panel** - Server persists up to 100 events per player (completions, contracts, breakdowns); fetched and shown in HQ Activity log on login
- ✅ **Mission Queue** - Pre-plan next mission while current is in flight; ship executes on arrival
- ❌ **Autopilot Profiles** - Save/recall fleet strategy (target asteroids, preferred colonies, transit mode)

### Visualization
- ✅ **Orbital Positions** - Real-time 2D positions of all bodies
- ✅ **Ship Trajectories** - Curved paths showing Brachistochrone/Hohmann transfers
- ✅ **Progress Bars** - Mission progress, skill XP, cargo levels
- ✅ **Activity Log** - Real-time events and notifications
- ✅ **Color-coded Status** - Ship states, alerts, warnings
- ✅ **Time Formatting** - Human-readable time (days, hours, minutes)
- ✅ **Search with Auto-pan** - Solar map search auto-centers on celestial objects
- ❌ **3D View** - Optional 3D orbital visualization
- ❌ **Detailed Stats Graphs** - Historical data charts (profit, production, etc.)

### Performance Optimization
- ✅ **Adaptive Orbital Updates** - Frequency based on speed and map visibility (90-99% reduction at low speeds)
- ✅ **Visible Tab Updates Only** - Hidden UI tabs don't refresh (50-70% reduction)
- ✅ **Trajectory Caching** - Paths calculated once and cached
- ✅ **Throttled Position Updates** - 10Hz update rate for smooth visuals
- ✅ **Real-time Throttling** - Event processing throttled for mobile performance

---

## Multiplayer & Server

### Server Backend
- ✅ **FastAPI Server** - RESTful API with async support
- ✅ **PostgreSQL Database** - Persistent state storage
- ✅ **SQLAlchemy ORM** - Database models and queries
- ✅ **Authentication** - JWT-based with password hashing
- ✅ **Rate Limiting** - Per-endpoint request limits
- ✅ **Admin Endpoints** - Admin-only resource creation
- ✅ **Security Audit** - All critical/high vulnerabilities fixed
- ✅ **Password Strength Validation** - Min 12 chars, complexity requirements
- ✅ **Auth Logging** - Failed/successful logins with IP + User-Agent
- ✅ **HTTPS Redirect** - Production security
- ✅ **Request Size Limits** - DoS protection
- ✅ **Exception Handler** - Graceful error responses

### Server Simulation
- ✅ **Tick System** - Server-side simulation at configurable speed (1x–200,000x)
- ✅ **Mission Processing** - Transit, mining, collection, trade missions
- ✅ **Rig Processing** - Ore generation, degradation, worker XP
- ✅ **Market Simulation** - Price drift, supply/demand
- ✅ **Payroll Processing** - Daily wage deduction
- ✅ **Contract Processing** - Contract evaluation and completion
- ✅ **State Sync** - /game/state endpoint returns full player state
- ✅ **World State Persistence** - Total ticks saved to database; game time survives server restarts
- ✅ **Speed Multiplier** - Simulation speed applied correctly server-side (was constant 1s bug, fixed)

### Multiplayer Features
- ✅ **Player Accounts** - Email-based with unique usernames
- ✅ **Cloud Saves** - Server-persisted game state
- ✅ **Shared Economy** - All players in same world
- ✅ **Backend Abstraction Layer** - LOCAL vs SERVER mode routing
- ✅ **Fog-of-War for Other Players** - Other players' ships use ghost contact system (light-speed delay, confidence decay, same as NPC rivals)
- ✅ **Session Restoration** - "Continue as [username]" button; optional (can ignore to log into different account)
- ✅ **Server-side Worker Spawning** - Colonies auto-generate available workers on independent timers
- ✅ **Admin Web UI** - HTML dashboard for server administration (worker spawning, state inspection)
- ✅ **Local Leaderboards** - Net worth ranking (cash + ships + cargo); NPC corps excluded; breakdown tooltip on hover
- ❌ **Player-to-Player Trading** - Direct ore/credit/ship exchanges
- ❌ **Shared Asteroids** - Multiple players mining same locations
- ✅ **PvP Combat** - Proximity-based combat via /game/attack; SSE notification to defender; NPC corps use same system
- ❌ **Colony Ownership** - Claim and develop asteroid colonies, collect tariffs from ships using them
- ❌ **Anti-Cheat Analysis** - Server-side behavioral anomaly detection (impossible transit times, out-of-range mining rates, unexplained credit deltas)
- ❌ **Chat System** - In-game communication
- ❌ **Alliances** - Formal player groups with shared resources

---

## Technical Systems

### Save/Load
- ✅ **Local Save System** - JSON-based save files
- ✅ **Cloud Saves** - Server-persisted state
- ✅ **Backward Compatibility** - Handle old save versions
- ✅ **Auto-save** - Periodic automatic saves
- ✅ **Manual Save** - Player-triggered saves
- ✅ **Name-based References** - Ships/workers referenced by name for save stability

### Time & Speed
- ✅ **Time Scale System** - 1x to 200,000x speed
- ✅ **1 Tick = 1 Game-Second** - At 1x speed
- ✅ **Speed Multiplier** - Accelerates game time
- ✅ **Real Transit Times** - 1 AU ≈ 450,000s ≈ 5.2 days at 0.3g
- ✅ **Time Formatting** - Display in days/hours/minutes
- ✅ **Pause Support** - 0x speed

### Debug & Development
- ✅ **Dev Stats Overlay** - Key 5 toggles debug info
- ✅ **Leak Detector** - Key 6 toggles memory leak tracking
- ✅ **Log-based Debugging** - Write diagnostics to res:// files
- ✅ **Autotest System** - Validates ship state, mission consistency
- ✅ **Console Logging** - Detailed event logging
- ✅ **Bug Report Dialog** - In-game issue reporting with free-text input
- ❌ **Realistic Launch Windows** - Hohmann transfers only valid at certain orbital phases; waiting for window is part of the decision
- ❌ **Replay System** - Record/playback game sessions

---

## Endgame & Long-term Goals

### Major Projects
- ❌ **The Interstellar Ship** - Mega-project endgame goal from GDD
- ❌ **Asteroid Redirect** - Move asteroids to strategic locations
- ❌ **Colony Founding** - Establish new colonies
- ❌ **Technology Milestones** - Major unlocks (FTL, antimatter, etc.)

### Advanced Gameplay
- ❌ **Campaign Mode** - Structured missions and story
- ❌ **Challenges** - Specific goals with rewards
- ❌ **Achievements** - Unlock system for milestones
- ❌ **Prestige System** - Reset with bonuses
- ❌ **Mod Support** - Custom content creation

---

## Summary Statistics

**Total Features Listed:** ~190

**Implemented (✅):** ~153 features (80%)
**Partial (🚧):** ~7 features (4%)
**Planned (❌):** ~30 features (16%)

**Lines of Code:** ~39,000+ total (post-refactoring; exact count pending)
- GDScript: 30,693+ lines (client)
- Python: 6,655+ lines (server)
- Scene files: 1,511+ lines (UI)

**Development Status:** Core gameplay complete, multiplayer-ready, significant expansion potential

---

*Last Updated: 2026-03-07 (planet textures, buy-ship Earth fix, BigInteger money, NPC corps, PvP combat, world reset, multi-world prep, new planned features)*
*This document should be updated as features are completed or new features are designed.*
