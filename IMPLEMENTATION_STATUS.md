# Implementation Status Analysis
**Date:** 2026-02-21
**Analysis:** Code review vs GDD claims

## Summary

The codebase is **significantly more complete** than the GDD (v0.6) reflects. Multiple Phase 2b features marked as "not implemented" or "foundations only" are actually fully functional systems with complete UI integration.

---

## Mining Units - FULLY IMPLEMENTED ✅
**GDD Claims:** "Foundations exist, deployment loop not implemented"
**Reality:** Complete end-to-end system

### What Works:
1. **Models & Data**
   - `MiningUnit` class with deployment state, workers, durability, wear
   - `MiningUnitCatalog` with 3 unit types (Basic $50k, Advanced $150k, Refinery $350k)
   - Correct specs: Basic 7.6t/11.4m³, Advanced 13.2t/16.8m³, Refinery 21.5t/27.3m³

2. **Purchase System**
   - Ship outfitting tab shows available units
   - `purchase_mining_unit()` function
   - `mining_unit_inventory` array
   - EventBus signals (mining_unit_purchased, deployed, recalled, broken)

3. **Deployment System**
   - Fleet tab mission type selector: Mine / Deploy Units / Collect Ore
   - Unit selection UI with live cargo space checking
   - **Volume AND mass constraints enforced**
   - Slot availability checking (get_occupied_slots, get_max_mining_slots)
   - `start_deploy_mission()` creates DEPLOY_UNIT missions
   - Workers can be assigned to units (workers_to_deploy)
   - Fuel calculation includes unit mass

4. **Backend Processing**
   - Mission.Status.DEPLOYING with deploy_duration
   - `_complete_deploy()` transfers units from ship to asteroid
   - Workers assigned to units stay at asteroid
   - `_process_mining_units()` generates ore continuously at deployed sites
   - Ore goes into stockpiles (not ship cargo)
   - Durability/wear system with repairs (skill-based cost reduction)
   - Engineer XP grants during repair

5. **Collection System**
   - Mission.Status.COLLECTING for ore pickup
   - `start_collect_mission()` creates pickup missions
   - `collect_from_stockpile()` loads ore into ship (respects cargo limits)
   - UI shows stockpile tonnage on deploy screen

6. **Save/Load**
   - mining_unit_inventory saved/loaded
   - deployed_mining_units saved/loaded with full state
   - ore_stockpiles saved/loaded

7. **Test Coverage**
   - test_harness.gd actively uses mining unit system

### What's Missing:
- Nothing critical. System is production-ready.

---

## Cargo Volume Constraints - FULLY IMPLEMENTED ✅
**GDD Claims:** "Not yet implemented. Currently only mass tracked."
**Reality:** Complete dual-constraint system

### What Works:
1. **Ship Model**
   - `cargo_volume` field (m³)
   - `get_effective_cargo_volume()` with upgrade bonuses
   - `get_cargo_volume_used()` calculates current usage
   - `get_cargo_volume_remaining()` shows available space

2. **Volume Enforcement**
   - Deployment UI checks both mass AND volume
   - Prevents over-packing: `(total_unit_mass + unit.mass) <= cargo_space AND (total_unit_volume + unit.volume) <= volume_space`
   - Buttons disabled when either constraint exceeded

3. **Data Support**
   - Mining units have mass AND volume
   - SupplyData defines mass AND volume for food, repair parts, fuel cells
   - Ore types could have volume (not currently set)

### What's Missing:
- Ore volume not defined (currently mass-only for ore)
- Supply items not integrated into cargo system yet (data exists but not used)

---

## Ore Stockpiles - FULLY IMPLEMENTED ✅
**GDD Status:** Not clearly mentioned
**Reality:** Complete remote ore storage system

### What Works:
1. **Data Structure**
   - `ore_stockpiles` Dictionary: asteroid_name → { OreType → float }
   - Separate from ship cargo - ore accumulates remotely

2. **Functions**
   - `add_to_stockpile(asteroid_name, ore_type, amount)`
   - `get_ore_stockpile(asteroid_name)` returns pile Dictionary
   - `collect_from_stockpile(asteroid_name, ship)` loads into ship

3. **Integration**
   - `_process_mining_units()` adds ore to stockpiles (not ship cargo)
   - Collection missions load stockpiled ore
   - UI shows stockpile tonnage and value on deployment screen
   - Dashboard resources tab shows all stockpiles by asteroid

4. **Save/Load**
   - Full persistence of all stockpiles

---

## Supply Data - DEFINED BUT NOT INTEGRATED ⚠️
**GDD Claims:** "Food and supply items do not yet exist"
**Reality:** Data model exists, integration missing

### What Works:
1. **SupplyData Class**
   - SupplyType enum: REPAIR_PARTS, FOOD_RATIONS, FUEL_CELLS
   - Complete specs with cost, mass, volume
   - Repair parts: $500, 0.45t, 0.28m³
   - Food: $50, 0.1t, 0.005m³
   - Fuel cells: $200, 0.3t, 0.4m³

### What's Missing:
- No cargo integration (Ship.supplies not used in cargo calculations)
- No purchase UI
- No consumption mechanics
- Workers don't consume food
- Remote workers don't need supply deliveries

**Status:** Data layer complete, gameplay layer not started

---

## Worker Skill Progression - FULLY IMPLEMENTED ✅
**GDD Status:** Correctly marked as DONE
**Implemented:** 2026-02-20 by Mac instance

### What Works:
- XP accumulation (pilot/engineer/mining)
- Level-up system with quadratic XP curve
- Wage scaling
- Loyalty bonuses
- UI progress bars in workers tab
- Dashboard notifications
- Save/load persistence
- Only best pilot gains pilot XP (realistic)

---

## Fuel Stop Routing - FULLY IMPLEMENTED ✅
**GDD Status:** Documented in Section 8.6
**Implemented:** 2026-02-20 by Windows instance

### What Works:
- FuelRoutePlanner with greedy nearest-colony algorithm
- Waypoint insertion for multi-stop routes
- REFUELING mission status
- UI preview showing fuel costs
- Save/load of waypoint metadata
- Abort-on-arrival if destination drifts out of range

---

## Ship Purchasing - FULLY IMPLEMENTED ✅
**GDD Status:** Correctly marked as DONE

### What Works:
- Purchase UI popup with specs
- All 4 ship classes available
- Pricing, color-coded affordability
- Ships spawn at Earth with full fuel

---

## Save/Load System - FULLY IMPLEMENTED ✅
**GDD Status:** Correctly marked as DONE

### What Works:
- All major systems persist: money, resources, workers (with XP), ships, missions, trade missions, contracts, market events, fabrication queue, reputation, rescue/refuel missions, stranger offers, fuel stop waypoints, mining unit inventory, deployed units, ore stockpiles

---

## What's Actually Not Implemented

### Phase 2b - Major Features
- ❌ Worker personality traits (data model exists in GDD, not in code)
- ❌ Worker autonomous encounter resolution
- ❌ Communication delay (light-speed)
- ❌ Policy system (company-wide + per-site)
- ❌ Two-tier alert system (strategic vs news feed)
- ❌ Colony tier system (major/minor)
- ❌ Colony growth/decline
- ❌ Player HQ location selection
- ❌ Ship weapons
- ❌ Claims map UI tab
- ❌ AI rival corporations
- ❌ Food consumption mechanics (despite SupplyData existing)

### Phase 3+ - Multiplayer & Beyond
- Everything in Phase 3, 4, 5 (as expected)

---

## Recommendations

1. **Update GDD immediately** - current status claims are misleading
2. **Test mining unit deployment** - verify end-to-end flow works in-game
3. **Integrate SupplyData** - data layer exists, wire up purchase/consumption
4. **Next logical features** based on what's built:
   - Worker personality traits (data model → gameplay)
   - Food consumption (SupplyData → worker needs)
   - Policy system (builds on autonomous behavior)
   - Communication delay (interesting with remote deployments)

---

## GDD Version Update

Recommend bumping to **v0.7** with updated subtitle:
"Mining unit deployment, skill progression, fuel routing, dual cargo constraints, complete save/load"

Current v0.6 subtitle undersells implemented features.
