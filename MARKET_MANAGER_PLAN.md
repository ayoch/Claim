# MarketManager Extraction Plan

## Overview

Extract market, stockpile, and supply management functions from `game_state.gd` into a dedicated `MarketManager` autoload.

**Target:** 10 functions (~350 lines)
**Estimated Effort:** 4-5 hours
**Pattern:** Follow successful MissionManager and WorkerManager extraction patterns

---

## Goals

1. **Reduce GameState complexity** - Remove market/stockpile logic (~350 lines)
2. **Improve organization** - Centralize all market operations
3. **Maintain compatibility** - Use forwarding stubs during transition
4. **Preserve functionality** - All market operations work in LOCAL and SERVER modes

---

## Architecture Decisions

### Data Ownership

**GameState keeps:**
- `market: MarketState` - Core market state (prices, inventory)
- `stockpiles: Dictionary` - Asteroid ore stockpiles
- `asteroid_supplies: Dictionary` - Food/fuel/parts at remote sites

**MarketManager owns:**
- No new state (operates on GameState data via dependency injection)
- All market operation logic

### Dependency Pattern

```gdscript
# MarketManager (autoload)
var _game_state: Node = null

func _ready() -> void:
    call_deferred("_initialize")

func _initialize() -> void:
    _game_state = get_node("/root/GameState")
```

---

## Functions to Extract (10 total)

### Category 1: Stockpile Management (3 functions)
1. **get_ore_stockpile(asteroid_name: String) -> Dictionary**
   - Returns stockpile dict for an asteroid
   - Lines: ~3
   - Call sites: ~5 (UI, simulation)

2. **add_to_stockpile(asteroid_name: String, ore_type: ResourceTypes.OreType, amount: float) -> void**
   - Adds ore to asteroid stockpile
   - Lines: ~6
   - Call sites: ~3 (mining completion)

3. **collect_from_stockpile(asteroid_name: String, ship: Ship) -> float**
   - Collect stockpiled ore into ship cargo
   - Lines: ~32
   - Call sites: ~2 (mission completion, manual collection)

### Category 2: Asteroid Supply Management (4 functions)
4. **get_asteroid_supplies(asteroid_name: String) -> Dictionary**
   - Returns supply dict (food, fuel, parts)
   - Lines: ~5
   - Call sites: ~4 (UI, deployment)

5. **add_to_asteroid_supplies(asteroid_name: String, supply_key: String, amount: float) -> void**
   - Add supplies to remote site
   - Lines: ~5
   - Call sites: ~3 (deployment, resupply)

6. **consume_asteroid_supply(asteroid_name: String, supply_key: String, amount: float) -> float**
   - Consume supplies (returns amount consumed)
   - Lines: ~9
   - Call sites: ~2 (simulation, rig consumption)

7. **get_asteroid_supply_days(asteroid_name: String, supply_key: String) -> float**
   - Calculate days of supply remaining
   - Lines: ~9
   - Call sites: ~2 (UI, policy decisions)

### Category 3: Ship Supply Management (1 function)
8. **buy_supplies(ship: Ship, supply_key: String, amount: float) -> bool**
   - Purchase supplies for ship (food, fuel, parts)
   - Lines: ~200 (complex, includes colony inventory checks, pricing)
   - Call sites: ~3 (UI, auto-provision, test harness)

### Category 4: Equipment Trading (1 function)
9. **sell_equipment_any_mode(equipment: Equipment, ship: Ship) -> void**
   - Sell equipment (routes to LOCAL/SERVER backend)
   - Lines: ~10
   - Call sites: ~2 (UI)

### Category 5: Market Events (1 function)
10. **apply_market_update_event(event: Dictionary) -> void**
    - Process market price updates from server
    - Lines: ~60
    - Call sites: ~1 (server_backend SSE handler)

---

## Implementation Phases

### Phase 1: Setup MarketManager (30 min)
- Create `core/autoloads/market_manager.gd`
- Add basic structure with dependency injection
- Register in `project.godot` after WorkerManager
- Commit skeleton

### Phase 2: Extract Stockpile Functions (1 hour)
- Migrate 3 stockpile functions
- Replace with forwarding stubs in GameState
- Update ~10 call sites
- Commit

### Phase 3: Extract Supply Functions (1.5 hours)
- Migrate 4 asteroid supply functions
- Migrate buy_supplies() (complex, 200 lines)
- Replace with forwarding stubs
- Update ~15 call sites
- Commit

### Phase 4: Extract Trading & Events (1 hour)
- Migrate sell_equipment_any_mode()
- Migrate apply_market_update_event()
- Replace with forwarding stubs
- Update ~3 call sites
- Commit

---

## Call Site Analysis

### High-Impact Functions (10+ call sites):
- None (market functions have fewer call sites than worker/mission functions)

### Medium-Impact Functions (5-10 call sites):
- **get_ore_stockpile()** - ~5 call sites (UI tabs)
- **get_asteroid_supplies()** - ~4 call sites (UI, simulation)

### Low-Impact Functions (1-4 call sites):
- Most functions have 1-3 call sites each

---

## Risks & Challenges

### Complexity Areas:
1. **buy_supplies()** - 200 lines, handles colony inventory, pricing, trade fees
2. **collect_from_stockpile()** - Cargo management, overflow handling
3. **Server integration** - apply_market_update_event() must work with SSE

### State Access:
- Market functions need access to: money, market, stockpiles, asteroid_supplies, colonies
- All accessed via `_game_state` reference

---

## Benefits

1. **Reduced GameState complexity** - Remove ~350 lines
2. **Improved testability** - Market logic isolated
3. **Better organization** - All market operations in one place
4. **Consistent pattern** - Follows MissionManager/WorkerManager pattern

---

## Success Criteria

- [ ] All 10 market functions extracted to MarketManager
- [ ] All call sites updated (estimated ~35 call sites)
- [ ] All forwarding stubs added to GameState
- [ ] Game compiles without errors
- [ ] All market operations work in both LOCAL and SERVER modes
- [ ] Stockpile collection works correctly
- [ ] Buy supplies works correctly
- [ ] Market events from server process correctly

---

## Files to Modify

### New Files:
- `core/autoloads/market_manager.gd`

### Modified Files:
- `core/autoloads/game_state.gd` - Add forwarding stubs
- `ui/tabs/*.gd` - Update call sites (5-6 files)
- `core/autoloads/simulation.gd` - Update call sites
- `core/autoloads/test_harness.gd` - Update call sites
- `core/backend/server_backend.gd` - Update apply_market_update_event call
- `project.godot` - Register MarketManager autoload

---

## Estimated Timeline

- **Phase 1 (Setup):** 30 minutes
- **Phase 2 (Stockpile):** 1 hour
- **Phase 3 (Supplies):** 1.5 hours
- **Phase 4 (Trading/Events):** 1 hour

**Total: ~4 hours**

---

**Status:** Ready to begin
**Created:** 2026-03-06
**Pattern:** MissionManager/WorkerManager extraction
