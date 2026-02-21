# Food Consumption System - Implementation Summary
**Date:** 2026-02-21
**Status:** COMPLETE ✅

## What Was Implemented

### Backend (NEW)
1. **Cargo Mass Fix** - `Ship.get_cargo_total()` now includes supplies mass
2. **Food Consumption** - `_process_food_consumption()` in simulation.gd:
   - Workers consume 2.8 kg/day (per SupplyData)
   - Consumption tracked for missions and trade missions
   - Food depleted → workers abandon ship, mission aborted
3. **Helper Functions**:
   - `Ship.get_supplies_mass()` - calculates total mass of supplies
   - `SupplyData.get_supply_type_from_key()` - converts key back to type enum
4. **Consequences**:
   - Workers abandon ship when food runs out
   - 20-point loyalty penalty per worker
   - Mission/trade mission aborted
   - Ship becomes idle at current position
5. **Signals**:
   - `ship_food_depleted(ship, workers_abandoned)` added to EventBus

### What Already Existed (Discovered)
1. **Ship.supplies Dictionary** - already in ship model
2. **SupplyData class** - fully defined (food, repair parts, fuel cells)
3. **buy_supplies()** function - complete purchase system
4. **Purchase UI** - full supplies purchase interface in fleet tab:
   - Spinboxes for each supply type
   - Cost preview
   - Cargo capacity checking
   - "Buy Supplies" button on ship cards
5. **Save/Load** - supplies already persisted
6. **Volume Tracking** - supplies already counted in cargo volume

## How It Works

### Player Flow
1. **Purchase Food**:
   - Click ship card → "Buy Supplies" button
   - Select quantity of Food Rations
   - Cost: $50/unit, 0.1t/unit, 0.005m³/unit
   - Shares cargo capacity with ore

2. **Food Consumption**:
   - Workers on missions consume 2.8 kg/day automatically
   - Visible in ship cargo display (shows "food: X units")
   - Runs out → workers abandon ship mid-mission

3. **Consequences**:
   - Mission fails, workers return to available pool
   - Major loyalty penalty
   - Ship left idle in space

### Technical Details
- **Consumption Rate**: 2.8 kg/day per worker (from SupplyData)
- **Storage**: Ship.supplies["food"] in units (not kg)
- **Mass**: Each unit = 0.1t
- **Volume**: Each unit = 0.005m³
- **Cost**: $50/unit

## What's NOT Implemented

1. **Asteroid Food Stockpiles** - Deployed workers at mining units don't consume food yet (TODO in code)
2. **Supply Delivery Missions** - No way to resupply remote mining units
3. **Food Warnings** - No low-food alerts before depletion

## Auto-Provisioning (2026-02-21)

**IMPLEMENTED:** Ships now automatically purchase food when docking at colonies (or Earth):
- Maintains 30-day food buffer based on crew size
- Auto-purchases when food falls below target level
- Uses `GameState.buy_supplies()` (respects money and cargo limits)
- Triggers at same locations as auto-refueling:
  - Mining missions returning to stationed colony
  - Trade missions arriving at destination colony
  - Trade missions completing at colony
  - Stationed ships completing jobs

**Technical Details:**
- Target food: `crew_size * 30 days * 2.8 kg/day / 100 kg/unit`
- Uses `ship.last_crew.size()` or `ship.min_crew` if no crew assigned
- Silently purchases (no UI notification) - same as auto-refuel behavior

## Next Steps (Optional Enhancements)

1. **Low Food Warnings**:
   - Alert when food < 7 days remaining
   - Show estimated days remaining in ship cards

2. **Automatic Food Calculation**:
   - Mission dispatch calculates food needed
   - Auto-suggest purchase amount
   - Or auto-load food if available

3. **Remote Supply Deliveries**:
   - Add SUPPLY_RUN mission type
   - Deployed workers at mining units consume food
   - Food stockpiles at asteroids
   - Players dispatch supply ships periodically

4. **Food Production**:
   - Colonies could produce food
   - Different prices at different colonies
   - Supply chain gameplay

## Files Modified

1. `core/models/ship.gd`:
   - `get_cargo_total()` - now includes supplies mass
   - `get_supplies_mass()` - new helper function

2. `core/data/supply_data.gd`:
   - `get_supply_type_from_key()` - new helper function

3. `core/autoloads/simulation.gd`:
   - `_process_food_consumption()` - new function
   - `_trigger_food_depletion()` - new function
   - `_auto_provision_at_location()` - new function (auto-buy food when docked)
   - Added call to _process_food_consumption() in _process() main loop
   - Added calls to _auto_provision_at_location() at all dock points

4. `core/autoloads/event_bus.gd`:
   - `ship_food_depleted` signal added

5. `core/data/ship_data.gd`:
   - Ships start with 200 food + 10 repair_parts

## Testing Checklist

- [ ] Purchase food from fleet tab "Buy Supplies" button
- [ ] Verify food shows in ship cargo display
- [ ] Verify food mass counts toward cargo capacity
- [ ] Dispatch mission with insufficient food
- [ ] Run at high speed until food depletes
- [ ] Verify workers abandon ship
- [ ] Verify mission aborts
- [ ] Verify loyalty penalty applied
- [ ] Check dashboard for food depletion alert
- [ ] Save/load with food on ships
- [ ] Verify food persists correctly

## Integration Notes

- Food system is **opt-in** - players who don't buy food will experience crew abandonment
- No tutorial or onboarding yet - players must discover the food mechanic
- Consider adding a warning on first mission dispatch: "Don't forget supplies!"
- Food mechanic adds strategic depth but could be frustrating if not communicated

## Balance Considerations

- **2.8 kg/day** seems reasonable (real rations ~1-2 kg, water recycled)
- **$50/unit** is cheap - 3-person crew for 10 days = 84 kg = 840 units = $42,000 (4% of Prospector cost)
- **Abandonment** is harsh - consider partial crew desertion instead?
- **No food at start** means first mission WILL fail unless player buys food
  - Should tutorial/starting condition include food on starter ship?

## Recommendation

Add a starting food supply to new games (e.g., 100 units on starter ship) and/or add a warning dialog on first mission dispatch if food < mission duration requirements.
