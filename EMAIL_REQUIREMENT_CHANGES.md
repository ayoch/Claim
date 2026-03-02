# Email Requirement Implementation - March 2, 2026

## Summary
Implemented required unique email addresses for all accounts as an anti-cheat measure. While determined users can still create multiple emails (Gmail aliases, temp emails), this catches many cases with minimal effort.

---

## Changes Made

### 1. Database Model (`server/server/models/player.py`)
**Changed email from optional to required:**
```python
# BEFORE:
email: Mapped[str | None] = mapped_column(String(255), unique=True, nullable=True, index=True)

# AFTER:
email: Mapped[str] = mapped_column(String(255), unique=True, nullable=False, index=True)
```

### 2. Pydantic Schema (`server/server/schemas/player.py`)
**Updated both input and output schemas:**
```python
# PlayerCreate - now requires email
class PlayerCreate(BaseModel):
    username: str = Field(..., min_length=3, max_length=32)
    email: EmailStr = Field(..., description="Required unique email address")  # Now required
    password: str = Field(..., min_length=8, max_length=128)

# PlayerOut - email always present
class PlayerOut(BaseModel):
    email: str  # Changed from str | None
```

### 3. Database Migration (`server/alembic/versions/d4e5f6a7b8c9_make_email_required.py`)
**Created migration that:**
- Deletes any existing players with NULL email (legacy accounts)
- Makes email column NOT NULL
- Includes rollback support

**To apply migration:**
```bash
cd server
alembic upgrade head
```

### 4. Backend Functions
**Updated all backend register functions to include email parameter:**

- `core/backend/server_backend.gd`:
  ```gdscript
  func register(username: String, password: String, email: String) -> Dictionary:
      var body := JSON.stringify({"username": username, "password": password, "email": email})
  ```

- `core/backend/backend_manager.gd`:
  ```gdscript
  func register(username: String, password: String, email: String) -> Dictionary:
      return await _active_backend.register(username, password, email)
  ```

- `core/backend/backend_interface.gd`:
  ```gdscript
  func register(username: String, password: String, email: String) -> Dictionary:
  ```

### 5. UI Changes (`ui/login_screen.gd`)
**Added email input and validation:**
- Added `@onready var email_input: LineEdit = %EmailInput`
- Added email validation in `_on_register()`:
  - Checks email is not empty
  - Basic format validation (contains @ and .)
  - Server-side handles full email validation with `EmailStr` type
- Updated `_set_processing()` to include email field
- Passes email to `BackendManager.register(username, password, email)`

---

## ⚠️ MANUAL STEP REQUIRED

### Add Email Input to Login Screen UI

You need to add an **EmailInput** LineEdit to `ui/login_screen.tscn` in the Godot editor:

1. Open `ui/login_screen.tscn` in Godot
2. Find the form container with `UsernameInput` and `PasswordInput`
3. Add a new `LineEdit` node between username and password
4. Configure it:
   - **Node Name:** `EmailInput`
   - **Unique Name:** Enabled (% symbol)
   - **Placeholder Text:** "Email address"
   - **Expand To Text Length:** Off
   - **Clear Button:** Enabled (recommended)
5. Save the scene

**Expected layout:**
```
VBoxContainer
├─ UsernameInput (LineEdit)
├─ EmailInput (LineEdit)  ← ADD THIS
├─ PasswordInput (LineEdit)
└─ Buttons...
```

---

## Testing Checklist

### Server-Side
- [ ] Run database migration: `cd server && alembic upgrade head`
- [ ] Verify no existing NULL emails in database
- [ ] Test registration with valid email
- [ ] Test registration with duplicate email (should fail)
- [ ] Test registration without email (should fail with validation error)
- [ ] Test registration with invalid email format (should fail)

### Client-Side
- [ ] Add EmailInput to login_screen.tscn (manual step above)
- [ ] Test UI shows email field
- [ ] Test email validation (empty, invalid format)
- [ ] Test registration success with valid email
- [ ] Test registration failure with duplicate email
- [ ] Test error messages display correctly

### Anti-Cheat Effectiveness
- [ ] Attempt to create multiple accounts with same email (should fail)
- [ ] Attempt to register without email (should fail)
- [ ] Verify legitimate users can create one account per email

---

## Known Limitations

This is **not a perfect anti-cheat solution**, but provides a good balance of security vs friction:

### Can Still Be Bypassed By:
1. **Gmail aliases:** `user+alt1@gmail.com`, `user+alt2@gmail.com` (same inbox)
2. **Temporary emails:** 10minutemail, guerrillamail, etc.
3. **Multiple email accounts:** Users can create unlimited Gmail/Outlook accounts
4. **Dot tricks:** Gmail ignores dots: `u.ser@gmail.com` == `user@gmail.com`

### Why This Is Still Valuable:
- **Catches casual cheaters** - most users won't bother with workarounds
- **Raises the effort barrier** - more annoying to maintain alt accounts
- **Foundation for future improvements** - can add email verification, age restrictions, etc.
- **Industry standard** - most online games require email
- **Account recovery** - enables password reset functionality

---

## Future Enhancements (Not Implemented)

### Phase 2: Email Verification
- Send verification code to email
- Accounts unverified until email confirmed
- Prevents temporary/fake emails

### Phase 3: Multi-Layer Anti-Cheat
- **Account age restrictions**: New accounts (< 7 days) have trade limits
- **Economic velocity monitoring**: Flag suspicious trading patterns
- **IP rate limiting**: Limit account creation per IP per day
- **Browser fingerprinting**: Detect multiple accounts from same device
- **Reputation system**: New accounts start with restrictions, earn privileges

### Phase 4: Advanced Detection
- **Gmail alias detection**: Normalize emails before uniqueness check
- **Disposable email blocking**: Blacklist known temp email domains
- **Machine learning**: Detect alt account behavior patterns

---

## Migration Path

### If You Have Existing Players with NULL Emails:

**Option 1: Delete them (migration does this automatically)**
- Simple, clean database
- Acceptable if server is in testing/beta

**Option 2: Require email update before next login**
- Preserve existing accounts
- Add migration logic to set placeholder emails
- Force email update on next login
- More complex, better for production with real users

The current migration uses **Option 1** (delete NULL emails). If you need Option 2, modify the migration:
```python
# Instead of DELETE, set placeholder:
op.execute("UPDATE players SET email = 'placeholder_' || id || '@example.com' WHERE email IS NULL")
```

---

## Files Modified

**Server:**
- `server/server/models/player.py`
- `server/server/schemas/player.py`
- `server/alembic/versions/d4e5f6a7b8c9_make_email_required.py` (new)

**Client:**
- `core/backend/server_backend.gd`
- `core/backend/backend_manager.gd`
- `core/backend/backend_interface.gd`
- `ui/login_screen.gd`
- `ui/login_screen.tscn` (requires manual edit in Godot)

**Documentation:**
- `EMAIL_REQUIREMENT_CHANGES.md` (this file)

---

## Rollback Plan

If you need to revert these changes:

1. **Database:** `cd server && alembic downgrade -1`
2. **Git:** `git revert <commit-hash>`
3. **Manual:** Remove EmailInput from login_screen.tscn

---

## Questions?

- **Q: Can users change their email after registration?**
  - A: Not currently implemented. Add a profile settings page to enable this.

- **Q: What about password reset?**
  - A: Email is now required, making password reset possible. Implement email sending next.

- **Q: Should we verify emails?**
  - A: Recommended for production. Implement email verification as Phase 2.

- **Q: What if someone registers with my email?**
  - A: First-come-first-served. With email verification, they'd need access to your inbox.
