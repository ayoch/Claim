# Claim Server

FastAPI-based simulation server for the Claim space mining game.

## Requirements

- Python 3.11+ — download from https://www.python.org/downloads/ (check "Add to PATH")
- PostgreSQL 14+ — download from https://www.postgresql.org/download/

## Windows First-Time Setup

```powershell
# Install Python from python.org (must check "Add to PATH" during install)
# Then from PowerShell or cmd:
python --version  # should say 3.11+

# Install PostgreSQL from postgresql.org
# Then create the DB:
psql -U postgres -c "CREATE DATABASE claim_dev;"
psql -U postgres -c "CREATE USER claim WITH PASSWORD 'claim';"
psql -U postgres -c "GRANT ALL ON DATABASE claim_dev TO claim;"
```

## Setup

```bash
# 1. Create and activate a virtual environment
python -m venv .venv
# Windows:
.venv\Scripts\activate
# Linux/macOS:
source .venv/bin/activate

# 2. Install dependencies
pip install -r requirements.txt

# 3. Create the database
createdb claim_dev
# Or via psql:
# psql -U postgres -c "CREATE DATABASE claim_dev;"
# psql -U postgres -c "CREATE USER claim WITH PASSWORD 'claim';"
# psql -U postgres -c "GRANT ALL ON DATABASE claim_dev TO claim;"

# 4. Copy environment config
cp .env.example .env
# Edit .env if your DB credentials differ

# 5. Run migrations (or let the server auto-create tables)
alembic upgrade head

# 6. Start the server
uvicorn server.main:app --reload
```

## First Run

```bash
# Seed asteroids + colonies (idempotent, safe to re-run)
curl -X POST http://localhost:8000/admin/seed

# Register a player account
curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d "{\"username\": \"player1\", \"password\": \"test\"}"

# Login and get JWT token
curl -X POST http://localhost:8000/auth/login \
  -F "username=player1" \
  -F "password=test"

# Use the token
export TOKEN="<paste token here>"

# Get game state
curl http://localhost:8000/game/state \
  -H "Authorization: Bearer $TOKEN"

# Give starter ship + workers
curl -X POST "http://localhost:8000/admin/give-starter-pack/1"

# Dispatch ship to an asteroid
curl -X POST http://localhost:8000/game/dispatch \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"ship_id\": 1, \"mission_type\": 0, \"asteroid_id\": 1, \"mining_duration\": 3600}"
```

Or just run the standalone seed script which does everything at once:

```bash
python seed.py
```

## API Reference

- **Swagger UI**: http://localhost:8000/docs
- **ReDoc**: http://localhost:8000/redoc

### Auth endpoints
| Method | Path | Description |
|--------|------|-------------|
| POST | /auth/register | Create account |
| POST | /auth/login | Get JWT token (form data) |
| GET  | /auth/me | Current player info |

### Game endpoints
| Method | Path | Description |
|--------|------|-------------|
| GET  | /game/state | Full game state |
| GET  | /game/asteroids | List all asteroids |
| GET  | /game/colonies | List all colonies |
| GET  | /game/market | Current ore prices |
| POST | /game/dispatch | Dispatch ship on mission |
| POST | /game/hire | Hire a worker |
| POST | /game/fire/{id} | Fire a worker |
| POST | /game/buy-ship | Purchase a ship |
| POST | /game/policies | Update company policies |

### Events
| Method | Path | Description |
|--------|------|-------------|
| GET  | /events/stream | SSE stream (auth required) |

Event types emitted:
- `connected` — on SSE connection
- `mission_arrived` — ship reached destination
- `mission_mining_complete` — mining phase done
- `mission_completed` — ship returned with cargo
- `mission_status_changed` — any status transition
- `market_update` — ore price change (>0.5% move)
- `payroll_deducted` — daily wages deducted

### Admin endpoints
| Method | Path | Description |
|--------|------|-------------|
| GET  | /admin/status | Server status + tick count |
| POST | /admin/seed | Seed asteroids + colonies |
| POST | /admin/give-starter-pack/{player_id} | Give starter ship + workers |

## Architecture

```
server/
  main.py           — FastAPI app, startup/shutdown hooks
  config.py         — Pydantic settings (reads .env)
  database.py       — SQLAlchemy async engine + session factory
  auth.py           — JWT + bcrypt utilities, get_current_player dep
  models/           — SQLAlchemy ORM models
    player.py
    ship.py
    worker.py
    mission.py
    asteroid.py
    colony.py
  schemas/          — Pydantic request/response schemas
    player.py
    game.py
  routers/          — FastAPI routers
    auth.py
    game.py
    events.py
    admin.py
  simulation/       — Background simulation
    tick.py         — Core tick processor (missions, market, payroll)
    runner.py       — asyncio task loop
    event_bus.py    — In-memory pub/sub for SSE
```

## Simulation

The simulation runs as a background asyncio task at 1 real second = 1 game second (1x speed).

Each tick:
1. **Missions** — advance elapsed time; transition TRANSIT_OUT -> MINING -> TRANSIT_BACK -> COMPLETED
2. **Market** — random-walk ore prices (±0.1%/tick, clamped to ±40% of base)
3. **Payroll** — deduct daily wages once per 86,400 ticks

Speed can be changed by setting `TICK_INTERVAL` in `.env` (e.g., `0.1` = 10x speed).

## Database Migrations

```bash
# Create a new migration after changing models
alembic revision --autogenerate -m "describe your change"

# Apply migrations
alembic upgrade head

# Rollback one step
alembic downgrade -1
```
