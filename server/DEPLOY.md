# Production Deployment Guide

**Platform:** Railway.app
**Time Required:** 30 minutes
**Cost:** $5/month (Starter plan)

---

## Prerequisites

- [ ] Code pushed to GitHub
- [ ] Railway account created ([railway.app](https://railway.app))
- [ ] Domain name (optional, can use Railway subdomain)

---

## Step 1: Generate Production Secrets (2 minutes)

### Generate SECRET_KEY

```bash
python3 -c "import secrets; print(secrets.token_urlsafe(64))"
```

**Copy the output** - you'll paste this into Railway.

**Example output:**
```
k9dX7HflQCsX12OSQmNS64ABZ2QWJCiFO5_o_yJoonqHLJ8jbIqDZbjHOCFmdmPCNOMI1JkbDLArQmYFOYu_Hg
```

⚠️ **NEVER commit this to git!**

---

## Step 2: Deploy to Railway (10 minutes)

### 2.1 Create New Project

1. Go to [railway.app/new](https://railway.app/new)
2. Click **"Deploy from GitHub repo"**
3. Authorize Railway to access your GitHub
4. Select your repository
5. Railway auto-detects Python and creates the project

### 2.2 Add PostgreSQL Database

1. In your Railway project dashboard
2. Click **"+ New"**
3. Select **"Database" → "PostgreSQL"**
4. Railway creates database and sets `DATABASE_URL` automatically ✅

### 2.3 Configure Environment Variables

1. Click on your **web service** (not the database)
2. Click **"Variables"** tab
3. Click **"+ New Variable"**
4. Add these three variables:

| Variable | Value |
|----------|-------|
| `ENVIRONMENT` | `production` |
| `SECRET_KEY` | `<paste generated key from Step 1>` |
| `CORS_ORIGINS` | `https://yourdomain.com` (or Railway URL for testing) |

**Note:** `DATABASE_URL` is automatically set by Railway - don't add it manually!

### 2.4 Deploy

Railway automatically deploys when you push to main branch.

**To trigger manual deploy:**
1. Click **"Deployments"** tab
2. Click **"Deploy"**

**Watch the build logs:**
- Look for: `Production settings validated for environment: production`
- Look for: `Claim Server starting up...`
- Look for: Health check passing

**Get your app URL:**
- In Railway dashboard, click **"Settings"** tab
- Under **"Domains"**, you'll see: `https://your-app.up.railway.app`
- Copy this URL

---

## Step 3: Run Database Migration (5 minutes)

Railway runs migrations automatically via `railway.toml` start command:
```toml
startCommand = "alembic upgrade head && uvicorn server.main:app --host 0.0.0.0 --port $PORT"
```

**Verify migration ran:**
1. Click **"Deployments"** tab
2. Click latest deployment
3. Check logs for: `Running upgrade -> 2a20b17739f3, add_is_admin_to_player`

If migration didn't run, manually trigger it:
1. Click on your service → **"Shell"** tab
2. Run: `alembic upgrade head`

---

## Step 4: Create Admin User (5 minutes)

### 4.1 Register First User

```bash
# Replace with your Railway URL
curl -X POST https://your-app.up.railway.app/auth/register \
  -H "Content-Type: application/json" \
  -d '{
    "username": "admin",
    "password": "ChangeThisToSecurePassword123"
  }'
```

**Expected response:**
```json
{
  "id": 1,
  "username": "admin",
  "money": 14000000,
  ...
}
```

### 4.2 Connect to Database

In Railway dashboard:
1. Click on **PostgreSQL** service
2. Click **"Connect"** tab
3. Copy the **"Postgres Connection URL"**

```bash
# Paste the connection URL from Railway
psql "postgresql://postgres:password@region.railway.app:5432/railway"
```

### 4.3 Grant Admin Privileges

```sql
-- Make the user an admin
UPDATE players SET is_admin = true WHERE username = 'admin';

-- Verify
SELECT id, username, is_admin FROM players WHERE username = 'admin';

-- Expected: is_admin = true

-- Exit
\q
```

---

## Step 5: Verify Deployment (5 minutes)

### Test Health Endpoint

```bash
curl https://your-app.up.railway.app/health
```

**Expected:**
```json
{"status":"ok"}
```

### Test API Documentation

Visit in browser:
```
https://your-app.up.railway.app/docs
```

Should see FastAPI Swagger UI.

### Test Admin Login

```bash
# Login as admin
curl -X POST https://your-app.up.railway.app/auth/login \
  -d "username=admin&password=ChangeThisToSecurePassword123"
```

**Expected:**
```json
{
  "access_token": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...",
  "token_type": "bearer"
}
```

Copy the `access_token` value.

### Test Admin Endpoint

```bash
# Replace YOUR_TOKEN with the access_token from above
curl https://your-app.up.railway.app/admin/status \
  -H "Authorization: Bearer YOUR_TOKEN"
```

**Expected:**
```json
{
  "status": "running",
  "total_ticks": 0,
  "player_count": 1,
  "ship_count": 0,
  "asteroid_count": 0
}
```

### Test Non-Admin Cannot Access Admin Endpoint

```bash
# Register a regular user
curl -X POST https://your-app.up.railway.app/auth/register \
  -H "Content-Type: application/json" \
  -d '{"username": "regularuser", "password": "TestPassword123"}'

# Login as regular user
curl -X POST https://your-app.up.railway.app/auth/login \
  -d "username=regularuser&password=TestPassword123"

# Copy the access_token

# Try to access admin endpoint
curl https://your-app.up.railway.app/admin/status \
  -H "Authorization: Bearer REGULAR_USER_TOKEN"
```

**Expected:**
```json
{
  "detail": "Admin access required"
}
```

✅ **If you get 403 Forbidden, admin security is working!**

### Test Rate Limiting

```bash
# Try to login 11 times rapidly (limit is 10/minute)
for i in {1..11}; do
  echo "Attempt $i:"
  curl -X POST https://your-app.up.railway.app/auth/login \
    -d "username=wronguser&password=wrong"
  echo ""
done
```

**Expected:**
- First 10 attempts: `401 Unauthorized` (wrong credentials)
- 11th attempt: `429 Too Many Requests` (rate limited)

✅ **If 11th attempt is blocked, rate limiting is working!**

---

## Step 6: Seed Game Data (Optional, 2 minutes)

```bash
# Login as admin and get token
TOKEN=$(curl -s -X POST https://your-app.up.railway.app/auth/login \
  -d "username=admin&password=YourPassword" | jq -r .access_token)

# Seed asteroids and colonies
curl -X POST https://your-app.up.railway.app/admin/seed \
  -H "Authorization: Bearer $TOKEN"
```

**Expected:**
```json
{
  "seeded": {
    "colonies": 9,
    "asteroids": 20
  },
  "message": "Seed complete"
}
```

---

## ✅ Deployment Complete!

Your server is now live at: `https://your-app.up.railway.app`

### What You Have

- ✅ Production-ready FastAPI server
- ✅ PostgreSQL database with migrations
- ✅ Admin user with full access
- ✅ Secure authentication (JWT, password validation)
- ✅ Rate limiting on auth endpoints
- ✅ HTTPS redirect enabled
- ✅ Request size limits (10 MB)
- ✅ Error logging to Railway

---

## Post-Deployment Tasks

### 1. Update Godot Client

Point your Godot client to the Railway URL:

```gdscript
# In backend_manager.gd or similar
const SERVER_URL = "https://your-app.up.railway.app"
```

### 2. Set Up Monitoring (Recommended)

**Railway Built-in:**
- Click service → **"Metrics"** tab
- Monitor CPU, memory, network

**External (Optional):**
- [UptimeRobot](https://uptimerobot.com/) - free uptime monitoring
- [Sentry](https://sentry.io/) - error tracking (free tier)

### 3. Configure Custom Domain (Optional)

If you have a domain:

1. Railway dashboard → Service → **"Settings"**
2. Under **"Domains"**, click **"+ Custom Domain"**
3. Enter your domain: `api.yourgame.com`
4. Add CNAME record at your DNS provider:
   ```
   Type: CNAME
   Name: api
   Value: <provided by Railway>
   ```
5. Update `CORS_ORIGINS` in Railway variables:
   ```
   CORS_ORIGINS=https://yourgame.com,https://api.yourgame.com
   ```

### 4. Set Up Backups (Recommended)

**Railway Pro Plan ($20/month):**
- Automatic daily backups
- 7-day retention
- One-click restore

**Manual Backups (Free Tier):**
```bash
# Get DATABASE_URL from Railway variables
# Run weekly (set up cron job)
pg_dump "$DATABASE_URL" > backup-$(date +%Y%m%d).sql

# Store backups somewhere safe (S3, Dropbox, etc.)
```

### 5. Review Logs

Check for errors in Railway dashboard:

1. Click service → **"Logs"** tab
2. Look for:
   - `WARNING` - failed login attempts (normal, some expected)
   - `ERROR` - actual errors (investigate these)

**Common first-deploy errors:**
- CORS errors → update `CORS_ORIGINS`
- Database connection errors → check DATABASE_URL is set
- Authentication errors → verify SECRET_KEY is set

---

## Troubleshooting

### Build Fails

**Error:** `Could not find requirements.txt`

**Fix:**
```bash
# Ensure requirements.txt exists in server/ directory
ls server/requirements.txt

# If missing, create it:
pip freeze > server/requirements.txt
git add server/requirements.txt
git commit -m "Add requirements.txt"
git push
```

### Health Check Fails

**Symptom:** Service keeps restarting, shows "Unhealthy"

**Debug:**
1. Check deployment logs for errors
2. Verify DATABASE_URL is set (Railway should set automatically)
3. Check migrations ran successfully
4. Manually test health endpoint:
   ```bash
   curl https://your-app.up.railway.app/health
   ```

**Common causes:**
- Database migrations failed
- Missing environment variables
- Port binding issue (should use `$PORT` from Railway)

### CORS Errors in Browser

**Error:** `CORS policy: No 'Access-Control-Allow-Origin'`

**Fix:**
1. Railway dashboard → Service → Variables
2. Update `CORS_ORIGINS` to include your frontend domain
3. Must use `https://` in production
4. No trailing slashes
5. Example: `CORS_ORIGINS=https://mygame.com,https://app.mygame.com`

### Database Connection Errors

**Error:** `could not connect to server`

**Fix:**
1. Verify PostgreSQL service is running (Railway dashboard)
2. Check `DATABASE_URL` is automatically set (should be)
3. Try connecting manually:
   ```bash
   # In Railway Shell
   python3 -c "import asyncpg; import os; asyncpg.connect(os.environ['DATABASE_URL'])"
   ```

### "Admin access required" Error

**Problem:** Can't access admin endpoints even as admin

**Fix:**
```bash
# Re-connect to database
psql "<Railway connection URL>"

# Verify admin flag
SELECT username, is_admin FROM players WHERE username = 'admin';

# If is_admin is false:
UPDATE players SET is_admin = true WHERE username = 'admin';
```

### Rate Limiting Not Working

**Problem:** Can spam endpoints unlimited times

**Cause:** Railway load balancer uses different IPs

**Fix:** Should work correctly with slowapi's `get_remote_address` - it checks `X-Forwarded-For` header. If still issues, check Railway logs to see what IP is being used.

---

## Updating Your App

### Automatic Deploys (Recommended)

Railway redeploys automatically on every push to main:

```bash
# Make changes
git add .
git commit -m "Add new feature"
git push origin main

# Railway automatically:
# 1. Pulls latest code
# 2. Runs migrations (alembic upgrade head)
# 3. Restarts service
# 4. Runs health check
```

### Manual Deploy

In Railway dashboard:
1. Click service
2. **"Deployments"** tab
3. Click **"Deploy"** button

### Rollback

If deployment breaks:

1. **"Deployments"** tab
2. Find last working deployment
3. Click **"⋮"** → **"Redeploy"**

---

## Scaling

### Vertical Scaling (More Resources)

1. Railway dashboard → Service → **"Settings"**
2. Under **"Resources"**
3. Upgrade plan:
   - Starter: 1 GB RAM ($5/month)
   - Pro: 8 GB RAM ($20/month)

### Horizontal Scaling (More Instances)

**Not needed for initial launch.**

When you reach 100+ concurrent users:
1. Settings → **"Replicas"**
2. Set to 2-4 instances
3. Requires Pro plan ($20/month)
4. May need Redis for rate limiting (see RAILWAY_DEPLOYMENT.md)

---

## Cost Summary

| Plan | Monthly | Good For |
|------|---------|----------|
| **Free** | $0 (with $5 credit) | Development only |
| **Starter** | $5 | Launch, up to ~100 users |
| **Pro** | $20 | Scaling, 100+ concurrent users |

**Additional costs:**
- PostgreSQL: Included in plan
- Custom domain: Free (bring your own)
- Redis: $3-5/month (only if needed for scaling)

---

## Security Checklist

Before announcing to public:

- [ ] `ENVIRONMENT=production` set
- [ ] `SECRET_KEY` is 64+ random characters
- [ ] `CORS_ORIGINS` uses HTTPS (not HTTP)
- [ ] Admin user created with strong password (12+ chars)
- [ ] Health check returns 200 OK
- [ ] Admin endpoints require authentication (test with curl)
- [ ] Rate limiting works (test 11 rapid logins)
- [ ] Logs show no errors
- [ ] Database backups configured
- [ ] Monitoring set up (UptimeRobot or similar)

---

## Support Resources

- **Railway Docs:** https://docs.railway.app/
- **Railway Discord:** https://discord.gg/railway
- **Server Logs:** Railway dashboard → Service → Logs
- **Database Access:** Railway dashboard → PostgreSQL → Connect

---

## Quick Reference Commands

```bash
# Generate SECRET_KEY
python3 -c "import secrets; print(secrets.token_urlsafe(64))"

# Connect to production database
psql "<Railway PostgreSQL connection URL>"

# Test health endpoint
curl https://your-app.up.railway.app/health

# Login as admin
curl -X POST https://your-app.up.railway.app/auth/login \
  -d "username=admin&password=YourPassword"

# Check server status (admin only)
curl https://your-app.up.railway.app/admin/status \
  -H "Authorization: Bearer YOUR_TOKEN"

# View API docs
open https://your-app.up.railway.app/docs

# Backup database
pg_dump "$DATABASE_URL" > backup.sql

# Restore database
psql "$DATABASE_URL" < backup.sql
```

---

## You're Live! 🚀

Your Claim server is now running in production.

**Next steps:**
1. Test with Godot client
2. Invite friends for alpha testing
3. Monitor Railway logs for issues
4. Iterate based on feedback

**Questions?** See:
- [DEVELOPMENT.md](DEVELOPMENT.md) - Local development
- [RAILWAY_DEPLOYMENT.md](RAILWAY_DEPLOYMENT.md) - Detailed Railway guide
- [SECURITY_AUDIT.md](SECURITY_AUDIT.md) - Security features
- [AUTH_SECURITY.md](AUTH_SECURITY.md) - Authentication details

Good luck with your launch! 🎮
