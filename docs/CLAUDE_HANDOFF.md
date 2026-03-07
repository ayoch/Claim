# Claude Code Handoff Document
**Last Updated:** 2026-03-06
**Current Instance:** Dweezil (Windows)

---

## 🚨 IMMEDIATE CONTEXT (Read This First)

### Latest Work Session: Visual Polish + MP Planet Fix
**Date:** 2026-03-07 (Windows/Dweezil)
**Status:** Complete — committed and pushed

**What was done:**

1. **Asteroid belt density shading** — replaced flat-alpha annulus with 48 Gaussian-density radial bands. `_belt_density(au)` uses broad Gaussian core minus narrow Gaussians at real Kirkwood gap positions (3:1 at 2.50, 5:2 at 2.82, 7:3 at 2.95, 4:3 at 3.17 AU). Each band is a single ring polygon (outer arc forward + inner arc backward = 48 draw calls, not 3072).

2. **Ship marker lerp at high sim speed** — at 100k sim speed, lerp factor was clamping to 1.0 (hard snap), causing jitter. Capped all three lerp factors (position, progress, rotation) at 0.85 per frame. Marker converges in ~3 frames instead of snapping instantly.

3. **Asteroid label zoom-invariance** — labels were scaling with camera zoom. Added `update_zoom(z)` to `asteroid_marker.gd` that counter-scales label and adjusts its position offset. Called from `_process` in `solar_map_view.gd` whenever `_zoom_level` changes — catches all zoom sources (buttons, scroll wheel, trackpad, touch pinch).

4. **Shipyard tab vertical stretch** — cards in "Buy New Ship" popup were stretching to fill full panel height (gap between ship name and description). Added `SIZE_SHRINK_BEGIN` to each card's `PanelContainer` and `HBoxContainer` header to prevent VBox from expanding them beyond natural content height.

5. **Planet orbital motion** — planets were driven by `Time.get_unix_time_from_system()` (real clock, 1 sec/sec), making them effectively frozen regardless of sim speed. Rewrote `EphemerisData` to track `_sim_elapsed` internally. `advance(dt)` increments it (called via `CelestialData.advance_planets(dt)` from `_process_orbits`, which already ran in both LOCAL and SERVER mode). `sync_to_ticks(ticks)` snaps to authoritative time when `total_ticks` jumps (save load, MP server poll). Planets now orbit at sim speed in both SP and MP.

**Files modified:**
- `solar_map/solar_map_view.gd` — belt density bands, `_belt_density()`, `_apply_zoom_to_asteroid_labels()`, `_last_label_zoom` check in `_process`
- `solar_map/asteroid_marker.gd` — `update_zoom()`, `_LABEL_BASE_OFFSET` const
- `solar_map/ship_marker.gd` — lerp cap 0.85 on position, progress, rotation
- `ui/tabs/ship_outfitting_tab.gd` — `SIZE_SHRINK_BEGIN` on card panel + class_header
- `core/data/ephemeris_data.gd` — sim-time driven positions (`_sim_elapsed`, `advance()`, `sync_to_ticks()`)
- `core/data/celestial_data.gd` — `advance_planets()` now calls `ephemeris.advance(dt)`, added `sync_ephemeris_to_ticks()`
- `core/autoloads/game_state.gd` — `sync_ephemeris_to_ticks()` called on save load and MP server poll

---

### Previous Work Session: Docs Update After Refactoring Pull
**Date:** 2026-03-06 (Windows/Dweezil)
**Status:** Complete — docs only, no code changes

**What was done:**
Pulled 70 commits from HK-47's large refactoring session. Updated stale status docs to reflect actual completion state. No code was modified.

**Key finding:** The refactoring is fully complete. All three manager extractions (MissionManager, WorkerManager, MarketManager) and the fleet_market_tab component split are done. MISSION_MANAGER_STATUS.md and REFACTORING_PROGRESS.md were written mid-session and never updated.

---

### Previous Work Session: Code Review Fixes (Bugs #1, #2, #11)
**Date:** 2026-03-06 (Windows/Dweezil)
**Status:** Complete — committed

**What was done:**
Full code review of the project followed by targeted fixes for the highest-priority issues.

**Bug #1 — Crew iterator mutation during ship destruction** (`simulation.gd`)
- `_check_ship_collisions` iterated `ship.crew` while calling `GameState.fire_worker(w)`, which calls `ship.crew.erase(worker)` internally, mutating the array mid-iteration. GDScript skips elements when this happens, leaving some crew unfired and their names unreleased.
- Fix: changed `for w in ship.crew:` to `for w in ship.crew.duplicate():` at the destruction site.

**Bug #2 — Dead throttle accumulators** (`simulation.gd`)
- `_life_support_accumulator`, `_food_consumption_accumulator`, and `_worker_fatigue_accumulator` were declared with matching `INTERVAL` constants but never used. The three functions ran raw every tick, processing tiny fractions of a day/hour on each call.
- Fix: added accumulator-based throttling to all three functions using the same pattern as `_process_payroll`/`_process_worker_leave`. Each function now accumulates `dt`, fires when it reaches its interval, and passes the full accumulated `effective_dt` to the logic. Food and life support now process hourly; worker fatigue processes daily.

**Bug #11 — Best-pilot/best-engineer scan loops duplicated** (`ship.gd` + `simulation.gd`)
- The same "find max skill worker in crew" loop was copy-pasted 8+ times across simulation.gd.
- Fix: added `get_best_pilot() -> Worker`, `get_best_engineer_skill() -> float`, and `get_best_engineer() -> Worker` as methods on `Ship`. Replaced all inline scan loops throughout simulation.gd.

**Cleanup:**
- Deleted `simulation.gd.bak`, `.bak2`, `.bak3` — those belong in git, not the source tree.

**Files modified:**
- `core/models/ship.gd` — 3 new crew-skill helper methods
- `core/autoloads/simulation.gd` — Bug #1, #2, #11 fixes; removed .bak files

---

### Previous Work Session: Ship Bugs + SERVER Mode Audit
**Date:** 2026-03-04 (Windows/Dweezil)
**Status:** Complete — NOT YET COMMITTED

**What was done:**
1. ✅ Ship `is_docked` fix — added `server_docked: bool` to `Ship`, modified `is_docked` getter to return true if `server_docked`. Fixes ships showing max thrust while docked and missing dispatch button.
2. ✅ `apply_server_state` — now sets `ship.server_docked` (was trying to set computed property `is_docked`, had no effect)
3. ✅ Fleet tab `_confirm_dispatch` — now routes through `BackendManager.dispatch_mission` in SERVER mode (was calling LOCAL-only `GameState.start_mission`)
4. ✅ `_add_fleet_stat_row` — fixed broken string comparison; now uses float comparison with format string. Thrust shows "0.00g" for docked ships, upgrades show correctly.
5. ✅ SERVER mode audit + fixes — guarded all LOCAL-only operations:
   - `workers_tab.gd`: fire_worker now routes through `BackendManager.fire_worker` in SERVER mode
   - `main_ui.gd`: custom speed input now routes through `_set_server_speed` in SERVER mode
   - `hq_tab.gd`: autoplay no longer calls `TimeScale.set_speed` in SERVER mode
   - `fleet_tab.gd` + `fleet_market_tab.gd`: fuel/money mutations moved inside LOCAL-only branches; cargo sell buttons blocked in SERVER mode; trade mission dispatch (`_select_colony_trade`) blocked in SERVER mode
   - `market_tab.gd`: `_sell_all_ores`, `_sell_ore`, `_start_trade`, `_start_remote_trade` all blocked in SERVER mode

**Files modified (not yet committed):**
- `core/models/ship.gd` — `server_docked` field + `is_docked` getter
- `core/autoloads/game_state.gd` — `apply_server_state` uses `server_docked`
- `ui/tabs/fleet_tab.gd` — dispatch SERVER routing, fuel guard, colony trade guard, sell guard
- `ui/tabs/fleet_market_tab.gd` — `_add_fleet_stat_row` refactor, fuel guard, colony trade guard, sell guard
- `ui/tabs/workers_tab.gd` — fire button SERVER routing
- `ui/tabs/hq_tab.gd` — autoplay TimeScale guard
- `ui/tabs/market_tab.gd` — sell/trade functions blocked in SERVER mode
- `ui/main_ui.gd` — custom speed input SERVER routing

**Known remaining gap:**
- Mission progress bars in fleet_tab still use local mission object state (stale between server polls). Low priority.
- **Railway action required:** Run `alembic upgrade head` to apply `k7l8m9n0o1p2_add_auto_sell_policy` migration before server will boot cleanly.

---

### Previous Work Session: Title Screen + Docs
**Date:** 2026-03-04 ~17:00–20:29 EST (Windows/Dweezil)
**Status:** Complete

**What was done:**
1. ✅ Pulled HK-47's worker location session, updated CLAUDE_HANDOFF and WORK_LOG
2. ✅ Moved "Play Online" above "New Game" on title screen (`ui/title_screen.tscn`)

**Files modified:**
- `ui/title_screen.tscn` — button reorder
- `docs/CLAUDE_HANDOFF.md`, `docs/WORK_LOG.txt` — session docs

---

### Previous Work Session: Worker Location System
**Date:** 2026-03-04 ~13:49–16:35 EST (Mac/HK-47)
**Status:** Complete — deployed, Railway migration required

**What was done:**
1. ✅ Worker location system — workers tied to specific colonies, can only crew ships at their location
2. ✅ Server-side worker spawning — auto-generates workers per colony on independent timers
3. ✅ Admin spawn endpoint — `/admin/spawn-workers` for manual seeding
4. ✅ New server models — Equipment, Rig, Stockpile, TradeMission + 6 new migrations
5. ✅ Admin web UI — HTML dashboard for server administration
6. ✅ Workers tab SERVER mode — candidates fetched from server, hire via API
7. ✅ Fog-of-war for other players — ghost contact system (lightspeed delay/confidence decay)
8. ✅ `docs/FEATURES.md` created — comprehensive feature list

**Worker Location System Details:**
- `worker.home_colony` (String) is the source of truth for location
- `assign_worker_to_ship()` now returns `Dictionary {success, error}`, validates location match
- Workers tab groups workers and ships by location, crew selection filtered to ship's location
- Fleet tab filters available crew to ship's docked location
- Save/load backward compat: auto-relocates workers to match assigned ship's location
- Server: `location_colony_id` FK added to workers table (`add_worker_location.py` migration)
- Server: `worker_spawning.py` — colony-based spawn timers (Earth: 1/day → Triton: 1/2 weeks)

**⚠️ Railway Action Required:**
- Run `alembic upgrade head` to apply worker location migration
- Seed workers: `POST /admin/spawn-workers` with count=30 (see `SPAWN_WORKERS_INSTRUCTIONS.md`)

**Fog-of-War:**
- Other players' ships now use ghost contact system (same as NPC rivals)
- Lightspeed delay + confidence decay — no more live positions for other players

**Unresolved / Needs Testing:**
- Railway DB migration not yet verified
- End-to-end gameplay at multiple colonies untested
- SERVER mode multiplayer with location system untested
- Old save backward compatibility needs user verification
- See `WORKER_LOCATION_TEST_CHECKLIST.md`

**Files modified:**
- `core/autoloads/game_state.gd` — location validation, backward compat save/load
- `core/autoloads/simulation.gd` — fog-of-war for other players
- `core/data/colony_data.gd` — colony ID→name mapping
- `core/models/worker.gd` — minor updates
- `ui/tabs/workers_tab.gd` — location-grouped UI, SERVER mode candidates/hire
- `ui/tabs/fleet_market_tab.gd` — crew filtered by ship location
- `server/server/models/worker.py` — location_colony_id field
- `server/server/simulation/tick.py` — worker spawning integrated
- `server/server/simulation/worker_spawning.py` (NEW)
- `server/server/routers/admin.py` — spawn-workers endpoint
- `server/server/routers/admin_ui.py` (NEW) — HTML admin dashboard
- `server/server/models/` — equipment.py, rig.py, stockpile.py, trade_mission.py (NEW)
- `server/alembic/versions/` — 6 new migrations
- `server/templates/` — admin HTML templates (NEW)
- `docs/FEATURES.md` (NEW)

---

### Previous Work Session: Market Tab UI Clipping Fix
**Date:** 2026-03-04 (Windows/Dweezil)
**Status:** Complete

**What was done:**
1. ✅ Reviewed all files in `docs/` folder
2. ✅ Fixed market tab clipping on left/right after 30% global font size increase

**Market Tab Fix:**
- **Symptom:** Market tab content clipped on left and right edges (all other tabs already fixed)
- **Root cause 1 (structure):** `ScrollContainer` was direct child of `MarginContainer` instead of nested inside an outer `VBoxContainer` — didn't match other tabs' layout pattern
- **Root cause 2 (content):** "Install on X", "Commission on X" buttons were placed in `HBoxContainer`s, one per docked ship. With multiple ships + larger font, combined minimum width exceeded window width, overflowing the layout
- **Fix 1:** `market_tab.tscn` — added outer `VBoxContainer` as direct child of `MarginContainer`; `ScrollContainer` nested inside with `size_flags_vertical = 3`. Now matches `fleet_market_tab`, `ship_outfitting_tab`, `workers_tab`, `fleet_tab` pattern exactly
- **Fix 2:** `market_tab.gd` — changed three multi-ship button rows from `HBoxContainer` to `VBoxContainer`: equipment install buttons, upgrade install buttons, dry dock commission buttons. Ship buttons now stack vertically, eliminating horizontal overflow

**Files modified:**
- `ui/tabs/market_tab.tscn` — structural layout fix
- `ui/tabs/market_tab.gd` — three multi-button rows HBox → VBox

---

### Previous Work Session: Server Integration Fixes & UX Polish
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
