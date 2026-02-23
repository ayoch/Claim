# Local Testing Checklist

## Prerequisites

Before starting, ensure you have:
- [ ] PostgreSQL running locally
- [ ] Python 3.11+ installed
- [ ] Virtual environment activated

## Setup Steps

```bash
# 1. Create database
psql -U postgres -c "CREATE DATABASE claim_dev;"
psql -U postgres -c "CREATE USER claim WITH PASSWORD 'claim';"
psql -U postgres -c "GRANT ALL ON DATABASE claim_dev TO claim;"

# 2. Install dependencies
cd server
python -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt

# 3. Configure environment
cp .env.example .env
# Edit .env if needed (default settings should work)

# 4. Start server
uvicorn server.main:app --reload
```

Server should start on http://localhost:8000

## Automated Testing

Run the test suite:
```bash
python test_local.py
```

This tests all core functionality automatically. If all tests pass, you're good!

## Manual Testing

### 1. Basic Connectivity

- [ ] Open http://localhost:8000 in browser → should see JSON welcome
- [ ] Open http://localhost:8000/docs → Swagger UI should load
- [ ] Click "Try it out" on `/health` → should return `{"status": "ok"}`

### 2. Database Seeding

```bash
curl -X POST http://localhost:8000/admin/seed
```

- [ ] Should return `{"asteroids_created": 200+, "colonies_created": 10+}`
- [ ] No errors in server logs

### 3. Authentication

**Register:**
```bash
curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "testplayer", "password": "TestPass123"}'
```

- [ ] Returns 201 with player ID
- [ ] Server logs show registration

**Register with weak password (should fail):**
```bash
curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "testplayer2", "password": "weak"}'
```

- [ ] Returns 422 validation error (password requirements not met)

**Login:**
```bash
curl -X POST http://localhost:8000/auth/login \
  -F "username=testplayer" \
  -F "password=TestPass123"
```

- [ ] Returns 200 with `access_token` and `token_type: "bearer"`
- [ ] Copy token for next steps

**Set token as variable:**
```bash
export TOKEN="<paste-token-here>"
```

### 4. Game State

```bash
curl http://localhost:8000/game/state \
  -H "Authorization: Bearer $TOKEN"
```

- [ ] Returns full game state with money, ships, workers, missions
- [ ] Initial money should be $10,000
- [ ] Ships and workers should be empty arrays

### 5. Starter Pack

```bash
curl -X POST http://localhost:8000/admin/give-starter-pack/1 \
  -H "Authorization: Bearer $TOKEN"
```

- [ ] Returns ship + 3 workers
- [ ] Ship has name, cargo capacity, fuel capacity
- [ ] Workers have skills (pilot_skill, engineer_skill, mining_skill)
- [ ] Workers have XP fields (pilot_xp, engineer_xp, mining_xp) all at 0.0

### 6. Mission Dispatch

**Get asteroid list:**
```bash
curl http://localhost:8000/game/asteroids \
  -H "Authorization: Bearer $TOKEN"
```

- [ ] Returns list of asteroids with name, semi_major_axis, eccentricity, ore_yield

**Dispatch mission:**
```bash
curl -X POST http://localhost:8000/game/dispatch \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "ship_id": 1,
    "mission_type": 0,
    "asteroid_id": 1,
    "mining_duration": 3600
  }'
```

- [ ] Returns 201 with mission ID
- [ ] Mission has status 0 (TRANSIT_OUT)
- [ ] Has departure_time, arrival_time, completion_time

### 7. Simulation Tick

**Check admin status:**
```bash
curl http://localhost:8000/admin/status
```

- [ ] Returns tick count and active missions
- [ ] Wait 5 seconds, run again
- [ ] Tick count should have increased by ~5 (at 1x speed)

**Check mission progress:**
```bash
curl http://localhost:8000/game/state \
  -H "Authorization: Bearer $TOKEN"
```

- [ ] Mission `elapsed_time` should be increasing
- [ ] Eventually mission status will change (TRANSIT_OUT → MINING → TRANSIT_RETURN → COMPLETED)

### 8. Worker Hiring

**Get colonies:**
```bash
curl http://localhost:8000/game/colonies \
  -H "Authorization: Bearer $TOKEN"
```

- [ ] Returns list of colonies with name, population, coordinates

**Hire worker:**
```bash
curl -X POST http://localhost:8000/game/hire \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"colony_id": 1}'
```

- [ ] Returns 201 with new worker
- [ ] Worker has randomized skills
- [ ] Money deducted ($200 sign-on bonus)

### 9. Ship Purchasing

```bash
curl -X POST http://localhost:8000/game/buy-ship \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "ship_class": 0,
    "ship_name": "My Second Ship",
    "colony_id": 1
  }'
```

- [ ] If sufficient funds: returns 201 with new ship
- [ ] If insufficient funds: returns 400 with error message
- [ ] Money deducted correctly

### 10. Worker Firing

```bash
curl -X POST http://localhost:8000/game/fire/2 \
  -H "Authorization: Bearer $TOKEN"
```

- [ ] Returns 200 success
- [ ] Worker removed from game state

### 11. Rate Limiting

**Test login rate limit (10/minute):**
```bash
for i in {1..12}; do
  curl -X POST http://localhost:8000/auth/login \
    -F "username=testplayer" \
    -F "password=wrong" &
done
wait
```

- [ ] First 10 requests return 401 (wrong password)
- [ ] Requests 11-12 return 429 (rate limit exceeded)
- [ ] Rate limit error includes `retry_after` field

### 12. SSE Events (Optional)

Open in browser or use curl:
```bash
curl -N http://localhost:8000/events/stream \
  -H "Authorization: Bearer $TOKEN"
```

- [ ] Immediately receives `connected` event
- [ ] While mission is active, receives `mission_status_changed` events
- [ ] When mission completes, receives `mission_completed` event
- [ ] When payroll fires (every 86,400 ticks), receives `payroll_deducted` event
- [ ] When market changes >0.5%, receives `market_update` event

### 13. Worker Skill Progression (Long-term)

To test XP accumulation, you need to either:
- Wait for a full mission cycle (may take hours at 1x speed)
- OR temporarily increase `TICK_INTERVAL` to 0.01 in `.env` (100x speed)

With accelerated time:
- [ ] Dispatch mission with crew
- [ ] Wait a few minutes
- [ ] Check game state: workers should have non-zero XP in relevant skills
- [ ] Eventually worker skills should level up (0.05 increments)
- [ ] When skill levels up, SSE emits `worker_skill_leveled` event
- [ ] Worker wage increases after skill-up

## Common Issues

**"Connection refused"**
- Server not running. Start with `uvicorn server.main:app --reload`

**"No module named 'server'"**
- Run from `server/` directory, or ensure PYTHONPATH is set

**"Password too weak"**
- Password must be 8+ characters with uppercase, lowercase, and number

**"Rate limit exceeded"**
- Wait 1 minute, or restart server to reset limits

**"Insufficient funds"**
- Use admin endpoints to give money: `curl -X POST http://localhost:8000/admin/give-money/1?amount=100000`

**Database errors**
- Drop and recreate database: `dropdb claim_dev && createdb claim_dev`
- Restart server (tables auto-create)

## Success Criteria

You're ready to proceed when:
- [x] All automated tests pass (`python test_local.py`)
- [x] Can register, login, get game state
- [x] Can dispatch missions and they progress over time
- [x] Can hire workers, buy ships, fire workers
- [x] Rate limiting works correctly
- [x] SSE events stream correctly
- [x] No errors in server logs
- [x] Worker XP accumulates during activities (test at high speed)

Once all checks pass, the server is ready for production hardening and deployment!
