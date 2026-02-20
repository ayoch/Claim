# Claude Instance Handoff Notes

**Last Updated:** 2026-02-19 22:13:49 EST
**Updated By:** Instance on Machine 2 (Mac laptop)
**Session Context:** Design conversation complete, GDD cleaned up
**Next Session Priority:** Review GDD changes, then begin implementation (crew roles plan is ready)

> **IMPORTANT FOR ALL INSTANCES:** Read this file at the start of EVERY session to check for updates from other instances. Update the timestamp above whenever you modify this document. If you see a newer timestamp than when you last read it, another instance has been working - read the Session Log below to catch up.

---

## Session Log
*(Most recent first)*

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

### Essential
- `GDD.md` - Complete game design document (~870 lines, v0.5 with consortia, policies, colony tiers, design pillars)
- `core/autoloads/simulation.gd` - Main simulation loop
- `core/autoloads/game_state.gd` - Central state management
- `core/data/celestial_data.gd` - Orbital mechanics, patched conics implementation

### For Context on Recent Work
- `solar_map/ship_marker.gd` - Patched conics trajectory visualization
- `solar_map/solar_map_view.gd` - Solar system view with throttling
- `ui/tabs/fleet_market_tab.gd` - Fleet management and market UI

### Plan File
- `C:\Users\Jonat\.claude\plans\compressed-knitting-hammock.md` - Position-aware dispatch plan (wait for design conversation before implementing)

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

- [ ] **READ THIS FILE FIRST** — check "Last Updated" timestamp for updates from other instances
- [ ] If timestamp is newer than expected, read Session Log to catch up
- [ ] Skim GDD.md (v0.5 — design conversation already completed)
- [ ] Check git status to see current work
- [ ] Ask user if they've reviewed GDD and are ready to proceed with implementation
- [ ] Review crew roles plan (`reactive-squishing-shannon.md`) — ready to implement
- [ ] Review position-aware dispatch plan (Windows machine plan file) — ready to implement
- [ ] **UPDATE TIMESTAMP** whenever you modify this handoff document
