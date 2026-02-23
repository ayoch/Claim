# Production Hardening Implementation Plan

**Target:** Make server production-ready before launch
**Priority:** Critical fixes first, then important, then nice-to-have
**Timeline:** 2-3 weeks

---

## Phase 1: Critical Fixes (Week 1)

### Task 1.1: Add Rate Limiting

**Goal:** Prevent request spam and DoS attacks

**Steps:**

1. **Install dependency:**
```bash
pip install slowapi
pip freeze > requirements.txt
```

2. **Create rate limiter setup** (`server/rate_limit.py`):
```python
from slowapi import Limiter
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded
from fastapi import Request, Response
from fastapi.responses import JSONResponse

limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["100/minute"],  # Global default
    storage_uri="memory://",  # Use Redis in production
)

async def rate_limit_handler(request: Request, exc: RateLimitExceeded) -> Response:
    return JSONResponse(
        status_code=429,
        content={
            "error": "Too many requests",
            "detail": "Rate limit exceeded. Please try again later."
        }
    )
```

3. **Update main.py:**
```python
from server.rate_limit import limiter, rate_limit_handler
from slowapi.errors import RateLimitExceeded

app = FastAPI(...)
app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, rate_limit_handler)
```

4. **Add limits to sensitive endpoints** (`routers/game.py`):
```python
from server.rate_limit import limiter

@router.post("/dispatch")
@limiter.limit("20/minute")  # 20 dispatches per minute per IP
async def dispatch(...):
    ...

@router.post("/hire")
@limiter.limit("10/minute")
async def hire(...):
    ...

@router.post("/buy-ship")
@limiter.limit("5/minute")
async def buy_ship(...):
    ...
```

5. **Add limits to auth endpoints** (`routers/auth.py`):
```python
@router.post("/register")
@limiter.limit("5/hour")  # Stricter for account creation
async def register(...):
    ...

@router.post("/login")
@limiter.limit("10/minute")  # Prevent brute force
async def login(...):
    ...
```

**Testing:**
```bash
# Test rate limit by making 25 rapid requests
for i in {1..25}; do
  curl -X POST http://localhost:8000/game/dispatch \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"ship_id": 1, "asteroid_id": 1}' &
done
# Should see 429 errors after 20 requests
```

**Production note:** Replace `storage_uri="memory://"` with Redis:
```python
limiter = Limiter(
    key_func=get_remote_address,
    storage_uri="redis://localhost:6379",
)
```

---

### Task 1.2: Input Validation

**Goal:** Prevent invalid/malicious input from corrupting game state

**Steps:**

1. **Update schemas** (`server/schemas/game.py`):

```python
from pydantic import BaseModel, Field, field_validator
from typing import Literal

class DispatchRequest(BaseModel):
    ship_id: int = Field(gt=0, description="Ship ID must be positive")
    asteroid_id: int = Field(gt=0, description="Asteroid ID must be positive")
    mission_type: int = Field(ge=0, le=3, description="Mission type 0-3")
    mining_duration: float = Field(
        ge=3600.0,      # Min 1 hour
        le=604800.0,    # Max 7 game-days
        description="Mining duration in game-seconds"
    )

    @field_validator('mining_duration')
    @classmethod
    def reasonable_duration(cls, v: float) -> float:
        # Additional business logic validation
        if v > 86400.0 * 14:  # 14 game-days
            raise ValueError('Mining duration too long (max 14 days)')
        return v

class HireRequest(BaseModel):
    count: int = Field(ge=1, le=10, description="Hire 1-10 workers at once")
    specialty: Literal["pilot", "engineer", "mining", "generalist"]
    max_wage: int = Field(ge=80, le=500, description="Max wage per worker")

class BuyShipRequest(BaseModel):
    ship_class: int = Field(ge=0, le=3, description="Ship class 0-3")
    ship_name: str = Field(min_length=1, max_length=64)

    @field_validator('ship_name')
    @classmethod
    def valid_name(cls, v: str) -> str:
        # No special characters that could break logging/display
        if not v.replace(' ', '').replace('-', '').isalnum():
            raise ValueError('Ship name must be alphanumeric')
        return v.strip()

class PolicyUpdate(BaseModel):
    thrust_policy: int = Field(ge=0, le=2)
    supply_policy: int = Field(ge=0, le=2)
    collection_policy: int = Field(ge=0, le=2)
    encounter_policy: int = Field(ge=0, le=3)
```

2. **Update auth schemas** (`server/schemas/player.py`):

```python
import re
from pydantic import BaseModel, Field, field_validator

class RegisterRequest(BaseModel):
    username: str = Field(min_length=3, max_length=32)
    password: str = Field(min_length=8, max_length=128)

    @field_validator('username')
    @classmethod
    def valid_username(cls, v: str) -> str:
        if not re.match(r'^[a-zA-Z0-9_-]+$', v):
            raise ValueError(
                'Username must contain only letters, numbers, hyphens, and underscores'
            )
        return v.lower()  # Normalize to lowercase

    @field_validator('password')
    @classmethod
    def strong_password(cls, v: str) -> str:
        if len(v) < 8:
            raise ValueError('Password must be at least 8 characters')
        if not re.search(r'[A-Z]', v):
            raise ValueError('Password must contain an uppercase letter')
        if not re.search(r'[a-z]', v):
            raise ValueError('Password must contain a lowercase letter')
        if not re.search(r'\d', v):
            raise ValueError('Password must contain a number')
        # Optional: check against common passwords list
        return v
```

3. **Add business logic validation** (`routers/game.py`):

```python
@router.post("/dispatch")
async def dispatch(req: DispatchRequest, ...):
    # Pydantic already validated types and ranges

    # Now validate business logic
    ship = await db.get(Ship, req.ship_id)
    if not ship:
        raise HTTPException(status_code=404, detail="Ship not found")
    if ship.player_id != player.id:
        raise HTTPException(status_code=403, detail="Ship belongs to another player")
    if not ship.is_stationed:
        raise HTTPException(status_code=409, detail="Ship is already on a mission")
    if ship.is_derelict:
        raise HTTPException(status_code=409, detail="Ship is derelict")
    if ship.fuel < 10.0:  # Need minimum fuel
        raise HTTPException(status_code=400, detail="Insufficient fuel")

    # Validate asteroid exists and is in range
    asteroid = await db.get(Asteroid, req.asteroid_id)
    if not asteroid:
        raise HTTPException(status_code=404, detail="Asteroid not found")

    distance = math.sqrt(
        (asteroid.position_x - ship.position_x)**2 +
        (asteroid.position_y - ship.position_y)**2
    )
    fuel_needed = distance * 100  # Simplified
    if fuel_needed > ship.fuel:
        raise HTTPException(
            status_code=400,
            detail=f"Insufficient fuel. Need {fuel_needed:.1f}, have {ship.fuel:.1f}"
        )

    # Continue with dispatch...
```

**Testing:**
```python
# Create test file: server/tests/test_validation.py
import pytest
from server.schemas.game import DispatchRequest, HireRequest
from pydantic import ValidationError

def test_dispatch_validation():
    # Valid
    req = DispatchRequest(
        ship_id=1,
        asteroid_id=5,
        mission_type=0,
        mining_duration=43200.0
    )
    assert req.ship_id == 1

    # Invalid - negative ID
    with pytest.raises(ValidationError):
        DispatchRequest(ship_id=-1, asteroid_id=5, mission_type=0, mining_duration=3600)

    # Invalid - duration too long
    with pytest.raises(ValidationError):
        DispatchRequest(ship_id=1, asteroid_id=5, mission_type=0, mining_duration=86400*30)

def test_password_validation():
    from server.schemas.player import RegisterRequest

    # Valid
    req = RegisterRequest(username="player1", password="SecurePass123")

    # Too short
    with pytest.raises(ValidationError):
        RegisterRequest(username="player1", password="short")

    # No uppercase
    with pytest.raises(ValidationError):
        RegisterRequest(username="player1", password="lowercase123")
```

Run tests:
```bash
pip install pytest pytest-asyncio
pytest server/tests/test_validation.py -v
```

---

### Task 1.3: Database Transactions

**Goal:** Ensure atomic operations, prevent data corruption

**Steps:**

1. **Create transaction decorator** (`server/database.py`):

```python
from functools import wraps
from typing import Callable
import logging

logger = logging.getLogger(__name__)

def transactional(func: Callable):
    """Decorator to wrap endpoint in explicit transaction with rollback on error."""
    @wraps(func)
    async def wrapper(*args, db: AsyncSession, **kwargs):
        try:
            async with db.begin():
                result = await func(*args, db=db, **kwargs)
                return result
        except Exception as e:
            logger.exception(f"Transaction failed in {func.__name__}: {e}")
            await db.rollback()
            raise
    return wrapper
```

2. **Apply to mutating endpoints** (`routers/game.py`):

```python
from server.database import transactional

@router.post("/dispatch")
@transactional
async def dispatch(
    req: DispatchRequest,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    # Transaction begins automatically via decorator
    ship = await db.get(Ship, req.ship_id)
    # ... validation ...

    # All these operations are atomic
    ship.is_stationed = False
    ship.fuel -= fuel_cost

    mission = Mission(
        player_id=player.id,
        ship_id=ship.id,
        asteroid_id=req.asteroid_id,
        status=STATUS_TRANSIT_OUT,
        # ...
    )
    db.add(mission)
    db.add(ship)

    # Commit happens automatically on success
    # Rollback happens automatically on exception
    return MissionOut.model_validate(mission)
```

3. **Alternative: Explicit transaction blocks** (for complex logic):

```python
@router.post("/buy-ship")
async def buy_ship(
    req: BuyShipRequest,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    stats = SHIP_CLASS_STATS[req.ship_class]
    cost = stats["base_price"]

    if player.money < cost:
        raise HTTPException(status_code=400, detail="Insufficient funds")

    # Explicit transaction for multiple operations
    async with db.begin():
        # Deduct money
        player.money -= cost
        db.add(player)

        # Create ship
        ship = Ship(
            player_id=player.id,
            ship_name=req.ship_name,
            ship_class=req.ship_class,
            **stats,
            fuel=stats["fuel_capacity"],
            is_stationed=True,
        )
        db.add(ship)

        # Log transaction
        from server.models.transaction import Transaction
        tx = Transaction(
            player_id=player.id,
            amount=-cost,
            description=f"Purchased {stats['class_name']}: {req.ship_name}",
        )
        db.add(tx)

        # All succeed or all fail together

    return ShipOut.model_validate(ship)
```

4. **Add to hire/fire workers:**

```python
@router.post("/hire")
async def hire_worker(
    req: HireRequest,
    player: Player = Depends(get_current_player),
    db: AsyncSession = Depends(get_db),
):
    total_cost = 0
    workers_to_add = []

    for _ in range(req.count):
        # Generate worker with requested specialty
        # ... worker generation logic ...
        total_cost += worker.wage
        workers_to_add.append(worker)

    if player.money < total_cost:
        raise HTTPException(status_code=400, detail="Insufficient funds")

    async with db.begin():
        player.money -= total_cost
        db.add(player)
        for worker in workers_to_add:
            db.add(worker)

    return [WorkerOut.model_validate(w) for w in workers_to_add]
```

**Testing:**
```python
# server/tests/test_transactions.py
import pytest
from sqlalchemy.exc import IntegrityError

@pytest.mark.asyncio
async def test_dispatch_rollback_on_error(async_session, test_player, test_ship):
    """Test that failed dispatch doesn't leave partial state."""
    initial_fuel = test_ship.fuel
    initial_stationed = test_ship.is_stationed

    # Mock an error during mission creation
    with pytest.raises(IntegrityError):
        async with async_session.begin():
            test_ship.is_stationed = False
            test_ship.fuel -= 50.0
            async_session.add(test_ship)

            # This should fail (invalid foreign key)
            mission = Mission(
                player_id=test_player.id,
                ship_id=test_ship.id,
                asteroid_id=999999,  # Doesn't exist
            )
            async_session.add(mission)

    # Verify ship state rolled back
    await async_session.refresh(test_ship)
    assert test_ship.fuel == initial_fuel
    assert test_ship.is_stationed == initial_stationed
```

---

### Task 1.4: Secrets Management

**Goal:** Remove secrets from version control, use environment variables

**Steps:**

1. **Update `.gitignore`:**
```bash
# Add to .gitignore
.env
.env.*
!.env.example
*.pem
*.key
```

2. **Create `.env.example` template:**
```bash
# .env.example - checked into git
DATABASE_URL=postgresql+asyncpg://user:password@localhost/claim_dev
SECRET_KEY=your-secret-key-here-min-32-chars
CORS_ORIGINS=http://localhost:3000,http://localhost:8080
TICK_INTERVAL=1.0
LOG_LEVEL=INFO
```

3. **Remove `.env` from git history:**
```bash
# If .env was already committed
git rm --cached server/.env
git commit -m "Remove .env from version control"

# Tell collaborators to create their own .env
echo "Copy .env.example to .env and update with your local values" > server/README_SETUP.md
```

4. **Update `config.py` for production:**
```python
from pydantic_settings import BaseSettings
from typing import List
import secrets

class Settings(BaseSettings):
    # Database
    DATABASE_URL: str = Field(
        default="postgresql+asyncpg://claim:claim@localhost/claim_dev",
        description="PostgreSQL connection string"
    )

    # Security
    SECRET_KEY: str = Field(
        default_factory=lambda: secrets.token_urlsafe(32),
        description="JWT signing key - MUST be set in production"
    )
    JWT_ALGORITHM: str = "HS256"
    JWT_EXPIRATION_MINUTES: int = 60 * 24 * 7  # 7 days

    # CORS
    CORS_ORIGINS: List[str] = Field(
        default=["http://localhost:3000"],
        description="Allowed CORS origins"
    )

    # Simulation
    TICK_INTERVAL: float = Field(
        default=1.0,
        ge=0.01,
        le=10.0,
        description="Seconds per game tick"
    )

    # Logging
    LOG_LEVEL: str = Field(
        default="INFO",
        description="Logging level: DEBUG, INFO, WARNING, ERROR"
    )

    class Config:
        env_file = ".env"
        case_sensitive = False

    def validate_production(self) -> None:
        """Call this on startup to ensure production settings are secure."""
        if self.SECRET_KEY == "change-me-in-production":
            raise ValueError("SECRET_KEY must be set to a secure random value in production")
        if len(self.SECRET_KEY) < 32:
            raise ValueError("SECRET_KEY must be at least 32 characters")
        if "*" in self.CORS_ORIGINS:
            raise ValueError("CORS_ORIGINS must not contain wildcard in production")

settings = Settings()
```

5. **Add startup validation** (`main.py`):
```python
import os

@app.on_event("startup")
async def on_startup():
    # Validate production settings
    if os.getenv("ENVIRONMENT") == "production":
        try:
            settings.validate_production()
        except ValueError as e:
            logger.error(f"Production validation failed: {e}")
            raise

    await init_db()
    # ...
```

6. **Production deployment with secrets:**

**Docker:**
```dockerfile
# Dockerfile
FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY server/ ./server/
CMD ["uvicorn", "server.main:app", "--host", "0.0.0.0", "--port", "8000"]
```

```yaml
# docker-compose.yml - secrets via environment
version: '3.8'
services:
  server:
    build: .
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - SECRET_KEY=${SECRET_KEY}
      - ENVIRONMENT=production
    env_file:
      - .env.production  # Not in git, created on server
```

**Kubernetes:**
```yaml
# k8s-secret.yaml (apply with kubectl)
apiVersion: v1
kind: Secret
metadata:
  name: claim-server-secrets
type: Opaque
stringData:
  database-url: "postgresql+asyncpg://..."
  secret-key: "..."  # Generated with: openssl rand -base64 32
```

**AWS:**
```python
# Use AWS Secrets Manager
import boto3
import json

def get_secret(secret_name):
    client = boto3.client('secretsmanager', region_name='us-east-1')
    response = client.get_secret_value(SecretId=secret_name)
    return json.loads(response['SecretString'])

# In config.py
if os.getenv("USE_AWS_SECRETS"):
    secrets = get_secret("claim-server-production")
    settings.SECRET_KEY = secrets['secret_key']
    settings.DATABASE_URL = secrets['database_url']
```

**Testing:**
```bash
# Local dev - use .env
cp .env.example .env
# Edit .env with local values
uvicorn server.main:app --reload

# Production - pass via environment
export DATABASE_URL="postgresql+asyncpg://..."
export SECRET_KEY=$(openssl rand -base64 32)
export ENVIRONMENT=production
uvicorn server.main:app --host 0.0.0.0
```

---

### Task 1.5: Database Indexes

**Goal:** Optimize query performance for common access patterns

**Steps:**

1. **Create migration** (if using Alembic):
```bash
cd server
alembic revision -m "add_performance_indexes"
```

2. **Edit migration file** (`alembic/versions/XXXX_add_performance_indexes.py`):
```python
"""add performance indexes

Revision ID: abc123
"""
from alembic import op

def upgrade():
    # Missions - frequently queried by player and status
    op.create_index(
        'ix_missions_player_status',
        'missions',
        ['player_id', 'status']
    )
    op.create_index(
        'ix_missions_ship',
        'missions',
        ['ship_id']
    )

    # Ships - queried by player, often filtered by stationed/derelict
    op.create_index(
        'ix_ships_player_stationed',
        'ships',
        ['player_id', 'is_stationed']
    )
    op.create_index(
        'ix_ships_player_derelict',
        'ships',
        ['player_id', 'is_derelict']
    )

    # Workers - queried by player and availability
    op.create_index(
        'ix_workers_player_available',
        'workers',
        ['player_id', 'is_available']
    )
    op.create_index(
        'ix_workers_ship',
        'workers',
        ['assigned_ship_id']
    )

    # Asteroids - spatial queries (if you add proximity search)
    op.create_index(
        'ix_asteroids_position',
        'asteroids',
        ['position_x', 'position_y']
    )

def downgrade():
    op.drop_index('ix_missions_player_status')
    op.drop_index('ix_missions_ship')
    op.drop_index('ix_ships_player_stationed')
    op.drop_index('ix_ships_player_derelict')
    op.drop_index('ix_workers_player_available')
    op.drop_index('ix_workers_ship')
    op.drop_index('ix_asteroids_position')
```

3. **Apply migration:**
```bash
alembic upgrade head
```

4. **Add indexes directly** (if not using Alembic):

Create `server/migrations/001_add_indexes.sql`:
```sql
-- Missions
CREATE INDEX IF NOT EXISTS ix_missions_player_status
    ON missions(player_id, status);
CREATE INDEX IF NOT EXISTS ix_missions_ship
    ON missions(ship_id);

-- Ships
CREATE INDEX IF NOT EXISTS ix_ships_player_stationed
    ON ships(player_id, is_stationed);
CREATE INDEX IF NOT EXISTS ix_ships_player_derelict
    ON ships(player_id, is_derelict);

-- Workers
CREATE INDEX IF NOT EXISTS ix_workers_player_available
    ON workers(player_id, is_available);
CREATE INDEX IF NOT EXISTS ix_workers_ship
    ON workers(assigned_ship_id);

-- Asteroids
CREATE INDEX IF NOT EXISTS ix_asteroids_position
    ON asteroids(position_x, position_y);
```

Apply:
```bash
psql -U claim -d claim_dev -f server/migrations/001_add_indexes.sql
```

5. **Verify indexes:**
```sql
-- Check indexes on missions table
\d+ missions

-- Analyze query performance
EXPLAIN ANALYZE
SELECT * FROM missions
WHERE player_id = 1 AND status IN (0, 1, 2);
-- Should show "Index Scan using ix_missions_player_status"
```

6. **Add composite indexes for common queries:**
```python
# If you frequently query "all active missions for player with their ships"
op.create_index(
    'ix_missions_active_with_ship',
    'missions',
    ['player_id', 'status', 'ship_id']
)

# If you query "available workers for a specific player"
op.create_index(
    'ix_workers_available_for_player',
    'workers',
    ['player_id', 'is_available', 'assigned_ship_id']
)
```

**Testing performance:**
```python
# server/tests/test_performance.py
import time
import pytest

@pytest.mark.asyncio
async def test_mission_query_performance(async_session, test_player):
    """Query should use index and complete quickly."""
    # Create 1000 missions
    for i in range(1000):
        mission = Mission(player_id=test_player.id, ...)
        async_session.add(mission)
    await async_session.commit()

    # Time the query
    start = time.time()
    result = await async_session.execute(
        select(Mission).where(
            Mission.player_id == test_player.id,
            Mission.status.in_([0, 1, 2])
        )
    )
    missions = list(result.scalars().all())
    elapsed = time.time() - start

    # Should complete in under 10ms with index
    assert elapsed < 0.01
    assert len(missions) > 0
```

---

## Phase 2: Important Fixes (Week 2)

### Task 2.1: CORS Configuration

Update `main.py`:
```python
from server.config import settings

app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS,  # No wildcards
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],  # Explicit methods
    allow_headers=["Authorization", "Content-Type"],  # Explicit headers
    max_age=3600,  # Cache preflight for 1 hour
)
```

---

### Task 2.2: Error Handling

Create `server/exceptions.py`:
```python
from fastapi import HTTPException, Request
from fastapi.responses import JSONResponse
from sqlalchemy.exc import SQLAlchemyError
import logging

logger = logging.getLogger(__name__)

async def sqlalchemy_exception_handler(request: Request, exc: SQLAlchemyError):
    """Don't leak database errors to client."""
    logger.exception(f"Database error on {request.method} {request.url.path}: {exc}")
    return JSONResponse(
        status_code=500,
        content={"error": "Internal server error", "detail": "A database error occurred"}
    )

async def validation_exception_handler(request: Request, exc: ValueError):
    """Return 400 for validation errors."""
    return JSONResponse(
        status_code=400,
        content={"error": "Validation error", "detail": str(exc)}
    )
```

Register in `main.py`:
```python
from server.exceptions import sqlalchemy_exception_handler, validation_exception_handler
from sqlalchemy.exc import SQLAlchemyError

app.add_exception_handler(SQLAlchemyError, sqlalchemy_exception_handler)
app.add_exception_handler(ValueError, validation_exception_handler)
```

---

### Task 2.3: Enhanced Health Check

Update health endpoint:
```python
from sqlalchemy import text

@app.get("/health")
async def health(db: AsyncSession = Depends(get_db)):
    try:
        # Check database
        await db.execute(text("SELECT 1"))

        # Check simulation is running
        from server.simulation.tick import get_total_ticks
        ticks = get_total_ticks()

        return {
            "status": "ok",
            "database": "connected",
            "simulation": "running",
            "total_ticks": ticks,
        }
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return JSONResponse(
            status_code=503,
            content={"status": "unhealthy", "error": str(e)}
        )
```

---

### Task 2.4: Request Logging

Create `server/middleware.py`:
```python
import time
import logging
from fastapi import Request
from starlette.middleware.base import BaseHTTPMiddleware

logger = logging.getLogger(__name__)

class RequestLoggingMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        start_time = time.time()

        # Process request
        response = await call_next(request)

        # Log completion
        duration = time.time() - start_time
        logger.info(
            f"{request.method} {request.url.path} "
            f"status={response.status_code} "
            f"duration={duration:.3f}s "
            f"client={request.client.host if request.client else 'unknown'}"
        )

        return response
```

Add to `main.py`:
```python
from server.middleware import RequestLoggingMiddleware

app.add_middleware(RequestLoggingMiddleware)
```

---

## Phase 3: Nice-to-Have (Week 3)

### Task 3.1: Prometheus Metrics

```bash
pip install prometheus-fastapi-instrumentator
```

```python
# main.py
from prometheus_fastapi_instrumentator import Instrumentator

@app.on_event("startup")
async def startup():
    Instrumentator().instrument(app).expose(app)
```

Metrics available at `/metrics`

---

### Task 3.2: Load Testing

Create `load_test.py` with Locust:
```python
from locust import HttpUser, task, between

class ClaimUser(HttpUser):
    wait_time = between(1, 3)

    def on_start(self):
        # Login
        response = self.client.post("/auth/login", data={
            "username": "test_user",
            "password": "test_pass"
        })
        self.token = response.json()["access_token"]

    @task(3)
    def get_state(self):
        self.client.get("/game/state", headers={
            "Authorization": f"Bearer {self.token}"
        })

    @task(1)
    def dispatch_mission(self):
        self.client.post("/game/dispatch", json={
            "ship_id": 1,
            "asteroid_id": 5,
            "mining_duration": 43200
        }, headers={
            "Authorization": f"Bearer {self.token}"
        })
```

Run:
```bash
locust -f load_test.py --host=http://localhost:8000
# Open http://localhost:8089, start with 100 users
```

---

## Verification Checklist

Before deploying to production:

- [ ] Rate limiting tested - verify 429 errors after limit
- [ ] Input validation tested - invalid requests return 400 with clear errors
- [ ] Transactions tested - failed operations don't leave partial state
- [ ] Secrets removed from git - `.env` in `.gitignore`, only `.env.example` committed
- [ ] Database indexes created - `EXPLAIN ANALYZE` shows index usage
- [ ] CORS locked down - only specific origins allowed
- [ ] Error handling tested - no stack traces leak to client
- [ ] Health check works - returns 503 if database unreachable
- [ ] Request logging enabled - see all requests in logs
- [ ] Load test passed - 100+ concurrent users without errors

---

## Deployment Script

Create `deploy.sh`:
```bash
#!/bin/bash
set -e

echo "Pre-deployment checks..."

# Validate environment
if [ -z "$SECRET_KEY" ]; then
    echo "ERROR: SECRET_KEY not set"
    exit 1
fi

if [ "$ENVIRONMENT" != "production" ]; then
    echo "ERROR: ENVIRONMENT must be 'production'"
    exit 1
fi

# Run migrations
echo "Running database migrations..."
alembic upgrade head

# Run tests
echo "Running tests..."
pytest server/tests/ -v

# Start server
echo "Starting server..."
uvicorn server.main:app --host 0.0.0.0 --port 8000 --workers 4
```

---

## Monitoring Setup (Post-Launch)

Add to production:
1. **Sentry** for error tracking
2. **Grafana** dashboard for metrics
3. **PagerDuty** for alerts
4. **Automated backups** with `pg_dump`

---

## Timeline Summary

**Week 1:** Critical security/stability fixes
**Week 2:** Important improvements
**Week 3:** Performance optimization + testing
**Week 4:** Final verification + deployment

Ready to deploy! 🚀
