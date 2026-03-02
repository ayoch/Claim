# Account Deletion & Asset Reclamation System

## Current State Analysis

### Existing Foreign Key Cascades
- **Ships:** `player_id ForeignKey(..., ondelete="CASCADE")` → **Deleted with player**
- **Workers:** `player_id ForeignKey(..., ondelete="CASCADE")` → **Deleted with player**
- **Missions:** `player_id ForeignKey(..., ondelete="CASCADE")` → **Deleted with player**

### Problem
Simple CASCADE delete is wasteful:
- Destroys valuable ships and equipment
- Removes skilled workers from the economy
- Creates no gameplay opportunities
- Makes the world feel empty/static

---

## Recommended Approach: Asset Reclamation

Make banned/deleted player assets available to other players instead of destroying them.

### What Happens to Each Asset Type

#### 1. Ships → Derelict Salvage Opportunities
**Current:** Deleted
**New:** Mark as derelict, set owner to NULL

```python
# Convert to derelict salvage
ship.player_id = None
ship.is_derelict = True
ship.derelict_reason = "Abandoned - owner account deleted"
ship.crew = []  # Remove all crew
ship.current_mission = None  # Cancel missions
```

**Gameplay Effect:**
- Ships become salvageable by any player
- Adds interesting "ghost ship" encounters
- Rewards active players with free ships/equipment
- Creates emergent storylines ("Found a derelict hauler full of platinum!")

#### 2. Workers → Free Agents
**Current:** Deleted
**New:** Return to hiring pool at last location

```python
# Make worker available for hire
worker.player_id = None
worker.ship_id = None
worker.is_available = True
worker.loyalty = 50.0  # Neutral loyalty
# Keep skills, experience, personality
```

**Gameplay Effect:**
- Skilled workers re-enter job market
- Creates "veteran worker" opportunities
- Maintains worker population size
- Preserves progression (high-skill workers don't vanish)

#### 3. Equipment → Stays With Ships
**Current:** Deleted
**New:** Remains equipped on derelict ships

```python
# Equipment stays with ship, can be salvaged
ship.equipment  # Unchanged - comes with the derelict
```

**Gameplay Effect:**
- Incentivizes salvage missions
- Valuable equipment becomes prizes
- Creates risk/reward scenarios

#### 4. Missions → Immediate Cancellation
**Current:** Deleted
**New:** Complete or cancel gracefully

```python
# Cancel active missions
mission.status = "CANCELLED"
mission.end_time = now()
# Ships stop mid-journey, become stationary derelicts
```

#### 5. Money & Resources → Forfeit
**Current:** Deleted
**New:** Gone (or auction to other players?)

```python
# Money is lost
player.money  # Not transferred anywhere

# Alternative: Bankruptcy auction
create_bankruptcy_auction(player.money, player.cargo)
```

#### 6. Colonies (if player-owned) → Revert to NPC
**Current:** Not implemented
**New:** Return to neutral/NPC ownership

```python
if colony.owner_id == deleted_player_id:
    colony.owner_id = None
    colony.tier = max(1, colony.tier - 1)  # Downgrade slightly
```

---

## Implementation Options

### Option 1: CASCADE DELETE (Current - Simple but Wasteful)
**Pros:**
- Already implemented
- Fast and clean
- No orphaned records

**Cons:**
- Destroys valuable assets
- Reduces economy size
- No gameplay opportunities
- World feels static

### Option 2: SOFT DELETE (Mark as deleted, keep data)
**Pros:**
- Can restore accounts
- Keep analytics data
- Reversible

**Cons:**
- Clutters database
- Assets stay locked
- Doesn't free up resources

### Option 3: ASSET RECLAMATION (Recommended)
**Pros:**
- Creates gameplay opportunities
- Maintains economy size
- Rewards active players
- Dynamic world
- Emergent storytelling

**Cons:**
- More complex implementation
- Need to handle edge cases
- Potential for exploitation (player deletes account, friend takes ships)

---

## Recommended Implementation

### Step 1: Add `delete_player_and_reclaim_assets()` Function

```python
async def delete_player_and_reclaim_assets(
    db: AsyncSession,
    player_id: int,
    reason: str = "Account deleted"
) -> dict:
    """
    Delete player account and reclaim assets for other players.

    Returns:
        dict: Summary of what was reclaimed
            {
                "ships_reclaimed": 3,
                "workers_freed": 12,
                "equipment_salvageable": 25,
                "money_forfeited": 15_000_000
            }
    """
    player = await db.get(Player, player_id)
    if not player:
        return {"error": "Player not found"}

    summary = {
        "player_id": player_id,
        "username": player.username,
        "reason": reason,
        "ships_reclaimed": 0,
        "workers_freed": 0,
        "equipment_salvageable": 0,
        "money_forfeited": player.money
    }

    # 1. Reclaim ships as derelicts
    ships = await db.execute(
        select(Ship).where(Ship.player_id == player_id)
    )
    for ship in ships.scalars():
        ship.player_id = None
        ship.is_derelict = True
        ship.derelict_reason = f"Abandoned: {reason}"
        ship.crew = []
        summary["ships_reclaimed"] += 1
        summary["equipment_salvageable"] += len(ship.equipment or [])

    # 2. Free workers to hiring pool
    workers = await db.execute(
        select(Worker).where(Worker.player_id == player_id)
    )
    for worker in workers.scalars():
        worker.player_id = None
        worker.ship_id = None
        worker.is_available = True
        worker.loyalty = 50.0  # Neutral
        summary["workers_freed"] += 1

    # 3. Cancel missions
    missions = await db.execute(
        select(Mission).where(Mission.player_id == player_id)
    )
    for mission in missions.scalars():
        mission.status = "CANCELLED"

    # 4. Delete player (CASCADE will handle remaining references)
    await db.delete(player)
    await db.commit()

    return summary
```

### Step 2: Add Admin Endpoint

```python
@router.delete("/admin/players/{player_id}", dependencies=[Depends(require_admin)])
async def delete_player_account(
    player_id: int,
    reason: str = "Admin action",
    db: AsyncSession = Depends(get_db)
):
    """Delete player account and reclaim assets."""
    summary = await delete_player_and_reclaim_assets(db, player_id, reason)
    return summary
```

### Step 3: Add Inactive Player Cleanup

```python
async def cleanup_inactive_players(db: AsyncSession, days_inactive: int = 90):
    """
    Delete players who haven't logged in for X days.
    Reclaim their assets for active players.
    """
    cutoff = datetime.now(timezone.utc) - timedelta(days=days_inactive)

    inactive = await db.execute(
        select(Player).where(Player.last_seen < cutoff)
    )

    results = []
    for player in inactive.scalars():
        summary = await delete_player_and_reclaim_assets(
            db,
            player.id,
            f"Inactive for {days_inactive} days"
        )
        results.append(summary)

    return results
```

---

## Database Changes Needed

### Option A: Keep CASCADE, Handle Manually (Simpler)
No schema changes needed. Before deleting player, manually update ships/workers.

**Pros:** No migration needed
**Cons:** Easy to forget, error-prone

### Option B: Change to SET NULL (Cleaner)
Change foreign key cascade behavior:

```python
# ship.py
player_id: Mapped[int | None] = mapped_column(
    Integer,
    ForeignKey("players.id", ondelete="SET NULL"),
    nullable=True,  # Changed from False
    index=True
)

# worker.py
player_id: Mapped[int | None] = mapped_column(
    Integer,
    ForeignKey("players.id", ondelete="SET NULL"),
    nullable=True,  # Changed from False
    index=True
)
```

**Migration:**
```python
def upgrade():
    # Make player_id nullable
    with op.batch_alter_table('ships') as batch_op:
        batch_op.alter_column('player_id', nullable=True)

    with op.batch_alter_table('workers') as batch_op:
        batch_op.alter_column('player_id', nullable=True)

    # Drop CASCADE constraint, add SET NULL
    op.drop_constraint('fk_ships_player_id', 'ships')
    op.create_foreign_key(
        'fk_ships_player_id',
        'ships', 'players',
        ['player_id'], ['id'],
        ondelete='SET NULL'
    )

    # Same for workers...
```

**Pros:** Automatic, can't forget
**Cons:** Requires migration, changes schema

---

## Anti-Abuse Measures

### Problem: Player Deletes Account, Friend Takes Ships
**Solution:** Cooling-off period for reclaimed assets

```python
# Add to Ship model
reclaimed_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
available_for_salvage_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)

# When player deleted
ship.reclaimed_at = now()
ship.available_for_salvage_at = now() + timedelta(days=7)  # 7-day wait

# Can't be salvaged until cooldown expires
if ship.available_for_salvage_at > now():
    return {"error": "Ship in quarantine - available in X days"}
```

### Problem: Mass Account Creation for Ship Farming
**Solution:** Only reclaim assets from accounts that played legitimately

```python
# Only reclaim if account met minimum criteria
if player.created_at + timedelta(days=7) < now() and player.money < 50_000_000:
    # Too new or too poor = delete everything (likely bot/farm account)
    DELETE CASCADE
else:
    # Legitimate player = reclaim assets
    RECLAIM ASSETS
```

---

## Testing Plan

### Test 1: Delete Player with Ships
1. Create player with 3 ships
2. Delete player account
3. **Expected:** 3 derelict ships appear, can be salvaged

### Test 2: Delete Player with Workers
1. Create player with skilled workers
2. Delete player account
3. **Expected:** Workers available in hiring pool at last location

### Test 3: Delete Mid-Mission
1. Player has ship on active mission to asteroid
2. Delete player account
3. **Expected:** Mission cancelled, ship becomes derelict at current position

### Test 4: Cooling-off Period
1. Delete player account
2. Try to salvage ship immediately
3. **Expected:** Error - "Ship in quarantine for X days"

### Test 5: Inactive Cleanup
1. Create player, don't log in for 90+ days
2. Run cleanup job
3. **Expected:** Account deleted, assets reclaimed

---

## UI/UX Considerations

### Discovery
How do players find reclaimed assets?

**Ships:**
- Appear as "derelict contacts" on solar map
- Show up in observation/scanner system
- "Unknown derelict detected" notifications

**Workers:**
- Filter in hiring UI: "Veterans" (previously employed)
- Show experience/skills prominently
- Badge: "🎖️ Veteran" or "Former Employee"

### Salvage Mechanics
**Ships:**
- Must travel to derelict location
- "Claim Derelict" action (instant or requires time?)
- Repair costs based on condition
- Keep equipped gear

**Workers:**
- Standard hiring process
- May have higher wages (experienced)
- Loyalty starts at 50 (neutral)

---

## Admin Tools Needed

### Delete Account Interface
```
Admin Panel → Players → [Select Player] → Delete Account

Options:
- Reason: [Dropdown: Banned - Cheating | Inactive | User Request | Other]
- Reclaim Assets: [X] Yes  [ ] No (full delete)
- Notify Player: [X] Send email notification
- Cooling Period: [7] days before assets available

[Delete Account]  [Cancel]
```

### Cleanup Job
```bash
# Manual run
python -m server.admin cleanup_inactive --days 90 --dry-run

# Cron job (every week)
0 0 * * 0 python -m server.admin cleanup_inactive --days 90
```

---

## Recommended Next Steps

1. **Immediate:** Implement Option 3A (manual reclaim, no migration)
   - Add `delete_player_and_reclaim_assets()` function
   - Add admin endpoint
   - Test with dev accounts

2. **Short-term:** Add cooling-off period (anti-abuse)
   - Add reclaimed_at timestamps
   - Enforce 7-day quarantine

3. **Medium-term:** Add discovery mechanics
   - Derelict ship scanner alerts
   - Veteran worker badges in hiring UI

4. **Long-term:** Migrate to SET NULL cascade (cleaner architecture)
   - Database migration
   - Update all queries to handle NULL player_id

---

## Cost/Benefit Analysis

**Development Time:**
- Option 1 (CASCADE): 0 hours (already implemented)
- Option 2 (Soft Delete): 2-4 hours
- Option 3A (Reclaim, manual): 4-6 hours
- Option 3B (Reclaim, SET NULL): 8-10 hours

**Gameplay Value:**
- Option 1: Low (assets disappear, world shrinks)
- Option 2: None (assets locked forever)
- Option 3: **High** (dynamic economy, emergent gameplay, salvage opportunities)

**Recommendation:** Start with Option 3A (manual reclaim), migrate to 3B later.

---

## Questions?

**Q: What if salvage creates inflation?**
A: Derelict ships require repair costs. Can also add "salvage fee" to claim ownership.

**Q: Should workers remember their old employer?**
A: Interesting! Could add flavor text: "Used to work for [deleted corp]"

**Q: What about player-to-player debts/contracts?**
A: Cancel all contracts, debts forgiven (or transferred to NPC debt collector?)

**Q: Can we restore deleted accounts?**
A: With Option 3A: No, assets are reclaimed. With Option 2: Yes, if within X days.

**Q: Should we notify other players when assets become available?**
A: Yes! System message: "Derelict ship detected in asteroid belt" creates content.
