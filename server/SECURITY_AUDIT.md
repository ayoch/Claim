# Server Security Audit & Deployment Hardening

**Date:** 2026-02-27
**Audited By:** Dweezil (Windows) + HK-47 (Mac)
**Priority:** HIGH - Must address before production deployment
**Status:** ✅ **CRITICAL & HIGH PRIORITY FIXES IMPLEMENTED** (2026-02-27)

---

## ✅ Implementation Status

**All critical and high priority security issues have been fixed:**

### CRITICAL Issues (5/5 FIXED ✅)
1. ✅ **Admin Endpoints Authentication** - Added `is_admin` field to Player model, created `require_admin()` dependency, secured all 3 admin endpoints
2. ✅ **Rate Limiting** - Added rate limiting to all admin endpoints (1/min for seed, 5/hour for starter packs, 10/min for status)
3. ✅ **Production Validation** - Fixed to check `ENVIRONMENT != "development"` instead of just `"production"` (prevents bypass)
4. ✅ **Database Credentials** - Removed hardcoded default, now required from environment (no default value)
5. ✅ **Secret Key** - Removed random generation default, now required from environment with min 32 char validation

### HIGH Priority Issues (5/5 FIXED ✅)
6. ✅ **HTTPS Enforcement** - Added `HTTPSRedirectMiddleware` for production environment
7. ✅ **Input Validation** - Added player_id validation (1-1,000,000 range) using Pydantic Path validator
8. ✅ **Verbose Errors** - Added generic exception handler that hides stack traces in production
9. ✅ **Request Size Limits** - Added `LimitUploadSize` middleware (10MB max for POST/PUT/PATCH)
10. ✅ **CORS HTTPS Validation** - Added validation that production CORS origins must use HTTPS

### MEDIUM Priority Issues (PARTIALLY IMPLEMENTED)
11. ⚠️ **Auth Logging** - Not yet implemented (requires logging infrastructure)
12. ⚠️ **Connection Pooling** - Not yet configured (database.py needs pool_size/max_overflow settings)
13. ✅ **JWT Expiry** - Reduced from 7 days to 1 hour (refresh tokens not yet implemented)

### Additional Improvements
- ✅ **Database Migration** - Created alembic migration for `is_admin` field
- ✅ **Development .env** - Updated with proper credentials and generated secure SECRET_KEY
- ✅ **Production .env Example** - Created `.env.production.example` with all required settings
- ✅ **Trusted Host Middleware** - Added for production (extracts from CORS origins)

### Files Modified (11 files)
1. `server/models/player.py` - Added `is_admin: bool` field
2. `server/auth.py` - Added `require_admin()` dependency
3. `server/config.py` - Removed DATABASE_URL/SECRET_KEY defaults, added HTTPS validation, reduced JWT expiry
4. `server/main.py` - Added HTTPS redirect, trusted host, request size limit, exception handler, fixed validation
5. `server/routers/admin.py` - Added auth + rate limiting to all 3 endpoints, input validation
6. `server/.env` - Updated with secure credentials for development
7. `server/.env.example` - Updated to reflect required fields
8. `server/.env.production.example` - Created with production-ready configuration
9. `alembic/versions/2a20b17739f3_add_is_admin_to_player.py` - Database migration for is_admin
10. `docs/CLAUDE_HANDOFF.md` - Documented security audit session
11. `docs/WORK_LOG.txt` - Added session 20 entry

### Next Steps Before Production
- [ ] Run database migration: `alembic upgrade head`
- [ ] Update PostgreSQL user credentials to match new .env settings
- [ ] Create admin user account (set `is_admin=true` in database)
- [ ] Implement auth attempt logging (medium priority)
- [ ] Configure database connection pooling (medium priority)
- [ ] Test all admin endpoints with non-admin user (should get 403 Forbidden)
- [ ] Test rate limiting (should get 429 Too Many Requests)
- [ ] Run security scanner (OWASP ZAP or similar)
- [ ] Set up production .env with real credentials
- [ ] Deploy behind reverse proxy with security headers

---

## CRITICAL Issues (Fix Before Production)

### 1. **Admin Endpoints Have NO Authentication** ⚠️ SEVERE
**Location:** `server/routers/admin.py`

**Vulnerability:**
```python
@router.get("/status")  # NO AUTHENTICATION
async def server_status(db: AsyncSession = Depends(get_db)):
    # ... exposes player count, ship count, tick count

@router.post("/seed")  # NO AUTHENTICATION
async def seed(db: AsyncSession = Depends(get_db)):
    # ... anyone can seed the database

@router.post("/give-starter-pack/{player_id}")  # NO AUTHENTICATION
async def give_starter_pack(player_id: int, db: AsyncSession = Depends(get_db)):
    # ... anyone can give any player free ships/workers!
```

**Impact:**
- `/admin/give-starter-pack/{player_id}` allows **anyone** to give **any** player free ships and workers
- Attackers can create unlimited resources for themselves
- `/admin/seed` can be spammed to duplicate database entries
- `/admin/status` leaks server metrics

**Fix Required:**
```python
from server.auth import get_current_player
from server.models.player import Player

# Create admin check dependency
async def require_admin(player: Player = Depends(get_current_player)) -> Player:
    if not player.is_admin:
        raise HTTPException(status_code=403, detail="Admin access required")
    return player

# Then on every admin endpoint:
@router.post("/seed")
async def seed(
    admin: Player = Depends(require_admin),  # ADD THIS
    db: AsyncSession = Depends(get_db)
):
    # ...
```

**Action:** Add `is_admin: bool` field to Player model, require admin auth on all `/admin/*` endpoints

---

### 2. **No Rate Limiting on Admin Endpoints**
**Location:** `server/routers/admin.py`

**Vulnerability:**
Even after adding auth, admin endpoints have no rate limiting. An attacker with stolen admin credentials could:
- Spam `/admin/seed` to create millions of database records (DoS)
- Repeatedly call `/admin/give-starter-pack` to duplicate resources

**Fix Required:**
```python
from slowapi import Limiter
from server.rate_limit import limiter

@router.post("/seed")
@limiter.limit("1/minute")  # Only once per minute
async def seed(request: Request, admin: Player = Depends(require_admin), ...):
    # ...

@router.post("/give-starter-pack/{player_id}")
@limiter.limit("5/hour")  # Max 5 starter packs per hour
async def give_starter_pack(request: Request, admin: Player = Depends(require_admin), ...):
    # ...
```

---

### 3. **Production Validation Not Enforced**
**Location:** `server/main.py:58`

**Vulnerability:**
```python
if settings.ENVIRONMENT == "production":
    try:
        settings.validate_production()
        logger.info("Production settings validated successfully")
    except ValueError as e:
        logger.error(f"Production validation failed: {e}")
        raise  # App crashes, but...
```

**Problem:**
- Validation only runs if `ENVIRONMENT == "production"`
- An attacker could set `ENVIRONMENT=staging` and bypass all checks
- Allows weak `SECRET_KEY`, localhost CORS, etc.

**Fix Required:**
```python
# Always validate if not explicitly in development
if settings.ENVIRONMENT != "development":
    settings.validate_production()
    logger.info(f"Production settings validated for environment: {settings.ENVIRONMENT}")
```

---

### 4. **Database Credentials in Config File**
**Location:** `server/config.py:13`

**Vulnerability:**
```python
DATABASE_URL: str = "postgresql+asyncpg://claim:claim@localhost/claim_dev"
```

Hardcoded database password `claim:claim` in source code.

**Fix Required:**
```python
DATABASE_URL: str = Field(
    ...,  # Required, no default
    description="Database connection string (must be set via environment variable)"
)
```

Force `DATABASE_URL` to come from `.env` file (which should be `.gitignore`'d)

---

### 5. **Secrets Generation at Runtime**
**Location:** `server/config.py:14-17`

**Vulnerability:**
```python
SECRET_KEY: str = Field(
    default_factory=lambda: secrets.token_urlsafe(32),
    description="JWT signing key - MUST be set in production"
)
```

**Problem:**
- If `SECRET_KEY` not set in `.env`, generates a **random** key each startup
- All JWT tokens become invalid on server restart
- Users logged out every deployment
- Different instances in load-balanced setup have different keys (tokens fail)

**Fix Required:**
```python
SECRET_KEY: str = Field(
    ...,  # No default - MUST be set
    description="JWT signing key from environment variable"
)

def __init__(self, **kwargs):
    super().__init__(**kwargs)
    if len(self.SECRET_KEY) < 32:
        raise ValueError("SECRET_KEY must be at least 32 characters")
```

---

## HIGH Priority Issues

### 6. **No HTTPS Enforcement**
**Location:** `server/main.py` (missing)

**Vulnerability:**
- No middleware to redirect HTTP → HTTPS
- Allows man-in-the-middle attacks
- JWT tokens sent over unencrypted connections

**Fix Required:**
```python
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.middleware.httpsredirect import HTTPSRedirectMiddleware

if settings.ENVIRONMENT == "production":
    app.add_middleware(HTTPSRedirectMiddleware)
    app.add_middleware(
        TrustedHostMiddleware,
        allowed_hosts=settings.ALLOWED_HOSTS.split(",")
    )
```

---

### 7. **No Input Validation on player_id Parameter**
**Location:** `server/routers/admin.py:186`

**Vulnerability:**
```python
@router.post("/give-starter-pack/{player_id}")
async def give_starter_pack(player_id: int, ...):
    # No validation that player_id is positive, reasonable range, etc.
```

Attacker could try `player_id=-1`, `player_id=999999999` to probe database or cause errors.

**Fix Required:**
```python
from pydantic import Field

@router.post("/give-starter-pack/{player_id}")
async def give_starter_pack(
    player_id: int = Path(..., ge=1, le=1000000),  # Validate range
    ...
):
```

---

### 8. **Verbose Error Messages**
**Location:** Throughout (FastAPI default behavior)

**Vulnerability:**
FastAPI's default 500 errors return full stack traces in production, leaking:
- File paths
- Database schema
- Internal logic

**Fix Required:**
```python
@app.exception_handler(Exception)
async def generic_exception_handler(request: Request, exc: Exception):
    if settings.ENVIRONMENT == "production":
        logger.error(f"Unhandled exception: {exc}", exc_info=True)
        return JSONResponse(
            status_code=500,
            content={"detail": "Internal server error"}
        )
    else:
        # In development, show full trace
        raise exc
```

---

### 9. **No Request Size Limits**
**Location:** `server/main.py` (missing)

**Vulnerability:**
- No limit on request body size
- Attacker can send gigabyte-sized JSON payloads
- Causes memory exhaustion (DoS)

**Fix Required:**
```python
app.add_middleware(
    LimitUploadSize,
    max_upload_size=10 * 1024 * 1024  # 10MB max
)
```

---

### 10. **CORS Credentials Without Strict Origins**
**Location:** `server/main.py:36`

**Vulnerability:**
```python
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.cors_origins_list,
    allow_credentials=True,  # ⚠️ Dangerous with permissive origins
    ...
)
```

If `CORS_ORIGINS` includes wildcards or multiple untrusted domains, **and** `allow_credentials=True`, allows credential theft via CSRF.

**Current mitigation:** `config.py:48` validates no wildcards in production ✅

**Additional fix:**
```python
# In production, also validate specific domains
if settings.ENVIRONMENT == "production":
    for origin in settings.cors_origins_list:
        if not origin.startswith("https://"):
            raise ValueError(f"Production CORS origins must use HTTPS: {origin}")
```

---

## MEDIUM Priority Issues

### 11. **No Logging of Authentication Attempts**
**Location:** `server/routers/auth.py` (missing)

**Problem:**
- No logs for failed login attempts
- Can't detect brute-force attacks
- No audit trail

**Fix:** Add logging to auth endpoints

---

### 12. **No Database Connection Pooling Limits**
**Location:** `server/database.py` (likely)

**Problem:**
- Default PostgreSQL connection pool might be unlimited
- Can exhaust database connections under load

**Fix:** Configure `max_overflow`, `pool_size` in SQLAlchemy engine

---

### 13. **JWT Tokens Never Expire (Long Expiry)**
**Location:** `server/config.py:23`

```python
ACCESS_TOKEN_EXPIRE_MINUTES: int = 60 * 24 * 7  # 7 days
```

**Problem:**
- Stolen tokens valid for a week
- No refresh token system

**Fix:** Reduce to 1 hour, implement refresh tokens

---

## Deployment Checklist

### Before Going Live:

- [ ] Add `is_admin` field to Player model
- [ ] Require admin auth on all `/admin/*` endpoints
- [ ] Add rate limiting to admin endpoints
- [ ] Remove hardcoded `DATABASE_URL`, force from environment
- [ ] Remove `SECRET_KEY` default, force from environment
- [ ] Add HTTPS redirect middleware
- [ ] Add trusted host middleware
- [ ] Add generic exception handler (hide stack traces)
- [ ] Add request size limits
- [ ] Validate CORS origins use HTTPS in production
- [ ] Add authentication attempt logging
- [ ] Configure database connection pool limits
- [ ] Reduce JWT expiry, add refresh tokens
- [ ] Set up proper `.env` file with strong secrets
- [ ] Add `SECRET_KEY` to environment (32+ character random string)
- [ ] Set `ENVIRONMENT=production`
- [ ] Set `DATABASE_URL` with real credentials
- [ ] Configure `CORS_ORIGINS` to actual frontend domain(s)
- [ ] Run `settings.validate_production()` on startup
- [ ] Test with security scanner (OWASP ZAP, etc.)

---

## Server Hardening (Infrastructure)

### Firewall Rules:
- Only allow ports 443 (HTTPS) and 22 (SSH) inbound
- Block all other ports
- Whitelist SSH to specific IPs if possible

### PostgreSQL:
- Run on separate server or container
- No public internet access
- Only accept connections from app server
- Use strong password (32+ characters)
- Enable SSL connections

### Reverse Proxy (Nginx/Caddy):
- Terminate SSL at proxy
- Add security headers (HSTS, CSP, X-Frame-Options)
- Rate limit at proxy level (per-IP)
- Hide server version headers

### Process Manager (systemd/supervisor):
- Run FastAPI with limited user (not root)
- Auto-restart on crash
- Capture logs to rotating files

### Monitoring:
- Set up error alerting (Sentry, LogRocket)
- Monitor CPU/memory/disk
- Track failed auth attempts
- Alert on unusual patterns

---

## Example Production `.env`

```bash
# Database (change password!)
DATABASE_URL=postgresql+asyncpg://claim_user:CHANGE_THIS_STRONG_PASSWORD@db.internal:5432/claim_prod

# Security (generate with: python -c "import secrets; print(secrets.token_urlsafe(64))")
SECRET_KEY=CHANGE_THIS_TO_64_CHAR_RANDOM_STRING_FROM_SECRETS_MODULE

# Environment
ENVIRONMENT=production
LOG_LEVEL=WARNING

# CORS (your actual frontend domain)
CORS_ORIGINS=https://claim.example.com

# JWT
ACCESS_TOKEN_EXPIRE_MINUTES=60

# Game settings
WORLD_NAME=Euterpe
TICK_INTERVAL=1.0
```

---

## Summary

**Severity Breakdown:**
- 🔴 **CRITICAL:** 5 issues (admin auth, rate limiting, validation, credentials, secrets)
- 🟠 **HIGH:** 5 issues (HTTPS, input validation, errors, size limits, CORS)
- 🟡 **MEDIUM:** 3 issues (logging, pooling, JWT expiry)

**Estimated Fix Time:** 4-6 hours for all critical + high issues

**Recommendation:** **DO NOT deploy to public internet until critical issues are resolved.**

The admin endpoints alone are a catastrophic vulnerability - anyone can give themselves unlimited resources.
