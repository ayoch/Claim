# Deployment Guide: Bug Reporting System

## Prerequisites

✅ All code changes committed to Git
✅ Server repository on Railway connected to GitHub
✅ Admin access to Railway dashboard

## Step 1: Run Database Migration

### Option A: Local Migration (Recommended)

```bash
cd /Users/jonathanboyd/Desktop/Claim/Claim/server

# Activate virtual environment
source .venv/bin/activate

# Run migration
alembic upgrade head

# Verify table was created
psql $DATABASE_URL -c "\dt bug_reports"
```

### Option B: Railway Auto-Migration

Migration will run automatically on next deployment via `railway.toml`:

```toml
[deploy]
startCommand = "alembic upgrade head && uvicorn server.main:app --host 0.0.0.0 --port $PORT"
```

## Step 2: Deploy to Railway

### Method 1: Git Push (Automatic)

```bash
cd /Users/jonathanboyd/Desktop/Claim/Claim

# Commit all changes
git add .
git commit -m "Add bug reporting system with sanitization"

# Push to main branch (triggers Railway deployment)
git push origin main
```

Railway will automatically:
1. Pull latest code
2. Run `alembic upgrade head` (migration)
3. Restart server with new endpoints

### Method 2: Manual Deployment (Railway Dashboard)

1. Go to https://railway.app/dashboard
2. Select "claim-production-066b" project
3. Click "Deployments" tab
4. Click "Deploy Now" or "Redeploy"

## Step 3: Verify Deployment

### Check Server Health

```bash
curl https://claim-production-066b.up.railway.app/health
# Expected: {"status":"ok"}
```

### Test Bug Report Endpoint

```bash
# Submit a test report
curl -X POST https://claim-production-066b.up.railway.app/api/bug-reports \
  -H "Content-Type: application/json" \
  -d '{
    "title": "Test report deployment",
    "description": "Testing the new bug reporting system after deployment",
    "category": "General",
    "game_version": "0.1.0",
    "backend_mode": "server",
    "reporter_username": "Admin"
  }'

# Expected: JSON response with report ID
```

### Verify Database

```bash
# Connect to Railway PostgreSQL
railway connect

# In psql shell
\dt bug_reports;                    # Verify table exists
SELECT * FROM bug_reports;          # View all reports
SELECT COUNT(*) FROM bug_reports;   # Count reports
```

## Step 4: Test Client Integration

### In Godot Editor

1. Open project in Godot 4.6
2. Check for compilation errors in Output panel
3. Run the game (F5)
4. Navigate to Settings menu
5. Click "🐛 Report a Bug"
6. Fill in form and submit

### Expected Behavior

**Local Mode:**
- Report saves to `user://bug_reports.json`
- Success message displays
- Dialog closes

**Server Mode:**
- HTTP POST to `/api/bug-reports`
- Server returns 201 Created
- Success message displays
- Report visible in database

## Step 5: Monitor Production

### Check Logs

```bash
# Railway CLI
railway logs

# Look for:
# - "POST /api/bug-reports" (submissions)
# - "GET /api/bug-reports" (admin views)
# - No 500 errors
```

### Check Rate Limiting

Submit 6 reports within 1 hour:
- First 5 should succeed (201)
- 6th should fail with 429 (rate limit)

### Check Sanitization

Submit report with HTML:
```json
{
  "title": "<script>alert('xss')</script>Test",
  "description": "<b>Bold text</b> and <script>malicious code</script>"
}
```

Expected result:
- HTML entities escaped: `&lt;script&gt;` etc.
- No script execution
- Text displayed safely

## Rollback Plan

If deployment fails:

### Option 1: Revert Git Commit

```bash
git revert HEAD
git push origin main
```

### Option 2: Downgrade Database

```bash
cd server
alembic downgrade -1  # Undo last migration
```

### Option 3: Railway Dashboard

1. Go to Deployments tab
2. Find previous working deployment
3. Click "Redeploy"

## Common Issues

### "Migration already applied"

If you see this error, the migration already ran. Check:
```sql
SELECT * FROM alembic_version;
-- Should show: 65573384f3cc
```

### "Table already exists"

The migration was partially applied. Options:
1. Drop table manually: `DROP TABLE bug_reports;`
2. Skip to next step (table is usable)

### "Rate limit exceeded"

Wait 1 hour or increase limit in `bug_reports.py`:
```python
@limiter.limit("10/hour")  # Increase from 5
```

### "Cannot import bug_reports"

Check that all files are in correct locations:
```bash
ls server/server/routers/bug_reports.py
ls server/server/models/bug_report.py
ls server/server/schemas/bug_report.py
```

## Success Criteria

✅ Migration runs without errors
✅ Server starts successfully
✅ `/health` endpoint returns 200
✅ POST `/api/bug-reports` accepts submissions
✅ Godot client compiles without errors
✅ Bug report dialog opens from Settings
✅ Form validation works
✅ Submissions save (local or server)
✅ HTML is escaped in database
✅ Rate limiting prevents spam
✅ Admin can view reports (next phase)

## Next Steps

After successful deployment:

1. **Test in production** - Submit real bug reports from game
2. **Monitor performance** - Check server logs for errors
3. **Build admin panel** - Web UI for viewing/managing reports
4. **User communication** - Announce feature to players
5. **Iterate** - Add features based on feedback

## Support

If issues persist:
- Check Railway logs: `railway logs`
- Check Alembic status: `alembic current`
- Verify database: `railway connect` → `\dt`
- Review error messages in production logs
