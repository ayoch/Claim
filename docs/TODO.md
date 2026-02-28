# Claim — Open Tasks
*Updated: 2026-02-28. Keep this current. Add things as they come up, strike them when done.*

---

## Deployment Blockers
*Must be done before Railway goes live.*

- [ ] Make `base_url` configurable in `core/backend/server_backend.gd` — currently hardcoded to `http://localhost:3000` (wrong port, wrong host). Should fall back to localhost:8000 for dev, read real URL from config for production.
- [ ] Add `server/Procfile` — tells Railway how to start the server: `web: uvicorn server.main:app --host 0.0.0.0 --port $PORT`
- [ ] Set up Railway account, connect GitHub repo, add PostgreSQL, set env vars, deploy from `main` branch

---

## Testing
*Do before or alongside deployment.*

- [ ] Run `test_local.py` on Mac to confirm server works end-to-end (has never been formally verified)
- [ ] Run `partnership_test.gd` to validate partnership system (created session 18, never run)
- [ ] Test partnership system at 200,000x speed for stability

---

## Client UI
- [ ] **Fuel warning on dispatch** — before player hits dispatch, show estimated fuel burn for the trip and flag if it will likely run dry. Client-side only, no server changes needed. Same math as server `_transit_time_seconds()`.
- [ ] **Torpedo restocking UI** — backend has been complete since session 16. Just needs the UI panel wired up.

---

## Server — Known Gaps
- [ ] **Partnership fuel constraint** — leader doesn't validate follower's fuel capacity before dispatching a pair. Low priority until partnerships are tested.
- [ ] **Orphaned shadow mission cleanup** — if a partnership leader is destroyed mid-mission, the follower's shadow mission is orphaned. Needs cleanup logic in ship destruction handler.

---

## Server — Security (Lower Priority)
*Not blockers — address during testing phase.*

- [ ] JWT expiry is 7 days — fine for a phone app but worth revisiting if refresh tokens get implemented
- [ ] Database connection pool limits not configured
- [ ] OWASP ZAP scan before public launch

---

## Deferred / Future
*Not for now. Noted so they don't get lost.*

- Refresh token system (JWT)
- Push notifications — Android/iOS native plugins needed (see `docs/MOBILE_NOTIFICATIONS.md`)
- Spatial partitioning for orbital calculations at very high player counts (see `performance_analysis.md`)
