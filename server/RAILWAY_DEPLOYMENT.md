# Railway Deployment Guide

**Platform:** Railway.app
**Type:** Zero-config deployment (no Docker required)
**Estimated Setup Time:** 10 minutes

---

## Prerequisites

- [Railway account](https://railway.app/) (free tier available)
- GitHub repository with this code
- Generated SECRET_KEY (see below)

---

## Step-by-Step Deployment

### 1. Create New Project

1. Go to [railway.app/new](https://railway.app/new)
2. Click **"Deploy from GitHub repo"**
3. Authorize Railway to access your GitHub
4. Select your repository
5. Railway will auto-detect Python and create the project

### 2. Add PostgreSQL Database

1. In your Railway project, click **"+ New"**
2. Select **"Database" → "PostgreSQL"**
3. Railway creates a database and sets `DATABASE_URL` automatically ✅
4. **Note:** `DATABASE_URL` is already configured - no manual setup needed!

### 3. Set Environment Variables

Click on your service → **"Variables"** tab → Add these:

#### Required Variables:

```bash
# Secret key (generate with command below)
SECRET_KEY=<paste generated key here>

# Environment
ENVIRONMENT=production

# CORS (your actual frontend domain)
CORS_ORIGINS=https://yourdomain.com

# Logging
LOG_LEVEL=WARNING
```

#### Generate SECRET_KEY:
```bash
python3 -c "import secrets; print(secrets.token_urlsafe(64))"
```
Copy the output and paste as `SECRET_KEY` value.

#### Optional Variables:
```bash
# Game settings (defaults shown)
WORLD_NAME=Euterpe
TICK_INTERVAL=1.0
ACCESS_TOKEN_EXPIRE_MINUTES=60
```

**Note:** `DATABASE_URL` and `PORT` are automatically set by Railway - don't add them manually!

### 4. Deploy

Railway automatically deploys when you push to your main branch.

**Manual deploy:**
1. Click **"Deploy"** in the Railway dashboard
2. Watch build logs
3. Wait for health check to pass

---

## Verify Deployment

### Check Health Endpoint

Railway provides a URL like: `https://your-app.up.railway.app`

```bash
curl https://your-app.up.railway.app/health
# Expected: {"status": "ok"}
```

### Check API Docs

Visit: `https://your-app.up.railway.app/docs`

You should see the FastAPI Swagger UI.

### Check Logs

In Railway dashboard:
1. Click on your service
2. Click **"Deployments"** tab
3. Click latest deployment
4. View build and runtime logs

**Look for:**
```
Production settings validated for environment: production
Claim Server starting up...
Simulation loop started for world: Euterpe
```

---

## Create Admin User

### 1. Connect to Database

Railway provides a PostgreSQL connection string. In the Railway dashboard:

1. Click on the **PostgreSQL** service
2. Click **"Connect"** tab
3. Copy the **"Postgres Connection URL"**

### 2. Connect via psql

```bash
# Using the connection URL from Railway
psql <paste connection URL here>
```

### 3. Create Admin User

First, register a user via API:

```bash
curl -X POST https://your-app.up.railway.app/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "YourSecurePassword123"
  }'
```

Then make them admin in database:

```sql
-- In psql session
UPDATE players SET is_admin = true WHERE username = 'admin';
\q
```

### 4. Test Admin Access

```bash
# Login to get token
curl -X POST https://your-app.up.railway.app/auth/login \
  -d "username=admin&password=YourSecurePassword123"

# Copy the access_token from response

# Test admin endpoint
curl https://your-app.up.railway.app/admin/status \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"

# Expected: server stats JSON
```

---

## Custom Domain (Optional)

### 1. Add Domain in Railway

1. Click on your service
2. Click **"Settings"** tab
3. Under **"Domains"**, click **"+ Custom Domain"**
4. Enter your domain (e.g., `api.yourgame.com`)

### 2. Configure DNS

Add these DNS records at your domain provider:

**Option A: CNAME (Recommended)**
```
Type: CNAME
Name: api (or your subdomain)
Value: <provided by Railway>
```

**Option B: A Record**
```
Type: A
Name: api
Value: <IP provided by Railway>
```

### 3. Update CORS

After domain is verified, update `CORS_ORIGINS`:

```bash
# In Railway Variables tab
CORS_ORIGINS=https://api.yourgame.com,https://yourgame.com
```

Railway will auto-deploy with new settings.

---

## Scaling & Performance

### Vertical Scaling

Railway offers different resource tiers:

- **Free Tier:** 512 MB RAM, shared CPU
- **Starter:** 1 GB RAM, shared CPU
- **Pro:** 8 GB RAM, dedicated CPU

Upgrade in **Settings → Resources**

### Horizontal Scaling

Railway supports multiple replicas:

1. Settings → **Replicas**
2. Set replica count (2-10)
3. Railway load balances automatically

**Note:** Requires Pro plan

### Database Scaling

PostgreSQL can be scaled independently:

1. Click PostgreSQL service
2. Settings → **Resources**
3. Increase storage/RAM as needed

---

## Monitoring

### Built-in Metrics

Railway provides:
- CPU usage
- Memory usage
- Network traffic
- Request count

View in **Metrics** tab of your service.

### Custom Logging

Your app logs are captured automatically:

```python
# In your code, use logger
logger.info("Important event")
logger.warning("Potential issue")
logger.error("Error occurred")
```

View in **Logs** tab (live streaming).

### Health Checks

Railway pings `/health` every 30 seconds (configured in `railway.toml`).

If health check fails 3 times, Railway restarts the service.

### External Monitoring (Recommended)

Consider adding:

**Sentry** (Error Tracking):
```bash
pip install sentry-sdk[fastapi]
```

**Uptime Monitoring:**
- [UptimeRobot](https://uptimerobot.com/) - free
- [Pingdom](https://www.pingdom.com/)
- [Better Uptime](https://betteruptime.com/)

---

## Cost Estimate

### Free Tier (Hobby Plan)

- **Service:** $0
- **PostgreSQL:** $0 (512 MB storage)
- **Monthly Allowance:** $5 credit
- **Execution Hours:** 500 hours/month free

**Good for:** Development, testing, low-traffic MVP

### Starter Plan ($5/month)

- **Unlimited execution hours**
- **1 GB RAM per service**
- **PostgreSQL included**

**Good for:** Small production apps, indie games

### Pro Plan ($20/month)

- **8 GB RAM**
- **Dedicated resources**
- **Priority support**
- **Multiple replicas**

**Good for:** Scaling apps, multiplayer games

**See:** [Railway Pricing](https://railway.app/pricing)

---

## Database Backups

### Automatic Backups

Railway Pro plan includes:
- Daily automated backups
- 7-day retention
- One-click restore

### Manual Backup (Free Tier)

```bash
# Get connection URL from Railway dashboard
pg_dump "<connection-url>" > backup.sql

# Restore if needed
psql "<connection-url>" < backup.sql
```

**Recommended:** Set up weekly backup cron job.

---

## Security Checklist

Before going live, verify:

- [ ] `ENVIRONMENT=production` set
- [ ] `SECRET_KEY` is 64+ random characters (not default)
- [ ] `CORS_ORIGINS` is your actual domain (HTTPS)
- [ ] `DATABASE_URL` uses SSL (Railway default)
- [ ] Admin user created with strong password
- [ ] Health check passes (`/health` returns 200)
- [ ] Tested admin endpoints require auth
- [ ] Tested rate limiting works (429 after limits)
- [ ] Reviewed deployment logs for errors
- [ ] Set up external monitoring (Sentry/Uptime)

---

## Troubleshooting

### Build Fails

**Check build logs:**
1. Railway dashboard → Deployments → Latest deployment
2. Look for Python errors or missing dependencies

**Common fixes:**
```bash
# Missing dependency
echo "missing-package==1.0.0" >> requirements.txt

# Python version issue (add runtime.txt)
echo "python-3.11" > runtime.txt
```

### Health Check Fails

**Symptoms:**
- Service restarts every 30 seconds
- "Health check timeout" in logs

**Debug:**
```bash
# Check health endpoint locally first
curl http://localhost:8000/health

# Check Railway logs for startup errors
# Look for database connection issues
```

**Common causes:**
- Database migrations failing
- `DATABASE_URL` not set (should be automatic)
- Port binding issue (must use `$PORT` env var)

### Database Connection Errors

**Error:** `could not connect to server`

**Fix:**
1. Verify PostgreSQL service is running (Railway dashboard)
2. Check `DATABASE_URL` is set (should be automatic)
3. Verify database migrations ran (`alembic upgrade head` in logs)

**Manual connection test:**
```bash
# In Railway Shell (click Shell tab)
python3 -c "import asyncpg; asyncpg.connect('$DATABASE_URL')"
```

### CORS Errors

**Error:** `CORS policy: No 'Access-Control-Allow-Origin'`

**Fix:**
1. Verify `CORS_ORIGINS` includes your frontend domain
2. Must use `https://` in production
3. No trailing slashes in domain
4. Redeploy after changing

### Rate Limit Not Working

**Error:** Can spam endpoints unlimited times

**Cause:** Railway uses multiple IPs (load balancer)

**Fix:** Use `X-Forwarded-For` header:
```python
# In rate_limit.py (already configured if using slowapi)
limiter = Limiter(key_func=get_remote_address, strategy="moving-window")
```

### Migrations Don't Run

**Error:** Tables don't exist

**Debug:**
```bash
# Check if migrations ran in deployment logs
# Look for: "alembic upgrade head"
```

**Manual run:**
1. Railway dashboard → Service → Shell
2. Run: `alembic upgrade head`

---

## Updating Your App

### Automatic Deploys

Railway redeploys on every push to main branch.

```bash
git add .
git commit -m "Update feature"
git push origin main

# Railway automatically:
# 1. Pulls latest code
# 2. Runs migrations
# 3. Restarts service
# 4. Health check
```

### Manual Deploys

In Railway dashboard:
1. Click service
2. Click **"Deploy"**
3. Select branch/commit
4. Click **"Deploy"**

### Rollback

If deployment breaks:

1. Deployments tab
2. Find last working deployment
3. Click **"⋮"** → **"Redeploy"**

---

## Environment-Specific Variables

### Development (Local)
```bash
ENVIRONMENT=development
# No DATABASE_URL or SECRET_KEY needed (uses defaults)
```

### Staging (Railway)
```bash
ENVIRONMENT=production  # Still validate production rules
DATABASE_URL=<Railway staging database>
SECRET_KEY=<unique staging key>
CORS_ORIGINS=https://staging.yourdomain.com
LOG_LEVEL=INFO  # More verbose for debugging
```

### Production (Railway)
```bash
ENVIRONMENT=production
DATABASE_URL=<Railway prod database>
SECRET_KEY=<unique prod key>
CORS_ORIGINS=https://yourdomain.com
LOG_LEVEL=WARNING  # Less verbose
```

---

## Next Steps

After successful deployment:

1. **Test all endpoints** via `/docs`
2. **Create admin user** and test admin endpoints
3. **Set up monitoring** (Sentry, UptimeRobot)
4. **Configure custom domain** (optional)
5. **Set up backups** (Pro plan or manual)
6. **Load test** your app (simulate user traffic)
7. **Document your API** for frontend developers

---

## Support

- **Railway Docs:** https://docs.railway.app/
- **Railway Discord:** https://discord.gg/railway
- **This Project:** See `SECURITY_AUDIT.md`, `AUTH_SECURITY.md`, `DEVELOPMENT.md`

---

## Quick Reference

**Deploy Command:** Push to main branch (auto-deploy)

**View Logs:** Railway dashboard → Service → Logs

**Connect to DB:** Railway dashboard → PostgreSQL → Connect

**Environment Variables:** Railway dashboard → Service → Variables

**Restart Service:** Railway dashboard → Service → Settings → Restart

**Health Check:** `https://your-app.up.railway.app/health`

**API Docs:** `https://your-app.up.railway.app/docs`

---

**Your app is now running on Railway!** 🚂
