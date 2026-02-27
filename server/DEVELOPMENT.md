# Local Development Setup

**Last Updated:** 2026-02-27

---

## Quick Start (No Configuration Required!)

The server is designed to run locally with **zero configuration** for development and testing.

### 1. Clone and Install

```bash
git clone <repo-url>
cd server
python3 -m venv .venv
source .venv/bin/activate  # On Windows: .venv\Scripts\activate
pip install -r requirements.txt
```

### 2. Run Immediately

```bash
# No .env file needed! Just run:
python -m uvicorn server.main:app --reload
```

**What happens:**
```
⚠️  Using development DATABASE_URL (no .env found)
⚠️  Generated random SECRET_KEY for development (tokens won't persist across restarts)
INFO:     Uvicorn running on http://127.0.0.1:8000
```

The server automatically uses safe development defaults:
- **DATABASE_URL:** `postgresql+asyncpg://claim_dev:claim_dev_password@localhost/claim_dev`
- **SECRET_KEY:** Randomly generated (32 chars)
- **ENVIRONMENT:** `development`
- **CORS_ORIGINS:** `http://localhost:3000,http://localhost:8080`

---

## Development Modes

### Mode 1: Zero-Config (Fastest for Testing)

**No .env file required!** Server starts immediately with dev defaults.

**Pros:**
- ✅ Instant startup, no configuration
- ✅ Safe for quick testing
- ✅ Can't accidentally commit secrets

**Cons:**
- ⚠️ SECRET_KEY changes each restart (JWT tokens invalidated)
- ⚠️ Must have PostgreSQL with exact credentials

**Best for:**
- Quick testing
- CI/CD pipelines
- Containers with PostgreSQL sidecar

### Mode 2: Persistent .env (Recommended)

Create a `.env` file for persistent tokens and custom database:

```bash
# Copy example
cp .env.example .env

# Edit .env - uncomment and set your values:
DATABASE_URL=postgresql+asyncpg://myuser:mypass@localhost/mydb
SECRET_KEY=my_persistent_dev_key_32_chars
ENVIRONMENT=development
```

**Pros:**
- ✅ JWT tokens persist across restarts
- ✅ Custom database credentials
- ✅ Matches your local PostgreSQL setup

**Cons:**
- ⚠️ Must create .env file
- ⚠️ Must ensure .env in .gitignore (it is!)

**Best for:**
- Active development
- Frontend integration testing
- Multiple developers on same machine

---

## Database Setup

### Option 1: Match Default Credentials

Create PostgreSQL user/database matching dev defaults:

```bash
# Connect to PostgreSQL
psql postgres

# Create user and database
CREATE USER claim_dev WITH PASSWORD 'claim_dev_password';
CREATE DATABASE claim_dev OWNER claim_dev;
GRANT ALL PRIVILEGES ON DATABASE claim_dev TO claim_dev;
\q

# Run migrations
alembic upgrade head
```

### Option 2: Use Your Existing Database

Create `.env` with your credentials:

```bash
DATABASE_URL=postgresql+asyncpg://your_user:your_pass@localhost/your_db
SECRET_KEY=any_string_at_least_32_characters_long
ENVIRONMENT=development
```

---

## Running the Server

### Standard Mode
```bash
uvicorn server.main:app --reload
```

### With Custom Port
```bash
uvicorn server.main:app --reload --port 8080
```

### With Debug Logging
```bash
# In .env or environment:
LOG_LEVEL=DEBUG

uvicorn server.main:app --reload
```

### Production-Like Mode (Test Security)
```bash
# In .env:
ENVIRONMENT=production
DATABASE_URL=postgresql+asyncpg://...  # REQUIRED
SECRET_KEY=...  # REQUIRED (min 32 chars)
CORS_ORIGINS=https://yourdomain.com  # MUST use HTTPS

uvicorn server.main:app
```

**Note:** Production mode requires all security settings. Use this to test production validation before deploying.

---

## API Documentation

Once running, visit:
- **Swagger UI:** http://localhost:8000/docs
- **ReDoc:** http://localhost:8000/redoc
- **Health Check:** http://localhost:8000/health

---

## Common Development Tasks

### Seed Database
```bash
curl -X POST http://localhost:8000/admin/seed \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"
```

### Create First User
```bash
curl -X POST http://localhost:8000/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "testuser", "password": "TestPassword123"}'
```

### Login
```bash
curl -X POST http://localhost:8000/auth/login \
  -d "username=testuser&password=TestPassword123"
```

### Make User Admin
```bash
psql claim_dev
UPDATE players SET is_admin = true WHERE username = 'testuser';
```

### Reset Database
```bash
alembic downgrade base
alembic upgrade head
```

---

## Environment Variables Reference

| Variable | Required | Default (Dev) | Description |
|----------|----------|---------------|-------------|
| `ENVIRONMENT` | No | `development` | `development` or `production` |
| `DATABASE_URL` | Prod only | Dev default | PostgreSQL connection string |
| `SECRET_KEY` | Prod only | Random (32 chars) | JWT signing key |
| `CORS_ORIGINS` | No | localhost:3000,8080 | Comma-separated origins |
| `LOG_LEVEL` | No | `INFO` | DEBUG/INFO/WARNING/ERROR |
| `WORLD_NAME` | No | `Euterpe` | Game world name |
| `TICK_INTERVAL` | No | `1.0` | Seconds per game tick |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | No | `60` | JWT token lifetime (1 hour) |

---

## Security Notes for Development

### What's Safe in Development:
- ✅ Random SECRET_KEY (tokens only valid for session)
- ✅ Weak database passwords (local only)
- ✅ HTTP CORS origins (localhost)
- ✅ Verbose error messages (helps debugging)

### What to NEVER Do:
- ❌ Commit `.env` to git (it's in .gitignore)
- ❌ Use development secrets in production
- ❌ Disable authentication for testing
- ❌ Set `ENVIRONMENT=development` in production

### Development Security Features (Still Active):
- ✅ Rate limiting on auth endpoints
- ✅ Password strength validation
- ✅ Admin role requirements
- ✅ Authentication logging
- ✅ Input validation

**Only difference:** Dev mode has defaults for DATABASE_URL and SECRET_KEY

---

## Troubleshooting

### "DATABASE_URL is required"
**Problem:** Running in production/staging without .env

**Solution:**
```bash
# Option 1: Switch to development
ENVIRONMENT=development uvicorn server.main:app --reload

# Option 2: Create .env with required values
echo 'ENVIRONMENT=development' > .env
```

### "Could not connect to database"
**Problem:** PostgreSQL not running or wrong credentials

**Solutions:**
```bash
# Check PostgreSQL is running
pg_isready

# Check connection
psql postgresql://claim_dev:claim_dev_password@localhost/claim_dev

# If failed, create user/database (see Database Setup above)
```

### "Production validation failed"
**Problem:** Using production mode with localhost CORS

**Solution:**
```bash
# Either switch to dev mode:
ENVIRONMENT=development uvicorn ...

# Or set production-valid CORS:
CORS_ORIGINS=https://yourdomain.com uvicorn ...
```

### "Tokens expire immediately"
**Problem:** SECRET_KEY changing each restart (no .env)

**Solution:**
```bash
# Create .env with persistent key
echo 'SECRET_KEY=my_persistent_dev_key_at_least_32_characters' > .env
```

### "Rate limit exceeded"
**Problem:** Hit rate limit during testing

**Solutions:**
```bash
# Wait 1 minute for login rate limit to reset
# Or restart server (dev mode resets counters)
# Or use different IP/username
```

---

## Docker Development (Optional)

### Docker Compose
```yaml
version: '3.8'
services:
  postgres:
    image: postgres:15
    environment:
      POSTGRES_USER: claim_dev
      POSTGRES_PASSWORD: claim_dev_password
      POSTGRES_DB: claim_dev
    ports:
      - "5432:5432"

  server:
    build: .
    environment:
      - ENVIRONMENT=development
      # No DATABASE_URL or SECRET_KEY needed - will use defaults
    ports:
      - "8000:8000"
    depends_on:
      - postgres
```

### Run
```bash
docker-compose up
```

Server will auto-connect to PostgreSQL with dev defaults!

---

## Testing

### Run Tests
```bash
pytest
```

### With Coverage
```bash
pytest --cov=server --cov-report=html
```

### Test Specific File
```bash
pytest tests/test_auth.py -v
```

---

## Next Steps

1. **For quick testing:** Just run `uvicorn server.main:app --reload`
2. **For active development:** Create `.env` with persistent SECRET_KEY
3. **For production testing:** Set `ENVIRONMENT=production` and required vars
4. **For team collaboration:** Share `.env.example`, let each dev customize

**Questions?** See `SECURITY_AUDIT.md` and `AUTH_SECURITY.md` for security details.
