# Warning & Communication System

## Overview

The warning system implements **realistic lightspeed communication delays** for all events in the game. Events that occur far from Earth take time to reach the player, creating authentic information lag in space operations.

## Core Principles

### 1. **Lightspeed Delay**
All communications travel at the speed of light: **499 seconds per AU**

Example distances:
- Moon to Earth: 0.0026 AU → ~1.3 seconds
- Mars to Earth: 0.5-2.5 AU → 4-20 minutes
- Jupiter to Earth: 4-6 AU → 33-50 minutes
- Saturn to Earth: 8-11 AU → 1-1.5 hours

### 2. **Event Timestamps**
Every warning shows **when the event actually occurred** (game time), not when you received the message.

Format: `[Day HH:MM]`
- Example: `[D1 12:34]` = Day 1 at 12:34

### 3. **Two-Stage Delays**
Many events involve **two lightspeed hops**:

**Example: Combat Violation**
```
1. Combat at 2 AU from colony
   ⏱️ Light travels 2 AU → colony (~16 min)
2. Colony issues violation
   ⏱️ Light travels colony → Earth (~1-60 sec depending on colony)
3. Player receives warning
```

Total delay = event→colony + colony→Earth

## Warning Format

```
[D1 12:34] [+5m delay] ⚔️ COMBAT: [YOUR] Slurry engaging [Rival Corp] Bandit (2.1 AU)
```

Components:
- **[D1 12:34]** = Event occurred on Day 1 at 12:34
- **[+5m delay]** = Message took 5 minutes to arrive (optional, only shown if delayed)
- **⚔️ COMBAT** = Event type
- **[YOUR]** = Your ship (ownership label)
- **[Rival Corp]** = Rival corporation ship
- **Slurry** = Ship name
- **(2.1 AU)** = Distance or other context

## Ship Ownership Labels

Combat and other ship-related warnings include ownership tags:

| Label | Meaning |
|-------|---------|
| **[YOUR]** | Player-owned ship |
| **[Corp Name]** | Rival corporation ship |
| *(no label)* | Unaffiliated/NPC ship |

Example:
```
[D1 15:23] [+3m delay] ⚔️ COMBAT: [YOUR] Slurry engaging [Ceres Mining Co] Harvester
```

## Event Types & Severities

### Critical Events (Auto-Pause)
These trigger auto-pause to 1x speed if enabled:

| Icon | Event | Description |
|------|-------|-------------|
| ⚔️ | Combat | Ship engaging another ship |
| 💀 | Crew Death | Worker killed in combat or starvation |
| 🚨 | Breakdown | Ship systems failed |
| 🚨 | Ship Destroyed | Ship lost (collision or life support) |
| 🚨 | Life Support | Oxygen running low (75%, 50%, 25%, 10%) |
| 🚨 | Final Warning | Colony violation count at 3/4 |
| 🚨 | Ban | Banned from colony (4+ violations) |
| ☢️ | Fusion Weapon | Fusion torpedo used (game over) |
| ⚡ | EMP Hit | Ship disabled by EMP |

### Warning Events
These don't auto-pause but still notify:

| Icon | Event | Description |
|------|-------|-------------|
| ⚠️ | Violation | Criminal violation recorded (1-2/4) |
| ⚠️ | Low Crew | Only 1 worker remaining |
| ⚠️ | All Deployed | No backup workers available |

## Violation System

### Physics-Correct Delays

Violations are issued by colonies **after they learn of events**, not instantly:

```
Timeline:
T+0s:     Combat happens 2 AU from Lunar Base
T+16m:    Lunar Base receives light from combat
T+16m:    Lunar Base issues violation
T+16m1s:  Player receives violation (1.3s delay Lunar Base→Earth)
```

### Violation Thresholds

Warnings are sent at specific thresholds to reduce spam:

| Count | Message | Severity |
|-------|---------|----------|
| 1/4 | ⚠️ VIOLATION - [Colony]: [Reason] (1/4) | Warning |
| 2/4 | ⚠️ [Colony]: 2 violations (4 = BAN) | Warning |
| 3/4 | 🚨 FINAL WARNING: [Colony] - one more = banned! | **Critical** |
| 4/4 | 🚨 BANNED FROM [Colony] - 4 violations | **Critical** |

### Violation Types

| Reason | Description | Strikes |
|--------|-------------|---------|
| `attacked_unarmed_ship` | Attacked vessel with no weapons | 1 |
| `attacked_unarmed_ship_major` | Unarmed attack (major offense) | 1 |
| `unprovoked_attack` | Attacked armed vessel | 1 |
| `crew_death_combat` | Caused crew deaths in combat | 1 |
| `fusion_weapon_use` | Used prohibited fusion weapons | 1 (×4 to all colonies) |

### Violation Decay

Violations decay after **30 game-days** (2,592,000 ticks)

## Auto-Pause System

### Settings
- **Setting:** `auto_pause_on_critical`
- **Default:** `true` (ON for safety)
- **UI Toggle:** Dashboard → "⚠️ Pause" button

### Behavior
When a **critical** warning is delivered:
1. If auto-pause is ON → simulation slows to 1x speed
2. Player can review the event without missing important updates
3. Manual speed adjustment available anytime

### Why Auto-Pause?
At 200,000x speed, critical events happen in milliseconds of real-time. Auto-pause ensures you don't miss:
- Ship destruction
- Crew deaths
- Colony bans
- Combat engagements

## Message Deduplication

### Base Message Matching
The system prevents duplicate warnings by comparing **base messages** (without timestamp/delay prefixes):

```gdscript
# These are treated as duplicates:
"[D1 12:30] [+5m delay] COMBAT: Ship A vs Ship B"
"[D1 12:31] [+6m delay] COMBAT: Ship A vs Ship B"

# Only the first is kept
```

### Deduplication Logic
1. Strip timestamp: `[D1 12:34]`
2. Strip delay: `[+5m delay]`
3. Compare remaining message + category + severity
4. If match found, skip (return existing ID)

### Warning Limit
Active warnings capped at **50** to prevent UI bloat. Oldest warnings auto-dismissed when limit exceeded.

## Push Notifications

Critical warnings trigger push notifications on supported platforms:

| Platform | Implementation |
|----------|----------------|
| **Desktop** | Window flash (already working) |
| **Android** | Requires plugin (see MOBILE_NOTIFICATIONS.md) |
| **iOS** | Requires plugin (see MOBILE_NOTIFICATIONS.md) |

## Implementation Details

### File Structure

```
core/autoloads/game_state.gd
├── add_warning()           # Queue warning with lightspeed delay
├── _deliver_warning()      # Deliver warning after delay
├── dismiss_warning()       # Remove warning by ID
├── send_push_notification() # Mobile/desktop notifications
└── _format_game_time()     # Format timestamps

core/autoloads/simulation.gd
└── _queue_violation()      # Queue violation with event→colony delay

core/models/colony.gd
└── add_violation()         # Issue violation (with colony→Earth delay)
```

### Warning Flow

```
Event occurs at position P at time T
    ↓
add_warning(message, severity, category, position_au, event_time)
    ↓
Calculate delay: distance(position_au, Earth) × 499 s/AU
    ↓
Queue in pending_orders: fires_at = T + delay
    ↓
[Time passes...]
    ↓
process_pending_orders() → delay elapsed
    ↓
_deliver_warning() called
    ↓
Check for duplicates (base message)
    ↓
Create warning with timestamp prefix
    ↓
If critical + auto_pause enabled → TimeScale.set_speed(1.0)
    ↓
Emit warning_added signal → UI updates
```

### Violation Flow

```
Combat occurs at position P at time T
    ↓
_queue_violation(colony, reason, position_au)
    ↓
Calculate delay: distance(position_au, colony) × 499 s/AU
    ↓
Queue in pending_orders: fires_at = T + delay
    ↓
[Time passes... colony learns of event]
    ↓
colony.add_violation(reason, event_time)
    ↓
Add to colony.violations array
    ↓
Check threshold (1, 2, 3, 4)
    ↓
If threshold met → add_warning() with colony→Earth delay
    ↓
Player receives violation warning
```

## Data Model

### Warning Structure
```gdscript
{
    "id": "warning_123",
    "message": "[D1 12:34] [+5m delay] ⚔️ COMBAT: ...",
    "severity": "critical",  # "warning" or "critical"
    "category": "combat"     # "combat", "criminal", "crew", "breakdown", etc.
}
```

### Violation Structure
```gdscript
{
    "timestamp": 123456.0,  # Game ticks when violation occurred
    "reason": "unprovoked_attack"
}
```

### Pending Order Structure
```gdscript
{
    "fires_at": 123456.0,       # Game ticks when order executes
    "ship": Ship or null,       # Ship (for orders) or null (for warnings/violations)
    "label": "warning_delivery", # "warning_delivery" or "violation_report"
    "fn": Callable              # Function to call when order fires
}
```

## Testing Timeline Accuracy

### Example Test Scenario

```
Setup:
- Your ship at Jupiter (5 AU from Earth)
- Lunar Base at Moon (0.0026 AU from Earth)
- Ship attacks rival at Jupiter

Expected Timeline:
T+0s:     Combat happens (5 AU from Earth, 5 AU from Moon)
T+2490s:  Combat warning arrives at Earth (5 AU × 499s)
          "[D1 12:00] [+41m delay] ⚔️ COMBAT: [YOUR] Ship vs [Rival] Ship"

T+2495s:  Lunar Base learns of combat (5 AU × 499s)
T+2496s:  Violation warning arrives at Earth (5 AU → Moon, Moon → Earth)
          "[D1 12:41] [+41m delay] ⚠️ VIOLATION - Lunar Base: ..."

Result: Combat message arrives FIRST (41m delay)
        Violation arrives 6s later (41m41s total)
```

### Debugging

Enable detailed logging:
```gdscript
# In add_warning():
print("Warning queued: %s | Delay: %.1fs | Event time: %s" %
      [message, delay, _format_game_time(event_time)])

# In _deliver_warning():
print("Warning delivered: %s | Now: %s" %
      [final_message, _format_game_time(GameState.total_ticks)])
```

## Future Enhancements

### Planned Features
- **Message Compression:** Batch similar warnings ("3 combat events at Jupiter")
- **Warning Categories Filter:** Hide/show specific event types
- **Audio Alerts:** Different sounds for different severity levels
- **Notification History:** Scrollable log of all past warnings
- **Priority Queue:** Critical warnings always appear first

### Multiplayer Considerations
When multiplayer is added:
- **Player-to-Player Messages:** Subject to lightspeed delay
- **Market Updates:** Delayed based on exchange location
- **News Broadcasts:** Propagate at lightspeed from origin
- **Faction Alerts:** Coordinated warnings from allied players (delayed)

## See Also

- **MOBILE_NOTIFICATIONS.md** - Mobile push notification plugin implementation
- **GDD.md** - Game design document with realistic physics requirements
- **LORE.md** - In-universe explanation of communication systems
