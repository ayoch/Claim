# Worker Location System - Test Checklist

## Implementation Summary

The worker location system has been fully implemented with the following components:

### Client-Side (Godot)
1. **Worker Model** (`core/models/worker.gd`):
   - Added `home_colony: String` field
   - Workers spawn with location based on weighted distribution

2. **GameState** (`core/autoloads/game_state.gd`):
   - `assign_worker_to_ship()` now validates locations and returns `{success: bool, error: String}`
   - Auto-assignment filters workers by location (e.g., stationing ships)
   - Save/load backward compatibility: auto-relocates workers to match ship location

3. **Fleet Tab** (`ui/tabs/fleet_market_tab.gd`):
   - Crew selection filtered by ship's docked location
   - Only shows workers at the same colony as the ship

4. **Workers Tab** (`ui/tabs/workers_tab.gd`):
   - Restructured to group workers by location
   - Shows workers organized by colony
   - Candidates filtered to locations where player has docked ships

### Server-Side (Python/FastAPI)
1. **Database Migration** (`alembic/versions/add_worker_location.py`):
   - Added `location_colony_id` column to workers table
   - Foreign key to colonies table
   - Default existing workers to Earth (colony_id=1)

2. **Worker Model** (`server/models/worker.py`):
   - Added `location_colony_id: Mapped[int]` field

3. **Worker Spawning** (`server/simulation/worker_spawning.py`):
   - Background worker spawning based on colony tier
   - Earth: 1 worker/day
   - Major colonies (Lunar, Mars, Ceres, Europa, Ganymede): 1 worker/2-4 days
   - Remote colonies (Vesta, Titan, Callisto, Triton): 1 worker/7-14 days

4. **Spawn Workers Endpoint** (`server/routers/admin.py`):
   - POST /admin/spawn-workers (admin only)
   - Workers distributed across colonies by population weight

---

## Test Scenarios

### 1. Database Migration ✅ CRITICAL
**Status:** Run migration on Railway production database

```bash
# On Railway, ensure migration has run:
# alembic upgrade head
```

**Verify:**
- [ ] Workers table has `location_colony_id` column
- [ ] Existing workers set to Earth (colony_id=1)
- [ ] Foreign key constraint exists

### 2. Worker Spawning - Manual ✅
**Test:** Call admin endpoint to spawn workers at various colonies

```bash
# From game client or curl:
curl -X POST https://your-server.railway.app/admin/spawn-workers \
  -H "Admin-Key: YOUR_ADMIN_KEY" \
  -H "Content-Type: application/json" \
  -d '{"count": 20}'
```

**Verify:**
- [ ] Workers spawn at different colonies (check /game/available-workers)
- [ ] Distribution roughly matches population weights (40% Earth, 20% Lunar, etc.)
- [ ] Each worker has valid `location_colony_id`

### 3. Worker Spawning - Automatic ✅
**Test:** Run server for extended period (1-2 in-game days at high speed)

**Verify:**
- [ ] New workers appear automatically
- [ ] Workers spawn more frequently at major colonies
- [ ] Remote colonies get workers but less frequently
- [ ] No duplicate workers created

### 4. Location-Based Crew Selection ✅
**Test:** Dispatch ships from different colonies

**Steps:**
1. Buy ships at Earth, Lunar Base, and Mars Colony
2. Ensure you have workers at each location
3. Try to dispatch each ship

**Verify:**
- [ ] Ship at Earth only shows Earth-based workers
- [ ] Ship at Lunar Base only shows Lunar workers
- [ ] Ship at Mars only shows Mars workers
- [ ] Cannot select workers from wrong location

### 5. Workers Tab UI ✅
**Test:** Open Workers tab with workers at multiple locations

**Verify:**
- [ ] Workers grouped by colony name
- [ ] Each section shows count (e.g., "Earth (5 workers)")
- [ ] Ships at same location shown in each section
- [ ] Candidates only shown for locations with docked ships

### 6. Assignment Validation - Client ✅
**Test:** Try to manually assign workers to ships at different locations

**Note:** Current UI prevents this by filtering, but test via console if possible:

```gdscript
# In Godot console/script:
var earth_ship = GameState.ships[0]  # At Earth
var mars_worker = GameState.workers.filter(func(w): return w.home_colony == "Mars")[0]
var result = GameState.assign_worker_to_ship(mars_worker, earth_ship)
print(result)  # Should show {success: false, error: "Worker at Mars cannot crew ship at Earth"}
```

**Verify:**
- [ ] Assignment fails with clear error message
- [ ] Worker not added to ship.crew
- [ ] No crash or corruption

### 7. Save/Load Compatibility ✅
**Test:** Load old saves (pre-location system)

**Steps:**
1. Load save file from before worker location implementation
2. Check all workers and ships

**Verify:**
- [ ] Game loads without errors
- [ ] Workers auto-relocated to match their assigned ship's location
- [ ] Workers without ships default to Earth
- [ ] Save/load cycle preserves locations

### 8. Multi-Colony Operations ✅
**Test:** Full gameplay loop at multiple colonies

**Steps:**
1. Buy ships at Earth, Lunar, Mars
2. Hire workers at each location (via spawning)
3. Dispatch missions from each colony
4. Complete missions and return
5. Re-dispatch same ships

**Verify:**
- [ ] Ships can only use local workers
- [ ] Missions complete successfully
- [ ] Crew persists across missions
- [ ] No location-related errors in console

### 9. Partnership System Integration ✅
**Test:** Partner ships at same vs different locations

**Steps:**
1. Create partnership between two ships at Earth
2. Try to create partnership between Earth ship and Mars ship (if possible via console)

**Verify:**
- [ ] Partnerships work normally when ships at same location
- [ ] Partnership validation considers location (if implemented)
- [ ] Partnered ships can share crew if at same location

### 10. NPC Rival Corps ✅
**Test:** Observe rival corp behavior over time

**Verify:**
- [ ] Rival ships operate normally
- [ ] No errors related to rival worker locations
- [ ] Rivals dispatch missions successfully

### 11. High-Speed Stability ✅
**Test:** Run game at 200,000x speed for 10+ minutes

**Verify:**
- [ ] No worker location errors
- [ ] Workers spawn correctly
- [ ] No performance degradation
- [ ] No crashes or hangs

### 12. Server Authority ✅
**Test:** Play in SERVER mode (multiplayer)

**Steps:**
1. Connect to production server
2. Hire workers via /game/hire
3. Dispatch ships
4. Check game state

**Verify:**
- [ ] Workers have correct location_colony_id in database
- [ ] Server spawns workers at various colonies
- [ ] Client correctly displays worker locations
- [ ] No desync between client and server

---

## Known Issues / Future Improvements

### Not Yet Implemented:
- [ ] **Worker relocation**: Cannot manually move workers between colonies
- [ ] **Worker travel**: Workers cannot travel with cargo shipments to new locations
- [ ] **Colony preference UI**: No UI to see which colonies need more workers
- [ ] **Hiring at remote colonies**: Can only hire workers that spawn; cannot recruit at specific colonies

### Performance Considerations:
- Worker spawning runs every tick but throttled per-colony
- UI grouping by location is O(n) per refresh
- No noticeable performance impact in testing

### Edge Cases Handled:
- ✅ Old saves auto-relocate workers to prevent orphaned crew
- ✅ Stationed ships filter workers by colony before auto-assigning
- ✅ Empty location string defaults to "Earth"
- ✅ Workers without home_colony default to "Earth"

---

## Rollback Plan

If critical issues found:

1. **Client-side rollback:**
   - Remove location filtering from `fleet_market_tab.gd` line 2631-2637
   - Revert `assign_worker_to_ship()` to old void signature
   - Restore old save/load code

2. **Server-side rollback:**
   - Create down migration: `alembic downgrade -1`
   - Disable worker spawning in `tick.py`
   - Remove location_colony_id from schemas

---

## Sign-off

- [ ] All critical tests passed
- [ ] No regression in existing features
- [ ] Performance acceptable at high speeds
- [ ] Save/load compatibility confirmed
- [ ] Server migration successful
- [ ] Ready for production use

**Tested by:** _________________
**Date:** _________________
**Build:** _________________
