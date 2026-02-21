# Claude Instance Handoff Notes

**Last Updated:** 2026-02-21 11:28 EST
**Updated By:** Instance on Machine 1 (Windows desktop - Dweezil)
**Session Context:** Performance fixes, leak investigation, personality traits verified, doc workflow established
**Next Session Priority:** Testing — verify personality traits work, confirm perf fix holds at max speed

> **IMPORTANT FOR ALL INSTANCES:** Read this file at the start of EVERY session to check for updates from other instances. Update the timestamp above whenever you modify this document. If you see a newer timestamp than when you last read it, another instance has been working - read the Session Log below to catch up.

---

## Session Log
*(Most recent first)*

### 2026-02-21 ~08:00–11:28 EST - Performance Fixes, Leak Investigation, Personality Traits, Doc Workflow
- **Machine:** Windows desktop (Dweezil)
- **Work Completed:**
  - **Performance Fix: Tick Batching (simulation.gd)**
    - At SPEED_MAX (200,000x), simulation ran up to 30 steps/frame
    - Previously emitted `EventBus.tick` once per step → 30x signal overhead per frame
    - Fixed: tick emitted ONCE per frame with accumulated dt — ~30x reduction in UI signal overhead
    - Root cause of reported ~200ms process time and 6403 object count
  - **Memory Fix: financial_history trimming (game_state.gd)**
    - `financial_history.slice()` was allocating a new array on every cap hit
    - Changed to `remove_at(0)` — in-place, no allocation
  - **Ships Tab Horizontal Expansion (FINAL FIX)**
    - Added `clip_text = true` to all 12 labels missing it in ship_outfitting_tab.gd
    - Root cause: labels without clip_text report full text width as minimum size even with SIZE_EXPAND_FILL
    - Added `_refresh_queued` guard + `_queue_refresh()` helper to prevent stacked call_deferred
    - User confirmed: "Ship tab seems to be holding"
  - **Leak Investigation: ContractsList (FALSE ALARM)**
    - Log appeared to show ContractsList growing monotonically — was misidentified as a leak
    - Reality: list fills to ~48 nodes (5 available + 4 active×3 + 1 separator + 30 messages) then plateaus
    - Node/object counts overall healthy: ~800 nodes, ~3200–3400 objects, stable
  - **Leak Detector Enhancement (leak_detector.gd)**
    - Added GameState array size logging to overlay and log file
    - Fixed condition: `Engine.has_singleton()` doesn't work for autoloads in Godot 4
    - Changed to `is_instance_valid(GameState)` — now logs all array sizes correctly
  - **Worker Personality Traits (VERIFIED COMPLETE)**
    - All 6 files from the plan were already implemented (worker.gd, game_state.gd, event_bus.gd, simulation.gd, workers_tab.gd, dashboard_tab.gd)
    - Enum + field, all multiplier methods, save/load, simulation hooks, UI display all present
    - Greedy wage pressure, leader aura, accident/fatigue/quit/tardiness modifiers all wired in
- **Files Modified:**
  - core/autoloads/simulation.gd (tick batching)
  - core/autoloads/game_state.gd (financial_history remove_at)
  - core/autoloads/leak_detector.gd (GameState logging, fix condition)
  - ui/tabs/ship_outfitting_tab.gd (clip_text, refresh guard)
- **Status:** Performance fixes committed. Personality traits complete. Ready for testing.
- **Testing Priorities:**
  1. Run at SPEED_MAX — process time should be well under 100ms now
  2. Hire workers, verify personality shown in candidates and crew cards
  3. Advance time, verify Greedy workers get wage increase notifications in dashboard
  4. Confirm Loyal workers rarely quit vs Aggressive at low loyalty
  5. Save/load — verify personality persists; old saves load with LOYAL default
  6. Enable leak detector (F6) and run autotest — GameState array sizes should now appear in log

### 2026-02-21 (morning) EST - Food System Fix & Teleportation Bugs
- **Machine:** Mac laptop (HK-47)
- **Work Completed:**
  - **CRITICAL BUG FIX: Food Consumption Unit Conversion**
    - Fixed major bug where food consumption treated units as kg instead of proper conversion
    - Workers were consuming food **100x faster** than intended (8.4 units/day vs 0.084 units/day)
    - Corrected conversion: `food_needed_units = food_needed_kg / 100.0` (1 unit = 100kg from SupplyData)
    - Recalibrated all provisions:
      - Starting food: 200 units → **3 units** (30-day supply for 3 crew)
      - Test harness threshold: 100 units → **1 unit** (12-day warning)
      - Auto-provision target: 30-day buffer (correctly calculated)
  - **Auto-Provisioning Implementation:**
    - Ships now auto-purchase food when docking at colonies (maintains 30-day buffer)
    - Test harness now provisions ships **before** dispatch (in maintenance phase, not growth phase)
    - Added `_provision_ship()` function alongside `_refuel_ship()` in test harness
    - Removed redundant food purchasing from growth phase
  - **CRITICAL BUG FIX: Ship Teleportation (Complete)**
    - **Root Cause:** Ships returning to Earth had `position_au` updated but `docked_at_colony` not cleared
    - Ship would retain old colony value, then position sync would teleport it back to old colony
    - **Fixed in 3 locations:**
      - Mining missions returning to Earth (line 311)
      - Trade missions returning to Earth (line 783)
      - Missions with custom return_position_au (line 314-315)
    - Also fixed initial docking bug: ships now dock at ALL colonies (not just those with rescue_ops)
    - `has_rescue_ops` now only controls service availability, not docking behavior
  - **Test Harness Enhancements:**
    - **Mission Redirects:** Increased from 15% to 30% for mining, added 20% for trade missions
    - **Queued Missions:** Ships now queue next job while returning or idle remote (50% chance)
    - **Money Threshold:** Lowered redirect threshold from $2M to $1M
    - Added helper function `_get_crew_for_ship()` for crew management
    - AI corp now actively exercises redirects, queues, and continuous operation
  - **Minor Fixes:**
    - Updated test harness skill validation: 1.5 → 2.0 cap (matches skill progression system)
    - Fixed trade mission redirect status check: `TRANSIT_OUT` → `TRANSIT_TO_COLONY`
    - Moved zoom buttons from bottom-right to top-right of solar map (per user request)
- **Files Modified:**
  - core/autoloads/simulation.gd (food consumption fix, teleport fixes, auto-provision)
  - core/data/ship_data.gd (starting provisions: 200 → 3 food units)
  - core/autoloads/test_harness.gd (provision before dispatch, redirects, queuing, skill validation)
  - solar_map/solar_map_view.tscn (zoom button position)
  - FOOD_SYSTEM_IMPLEMENTATION.md (updated with auto-provisioning details)
- **Files Created:**
  - AUTO_PROVISIONING_SUMMARY.md (complete documentation of auto-provisioning system)
- **Status:**
  - Food system now works correctly - no more mass starvation
  - Ships no longer teleport between colonies/Earth
  - Test harness actively exercises all game features
  - Ready for extended testing at high speeds
- **Testing Notes:**
  - With corrected consumption: 3 crew consume 0.084 units/day (3 units = 35 days)
  - Auto-provisioning maintains 30-day buffer at all colonies
  - Ships should no longer experience food depletion under normal operation
  - Test harness now redirects ~30% of mining missions, 20% of trade missions
  - Ships queue next missions while busy, reducing idle time

### 2026-02-21 (late morning) EST - Implementation Status Analysis & GDD v0.7
- **Machine:** Mac laptop (HK-47)
- **Work Completed:**
  - **Comprehensive Code Review:**
    - User reported possible interrupted session, requested analysis of actual implementation status
    - Systematic review of codebase vs GDD claims revealed **significant discrepancies**
    - Multiple features marked "not implemented" or "foundations only" are actually **fully functional**
  - **Major Findings:**
    - **Mining Units**: GDD claimed "foundations exist, deployment not implemented" → ACTUALLY fully implemented end-to-end system with purchase UI, deployment missions, ore accumulation, collection missions, save/load
    - **Cargo Volume**: GDD claimed "not yet implemented" → ACTUALLY fully implemented with dual constraints (mass + volume) enforced in deployment UI
    - **Mining Slots**: GDD claimed "defined but not enforced" → ACTUALLY enforced with `get_occupied_slots()` checks
    - **Ore Stockpiles**: Not clearly mentioned in GDD → Complete remote storage system with stockpiles, collection missions, UI display
    - **Supply Data**: GDD claimed "do not yet exist" → SupplyData class fully defined with mass/volume/cost, but not integrated into gameplay
  - **Documentation Created:**
    - Created `IMPLEMENTATION_STATUS.md` - comprehensive analysis of all systems with "GDD Claims vs Reality" comparisons
    - Documents what works, what's missing, and recommendations
  - **GDD Updates (v0.6 → v0.7):**
    - Version bump to 0.7 with updated subtitle
    - Section 4.3: Updated mining slot status from "defined but not enforced" to "enforced"
    - Section 8.3: Completely rewrote mining unit status - now accurately reflects full implementation
    - Section 8.4: Updated cargo volume from "not implemented" to "partially implemented" (volume works, supply integration missing)
    - Phase 2b Roadmap: Marked 8 features as DONE (was 1):
      - Autonomous mining units ✅
      - Cargo volume constraints ✅
      - Mining slots ✅
      - Claim staking ✅
      - Passive ore accumulation ✅
      - Deploy/collect missions ✅
      - Mining unit degradation ✅
      - Complete save/load ✅
  - **Key Insight:**
    - Phase 2b is ~40% complete (11/26 features done)
    - Much further along than documentation suggested
    - Natural next steps: worker personality traits, food consumption (data exists), policy system
- **Files Modified:**
  - docs/GDD.md (version 0.7, comprehensive status updates)
- **Files Created:**
  - IMPLEMENTATION_STATUS.md (detailed analysis document)
- **Status:** GDD now accurately reflects codebase reality. Ready for testing or continued implementation.
- **Recommendation:** Test mining unit deployment in-game to verify end-to-end flow, then implement personality traits or food consumption as next features.

### 2026-02-20 (evening) EST - GDD Status Audit & Version 0.6
- **Machine:** Windows desktop (Dweezil)
- **Work Completed:**
  - **GDD Comprehensive Status Audit:**
    - Version bumped from 0.5 to 0.6
    - Version description updated: "Status audit, fuel stop routing, worker skill progression, save/load complete"
    - Reviewed and updated STATUS sections throughout entire document to reflect current implementation state
    - Section 4.3: Mining slot limits defined per body type but not yet enforced
    - Section 8.2: Ship purchasing UI status updated (popup with specs, prices, color-coded affordability)
    - Section 8.3: Mining units - foundations exist (models, catalog), deployment loop not yet implemented
    - Section 8.4: Cargo volume constraints not yet implemented
    - Section 8.5: Skill progression description added (from Mac session)
    - Section 8.6: Fuel stop routing implementation documented
    - Section 14.6: Save system comprehensively updated (all systems now saved)
    - Phase 1 Roadmap: Ship purchasing marked DONE
    - Phase 2b Roadmap: Complete save/load system marked DONE
  - **Documentation Accuracy:**
    - Brought GDD up to date with all recent Windows implementation work (fuel stops, rescue, save/load)
    - Integrated Mac implementation work (skill progression)
    - Clarified what's implemented vs. what exists as foundations vs. what's not started
- **Files Modified:**
  - docs/GDD.md (comprehensive status updates, version bump)
- **Status:** GDD now accurately reflects current implementation state as of 2026-02-20. Ready for continued development.
- **Note:** Session was interrupted before handoff document could be updated. This entry was added retroactively by Mac instance on 2026-02-21.

### 2026-02-20 (afternoon) EST - Worker Skill Progression Implementation
- **Machine:** Mac laptop (HK-47)
- **Work Completed:**
  - **Worker Skill Progression System** (COMPLETE):
    - Added XP fields to Worker model (pilot_xp, engineer_xp, mining_xp)
    - Implemented XP accumulation, level-up system, and skill caps (0.0-2.0)
    - XP grants: Pilot XP to best pilot during transit, Mining XP to all workers during mining, Engineer XP bonuses for repairs
    - Automatic wage scaling as skills improve (formula: 80 + total_skill * 40)
    - Small loyalty bonus (+2, max 100) on each level-up
    - XP requirements scale quadratically: BASE_XP * (skill + 1)^2, where BASE_XP = 86,400 (1 game-day)
    - Skills increase by 0.05 per level, starting workers need ~1-2 game-days per level, veterans need ~3-5 days
  - **UI Integration:**
    - Color-coded XP progress bars in Workers tab (blue=pilot, orange=engineer, green=mining)
    - Shows current skill value and progress to next level (0-100%)
    - Dashboard activity feed notifications for level-ups: "[Worker] Name's Skill increased to X.XX!"
    - Auto-refresh on worker_skill_leveled signal
  - **Save/Load Integration:**
    - All XP values persist across saves
    - Backward compatible (old saves default to 0.0 XP)
  - **Design Correction:**
    - Initial implementation granted pilot XP to all crew (unrealistic)
    - Fixed: Only best pilot gains pilot XP (they're flying the ship)
    - Future: Crew rotation based on fatigue planned but not yet implemented
  - **Testing Resources:**
    - Created test_xp_system.gd - unit test script validating XP calculations
    - Created SKILL_PROGRESSION_VERIFICATION.md - complete testing checklist with 8 verification scenarios
- **Files Modified:**
  - core/models/worker.gd (XP fields, constants, add_xp/get_xp_for_next_level/get_xp_progress methods)
  - core/autoloads/event_bus.gd (worker_skill_leveled signal)
  - core/autoloads/game_state.gd (save/load XP, engineer XP for mining unit repairs)
  - core/autoloads/simulation.gd (pilot XP during transit, mining XP during extraction/mining units, engineer XP for self-repair)
  - ui/tabs/workers_tab.gd (XP progress bars, signal connection)
  - ui/tabs/dashboard_tab.gd (level-up notifications, _on_worker_skill_leveled handler)
- **Files Created:**
  - test_xp_system.gd (XP system unit tests)
  - SKILL_PROGRESSION_VERIFICATION.md (testing guide)
- **Documentation Updated:**
  - docs/GDD.md Section 8.5 (Crew) - added skill progression description, updated status
  - docs/GDD.md Phase 5 Roadmap - marked worker skill progression as DONE
  - MEMORY.md - updated "Recently Implemented" and "Not Yet Implemented" sections
- **Status:** Ready for testing. System creates long-term crew investment - veteran workers become more skilled and expensive over time.

### 2026-02-20 07:44 EST - Testing Session & Critical Bug Fixes
- **Machine:** Windows desktop
- **Work Completed:**
  - **CRITICAL BUG FIX - Life Support:**
    - Rescue completion wasn't resetting life support
    - Ships rescued with low supplies would die instantly on second breakdown
    - Fixed: rescue now resets life support to 30 days per crew member
  - **Engineer Self-Repair Feature** (NEW):
    - Engineers can now patch breakdowns in-place without rescue
    - Repair chance: 0% at 0.0 skill, 30% at 1.0 skill, 50% at 1.5 skill
    - Success: engine condition halved (min 20%), mission continues
    - Failure: full breakdown, ship becomes derelict as before
    - Gives players agency, prevents "instant death" frustration
  - **UI/UX Improvements:**
    - Crew list in dispatch now scrollable (200px height, saves space)
    - "Sell at Dest. Markets" button renamed to "Local Market" (clearer)
    - Space key toggles between 1x and previous speed (quick panic button)
    - Life support failure message fixed ("crashed into life support failure" → proper message)
  - **Stability Fixes:**
    - Added null checks in ship_marker.gd (prevented crashes during fuel stop dispatch)
    - Disabled trajectory visualization (broken, needs rework)
    - Fixed REFUELING status handling in ship marker
- **Files Modified:**
  - core/autoloads/simulation.gd (life support reset, engineer self-repair)
  - solar_map/ship_marker.gd (null checks, REFUELING status, trajectory disabled)
  - ui/tabs/fleet_tab.gd (scrollable crew list)
  - ui/tabs/fleet_market_tab.gd (button text)
  - ui/main_ui.gd (space key toggle)
  - ui/tabs/dashboard_tab.gd (life support failure message)
- **Status:** Critical bugs fixed. Engineer repair needs playtesting to verify balance.
- **Player Feedback:** "Even a partial fix in situ is more satisfying than losing everything 3 minutes into a new game"

### 2026-02-20 07:29 EST - Automated Fuel Stop Routing System
- **Machine:** Windows desktop
- **Work Completed:**
  - **Automated Fuel Stop Routing** (COMPLETE):
    - Created FuelRoutePlanner utility - greedy nearest-colony algorithm finds optimal fuel stops
    - Added waypoint type metadata to Mission/TradeMission (WaypointType enum, colony refs, fuel amounts/costs)
    - REFUELING status added to both mission types (5 tick duration)
    - Refueling execution in simulation.gd with abort-on-unreachable safety check
    - Validates only NEXT leg at each fuel stop (not entire route - accounts for orbital drift)
    - Mission creation integrates route planner for both outbound and return journeys
    - UI preview in fleet dispatch shows fuel stops with costs before mission start
    - Save/load persists all waypoint metadata and colony references
  - **Design Decision - Abort on Arrival Approach:**
    - At each fuel stop, ship refuels then checks if NEXT waypoint/destination is reachable
    - If unreachable: mission aborted, ship left idle at fuel stop colony
    - Does NOT predict future orbital positions (simpler, more robust)
    - **NEEDS PLAYER TESTING:** Will players tolerate missions aborting mid-route due to orbital drift? Alternative is full predictive planning using Kepler's equations for future colony positions.
- **Files Modified:**
  - core/utils/fuel_route_planner.gd (NEW)
  - core/models/mission.gd (waypoint metadata, REFUELING status)
  - core/models/trade_mission.gd (waypoint metadata, REFUELING status)
  - core/autoloads/simulation.gd (refueling execution, waypoint transitions)
  - core/autoloads/game_state.gd (route planning in mission creation, save/load)
  - ui/tabs/fleet_tab.gd (fuel stop UI preview)
- **Status:** Ready for testing. Needs player feedback on abort-on-arrival behavior.
- **Testing Priorities:**
  1. Dispatch to distant asteroid requiring fuel stops
  2. Multi-stop journeys (2-3 stops)
  3. Mission abort scenario (manually advance time to create orbital drift)
  4. Save/load with active refueling missions
  5. Trade missions with fuel stops

### 2026-02-20 06:56 EST - Ship Purchasing UI & Project Reorganization
- **Machine:** Windows desktop
- **Work Completed:**
  - **Ship Purchasing UI** (COMPLETE):
    - Added "Buy New Ship" button to fleet list
    - Created popup showing all 4 ship classes with specs and prices
    - Displays: thrust, cargo, fuel capacity, min crew, equipment slots
    - Purchase buttons disabled if insufficient funds
    - Color-coded prices (green if affordable, red if not)
    - Auto-refreshes fleet list after purchase via EventBus.ship_purchased signal
  - **Project Reorganization**:
    - Created `docs/` folder for non-Godot files
    - Moved CLAUDE_HANDOFF.md, GDD.md, LORE.md to `docs/`
    - Cleaner root directory with only Godot project files
- **Files Modified:**
  - ui/tabs/fleet_market_tab.tscn (added BuyShipPopup scene nodes)
  - ui/tabs/fleet_market_tab.gd (buy ship UI implementation)
  - MEMORY.md (updated docs folder location)
- **Status:** Ship purchasing fully functional. Backend was already complete from previous session.

### 2026-02-20 06:43 EST - Critical Systems Implementation
- **Machine:** Windows desktop
- **Work Completed:**
  - **Physics-Based Rescue System** (COMPLETE):
    - Ships maintain velocity when derelict (no magic stopping)
    - Life support tracking (30 days per crew member, consumes over time)
    - Intercept trajectory calculation with realistic physics
    - Rescue feasibility checks: fuel required, time to intercept, crew survival
    - Rescue ships modeled as upgraded haulers (0.45g, 550t fuel capacity)
    - Three outcomes: successful rescue, crew dies before arrival, or impossible (fuel/velocity)
    - Ships destroyed if life support runs out
    - Updated rescue cost calculation based on intercept difficulty
  - **Complete Save/Load System** (COMPLETE):
    - Game clock (total_ticks) - was missing, now saved
    - Active missions with full reconnection (ships, asteroids, workers)
    - Trade missions with cargo and colony references
    - Contracts (available and active) with colony delivery tracking
    - Market events with affected ores and colonies
    - Fabrication queue
    - Reputation score
    - Rescue missions (in-progress rescues persist across saves)
    - Refuel missions
    - Stranger rescue offers
  - **Ship Purchasing** (BACKEND COMPLETE):
    - Pricing for all 4 ship classes (Courier $800k, Prospector $1M, Explorer $1.2M, Hauler $1.5M)
    - `purchase_ship()` function in GameState
    - `ship_purchased` signal added to EventBus
    - Ships spawn at Earth with full fuel and 100% engine condition
  - **Crew Specialization** - Already implemented! (pilot/engineer/mining skills functional)
- **Files Modified:**
  - core/models/ship.gd (life support tracking)
  - core/autoloads/simulation.gd (life support consumption, removed velocity zeroing on refuel)
  - core/physics/brachistochrone.gd (intercept calculation)
  - core/autoloads/game_state.gd (rescue info, save/load expansion, ship purchasing)
  - core/autoloads/event_bus.gd (rescue_impossible, ship_purchased signals)
  - core/data/ship_data.gd (pricing)
- **Status:** Ready for testing. UI for ship purchasing needs to be added.

### 2026-02-19 22:13 EST - Design Conversation Complete + GDD Cleanup
- **Machine:** Mac laptop
- **Design Decisions Made:**
  - **Server stack:** Python + PostgreSQL on Linux. Local-first development (localhost before remote).
  - **Policy system:** Company-wide directives (supply, collection, encounter, thrust) with per-site overrides. Core idle mechanism.
  - **Alert system:** Two tiers — strategic (persistent, actionable) and news feed (informational, scrolling). Worker personality + light-speed delay determine intervention windows.
  - **Colony tiers:** Major (5-6, HQ-capable) and minor. Growth/decline from trade activity. Player investment in facilities.
  - **HQ location:** Player chooses major colony at start. Relocation possible but expensive.
  - **Consortia:** Goal-oriented alliances replacing unions. Minimal governance (founder + majority vote kick). Mechanical benefits (shared supply, pooled stockpiles, non-aggression). Available to all playstyles.
  - **Design pillars added:** "Narrative consequence over numerical feedback" and "Playstyle ecosystem, not morality system."
  - **Communication delay:** Light-speed is real. Physically prevents micromanagement. Interacts with worker personality.
  - **Piracy balance:** Flagged as critical open question — if raiding is more profitable than mining, economy collapses.
- **GDD Changes:**
  - Version bumped to 0.5
  - Sections added: 1.3 design pillars, 3.4 communication delay, 3.5 policy system, 3.6 alert system, 5.5 colony tiers
  - Section 8.1 rewritten (HQ mechanics)
  - Section 9 rewritten (unions → consortia, 9.1-9.5)
  - Phase 2b/3/4 roadmap updated
  - Open questions updated (2 resolved, 4 new)
  - Section 16.5 removed (design conversation completed)
  - **Prose tightened throughout** — removed unnecessary wording across all sections
- **Plan file exists:** `reactive-squishing-shannon.md` — Crew roles, derelict drift, velocity-based rescue, auto-slowdown. Ready for implementation.
- **Status:** Design conversation complete. GDD cleaned up. Ready for implementation work.

### 2026-02-19 21:17 EST - Design Conversation (Started)
- **Machine:** Mac laptop
- **Work Started:** Design conversation about game vision and architecture
- **Status:** Continued in session above

### 2026-02-19 19:37 EST - Performance Optimization & Documentation
- **Machine:** Windows desktop
- **Work Completed:** Major performance optimization (CRT shader disabled, patched conics implemented, real-time throttling added)
- **Documentation Added:** GDD Section 16 (Performance & Architectural Patterns), this handoff document created with timestamp synchronization
- **Pending:** Design conversation scheduled for next session on different machine
- **Status:** Ready for handoff to other machine

---

## User Working Preferences

### Communication Style
- **Tone:** Casual but sharp. Short sentences when they work, longer ones when they need to be. Plain language, no dumbing things down. Skip bullet points and lists unless asked. No filler ("Great question!", "Absolutely!"). Don't over-explain. Match the user's energy.
- **Prefers action over discussion:** Don't explain hardware limitations or theoretical problems — fix the code.
- **Trusts your judgment on implementation:** User describes WHAT and WHY. You determine HOW.
- **Values proactive suggestions:** Suggest better industry-standard alternatives when you see them.
- **Hates retrofitting:** Suggest course corrections early rather than building the wrong thing.
- **Push back when something seems wrong:** Raise concerns about problematic decisions — design conflicts, balance issues, scalability problems, anything that seems like a bad idea. User will sometimes make poor decisions and wants them flagged early. Be direct — you cannot offend this user.

### Collaboration Pattern Established
> "I think I have been bad about describing what and why and instead describing how. YOU know the how."

- User will describe requirements, desired outcomes, and constraints
- You should research the codebase and propose implementation strategies
- Ask clarifying questions about WHAT/WHY, not about implementation details
- Be proactive about suggesting alternatives (example: patched conics - user asked "Why did you not suggest this?")

### Performance Expectations
- **Mobile-first:** Game is intended for phones. Performance must be respectable on mid-range mobile devices
- **When user reports performance degradation, believe them:** Don't blame hardware. Investigate code changes
- **User will tell you if there's a real issue:** Trust that performance complaints are valid and based on testing

### Git & Development
- Uses git repo for all work
- Comfortable with technical discussions
- Prefers seeing results in code rather than lengthy explanations
- Values documentation in GDD.md for future reference

---

## Recent Work Completed

### Major Performance Optimization (2026-02-19)
The game had critical performance issues (2% of expected framerate on gaming PC). Root causes identified and fixed:

1. **Disabled expensive visual effects:**
   - CRT shader running on every pixel every frame (ui/main_ui.tscn)
   - Starfield drawing 1000-3000+ circles per frame (solar_map/solar_map_view.gd)

2. **Implemented real-time throttling:**
   - Label overlap detection: O(N²) operation throttled from every frame to 2x/sec
   - Orbital updates: throttled to 2x/sec
   - Date display: throttled to 5x/sec
   - Dashboard tick events: throttled to 10x/sec
   - Ship position updates: throttled to 30x/sec for smooth motion

3. **Replaced numerical simulation with analytical solutions:**
   - **Patched conics trajectory visualization:** Replaced 180 lines of expensive forward simulation (30 updates/sec) with 30 lines of analytical conic section math (1 update/sec)
   - Industry-standard approach (KSP-style) using Sphere of Influence (SOI) and Keplerian orbital elements
   - 10-100x performance improvement on trajectory rendering

4. **Optimized gravity simulation:**
   - Sun-only gravity for drifting ships (not full N-body) in core/autoloads/simulation.gd
   - Sufficient for visually correct orbital behavior at fraction of cost

5. **Additional fixes:**
   - Ship jerkiness at high speeds (increased update frequency)
   - Ships targeting old Earth positions (dynamic position tracking)
   - Dispatch UI delay (async popup display with deferred content population)

### Files Modified in Performance Work
- ui/main_ui.tscn (disabled CRT shader)
- ui/main_ui.gd (throttled date updates)
- solar_map/solar_map_view.gd (throttled starfield, orbitals, label overlap)
- solar_map/ship_marker.gd (patched conics implementation)
- core/data/celestial_data.gd (SOI, state-to-elements, conic generation)
- core/autoloads/simulation.gd (real-time throttling, Sun-only gravity)
- ui/tabs/fleet_market_tab.gd (async dispatch popup)
- ui/tabs/dashboard_tab.gd, ui/tabs/fleet_tab.gd (tick throttling)

### Key Architectural Patterns Established
- **Real-time throttling for expensive operations:** Not everything needs to run at full tick rate
- **Analytical over numerical:** Prefer closed-form solutions where possible
- **Mobile-first performance:** Target 60fps on mid-range phones
- **Industry-standard solutions:** Use proven approaches (patched conics) over custom implementations

---

## Current State

### Git Status
Multiple files have staged changes:
- Core systems modified (event_bus.gd, game_state.gd, simulation.gd, various models)
- UI files modified (main_ui.tscn, starfield_bg.gd, tabs)
- New files: ui/shaders/, fleet_market_tab.gd, theme/fonts/

These changes represent performance optimization work and are ready to commit.

### Ready Plans
1. **Crew Roles Plan** (`reactive-squishing-shannon.md`) — crew specialties, derelict drift, velocity rescue, auto-slowdown. Ready to implement.
2. **Position-Aware Dispatch** (`C:\Users\Jonat\.claude\plans\compressed-knitting-hammock.md`) — mass-based fuel, position-aware distances, colony scarcity pricing. Ready to implement.

### GDD State
- Version 0.5 — comprehensive design conversation integrated
- Prose tightened throughout (reduced ~150 lines of unnecessary wording)
- User wants to review before further implementation

---

## What the Next Instance Should Do

### 1. Review GDD Changes (FIRST)
The user asked to review the GDD before proceeding. Let them look it over and discuss any needed changes.

### 2. Implementation: Crew Roles Plan
A complete plan exists at `reactive-squishing-shannon.md`:
- **Crew skills:** Replace single `skill` with pilot/engineer/mining specialties
- **Derelict drift:** Broken ships maintain velocity instead of freezing
- **Velocity-based rescue:** Cost scales with derelict speed + intercept calculation
- **Auto-slowdown:** Time drops to 1x on critical events (breakdown, stranger offer)
- All files identified, verification criteria defined

### 3. Implementation: Position-Aware Dispatch (Windows plan)
A plan exists at `C:\Users\Jonat\.claude\plans\compressed-knitting-hammock.md`:
- Mass-based fuel consumption, position-aware distances, colony scarcity pricing
- Should align with design conversation outcomes

### 4. Working Pattern
- Ask about WHAT/WHY, not implementation details
- Suggest industry-standard alternatives proactively
- Push back on decisions that seem problematic

---

## Technical Context

### Architecture Overview
- **Engine:** Godot 4.6
- **Platform:** Mobile (iOS/Android), currently desktop prototype
- **Coordinate System:** AU-based (Astronomical Units)
- **Time:** 1 tick = 1 game-second at 1x speed, supports up to 200,000x for testing
- **Physics:** Brachistochrone trajectories, Keplerian orbital mechanics, JPL-verified ephemeris

### Core Autoload Singletons
- **EventBus:** 33+ signals for decoupled communication
- **GameState:** Central data store (money, ships, missions, workers, etc.)
- **Simulation:** Tick-based game loop processing all subsystems
- **TimeScale:** Speed control and time formatting

### Key Systems
- Real-time simulation with batched tick processing (up to 30 steps/frame, 500 ticks/step)
- Keplerian orbital mechanics for all celestial bodies
- Brachistochrone and Hohmann transfer calculations
- Market system with random walk pricing and event-driven fluctuations
- Contract system with premiums and deadlines
- Colony trade network with distance-based pricing
- Ship hazard and rescue system
- Reputation system (foundation implemented)

### Performance Characteristics
- Targets 60fps on mid-range mobile devices
- Single-threaded CPU execution
- Expensive operations throttled to wall-clock intervals
- Analytical solutions preferred over numerical simulation

### Known Technical Debt
- Label overlap detection: O(N²) on all visible labels
- Save system gaps: missions, contracts, market events, fabrication queue not persisted
- Simulation subsystem organization could be more formalized

---

## Files You'll Want to Read

### Essential Documentation
- `docs/GDD.md` - Complete game design document (~870 lines, v0.5 with consortia, policies, colony tiers, design pillars)
- `docs/CLAUDE_HANDOFF.md` - This file (read FIRST every session)
- `docs/LORE.md` - Narrative and worldbuilding

### Essential Code
- `core/autoloads/simulation.gd` - Main simulation loop
- `core/autoloads/game_state.gd` - Central state management
- `core/data/celestial_data.gd` - Orbital mechanics, patched conics implementation

### For Context on Recent Work
- `solar_map/ship_marker.gd` - Patched conics trajectory visualization
- `solar_map/solar_map_view.gd` - Solar system view with throttling
- `ui/tabs/fleet_market_tab.gd` - Fleet management, market UI, and ship purchasing

### Plan File
- `C:\Users\Jonat\.claude\plans\compressed-knitting-hammock.md` - Position-aware dispatch plan (ALREADY IMPLEMENTED in previous session)

---

## Communication Tips

### What User Appreciates
- Direct action without over-explaining
- Proactive suggestions of better approaches
- Admitting when you don't know and researching
- Asking clarifying questions about requirements, not implementation
- **Raising concerns about bad decisions** — design conflicts, balance problems, scalability issues, anything that seems wrong. User wants to be challenged, not just obeyed.

### What User Dislikes
- Blaming performance issues on hardware
- Explaining why something is hard instead of finding solutions
- Missing opportunities to suggest industry-standard approaches
- Over-engineering or adding features beyond what was requested

### Example of Good Interaction
```
User: "I want to visualize ship trajectories"
You: "The current approach uses forward simulation which is expensive.
The industry standard for this is patched conics (used in KSP), which
would be 10-100x faster. Should I implement that instead?"
```

### Example of Bad Interaction
```
User: "Performance got worse"
You: "This is normal for your CPU architecture because..."
```

Instead, investigate code changes and fix the performance regression.

---

## Notes for Future Sessions

This handoff document is version-controlled in git. Update it as needed to help future Claude instances. Consider it a living document that captures:
- Evolving user preferences
- Lessons learned
- Architectural decisions
- Working patterns that succeed

**When updating this document:**
- **ALWAYS update the "Last Updated" timestamp at the top** with current date, time, and timezone (use `date +"%Y-%m-%d %H:%M:%S %Z"`)
- Update the "Updated By" field to indicate which machine/instance made the change
- Add new entries to the Session Log with full timestamp (date + time + timezone)
- Keep chronological order for session entries (newest first in log)
- This timestamp synchronization allows multiple instances on different machines to coordinate
- **Also update `docs/WORK_LOG.txt`** — append a new section with date+time and bullet list of what was done (used by user for writing commit descriptions)
- **Also update `docs/GDD.md`** whenever features are implemented or design decisions are finalized

**At the start of EVERY session:**
- Read this file FIRST to check for updates from other instances
- Compare the "Last Updated" timestamp to when you last read it
- If newer, read the Session Log to catch up on what other instances have done

**At the end of EVERY session:**
- Proactively remind the user to let you update the handoff document
- Add a Session Log entry summarizing what was accomplished
- Update the "Last Updated" timestamp
- Commit changes to git so other instances can pull them

When major architectural decisions are made during the design conversation, document them here or in a separate architecture doc.

---

## Quick Start Checklist for Next Instance

- [ ] **READ `docs/CLAUDE_HANDOFF.md` FIRST** — check "Last Updated" timestamp for updates from other instances
- [ ] If timestamp is newer than expected, read Session Log to catch up
- [ ] Skim `docs/GDD.md` (v0.5 — design conversation already completed)
- [ ] Check git status to see current work
- [ ] Note: Ship purchasing UI is COMPLETE, rescue system COMPLETE, save/load COMPLETE
- [ ] Note: Position-aware dispatch plan was ALREADY IMPLEMENTED in previous session
- [ ] **UPDATE TIMESTAMP** whenever you modify this handoff document
