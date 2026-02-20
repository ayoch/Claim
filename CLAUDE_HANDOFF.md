# Claude Instance Handoff Notes

**Last Updated:** 2026-02-19 19:37:44 EST
**Updated By:** Instance on Machine 1 (Windows desktop)
**Session Context:** Performance optimization work completed, design conversation pending
**Next Session Priority:** Design conversation about game vision before further implementation

> **IMPORTANT FOR ALL INSTANCES:** Read this file at the start of EVERY session to check for updates from other instances. Update the timestamp above whenever you modify this document. If you see a newer timestamp than when you last read it, another instance has been working - read the Session Log below to catch up.

---

## Session Log
*(Most recent first)*

### 2026-02-19 19:37 EST - Performance Optimization & Documentation
- **Machine:** Windows desktop
- **Work Completed:** Major performance optimization (CRT shader disabled, patched conics implemented, real-time throttling added)
- **Documentation Added:** GDD Section 16 (Performance & Architectural Patterns), this handoff document created with timestamp synchronization
- **Pending:** Design conversation scheduled for next session on different machine
- **Status:** Ready for handoff to other machine

---

## User Working Preferences

### Communication Style
- **Prefers action over discussion:** Don't explain hardware limitations or theoretical problems - fix the code
- **Trusts your judgment on implementation:** User describes WHAT they want and WHY they want it. You determine HOW to implement it
- **Values proactive suggestions:** When user proposes a specific implementation approach, consider if there are better industry-standard alternatives and suggest them proactively
- **Hates retrofitting:** User acknowledges they may lead you down suboptimal paths. It's better to suggest course corrections early than to build the wrong thing and retrofit later

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

### Pending Plan (DO NOT START YET)
A plan file exists at `C:\Users\Jonat\.claude\plans\compressed-knitting-hammock.md`:
- **Topic:** Position-Aware Ship Dispatch with Realistic Physics
- **Includes:** Mass-based fuel consumption, position-aware distance calculations, colony scarcity pricing, fuel cost increases
- **Status:** Plan is complete but implementation should WAIT for design conversation

**IMPORTANT:** User wants a design conversation BEFORE continuing with this or any other major implementation work.

### GDD Updates Made
Added Section 16: Performance & Architectural Patterns to GDD.md documenting:
- Performance optimization principles learned
- Preference for industry-standard solutions
- Technical debt identified
- Collaborative pattern (user describes WHAT/WHY, you determine HOW)
- Note about pending architectural discussion

---

## What the Next Instance Should Do

### 1. Design Conversation (FIRST PRIORITY)
User wants a comprehensive conversation about:
- What the game is supposed to do and why
- Feature prioritization and roadmap alignment
- Architectural patterns for new features
- Technical debt remediation strategy

**Output from this conversation should be:**
- Integrated into GDD.md, OR
- Stored in a separate architectural reference document (your choice based on scope)

### 2. After Design Conversation
- Review the pending plan (position-aware dispatch, mass-based fuel)
- Determine if it aligns with the clarified design vision
- Proceed with implementation if aligned, or revise based on new understanding

### 3. Working Pattern
- Ask clarifying questions about requirements and desired outcomes
- Propose implementation strategies based on your research
- Suggest industry-standard approaches proactively
- Be honest when a proposed approach has better alternatives

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
- `GDD.md` - Complete game design document (780 lines, now includes Section 16 on performance patterns)
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

- [ ] **READ THIS FILE FIRST** - Check "Last Updated" timestamp to see if other instances have been working
- [ ] If timestamp is newer than expected, read Session Log to catch up
- [ ] Skim GDD.md (especially Section 16: Performance & Architectural Patterns)
- [ ] Check git status to see current work
- [ ] Initiate design conversation with user about game vision
- [ ] Document results of design conversation (update this file with new timestamp!)
- [ ] Review pending plan in context of design conversation outcomes
- [ ] Proceed with aligned implementation work
- [ ] **UPDATE TIMESTAMP** whenever you modify this handoff document
