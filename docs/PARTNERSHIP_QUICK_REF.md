# Partnership System - Quick Reference

## Creating Partnerships

```gdscript
# Validation
var check := ship1.can_partner_with(ship2)
if check["valid"]:
    GameState.create_partnership(ship1, ship2)
else:
    print("Cannot partner: %s" % check["reason"])
```

**Requirements:**
- Both ships idle (no active mission)
- Neither derelict
- Within 0.02 AU proximity
- Neither already partnered

## Breaking Partnerships

```gdscript
GameState.break_partnership(ship1, ship2, "reason")
```

Automatically:
- Clears partner references
- Converts shadow mission to independent
- Emits `partnership_broken` signal

## Partnership Roles

```gdscript
ship.is_partnered()  # bool
ship.get_partnership_role()  # "solo", "leader", or "follower"
ship.is_partnership_leader  # bool (leader = true, follower = false)
```

## Mission Dispatch

**Leader dispatches:**
```gdscript
var mission = GameState.start_mission(leader_ship, asteroid)
# Follower automatically gets shadow mission
# Both ships travel together
```

**Shadow mission characteristics:**
- `is_partnership_shadow = true`
- Status synced with leader every tick
- Position co-located with leader
- Independent fuel consumption

## Mutual Aid (Automatic)

**Fuel Transfer:**
- Triggers when follower derelict with `reason = "out_of_fuel"`
- Leader stops and transfers up to 50% of fuel
- Follower recovers, mission resumes
- Activity log: "⛽ [Leader] transferred XXX fuel to [Follower]"

**Engineer Repair:**
- Triggers when follower derelict with `reason = "breakdown"`
- Leader's best engineer repairs follower
- Requires engineer skill ≥ 0.5
- Engine restored to 50-100% (skill-based)
- Activity log: "🔧 [Leader] repaired [Follower] (Engineer: [Name])"
- Partnership breaks if no qualified engineer

## Combat Bonuses

**Threat Assessment:**
- Rival corps see combined firepower from both ships
- Partner must be within 0.1 AU to count
- More weapons = exponentially lower attack probability

**Damage Distribution:**
- Damage splits proportionally by cargo capacity
- Example: 100t + 200t ships → 33% / 67% damage split
- Both ships take crew casualties proportionally

## NPC Partnerships

**Formation conditions:**
- Corp aggression ≥ 0.5
- High-value asteroid (ore_value ≥ 0.5)
- Player threat nearby (armed ships, proximity < 0.5 AU)
- Player threat ≥ 2

**Behavior:**
- Dispatches two idle ships as pair
- Both transit and mine at same asteroid
- Simplified (no full tracking/mutual aid)

## Save/Load

**Saved fields:**
```gdscript
ship_data["partner_ship_name"] = s.partner_ship_name
ship_data["is_partnership_leader"] = s.is_partnership_leader
```

**Load resolution:**
```gdscript
# After all ships loaded, resolve references
for s in ships:
    if s.partner_ship_name != "":
        var partner_arr := ships.filter(func(sh): return sh.ship_name == s.partner_ship_name)
        if not partner_arr.is_empty():
            s.partner_ship = partner_arr[0]
```

## UI Integration

**Fleet Tab:**
- Partnership status: "🤝 [Role]: Partnered with [Name]"
- Create button (idle docked ships)
- Break button (partnered ships)
- Selection dialog (shows eligible ships with stats)

**Dashboard:**
- 🤝 "Partnership: [Leader] + [Follower]"
- 💔 "Partnership ended: [Ship1] & [Ship2] ([Reason])"
- ⛽ "[Leader] transferred XXX fuel to [Follower]"
- 🔧 "[Leader] repaired [Follower] (Engineer: [Name])"

## Event Signals

```gdscript
EventBus.partnership_created.connect(func(leader: Ship, follower: Ship):
    # Called when partnership formed
)

EventBus.partnership_broken.connect(func(ship1: Ship, ship2: Ship, reason: String):
    # Called when partnership ends
)

EventBus.partnership_aid_provided.connect(func(leader: String, follower: String, aid_type: String, details: Dictionary):
    # Called when mutual aid provided
    # aid_type: "fuel_transfer" or "engineer_repair"
    # details: {"amount": float} or {"engineer": String, "skill": float}
)
```

## Common Patterns

### Check if ship needs partner for dangerous mission
```gdscript
if ship.is_armed():
    # Well-armed, can go solo
    GameState.start_mission(ship, asteroid)
else:
    # Unarmed, find a partner first
    for other in GameState.ships:
        if other.is_armed() and ship.can_partner_with(other)["valid"]:
            GameState.create_partnership(other, ship)  # Armed ship leads
            break
    GameState.start_mission(ship.partner_ship if ship.partner_ship else ship, asteroid)
```

### Monitor partnership health
```gdscript
func check_partnership_status(ship: Ship) -> void:
    if not ship.is_partnered():
        return

    var partner := ship.partner_ship
    if partner.is_derelict:
        print("Partner %s needs help!" % partner.ship_name)

    var distance := ship.position_au.distance_to(partner.position_au)
    if distance > 0.5:
        print("Partner %s drifted too far!" % partner.ship_name)
```

### Station paired ships
```gdscript
# Both ships must be at same colony
GameState.station_ship(leader, colony, ["mining", "patrol"])
GameState.station_ship(follower, colony, ["mining", "patrol"])

# They'll dispatch together automatically when jobs trigger
```

## Performance Notes

- **Sync overhead:** O(n) where n = partnered leader ships
- **Typical impact:** < 0.1ms with 10 partnerships at 200,000x speed
- **Combat calculations:** +2-3 array operations per check
- **NPC formation:** Only checks aggressive corps, every 3600 ticks

## Debugging

**Check partnership state:**
```gdscript
print("Partnered: %s" % ship.is_partnered())
print("Role: %s" % ship.get_partnership_role())
print("Partner: %s" % (ship.partner_ship.ship_name if ship.partner_ship else "none"))
print("Leader: %s" % ship.is_partnership_leader)
```

**Check mission sync:**
```gdscript
if ship.is_partnered() and ship.current_mission:
    var mission = ship.current_mission
    print("Shadow: %s" % mission.is_partnership_shadow)
    if mission.is_partnership_shadow and mission.partnership_leader_mission:
        var leader_mission = mission.partnership_leader_mission
        print("Status match: %s" % (mission.status == leader_mission.status))
        print("Position match: %s" % ship.position_au.is_equal_approx(mission.ship.partner_ship.position_au))
```

## Testing Script

Run `partnership_test.gd` from Godot editor:
- Validates creation
- Tests roles assignment
- Verifies shadow mission creation
- Tests save/load persistence
- Tests partnership breaking

## Full Documentation

See `docs/PARTNERSHIP_SYSTEM.md` for:
- Complete architecture
- Implementation details
- Edge cases
- Future enhancements
- Known issues
