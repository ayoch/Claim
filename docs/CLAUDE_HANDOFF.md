# Claude Code Handoff Document
**Last Updated:** 2026-02-27
**Current Instance:** HK-47 (Mac) → Dweezil (Windows)

---

## 🚨 IMMEDIATE CONTEXT (Read This First)

### Latest Work Session: Local Economy System
**Date:** 2026-02-27 (Mac/HK-47)
**Status:** Backend complete, UI pending
**Handoff Doc:** `HANDOFF_2026-02-27_LOCAL_ECONOMY.md` (read this for full details)

**What was done:**
- Implemented per-colony markets (10 trading hubs: Earth + 9 colonies)
- Each location has independent prices and inventory
- Supply/demand pricing: selling ore increases inventory and lowers prices
- Arbitrage opportunities: price differences between locations create profitable trade routes
- Save/load system updated (backward compatible)

**What's needed next:**
- UI to show price comparisons when selecting trade destinations
- "Find Best Price" button to identify arbitrage opportunities
- Inventory level display at colonies
- Arbitrage opportunity notifications

**Files modified:**
- `core/data/market_state.gd` (major refactor)
- `core/models/colony.gd` (use location-based prices)
- `core/data/market_data.gd` (add location parameter)
- `core/autoloads/simulation.gd` (update inventory on sales)
- `core/autoloads/game_state.gd` (location-based save/load)

---

## 📋 Project Status Overview

### Core Systems (Complete)
✅ Orbital physics (Brachistochrone, Hohmann, gravity assists, intercepts)
✅ Mining missions with fuel routing and waypoint navigation
✅ Trade missions to colonies
✅ Worker hiring, skills (pilot/engineer), XP progression, wage scaling
✅ Ship purchasing, equipment, upgrades, durability, repair
✅ Combat system (7 weapon types, multi-phase resolution, crew casualties)
✅ Criminal violation system (player + NPC corps face consequences)
✅ Rescue/refuel missions (physics-based, worker loss risk)
✅ Stranger rescue offers (tip-based, reputation system)
✅ Contracts system (delivery, partial fulfillment, deadlines)
✅ Market events (GLUT, SHORTAGE, DEMAND_SPIKE, etc.)
✅ **Local economy (NEW):** Per-colony markets with supply/demand pricing
✅ Autoplay/AI corporation (full automation with 6 policy settings)
✅ Save/load system
✅ Ship partnerships (leader/follower, mutual aid, combat synergy)
✅ Stationed ships (automated remote operations)
✅ Deployable mining units (permanent asteroid harvesters)

### UI Systems (Complete)
✅ Dashboard tab (company stats, policies, activity log)
✅ Fleet/Market tab (ship management, mission dispatch, trade)
✅ Workers tab (hiring, firing, crew assignment)
✅ Ship Outfitting tab (equipment, upgrades, stats)
✅ Solar Map tab (2D heliocentric view, ship trajectories, search/sort)
✅ Main menu (new game, load, settings, multiplayer coming soon)
✅ Trajectory visualization (Brachistochrone curves, Hohmann ellipses)
✅ Search & sort UI (alphabetical, name search for destinations)

### Multiplayer Server (In Progress)
✅ FastAPI backend with PostgreSQL
✅ Authentication (JWT, password validation, rate limiting)
✅ Admin endpoints (secured with admin role requirement)
✅ Player management (registration, login, profiles)
✅ Leaderboard system (local + server)
✅ Blog/website system (SQLite, Markdown posts)
✅ Security hardening (HTTPS redirect, request size limits, exception handling)
✅ Event streaming (SSE endpoint for real-time updates)
🔄 Game state synchronization (not yet implemented)
🔄 Server-side simulation (not yet implemented)

### Pending Features
⏳ Arbitrage trading UI (backend done, needs display)
⏳ Torpedo restocking UI (backend done, needs UI)
⏳ Colony growth/decline system
⏳ Fuel processor equipment (extract fuel from water ice)
⏳ Player fuel depots (deploy fuel caches)
⏳ Loan system (borrow money, interest payments)
⏳ Interstellar ship project (endgame goal)

---

## 🔧 Critical System Details

### Time & Economy Calibration
- **1 tick = 1 game-second** at 1x speed
- **Transit times are real seconds:** 1 AU ≈ 450,000s ≈ 5.2 days at 0.3g
- **Mining rate:** BASE_MINING_RATE = 0.0001 (fills cargo in ~1 game-day)
- **Payroll:** 86,400 ticks (1 game-day), workers earn $80-200/day
- **Market drift:** every 90 ticks
- **Survey events:** every 120 ticks, 15% chance
- **Contract generation:** every 150 ticks, 40% chance

### Policy System (6 Active Policies)
1. **Thrust** — Conservative/Balanced/Aggressive/Economical
2. **Resupply** — Proactive/Routine/Minimal/Manual
3. **Pickup Threshold** — Aggressive/Routine/Patient/Manual (stockpile collection)
4. **Encounter** — Avoid/Coexist/Confront/Defend (combat behavior)
5. **Repair** — Always/As Needed/Never (engine repair)
6. **Mining Threshold** — Quick Return (50%)/Standard (75%)/Maximum Haul (95%)

### Autoplay System
- Toggle on Dashboard enables full AI corporation
- AI makes all decisions: hiring, purchasing, dispatching, contracts, combat
- Auto-speed: enabling autoplay sets speed to max, disabling resets to 1x
- Key 5 toggles dev stats overlay (AI runs based on autoplay setting, not Key 5)

### Local Economy System (NEW - 2026-02-27)
- **10 trading hubs:** Earth + 9 colonies (Lunar Base, Mars Colony, Ceres Station, Vesta Refinery, Europa Lab, Ganymede Port, Titan Outpost, Callisto Base, Triton Station)
- **Location-based prices:** Each hub has independent prices (start with ±10% variation)
- **Inventory tracking:** Each hub tracks 300-700 tons per ore type
- **Supply/demand:** Selling ore increases inventory → lowers prices; buying ore decreases inventory → raises prices
- **Price sensitivity:** 2% change per 100 tons deviation from 500t ideal
- **Arbitrage opportunities:** Price differences create profitable trade routes
- **Independent drift:** Each hub's prices drift separately every 90 ticks
- **Backend complete, UI pending:** Need price comparison display, "Find Best Price" button, inventory indicators

---

## 🗂️ Architecture Quick Reference

### Autoloads (Singletons)
- **EventBus:** Signal-only communication hub (no state)
- **GameState:** Authoritative state store (money, resources, ships, workers, missions, market, contracts, etc.)
- **Simulation:** Tick loop driver (processes missions, orbits, breakdowns, rescues, payroll, events)
- **TimeScale:** Controls simulation speed (1x to 200,000x)
- **TestHarness:** AI corporation logic (merged into autoplay system)

### Data Files (Static)
- **CelestialData:** 200+ bodies (planets, moons, asteroids)
- **MarketData:** Base ore prices, equipment catalog
- **MarketState:** **Dynamic prices + inventory per location (NEW)**
- **ShipData:** Ship class templates, names
- **UpgradeCatalog:** Ship upgrade definitions
- **ColonyData:** 9 colonies with price multipliers
- **CompanyPolicy:** Policy rules and AI decision logic

### Models (Mutable State)
- **Ship:** position, fuel, cargo, equipment, crew, upgrades, derelict status, stationed jobs
- **Mission:** mining missions (TRANSIT_OUT → MINING → TRANSIT_BACK)
- **TradeMission:** colony trading (TRANSIT_OUT → SELLING/IDLE_AT_COLONY → TRANSIT_BACK)
- **Worker:** name, pilot_skill, engineer_skill, xp, wage, assigned_mission
- **Equipment:** type, durability, wear_per_tick, mining_bonus/weapon_power
- **ShipUpgrade:** installed upgrades affecting ship stats
- **Colony:** orbital position, price_multipliers, violations, bans
- **Contract:** delivery contracts with deadlines, partial fulfillment
- **MarketEvent:** price-affecting events with duration

---

## 🐛 Known Issues & Debugging

### Ship Teleporting Bug (FIXED 2026-02-24)
- **Symptom:** Ships arrive at one asteroid but leave from a different location
- **Fix:** Clear return_legs and reset return_waypoint_index when manually ordering return
- Only affected manual returns with fuel stop waypoints

### Real-Time Throttle Pattern
- Functions with real-time throttle must accumulate `dt`, not use single step's `dt`
- At 200,000x speed, throttled functions skip most calls
- Fixed in: `_process_contracts`, `_process_survey_events`
- Still uses raw dt (low priority): `_update_ship_positions` (only affects derelict drift)

### Debugging Workflow
- **Log-based debugging preferred:** Write to `res://` log files, read back with Read tool
- **Leak detector:** `core/autoloads/leak_detector.gd` (Key 6), logs to `res://leak_log.txt`
- **All logs to `res://`** (project dir), NOT `user://`, so both instances can access

---

## 📚 Documentation Files

### Primary Docs (Read These)
- **MEMORY.md** (in `.claude/projects/.../memory/`) — Project overview, recently implemented features, gotchas
- **HANDOFF_2026-02-27_LOCAL_ECONOMY.md** — Detailed handoff for today's local economy work
- **GDD.md** — Game design document (core gameplay loops, economy, combat, endgame)
- **LORE.md** — Setting, factions, narrative background
- **WORK_LOG.txt** — Chronological development log

### Technical Docs
- **architecture.md** (in `.claude/projects/.../memory/`) — Full file map, system details
- **models.md** (in `.claude/projects/.../memory/`) — All data models and properties
- **debugging.md** (in `.claude/projects/.../memory/`) — Debugging patterns and workflows
- **server_side_reference.md** (in `.claude/projects/.../memory/`) — Server-side analysis for multiplayer

### Server Docs
- **server/README.md** — Server setup, deployment, API reference
- **server/SECURITY.md** — Security audit results, hardening checklist

---

## 🚀 Typical Development Workflow

### Starting a Session (Dweezil/Windows)
1. Read **MEMORY.md** for project context
2. Read latest **HANDOFF_*.md** for recent work
3. Pull latest changes from git (if working across instances)
4. Check **Not Yet Implemented** section in MEMORY.md for TODOs
5. Ask user what they want to work on

### Making Changes
1. Read affected files first (Edit tool requires prior Read)
2. Test in Godot (run game, verify behavior)
3. Write log files to `res://` for debugging (not `user://`)
4. Update MEMORY.md if adding significant features
5. Create handoff doc if switching instances mid-task

### Ending a Session (Switching to HK-47/Mac)
1. Commit changes to git (if applicable)
2. Update MEMORY.md with "Recently Implemented"
3. Create HANDOFF_*.md with detailed context
4. List pending tasks/TODOs clearly

---

## 💡 Quick Tips for Dweezil

### GDScript Gotchas
- Dictionary access: `dict["key"]` NOT `dict.key`
- Hand-written `.tscn` files: no fake UIDs, no type redeclaration on instances
- `unique_name_in_owner` scoped to owning scene, prefer `$` paths

### Performance
- UI tabs only update when visible (check `visible` flag)
- Orbital position updates adaptive based on speed
- Market drift now 10x more calculations (10 hubs), but still negligible

### Testing the Local Economy
1. Start new game → check if prices differ between Earth and colonies
2. Dispatch trade mission to Triton → sell ore → check if price dropped
3. Save and load → verify prices and inventories persist
4. Load old save → verify global prices convert to location-based

### Next Priority: UI
- Add price comparison in Fleet tab when selecting trade destinations
- Show profit/loss calculation: `(colony_price - earth_price) * cargo_tons`
- Color-code: green for profit, red for loss
- See HANDOFF_2026-02-27_LOCAL_ECONOMY.md for code examples

---

## 📞 Contact & Handoff Notes

### Instance Coordination
- **HK-47 (Mac):** Jonathan's laptop (this instance)
- **Dweezil (Windows):** Jonathan's desktop (next instance)
- Use git to sync code changes between instances
- Use handoff docs to sync context and state

### Communication Protocol
- Always read MEMORY.md at session start
- Always read latest HANDOFF_*.md if switching mid-task
- Update MEMORY.md when completing major features
- Create new HANDOFF_*.md when switching instances mid-work

---

## 🎯 Current Priorities (for Dweezil)

### High Priority (This Week)
1. **Local Economy UI** — Show price comparisons, best price finder, inventory display
2. **Torpedo Restocking UI** — Backend complete, needs UI in Fleet/Outfitting tab
3. **Testing** — Verify local economy works correctly in gameplay

### Medium Priority (Next Week)
4. **Arbitrage Notifications** — Alert when big price gaps exist (>20%)
5. **Expand to 15 Hubs** — Add 5 virtual belt markets for asteroid miners
6. **NPC Market Participation** — Rival corps affect inventories when trading

### Low Priority (Future)
7. **Colony Growth/Decline** — Population changes affect markets
8. **Fuel Processor Equipment** — Extract fuel from water ice
9. **Player Fuel Depots** — Deploy fuel caches at remote locations
10. **Loan System** — Borrow money, manage debt/interest

---

## 🔗 Useful Commands

### Git (if using version control)
```bash
git status                    # Check current state
git add .                     # Stage all changes
git commit -m "message"       # Commit with message
git pull                      # Pull changes from other instance
git push                      # Push changes for other instance
```

### Godot
```bash
godot --editor                # Open Godot editor
godot -d                      # Run with debugger
godot --export-release        # Export release build
```

### Server (FastAPI)
```bash
cd server
uvicorn server.main:app --reload       # Run dev server
alembic revision --autogenerate -m ""  # Create migration
alembic upgrade head                   # Run migrations
```

---

## 📖 Additional Reading

- **Game Design Philosophy:** Read GDD.md for vision and goals
- **Lore & Setting:** Read LORE.md for narrative context
- **Server Architecture:** Read server/README.md for multiplayer plans
- **Security:** Read server/SECURITY.md for hardening checklist

---

**Welcome, Dweezil! The local economy backend is solid. Your mission: make it visible to players through UI.**

**Good luck! 🚀**
