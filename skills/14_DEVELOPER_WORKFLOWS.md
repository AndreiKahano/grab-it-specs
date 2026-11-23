# 14 — Developer Workflows

**Purpose:** Setup, then step-by-step recipes for common tasks, each linking the lockstep set or failure story it guards against. End each with "add what surprised you to `INBOX.md`".

**Confidence note:** inferred from git-guidelines.md, architecture, and db-design-choices.md on 2026-11-23. The code wins (see 16).

---

## Initial Setup

### Prerequisites
- Node.js 20+ (API, Web, Specs tooling)
- JDK 17+ (Android)
- Android Studio Ladybug+ (Android)
- Docker (Testcontainers for API tests)
- Git 2.40+
- Google Cloud project (OAuth credentials)
- Supabase project

### Clone & Install
```bash
git clone <ecosystem-repo> grab-it-ecosystem
cd grab-it-ecosystem

# API
cd grab-it-api
npm ci
cp .env.example .env.local  # fill in secrets

# Web
cd ../grab-it-web
npm ci
cp .env.example .env.local  # fill in VITE_* vars

# Android
cd ../grab-it-android
./gradlew dependencies  # verifies Gradle setup

# Specs
cd ../grab-it-specs
npm ci
```

### Verify Setup
```bash
# API tests
cd grab-it-api && npm test

# Web tests
cd grab-it-web && npm test

# Android tests (requires emulator/device)
cd grab-it-android && ./gradlew test

# Specs lint
cd grab-it-specs && npm run lint
```

---

## Common Tasks

### 1. Add a New Syncable Entity (Table)

**Lockstep set:** 04_CHANGE_RULES #1  
**Failure stories:** 06_FAILURE_STORIES #1, #4, #6, #9

**Steps:**
1. **Specs**: Edit `db-design-choices.md` — add table design, columns, relationships, denormalizations, natural key
2. **API**: Create migration `supabase/migrations/NNNN_add_<entity>.sql` (additive, idempotent, backfill, index)
3. **API**: Add sync endpoints in `src/routes/<entity>/` (push/pull, scoped, allowlist)
4. **API**: Write integration test (create → push → pull → edit → push → pull on second client)
5. **Android**: Add entity + DAO in `data/local/db/entity/`
6. **Android**: Add client migration in `data/local/db/migrations/` (guarded by `PRAGMA table_info`)
7. **Android**: Add to sync engine in `data/sync/<Entity>Sync.kt` (push dirty, pull scoped, orphan guard, natural-key adoption)
8. **Android**: Write integration test (Room test DB)
9. **Web**: Add TypeScript types in `src/types/<entity>.ts`
10. **Web**: Add API client methods in `src/lib/api/<entity>.ts`
11. **Web**: Add UI components as needed
12. **All**: Update 04_CHANGE_RULES if new lockstep pattern
13. **Commit**: Split per repo: `grab-it-api/<entity>: Add <entity> table and sync`, `grab-it-android/<entity>: Add <entity> local storage and sync`, `grab-it-web/<entity>: Add <entity> types and UI`
14. **Test**: Run full test suite on all three repos
15. **Manual drill**: Fresh install → create offline → sync → pull on second device → verify

**Add what surprised you to `INBOX.md`.**

---

### 2. Add a Column to Existing Syncable Table

**Lockstep set:** 04_CHANGE_RULES #1 (schema)  
**Failure stories:** 06_FAILURE_STORIES #7

**Steps:**
1. **Specs**: Update `db-design-choices.md` — document column, purpose, denormalization if any
2. **API**: Create migration `supabase/migrations/NNNN_add_<col>_to_<table>.sql`:
   - `ADD COLUMN IF NOT EXISTS`
   - Backfill `WHERE col IS NULL`
   - `CREATE INDEX IF NOT EXISTS` if queried
3. **API**: Add column to push allowlist (if client-writable) or keep server-only
4. **API**: Update TypeScript types (if shared) or regenerate
5. **Android**: Add client migration (guarded by `PRAGMA table_info`)
6. **Android**: Update entity + DAO
7. **Android**: If client-writable, ensure edit path bumps `updated_at`
8. **Web**: Update TypeScript types
9. **Web**: Update API client if needed
10. **Test**: Migration idempotency (run twice), upgrade path (old version → new)
11. **Commit**: Per repo with scopes
12. **Manual drill**: Upgrade existing install with data → verify column works

**Add what surprised you to `INBOX.md`.**

---

### 3. Fix a Sync Bug

**Lockstep set:** 04_CHANGE_RULES #2-6 (sync protocol)  
**Failure stories:** 06_FAILURE_STORIES #1, #2, #5, #8, #9  
**Debugging:** 05_DEBUGGING_PLAYBOOK

**Steps:**
1. **Reproduce**: Minimal steps (offline edit → sync → pull on second client)
2. **Correlation ID**: Add temporary logging with correlation ID across client → API → DB
3. **Diagnose**: Check 05_DEBUGGING_PLAYBOOK for symptom match
4. **Identify lockstep**: Which set was violated? (dirty check, LWW, soft delete, attribution, orphan guard, natural-key adoption)
5. **Fix**: Minimal change to restore invariant
6. **Test**: Add regression test for exact scenario (unit + integration)
7. **Verify**: Run all sync tests; manual drill with two clients
8. **Document**: Add to 06_FAILURE_STORIES if new pattern; update 04_CHANGE_RULES if new guard needed
9. **Commit**: `grab-it-api/sync: Fix <symptom> by <invariant restored>`, etc.
10. **Manual drill**: Original repro steps → verify fixed

**Add what surprised you to `INBOX.md`.**

---

### 4. Run a Database Migration

**Lockstep set:** 04_CHANGE_RULES (migration idempotency)  
**Failure stories:** 06_FAILURE_STORIES #7  
**Deployment:** 10_DEPLOYMENT

**Steps:**
1. **Verify**: Migration is additive, idempotent, gated (`IF NOT EXISTS`, `WHERE col IS NULL`)
2. **Test locally**: `npm run migrate` (API) → verify schema; run twice → no errors
3. **Test upgrade**: Install old version → create data → apply migration → verify data intact
4. **Stage**: Deploy to staging (auto on `beta` branch)
5. **Verify staging**: Health check + smoke test sync
6. **Promote**: `beta` → `release` after QA sign-off
7. **Deploy production**: Tag `BCN.0X.Y.00Z` on `release` branch → CI deploys
8. **Monitor**: Migration duration, error rate, sync success rate
9. **Rollback plan**: Previous tag (migrations additive → safe)

**Add what surprised you to `INBOX.md`.**

---

### 5. Release a New Version

**Versioning:** git-guidelines.md Part 2  
**Deployment:** 10_DEPLOYMENT  
**Testing:** 11_TESTING

**Steps:**
1. **Confirm**: WBS/Gantt 100% complete; only testing/defects remain
2. **Promote**: `main` → `beta` (reviewed merge)
3. **Beta test**: System testing + manual drills (11_TESTING)
4. **Fix defects**: On `beta`, cherry-pick to `main`
5. **Promote**: `beta` → `release` (reviewed merge)
6. **Build & publish**: CI builds all components, publishes to release website
7. **Alpha**: Tag `WCN.0X.Y.00Za`, `BCN.0X.Y.00Za`, `ACN.0X.Y.00Za` → internal test
8. **Beta**: Tag `...b` → wider test
9. **RC**: Tag `...rc` → final regression
10. **Iterate**: Defects → `a2`, `b2`, `rc2` (same build number)
11. **Approve**: Final approver signs off on `rcN`
12. **Deploy**: Exact approved tag to production
13. **Record**: Update git-guidelines.md release tables, 00_INDEX.md changelog
14. **Post-release**: Process INBOX.md, retrospective

**Add what surprised you to `INBOX.md`.**

---

### 6. Debug a Production Issue

**Debugging:** 05_DEBUGGING_PLAYBOOK  
**Failure stories:** 06_FAILURE_STORIES

**Steps:**
1. **Correlation ID**: Get from user report / logs / Sentry
2. **Search logs**: All components (API, Web, Android) for correlation ID
3. **Check symptoms**: Match to 05_DEBUGGING_PLAYBOOK
4. **Check failure stories**: Known pattern in 06_FAILURE_STORIES?
5. **Reproduce locally**: Minimal steps with same data
6. **Fix**: Follow "Fix a Sync Bug" or relevant workflow
7. **Hotfix**: If critical, cherry-pick to `release` branch, tag `rcN+1`, deploy
8. **Post-mortem**: Add to 06_FAILURE_STORIES if new; update 15_KNOWN_LIMITATIONS

**Add what surprised you to `INBOX.md`.**

---

### 7. Update a Dependency

**Dependencies:** 13_DEPENDENCIES  
**Testing:** 11_TESTING

**Steps:**
1. **Monthly (security)**: `npm audit fix` / `gradle dependencyCheckUpdate` → PR → auto-merge if green
2. **Quarterly (feature)**: Pick 1-2 deps → read changelog → update in branch → test → PR
3. **Major version**: Spike (2 days max) → if blocked, INBOX.md → defer
4. **Never skip minors**: Update sequentially
5. **Lockfile**: Commit `package-lock.json` / `gradle.lockfile` with update

**Add what surprised you to `INBOX.md`.**

---

### 8. Add a New API Endpoint

**API:** 08_API  
**Lockstep set:** 04_CHANGE_RULES #1  
**Security:** 09_SECURITY

**Steps:**
1. **Specs**: Document route, auth, request/response, errors in spec
2. **API**: Add handler in `src/routes/<resource>/`
3. **API**: Add Zod validation (body, query, params)
4. **API**: Add RLS policy or query filter for scoping
5. **API**: Write integration test (happy + auth + validation + scoping)
6. **Web**: Add TypeScript types in `src/types/`
7. **Web**: Add API client method in `src/lib/api/`
8. **Android**: Add Retrofit interface + DTO + repository method
9. **Security review**: Check 09_SECURITY checklist
10. **Commit**: Per repo with scopes
11. **Test**: Full suite + manual drill

**Add what surprised you to `INBOX.md`.**

---

### 9. Onboard a New Developer

**Setup:** This document (Initial Setup)  
**Architecture:** 01_ARCHITECTURE  
**Project structure:** 02_PROJECT_STRUCTURE  
**Code style:** 03_CODE_STYLE

**Steps:**
1. **Read**: 01_ARCHITECTURE, 02_PROJECT_STRUCTURE, 03_CODE_STYLE, 04_CHANGE_RULES
2. **Setup**: Run Initial Setup → verify all tests pass
3. **Pair**: Walk through "Add a New Syncable Entity" with buddy
4. **First task**: Small bug fix (sync or UI) with full workflow
5. **Review**: First PR gets extra review on commit scope, lockstep sets
6. **Retrospective**: After 1 week, what was confusing? → INBOX.md

**Add what surprised you to `INBOX.md`.**

---

### 10. Handle a Security Incident

**Security:** 09_SECURITY  
**Failure stories:** 06_FAILURE_STORIES #3, #5

**Steps:**
1. **Detect**: Alert / report / audit finding
2. **Contain**: Revoke tokens; disable API key; block IP; rotate secrets
3. **Investigate**: Correlation ID logs; audit trail (`created_by`, `*_by`)
4. **Remediate**: Patch; rotate all related secrets; deploy
5. **Verify**: Penetration test / security scan
6. **Post-mortem**: Add to 06_FAILURE_STORIES; update 15_KNOWN_LIMITATIONS
7. **Notify**: Stakeholders per policy

**Add what surprised you to `INBOX.md`.**

---

## Git Workflow

### Branch Strategy
- `main` — development (commit directly or short-lived feature branches)
- `beta` — QA/system testing (promoted from `main`)
- `release` — release testing (promoted from `beta`)
- **No long-lived feature branches** — integrate daily

### Commit Rules (from git-guidelines.md)
```
scope: Imperative summary

Why this change was necessary. Wrap at 72 chars.

Fixes #1234 — Ticket description
See-also #1201 — Related change
```

### Scope Examples
- `grab-it-api/sync: Retry failed record pulls`
- `grab-it-web/auth: Keep password errors beside the field`
- `grab-it-android/sync: Preserve drafts when switching tabs`
- `grab-it-specs/schema: Clarify soft-delete columns`

### PR Process
1. Branch from `main` (or commit directly to `main` for small changes)
2. CI runs: format, lint, typecheck, unit, integration
3. Review: At least one approval; check lockstep sets
4. Merge to `main` (squash or rebase; preserve commit message)
5. Delete branch

---

## Code Review Checklist

- [ ] Scope follows conventions (product/feature)
- [ ] Summary passes one-sentence test
- [ ] No silent failures (`Miss →` comments)
- [ ] Attribution columns not accepted from client
- [ ] `updated_at` bumped on every mutation
- [ ] `synchronized_at` only written by sync
- [ ] Soft delete used (`archived_at`)
- [ ] Migration additive, idempotent, gated
- [ ] Lockstep set updated (04_CHANGE_RULES)
- [ ] Tests cover happy path + error cases
- [ ] No PII in logs
- [ ] Dependencies justified (if new)

---

## Useful Commands

### Sync Debugging
```bash
# Android: view sync logs
adb logcat -s SyncEngine:D AuthRepository:D

# Android: inspect database
adb exec-out run-as com.grab.it cat databases/grab_it.db > grab_it.db
sqlite3 grab_it.db "SELECT uuid, updatedAt, synchronizedAt, archivedAt FROM note;"

# Server: recent sync activity
psql $SUPABASE_URL -c "SELECT uuid, updated_at, archived_at, created_by FROM note ORDER BY updated_at DESC LIMIT 20;"

# Server: orphaned children
psql $SUPABASE_URL -c "SELECT n.uuid, n.notebook_uuid FROM note n LEFT JOIN notebook nb ON nb.uuid = n.notebook_uuid WHERE n.notebook_uuid IS NOT NULL AND nb.uuid IS NULL;"
```

### Git/Release
```bash
# Verify commit scopes
git log --oneline -20 --grep="^grab-it-"

# Check tags
git tag --sort=creatordate | tail -10

# Commits since last tag
git log $(git describe --tags --abbrev=0)..HEAD --oneline
```

### Database
```bash
# API: run migrations
cd grab-it-api && npm run migrate

# API: generate types (if using)
cd grab-it-api && npm run generate:types
```

---

## Cross-References

| Task | Guards Against | References |
|------|----------------|------------|
| New entity | Schema drift, missing lockstep | 04_CHANGE_RULES #1, 06_FAILURE_STORIES #1, #4, #6, #9 |
| Add column | Migration failure, drift | 04_CHANGE_RULES #1, 06_FAILURE_STORIES #7 |
| Fix sync bug | Silent data loss, corruption | 05_DEBUGGING_PLAYBOOK, 06_FAILURE_STORIES #1, #2, #5, #8, #9 |
| Run migration | Deploy failure, data loss | 10_DEPLOYMENT, 06_FAILURE_STORIES #7 |
| Release | Untested code in prod | 10_DEPLOYMENT, 11_TESTING |
| Debug prod | Slow resolution, recurrence | 05_DEBUGGING_PLAYBOOK, 06_FAILURE_STORIES |
| Update dep | Vulnerability, breakage | 13_DEPENDENCIES, 11_TESTING |
| New endpoint | Scoping bug, validation gap | 08_API, 09_SECURITY, 04_CHANGE_RULES #1 |
| Onboard | Knowledge gaps | 01_ARCHITECTURE, 02_PROJECT_STRUCTURE, 03_CODE_STYLE |
| Security incident | Recurrence, blind spots | 09_SECURITY, 06_FAILURE_STORIES #3, #5 |