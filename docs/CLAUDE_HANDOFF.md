# Claude Code Handoff Document
**Last Updated:** 2026-03-02
**Current Instance:** HK-47 (Mac) → Dweezil (Windows)

---

## 🚨 IMMEDIATE CONTEXT (Read This First)

### Latest Work Session: Server Integration Fixes & UX Polish
**Date:** 2026-03-02 (Mac/HK-47) - Session 3
**Status:** Complete and pushed to main

**What was done:**
1. ✅ Fixed server simulation speed multiplier (dt calculation bug)
2. ✅ Fixed ship dispatch in SERVER mode (endpoint, asteroid IDs, autoplay routing)
3. ✅ Implemented session restoration with optional "Continue as [username]" button
4. ✅ Separated login and registration screens (email only on registration)
5. ✅ Implemented world state persistence (WorldState model + migration)
6. ✅ Removed green speed indicator from date/time line
7. ✅ Made speed bar visible on all tabs (was HQ-only in SERVER mode)
8. ✅ Fixed account settings dialog crash (custom_minimum_size → min_size)
9. ✅ Removed duplicate account settings button from HQ tab

**Server Speed Fix:**
- **Bug:** At 100,000x speed, server ticked rapidly but only processed 1 game-second per tick
- **Root cause:** `dt = settings.TICK_INTERVAL` was constant instead of multiplied by speed_multiplier
- **Fix:** Changed `server/server/simulation/runner.py:24` to `dt = settings.TICK_INTERVAL * speed_multiplier`
- Ships now leave port correctly at all simulation speeds

**Ship Dispatch Fixes (SERVER mode):**
- **Bug 1:** Wrong endpoint - client called `/api/missions`, server has `/game/dispatch`
- **Fix:** Changed `core/backend/server_backend.gd:236` to use correct endpoint
- **Bug 2:** Asteroid ID mismatch - server expects DB IDs (start at 1), client sent array indices (start at 0)
- **Fix:** Added `+ 1` offset in `game_state.gd::dispatch_mission_any_mode()` when converting indices to IDs
- **Bug 3:** Autoplay called `start_mission()` directly (LOCAL-only), skipped BackendManager in SERVER mode
- **Fix:** Added `server_id` field to Ship model, created `dispatch_mission_any_mode()` for routing
- Modified `simulation.gd::_policy_dispatch_idle_ship()` to use new routing function
- Autoplay now works correctly in SERVER mode

**Session Restoration UX:**
- User feedback: "Imagine you're playing on a tablet you and your wife share, but there's no way to log in to your account because the game forces you to use hers."
- Replaced automatic login with optional "Continue as [username]" button
- Button only shows when valid session token exists
- User can ignore button and login as different account
- File: `ui/login_screen.gd` - added `_check_saved_session()` and `_on_continue_session()`

**Login/Registration Separation:**
- Email no longer required for login (only username + password)
- New registration screen (`ui/register_screen.gd/tscn`) asks for username, email, password
- Login screen's "Register" button navigates to registration screen
- Registration auto-logins after successful account creation
- Cleaner UX - fields match requirements for each flow

**World State Persistence:**
- **Bug:** Server reset to initial date (3/2/2026) on restart, losing all elapsed time
- Created `WorldState` model in `server/server/models/world_state.py`
- Stores `total_ticks` globally (independent of player accounts)
- Migration created: `server/alembic/versions/e1f2g3h4i5j6_add_world_state.py`
- Server loads world state on startup (`runner.py`) and saves every 100 ticks (`tick.py`)
- Game time now persists across server restarts

**UI Polish:**
- Removed green "SERVER: 100,000x" indicator from date/time line (redundant with speed bar)
- Speed bar now visible on all tabs in SERVER mode (was HQ-only)
- Fixed AcceptDialog crash: `custom_minimum_size` property doesn't exist on AcceptDialog
- Changed to `min_size = Vector2i(400, 200)` in `ui/tabs/hq_tab.gd`
- Removed duplicate account settings button from HQ tab (already in main menu settings)

**Commit Hashes:**
- 091f819 - Server simulation speed fix
- 8508f99 - Ship dispatch endpoint fix
- 889a4ac - Asteroid ID offset fix
- ca54817 - Autoplay routing fix with dispatch_mission_any_mode
- e29841f - Session restoration with optional "Continue as" button
- f60d01c - Login/registration screen separation
- eb1ebe0 - World state persistence (WorldState model + migration)
- c8775e2 - UI polish (removed green speed indicator, speed bar on all tabs)
- c286e5e - Account settings dialog crash fix
- c2cf1f1 - Removed duplicate account settings button

**Files modified:**
- `server/server/simulation/runner.py` - Fixed speed multiplier, added world state loading
- `server/server/simulation/tick.py` - Added world state persistence (load/save functions)
- `server/server/models/world_state.py` (NEW) - WorldState model for persistent game time
- `server/alembic/versions/e1f2g3h4i5j6_add_world_state.py` (NEW) - Migration
- `core/backend/server_backend.gd` - Fixed dispatch endpoint
- `core/models/ship.gd` - Added server_id field
- `core/autoloads/game_state.gd` - Added dispatch_mission_any_mode() function, store server_id on sync
- `core/autoloads/simulation.gd` - Modified autoplay to use dispatch_mission_any_mode()
- `ui/login_screen.gd` - Added optional session restoration button
- `ui/register_screen.gd` (NEW) - Dedicated registration screen
- `ui/register_screen.tscn` (NEW) - Registration screen UI
- `ui/main_ui.gd` - Made speed bar visible on all tabs
- `ui/main_ui.tscn` - Removed ServerSpeedDisplay label
- `ui/tabs/hq_tab.gd` - Fixed dialog crash, removed duplicate account settings button

**Server Integration Status:**
- ✅ Ship dispatch working in SERVER mode (manual + autoplay)
- ✅ Simulation speed multiplier applied correctly
- ✅ World state persists across server restarts
- ✅ Session restoration UX polished
- ✅ Login/registration flows separated
- ✅ All UI indicators consistent and non-redundant
- ⏳ Collection missions (skipped in SERVER mode - not yet implemented server-side)
- ⏳ Trade missions (not yet implemented server-side)

---

### Previous Work Session: Multi-Player Shared World
**Date:** 2026-03-02 (Mac/HK-47) - Session 2
**Status:** Complete and deployed to Railway

**What was done:**
1. ✅ Fixed server ship position interpolation during transit
2. ✅ Verified client simulation properly disabled in SERVER mode
3. ✅ Confirmed 2-second server polling is working correctly
4. ✅ Implemented SSE event handlers for real-time updates
5. ✅ Improved SSE delivery frequency (35s → 6s latency)
6. ✅ **Implemented multi-player ship visibility** - all players see each other!

**Ship Position Fix:**
- Server simulation interpolates positions using `mission.destination_x/destination_y`
- These fields were NEVER set during mission creation → ships moved to (0,0)
- Fixed by adding destination coordinates to Mission constructor
- Complete flow now works: server sim → ShipOut → 2s polling → apply_server_state()

**SSE Real-Time Events:**
- Added `apply_worker_skill_event()` to handle skill level-ups from server
- Added `apply_market_update_event()` to handle price changes from server
- Added `market_state_changed` signal to EventBus
- Reduced SSE timeout from 30s to 5s, reconnect delay from 5s to 1s
- Events now delivered every ~6 seconds instead of ~35 seconds

**Multi-Player Ship Visibility:**
- New `/game/world` endpoint returns ALL players' ships with owner info
- ShipOut schema includes `player_id` and `owner_username` fields
- Client polls world state every 2 seconds (alongside personal state)
- GameState separates own ships from `other_players_ships` array
- Solar map renders other players' ships as cyan diamonds
- Labels show "Ship Name (Owner)" for other players
- Real-time updates: see other players move in real-time!

**Server Integration Status:**
- ✅ Client simulation disabled in SERVER mode (simulation.gd:164-165)
- ✅ Ship position updates from server working
- ✅ State polling every 2 seconds (main_ui.gd:26)
- ✅ SSE event broadcasting (worker skills, market prices, payroll)
- ✅ **Multi-player shared world** - all players' ships visible on solar map!
- ⏳ True real-time SSE streaming via StreamPeerTCP (future enhancement)
- ⏳ Player interactions (trading, messaging, combat)

**Files modified:**
- `server/routers/game.py` - Added destination_x/y to mission creation
- `server/routers/events.py` - Reduced SSE timeout to 5 seconds
- `core/autoloads/game_state.gd` - Added SSE event handler methods
- `core/autoloads/event_bus.gd` - Added market_state_changed signal
- `core/backend/server_backend.gd` - Reduced reconnect delay to 1 second

### Previous Session: Server Infrastructure & Auth Polish
**Date:** 2026-03-02 (Mac/HK-47)
**Status:** Complete and deployed to Railway
**Handoff Doc:** `HANDOFF_2026-03-02_SERVER_IMPROVEMENTS.md` (read this for full details)

- Dark River splash screen, session persistence, admin controls, account settings
- See handoff doc for full details

### Earlier Session: Local Economy System
**Date:** 2026-02-27 (Mac/HK-47)
**Status:** Backend complete, UI pending
**Handoff Doc:** `HANDOFF_2026-02-27_LOCAL_ECONOMY.md`
- Per-colony markets with supply/demand pricing
- Arbitrage trading opportunities
- **Still needs:** UI for price comparisons and trade route optimization

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

### Multiplayer Server (Deployed!)
✅ **Railway Deployment** — Server live at `https://claim-production-066b.up.railway.app`
✅ FastAPI backend with PostgreSQL (Railway free tier)
✅ Authentication (JWT, password validation, rate limiting)
✅ Admin endpoints (secured with admin role requirement)
✅ Player management (registration, login, profiles)
✅ Leaderboard system (local + server)
✅ Blog/website system (SQLite, Markdown posts)
✅ Security hardening (HTTPS redirect, request size limits, exception handling)
✅ Event streaming (SSE endpoint for real-time updates)
✅ **Server health indicator** — Title screen shows connection status (green/red light)
✅ **Backend mode switching** — BackendManager toggles LOCAL (file saves) vs SERVER (HTTP)
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

### Stack Overflow in UI Tabs (FIXED 2026-03-02)
- **Symptom:** Game crashes with "Stack overflow (stack size: 1024)" when opening HQ tab
- **Root cause:** Helper function `_lbl()` called itself recursively instead of creating Label
- **Fix:** Changed `var l := _lbl()` to `var l := Label.new()` in 6 tab files
- **Affected files:** hq_tab.gd, workers_tab.gd, market_tab.gd, ship_outfitting_tab.gd, fleet_tab.gd, fleet_market_tab.gd

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
