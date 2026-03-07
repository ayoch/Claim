# How to Spawn Available Workers

## Problem
The server database has no available workers for hire. The `/game/available-workers` endpoint returns an empty array because there are no workers with `player_id = NULL` in the database.

## Solution
I've added a new admin endpoint: `POST /admin/spawn-workers`

## Steps to Spawn Workers

### Option 1: Using curl (Terminal)

Wait ~2 minutes for Railway deployment to complete, then run:

```bash
curl -X POST "https://claim-production-066b.up.railway.app/admin/spawn-workers?count=10" \
  -H "X-Admin-Key: YOUR_ADMIN_KEY_HERE" \
  -H "Content-Type: application/json"
```

Replace `YOUR_ADMIN_KEY_HERE` with the actual admin key from Railway environment variables.

### Option 2: Using the spawn_workers.sh script

1. Edit `spawn_workers.sh` and replace `your-admin-key-here` with the actual admin key
2. Run: `./spawn_workers.sh`

### Option 3: Find the admin key

Check Railway dashboard → Your Project → Variables → `ADMIN_KEY`

## Expected Result

The endpoint will create 10 random workers with:
- Random skills (pilot, engineer, mining)
- Wages based on total skill ($80-200)
- Random personalities
- Random home colonies
- **player_id = NULL** (available for hire)

After spawning, the "New Candidates" button in the Workers tab will fetch these workers from the server.

## Verification

After running the spawn command, in the game:
1. Click "New Candidates" button in Workers tab
2. You should see 10 workers available for hire
3. Click "Hire" on a worker - it should work now!

## What Was Fixed

- Added `/admin/spawn-workers` endpoint to server
- Fixed workers_tab to fetch candidates from server in SERVER mode
- Fixed hire button to call server API in SERVER mode
- All type inference errors fixed (game now compiles without warnings)
