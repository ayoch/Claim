# MissionManager Extraction Status

**Last Updated:** 2026-03-06
**Progress:** 6 of 15 functions migrated (40% complete)
**Lines Migrated:** ~306 lines from game_state.gd to mission_manager.gd

---

## ✅ Completed Migrations (6/15)

### 1. complete_mission() ✅
- **Lines:** 30
- **Call Sites Updated:** 1 (simulation.gd line 520)
- **Complexity:** Medium - Cargo handling, ore sales/stockpiling
- **Dependencies:** GameState.money, settings, add_resource(), record_transaction()

### 2. complete_trade_mission() ✅
- **Lines:** 18
- **Call Sites Updated:** 2 (simulation.gd lines 911, 953)
- **Complexity:** Low - Simple cargo return logic
- **Dependencies:** GameState.add_resource()

### 3. calculate_asteroid_intercept() ✅
- **Lines:** 27
- **Call Sites Updated:** 1 (simulation.gd line 1951) + 2 internal stubs
- **Complexity:** Medium - 3-iteration convergence algorithm
- **Dependencies:** None (pure calculation)

### 4. redirect_mission() + _apply_redirect_mission() ✅
- **Lines:** 107
- **Call Sites Updated:** 1 (test_harness.gd line 854)
- **Complexity:** High - Momentum arc physics, trajectory calculation
- **Dependencies:** GameState.queue_ship_order(), money, calculate_asteroid_intercept()

### 5. redirect_trade_mission() + _apply_redirect_trade_mission() ✅
- **Lines:** 98
- **Call Sites Updated:** 2 (fleet_market_tab.gd line 1277, test_harness.gd line 869)
- **Complexity:** High - Momentum arcs, fuel validation
- **Dependencies:** GameState.queue_ship_order(), money

### 6. dispatch_mission_any_mode() ✅
- **Lines:** 26
- **Call Sites Updated:** 1 (simulation.gd line 1651)
- **Complexity:** Low - Mode routing logic
- **Dependencies:** GameState.asteroids, start_mission()

---

## ⏳ Remaining Functions (9/15)

### Dispatch Functions (2)
**Estimated Lines:** ~100 total

1. **dispatch_idle_ship()** + _apply_dispatch_idle_ship()
   - Redirects idle ships to new destinations
   - ~50 lines estimated
   - Depends on: start_mission(), queue_ship_order()

2. **dispatch_idle_ship_trade()** + _apply_dispatch_idle_ship_trade()
   - Redirects idle ships to trade missions
   - ~50 lines estimated
   - Depends on: start_trade_mission(), queue_ship_order()

### Creation Functions (5)
**Estimated Lines:** ~900 total (largest chunk remaining)

3. **start_mission()**
   - Core mission creation logic
   - ~200 lines estimated
   - Most complex remaining function
   - Depends on: calculate_asteroid_intercept(), fuel routing, many GameState properties

4. **start_deploy_mission()**
   - Deploy mining units and workers
   - ~180 lines estimated
   - Similar to start_mission with unit deployment logic

5. **start_collect_mission()**
   - Collect ore from deployed units
   - ~180 lines estimated
   - Similar to start_mission with pickup logic

6. **start_trade_mission()**
   - Create trade missions to colonies
   - ~150 lines estimated
   - Cargo loading, route planning

7. **start_fleet_rescue()**
   - Rescue derelict ships
   - ~140 lines estimated
   - Crew transfer, supply delivery

### Helper Functions (2)
**Estimated Lines:** ~170 total

8. **check_hitchhike_opportunities()**
   - Worker hitchhiking logic
   - ~70 lines estimated
   - Depends on: GameState.workers, hitchhike pool

9. **_start_queued_mission()**
   - Internal helper for queued missions
   - ~100 lines estimated
   - Depends on: start_mission(), start_trade_mission()

---

## Migration Pattern Established ✅

### Dependency Injection
```gdscript
var _game_state: Node = null

func _initialize() -> void:
	_game_state = get_node("/root/GameState")
```

### GameState Access
```gdscript
_game_state.money -= cost
_game_state.add_resource(ore_type, amount)
_game_state.queue_ship_order(ship, label, callable)
```

### Backward Compatibility
```gdscript
## DEPRECATED: Forwarding stub
func old_function(...) -> ReturnType:
	return MissionManager.old_function(...)
```

### Call Site Updates
```gdscript
# Before:
GameState.complete_mission(mission)

# After:
MissionManager.complete_mission(mission)
```

---

## Estimated Remaining Work

### Time Estimate
- **Remaining Lines:** ~1,170 lines of mission logic
- **Functions to Migrate:** 9 functions
- **Call Sites to Update:** ~15-20 locations
- **Estimated Time:** 4-6 hours of focused work

### Complexity Breakdown
- **Simple (dispatch):** 2 functions, ~2 hours
- **Complex (creation):** 5 functions, ~3-4 hours
- **Helpers:** 2 functions, ~1 hour

### Blockers
None - pattern is proven, all dependencies resolved

---

## Benefits of Completion

### Code Organization
- **GameState Size:** 4,583 lines → ~3,400 lines (26% reduction)
- **MissionManager Size:** 0 lines → ~1,500 lines (focused, single-responsibility)
- **Maintainability:** Mission logic centralized and isolated

### Testing
- Mission logic testable in isolation
- Mock dependencies via dependency injection
- Easier to add unit tests

### Future Refactoring
- Establishes pattern for WorkerManager extraction
- Establishes pattern for MarketManager extraction
- Proves feasibility of breaking up god objects

---

## Decision Points

### Option A: Complete MissionManager Now (Recommended)
**Effort:** 4-6 hours
**Benefit:** Full extraction complete, pattern proven, major milestone achieved

**Pros:**
- Finish what we started (40% → 100%)
- Establish complete pattern for other managers
- Achieve significant code organization improvement

**Cons:**
- Requires continued focused effort
- Creation functions are complex (need careful migration)

### Option B: Pause and Move to Other Tasks
**Current State:** Partially extracted (40% complete)
**Benefit:** Partial improvement, proven pattern

**Pros:**
- Can apply learnings to other refactorings
- Already achieved significant value

**Cons:**
- Leaves MissionManager incomplete
- Mixed code organization (some in Manager, some in GameState)
- May be confusing for future development

---

## Recommendation

**Complete the MissionManager extraction** in the next session. We're at 40% with the hardest parts (redirect physics) already done. The remaining creation functions follow similar patterns and will be straightforward to migrate.

**Rationale:**
1. Pattern is proven and consistent
2. All dependencies resolved
3. 60% remaining is mostly repetitive work
4. Achieving 100% completion sets strong precedent for other managers
5. Mixed state (40% extracted) is awkward for long-term maintenance

---

## Next Steps (If Continuing)

1. **dispatch_idle_ship()** - Simple dispatch logic (~30 min)
2. **dispatch_idle_ship_trade()** - Similar to above (~30 min)
3. **start_mission()** - Largest function, careful migration (~90 min)
4. **start_deploy_mission()** - Similar to start_mission (~60 min)
5. **start_collect_mission()** - Similar to start_mission (~60 min)
6. **start_trade_mission()** - Trade-specific creation (~45 min)
7. **start_fleet_rescue()** - Rescue-specific creation (~45 min)
8. **check_hitchhike_opportunities()** - Helper logic (~30 min)
9. **_start_queued_mission()** - Internal routing (~30 min)

**Total Estimated:** 5-6 hours to complete remaining 60%
