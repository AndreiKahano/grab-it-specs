# 11 — Testing

**Purpose:** Honest coverage, how the team gains confidence, what must be tested, manual drills, mocking, and the dimensions that break.

**Confidence note:** inferred from architecture, git-guidelines.md, and db-design-choices.md on 2026-11-23. The code wins (see 16).

---

## Testing Philosophy

- **Test the lockstep sets** (04_CHANGE_RULES) — they cause most incidents
- **Test failure stories** (06_FAILURE_STORIES) — regression for every incident
- **Test at the boundaries** — auth, scoping, sync, migrations
- **Honest coverage** — don't count lines; count scenarios that matter
- **Fast feedback** — unit < integration < e2e < manual

---

## Test Pyramid (Target Distribution)

| Layer | % | Speed | Scope | Tools |
|-------|---|-------|-------|-------|
| **Unit** | 60% | <1s | Pure functions, validators, mappers, LWW logic | Vitest, JUnit |
| **Integration** | 30% | 1-10s | Repository + DB, API handlers, sync engine | Testcontainers, Supertest, Room test DB |
| **E2E** | 8% | 10-60s | Critical user flows (auth, sync, CRUD) | Playwright, Espresso |
| **Manual** | 2% | Hours | Exploratory, usability, edge cases | Checklists |

---

## What Must Be Tested (Non-Negotiable)

### 1. Sync Protocol (Core)
| Scenario | Layer | Key Assertions |
|----------|-------|----------------|
| Create offline → push → pull on second client | Integration | Row exists on both; `synchronized_at` clean |
| Edit offline → push → pull | Integration | `updated_at` bumped; LWW wins |
| Concurrent edit (two clients) → sync both | Integration | Newer `updated_at` wins; delete wins tie |
| Delete → push → pull on other client | Integration | Tombstone received; row soft-deleted locally |
| Re-add deleted (same natural key) | Integration | Partial unique index allows; no duplicate |
| Child before parent in pull | Integration | Orphan guard skips; retries next sync |
| Natural-key adoption (two UUIDs, same logical) | Integration | Local row updated with server UUID |
| Clock skew (future `updated_at`) | Unit + Integration | Server rejects >30s future; NTP warn on client |
| Large dataset delta pull | Integration | `since` cursor returns only changes |

### 2. Authentication & Authorization
| Scenario | Layer | Key Assertions |
|----------|-------|----------------|
| Google ID token → session | Integration | Valid token → access+refresh; invalid → 401 |
| Token refresh rotation | Integration | Old refresh revoked; new pair issued |
| Cross-user data access attempt | Integration | User A cannot read User B's notes (RLS/app filter) |
| Forged `created_by` in push | Integration | Server overwrites with `auth.uid()` |
| Expired token on sync | Integration | 401 → client triggers refresh → retry |
| Rate limit exceeded | Integration | 429 with `Retry-After` |

### 3. Database & Migrations
| Scenario | Layer | Key Assertions |
|----------|-------|----------------|
| Migration idempotent (run twice) | Integration | Second run succeeds; no errors |
| Migration on fresh install | Integration | Schema matches latest |
| Migration upgrade path (vN → vN+1) | Integration | Real data upgrades; no data loss |
| Soft delete uniqueness | Unit | Partial unique index allows re-add |
| Server FK absent → child-before-parent works | Integration | Child inserts; parent later → consistent |
| Client FK present → local integrity | Unit | SQLite FK violation on bad local write |

### 4. API Contract
| Scenario | Layer | Key Assertions |
|----------|-------|----------------|
| Request validation (UUID, enum, timestamp) | Unit | Invalid → 400 VALIDATION_ERROR |
| Response envelope (success/error) | Unit | Matches spec exactly |
| Scoping on every data endpoint | Integration | Only user's data returned |
| Push allowlist excludes attribution | Unit | `created_by` stripped; server stamps |
| Versioning (v1 vs v2) | Integration | v1 still works after v2 deploy |

---

## Mocking Strategy

| Dependency | Mock Approach |
|------------|---------------|
| **Supabase/Postgres** | Testcontainers (real Postgres) for integration; **never mock SQL** |
| **Google OAuth** | Mock ID token verification; test with valid/invalid/expired tokens |
| **Network** | MSW (Mock Service Worker) for web E2E; `MockWebServer` for Android |
| **Time** | Fixed clock in tests (`now() = 2026-11-23T10:00:00Z`); test skew separately |
| **File system** | Real temp dirs; no mocking |
| **Crypto/UUID** | Real implementations; deterministic seeds for reproducibility |

**Rule:** Mock external services (Google, network), not your own database or logic.

---

## Test Data Management

| Approach | When |
|----------|------|
| **Factories** (not fixtures) | All tests — `createNote({ overrides })` |
| **Scoped to test** | Each test gets fresh DB (transaction rollback or new container) |
| **Realistic but minimal** | Only fields needed for the scenario |
| **Natural keys explicit** | Factory ensures `(workspace_uuid, title)` unique for adoption tests |

---

## Manual Drills (Pre-Release Checklist)

Perform on `beta` branch before `release` promotion:

1. **Fresh install + sign in** — Web and Android
2. **Offline create** — Airplane mode → create note → online → sync
3. **Cross-device sync** — Create on Web → sync → open Android → verify
4. **Concurrent edit** — Edit same note on Web and Android offline → sync both
5. **Delete & re-add** — Delete tag → re-add same tag → verify no error
6. **Large workspace** — 1000+ notes → measure sync time
7. **Token expiry** — Wait for access token expiry → attempt sync → verify refresh
8. **Migration upgrade** — Install old version → create data → upgrade → verify
9. **Permission boundary** — Two users, same workspace → verify isolation
10. **Error recovery** — Kill network mid-sync → restore → verify no data loss

**Record:** Sync time, error rate, any surprises → add to INBOX.md

---

## Dimensions That Break (Where Bugs Hide)

| Dimension | Why It Breaks | Test Focus |
|-----------|---------------|------------|
| **Time** | Clock skew, DST, leap seconds, timestamp precision | Fixed clock + skew injection |
| **Order** | Child before parent, push/pull interleaving, batch partial failure | Permutation tests |
| **Scale** | 10 → 10K → 1M rows; delta pull vs full pull | Load test with realistic data |
| **Partial data** | Client has subset; joins miss parents | Scoped pull + orphan guard |
| **Conflict** | Same row, two clients, same second | LWW tie-breaker (delete wins) |
| **Migration** | Upgrade path, idempotency, legacy columns | Fresh + upgrade + double-run |
| **Auth** | Token expiry, refresh rotation, revocation | Time travel + concurrent refresh |
| **Network** | Flaky, slow, timeout, reorder | Chaos mesh / throttling |

---

## CI/CD Test Gates

| Stage | Runs | Must Pass |
|-------|------|-----------|
| **Pre-commit** | Format, lint, typecheck | All |
| **PR** | Unit + Integration (DB in Testcontainers) | All |
| **Main** | Full suite + E2E (staging deploy) | All |
| **Beta** | Manual drills + performance baseline | Manual sign-off |
| **Release** | Regression suite on `release` branch | All + approver sign-off |

---

## Coverage Targets (Honest)

| Area | Target | Measurement |
|------|--------|-------------|
| Sync engine (push/pull/LWW) | 100% branches | Branch coverage |
| Auth/authorization | 100% branches | Branch coverage |
| Validators (request/response) | 100% branches | Branch coverage |
| Migrations | 100% scripts run | Integration test count |
| API handlers | 90% lines | Line coverage (excl. trivial) |
| UI components | 70% lines | Line coverage |
| **Overall** | **Not a number** | **Scenario coverage** (see "What Must Be Tested") |

**Rule:** A scenario in "What Must Be Tested" without a test is a gap, regardless of coverage %.

---

## Test Commands

### grab-it-api
```bash
# Unit + Integration
npm test

# With Testcontainers (requires Docker)
npm run test:integration

# E2E against staging
npm run test:e2e -- --env=staging
```

### grab-it-web
```bash
# Unit
npm test

# E2E (Playwright)
npm run test:e2e

# Visual regression
npm run test:visual
```

### grab-it-android
```bash
# Unit
./gradlew test

# Integration (Room test DB)
./gradlew connectedAndroidTest

# E2E (Espresso)
./gradlew connectedAndroidTest -Pandroid.testInstrumentationRunnerArguments.class=com.grab.it.e2e.SyncTest
```

---

## Cross-References

| Topic | Document |
|-------|----------|
| Lockstep sets to test | 04_CHANGE_RULES |
| Failure stories as regression | 06_FAILURE_STORIES |
| Debugging test failures | 05_DEBUGGING_PLAYBOOK |
| Database migration testing | 07_DATABASE |
| API contract testing | 08_API |
| Security testing | 09_SECURITY |
| Release testing stages | 10_DEPLOYMENT |
| Developer workflows (running tests) | 14_DEVELOPER_WORKFLOWS |
| Performance testing | 12_PERFORMANCE |