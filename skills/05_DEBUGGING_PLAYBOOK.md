# 05 — Debugging Playbook

**Purpose:** Where the logs are, then each symptom (by its exact message) with its causes by frequency and a diagnostic shortcut. Add useful commands.

**Confidence note:** inferred from architecture and db-design-choices.md on 2026-11-23. The code wins (see 16).

---

## Log Locations

| Component | Log Location | Access |
|-----------|--------------|--------|
| **grab-it-api** | Supabase Logs / Postgres logs | Supabase Dashboard → Logs |
| **grab-it-api** | Application logs (stdout/stderr) | Hosting platform (Vercel, Railway, etc.) |
| **grab-it-web** | Browser DevTools Console | F12 → Console |
| **grab-it-web** | Network tab | F12 → Network (filter: fetch/XHR) |
| **grab-it-android** | Logcat | `adb logcat` or Android Studio Logcat |
| **grab-it-android** | SQLite database | `adb shell` → `sqlite3 /data/data/<pkg>/databases/<db>` |
| **Sync** | Correlation ID in all logs | Generate per sync cycle; search across components |

---

## Common Symptoms & Diagnostics

### 1. "Row not syncing" / "Edits never reach server"

| Frequency | Cause | Diagnostic Shortcut |
|-----------|-------|---------------------|
| High | `updated_at` not bumped on local edit | Check entity: `updatedAt` = `createdAt` after edit → **Miss → bump `updatedAt` on every mutation** |
| High | `synchronized_at` written on edit (not just sync) | Query: `SELECT * FROM note WHERE synchronizedAt = updatedAt AND synchronizedAt IS NOT NULL` → should be 0 for dirty rows |
| Medium | Push allowlist excludes column | Check API push handler: column in allowlist? |
| Medium | Network/auth failure | Logcat: `SyncEngine` → look for 401/403/5xx |
| Low | UUID collision (two clients same UUID) | Server logs: `ON CONFLICT (uuid)` → check `created_by` differs |

**Quick check:** `adb shell sqlite3 db "SELECT uuid, updatedAt, synchronizedAt FROM note WHERE synchronizedAt IS NULL OR synchronizedAt <> updatedAt;"` — should show dirty rows.

---

### 2. "Duplicate rows after sync" / "Same data appears twice"

| Frequency | Cause | Diagnostic Shortcut |
|-----------|-------|---------------------|
| High | Natural-key adoption not working | Pull logic: does it check `(note_uuid, tag_uuid)` before insert? |
| Medium | Client generated different UUIDs for same logical record | Search server: `SELECT uuid, created_by FROM note WHERE title = 'X' AND body = 'Y';` |
| Low | Push without LWW → both inserted | Server logs: upsert `ON CONFLICT` path taken? |

**Quick check:** Server: `SELECT uuid, title, created_by, created_at FROM note ORDER BY created_at DESC LIMIT 20;`

---

### 3. "Deleted row reappears" / "Delete not syncing"

| Frequency | Cause | Diagnostic Shortcut |
|-----------|-------|---------------------|
| High | Hard `DELETE` used instead of `archived_at` | Check SQL: `DELETE FROM note` vs `UPDATE note SET archived_at = now()` |
| High | Pull excludes archived rows | API pull query: `WHERE archived_at IS NULL` → **Miss → pull must include archived** |
| Medium | Partial unique index missing | Server: `\d note_tag` → look for `WHERE archived_at IS NULL` index |
| Medium | Client doesn't apply tombstone on pull | Android: pull handler sets `archivedAt` from server? |

**Quick check:** Server: `SELECT uuid, archived_at FROM note WHERE archived_at IS NOT NULL ORDER BY archived_at DESC;`

---

### 4. "Unique constraint violation on sync" / "Duplicate key error"

| Frequency | Cause | Diagnostic Shortcut |
|-----------|-------|---------------------|
| High | Partial unique index missing on server | `\d <table>` → check `WHERE archived_at IS NULL` |
| High | Client inserts duplicate live row locally | Android: `UNIQUE` index on `(notebook_uuid, title) WHERE archivedAt IS NULL`? |
| Medium | Natural key collision (two clients same logical record) | Check `created_by` differs on same natural key |

**Quick check:** Server: `SELECT * FROM note_tag WHERE archived_at IS NULL AND note_uuid = 'X' AND tag_uuid = 'Y';`

---

### 5. "Authentication failed" / "401 on sync"

| Frequency | Cause | Diagnostic Shortcut |
|-----------|-------|---------------------|
| High | Token expired | Logcat: `AuthRepository` → token refresh failure |
| High | Google Sign-In token not sent | Network tab: `Authorization: Bearer <token>` header present? |
| Medium | Supabase Auth misconfigured | API logs: `JWT validation failed` |
| Low | Clock skew (token `exp` in past) | Device time vs server time |

**Quick check:** `adb logcat | grep -i "token\|auth\|401"`

---

### 6. "Migration failed" / "Schema mismatch"

| Frequency | Cause | Diagnostic Shortcut |
|-----------|-------|---------------------|
| High | Migration not idempotent (re-run fails) | Check `IF NOT EXISTS`, `ADD COLUMN IF NOT EXISTS` |
| High | Client migration guard failed | `PRAGMA table_info(note)` → column exists? |
| Medium | Migration order wrong (FK before table) | Migration filenames: `NNNN_` prefix = order |
| Medium | Server migration applied, client not upgraded | Version check: client `dbVersion` vs server migration |

**Quick check:** Android: `adb shell sqlite3 db "PRAGMA table_info(note);"` — compare to migration.

---

### 7. "Sync extremely slow" / "Timeout on pull"

| Frequency | Cause | Diagnostic Shortcut |
|-----------|-------|---------------------|
| High | No delta pull — full dataset every time | API pull: `SELECT * FROM note` (no cursor/version) |
| High | Missing index on scoped pull column | `EXPLAIN ANALYZE SELECT * FROM note WHERE workspace_uuid = 'X';` |
| Medium | Large `jsonb` column pulled unnecessarily | Select only needed columns |
| Low | Network latency | `ping api.grab-it.com` |

**Quick check:** API logs: pull query duration + row count.

---

### 8. "Data loss on concurrent edit" / "Older edit won"

| Frequency | Cause | Diagnostic Shortcut |
|-----------|-------|---------------------|
| High | Client clock fast → `updated_at` in future | Device time vs NTP |
| High | Server LWW not enforced (missing `WHERE`) | Check upsert: `WHERE note.updated_at < EXCLUDED.updated_at` |
| Medium | Pull overwrote dirty row | Pull handler: `if (local.updatedAt > server.updatedAt) skip` |

**Quick check:** Server: `SELECT uuid, updated_at, created_by FROM note ORDER BY updated_at DESC LIMIT 10;`

---

## Useful Commands

### Android (adb)
```bash
# View sync logs
adb logcat -s SyncEngine:D AuthRepository:D

# Inspect SQLite database
adb shell
sqlite3 /data/data/com.grab.it/databases/grab_it.db
.tables
.schema note
SELECT uuid, title, updatedAt, synchronizedAt, archivedAt FROM note;
SELECT * FROM note WHERE synchronizedAt IS NULL OR synchronizedAt <> updatedAt;
.exit

# Pull database to host for analysis
adb exec-out run-as com.grab.it cat databases/grab_it.db > grab_it.db
sqlite3 grab_it.db
```

### Server (Supabase/Postgres)
```sql
-- Check table structure
\d note

-- Check indexes
\di idx_note*

-- Recent sync activity
SELECT uuid, updated_at, archived_at, created_by
FROM note
ORDER BY updated_at DESC
LIMIT 20;

-- Orphaned children (parent missing)
SELECT n.uuid, n.notebook_uuid
FROM note n
LEFT JOIN notebook nb ON nb.uuid = n.notebook_uuid
WHERE n.notebook_uuid IS NOT NULL AND nb.uuid IS NULL;

-- Soft delete status
SELECT count(*) AS live FROM note WHERE archived_at IS NULL;
SELECT count(*) AS archived FROM note WHERE archived_at IS NOT NULL;

-- Partial unique index check
SELECT indexname, indexdef FROM pg_indexes WHERE tablename = 'note_tag';
```

### Web (Browser DevTools)
```javascript
// In console: inspect sync state
// Network tab: filter "sync" or "push" or "pull"
// Check request/response payloads
// Application tab: IndexedDB / LocalStorage for offline data
```

### Git / Release
```bash
# Verify commit scopes
git log --oneline -20 --grep="^grab-it-"

# Check tag derivation (per git-guidelines)
git tag --sort=creatordate | tail -10

# Find commits since last tag
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

---

## Debugging Checklist (When Stuck)

1. **Reproduce locally** — same steps, same data
2. **Correlation ID** — search logs across all components
3. **Check the lockstep set** (04_CHANGE_RULES) — did all files change?
4. **Verify invariants** — `updated_at` bumped? `synchronized_at` only by sync? Soft delete used?
5. **Compare schemas** — server migration vs client migration vs types
6. **Check clocks** — device time, server time, NTP
7. **Minimal repro** — strip to one entity, one client, one edit
8. **Add logging** — temporary `DEBUG` logs at decision points
9. **Check INBOX/06_FAILURE_STORIES** — seen this before?