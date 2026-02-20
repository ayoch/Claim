# Worker Skill Progression - Verification Guide

## Implementation Complete ✅

The worker skill progression system has been fully implemented and is ready for testing.

## What Was Implemented

### Core System
- **XP Fields**: Each worker now has `pilot_xp`, `engineer_xp`, `mining_xp`
- **XP Accumulation**: Workers gain XP while performing relevant work (1 tick = 1 XP)
- **Level-Up System**: Skills increase by 0.05 per level, cap at 2.0 (up from 1.5 max at hire)
- **Wage Scaling**: Wages automatically increase as skills improve
- **Loyalty Bonus**: +2 loyalty per level-up (max 100)

### XP Sources

#### Pilot XP
- Gained during mission TRANSIT_OUT phase (outbound journey)
- Gained during mission TRANSIT_RETURN phase (return journey)
- **Rate**: 1 XP per game-tick while in transit

#### Mining XP
- Gained during mission MINING phase
- Gained continuously while assigned to deployed mining units
- **Rate**: 1 XP per game-tick while mining

#### Engineer XP
- **Bonus**: Half-day worth (43,200 XP) when successfully self-repairing breakdowns
- **Bonus**: Quarter-day worth (21,600 XP) when repairing mining units
- **Rate**: Continuous accumulation during active work

### XP Requirements
- **Formula**: `XP_needed = 86,400 * (current_skill + 1)^2`
- **Starting workers** (skill 0.0-0.5): ~1-2 game-days per level
- **Experienced workers** (skill 1.0-1.5): ~3-5 game-days per level
- **Cap**: Skills stop at 2.0

### UI Features
- **Workers Tab**:
  - Color-coded XP progress bars (blue=pilot, orange=engineer, green=mining)
  - Shows current skill value and progress to next level
  - Auto-refreshes on level-up

- **Dashboard Tab**:
  - Level-up notifications in activity feed
  - Format: "[Worker] Ada Chen's Pilot skill increased to 1.35!"

### Save/Load
- All XP values persist across saves
- Backward compatible (old saves default to 0.0 XP)

---

## Testing Checklist

### 1. Basic XP Accumulation
- [ ] Start a new game or load existing save
- [ ] Hire a worker (note their initial skills)
- [ ] Send them on a mining mission to a nearby asteroid
- [ ] Run at moderate speed (1000x-10,000x)
- [ ] Check Workers tab — XP bars should be filling
- [ ] **Expected**: Pilot bar fills during transit, Mining bar fills during extraction

### 2. Level-Up Verification
- [ ] Wait for a level-up to occur (watch for dashboard notification)
- [ ] Check the activity feed: "[Worker] [Name]'s [Skill] skill increased to [Value]!"
- [ ] Verify skill value increased by 0.05
- [ ] Verify wage increased (check before/after value)
- [ ] **Expected**: Skill goes from X.XX to X.XX+0.05, wage increases proportionally

### 3. Mining Unit XP
- [ ] Deploy a mining unit to an asteroid (if system is implemented)
- [ ] Assign workers to the unit
- [ ] Run at high speed (50,000x+)
- [ ] Watch Workers tab — Mining XP should accumulate continuously
- [ ] **Expected**: Workers gain mining skill even while not on missions

### 4. Engineer Self-Repair Bonus
- [ ] Send a ship with an engineer on a long mission
- [ ] Wait for a breakdown to occur
- [ ] If engineer self-repairs (check console: "Engineer patched breakdown in-situ")
- [ ] Check engineer's XP — should see a large jump
- [ ] **Expected**: Engineer gains half-day worth of XP as bonus

### 5. High-Speed Testing
- [ ] Run game at maximum speed (200,000x) for several in-game weeks
- [ ] Monitor skill progression — should approach cap (2.0) but never exceed
- [ ] Watch for any errors or crashes
- [ ] **Expected**: Skills grow smoothly to 2.0, then stop gaining XP

### 6. Save/Load Persistence
- [ ] Note current XP values for several workers
- [ ] Save the game
- [ ] Close and reopen Godot
- [ ] Load the save
- [ ] Verify XP values match what was saved
- [ ] **Expected**: All XP values persist correctly

### 7. Wage Progression
- [ ] Track a worker's wage over time as skills increase
- [ ] Formula: `wage = 80 + (pilot + engineer + mining) * 40`
- [ ] Verify wage increases match skill increases
- [ ] **Expected**: Fresh hire (~$100-140) → Veteran (~$220-240)

### 8. Edge Cases
- [ ] Worker at skill cap (2.0) — verify they stop gaining XP
- [ ] Worker with 0.0 in a skill — verify they can start gaining from zero
- [ ] Multiple simultaneous level-ups (add massive XP via console if needed)
- [ ] **Expected**: System handles all edge cases gracefully

---

## Quick Console Test

If you want to test the system quickly without waiting for missions:

1. Open the Godot editor
2. Run the game
3. Hire a worker
4. Open the debugger console
5. Access a worker and manually add XP:
   ```gdscript
   var worker = GameState.workers[0]
   worker.add_xp(0, 86400.0)  # Add 1 day of pilot XP (should level up)
   worker.add_xp(1, 200000.0)  # Add lots of engineer XP (multiple level-ups)
   ```

Or run the included test script:
1. Add `test_xp_system.gd` to your scene tree as an autoload or attach to a node
2. Run the game
3. Check the console output for test results

---

## Known Behavior

- **XP bars update every 200ms** (real-time throttle) to reduce UI overhead
- **Multiple level-ups** can occur in one `add_xp()` call (e.g., if lots of time passed at high speed)
- **Loyalty caps at 100** even with many level-ups
- **Wage formula** ensures consistency with hiring market (no exploit from firing/rehiring)

---

## Files Modified

1. `core/models/worker.gd` — XP fields, methods, constants
2. `core/autoloads/event_bus.gd` — worker_skill_leveled signal
3. `core/autoloads/game_state.gd` — save/load XP, mining unit repair bonus
4. `core/autoloads/simulation.gd` — XP grants during missions, mining units, self-repair
5. `ui/tabs/workers_tab.gd` — XP progress bars
6. `ui/tabs/dashboard_tab.gd` — level-up notifications

---

## Next Steps

After verification, consider:
- Balancing XP rates if progression feels too fast/slow
- Adding XP gain notifications (subtle UI feedback during accumulation)
- Creating achievements for maxing out skills
- Implementing worker personality traits that interact with skills
