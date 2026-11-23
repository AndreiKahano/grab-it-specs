# 10 — Deployment

**Purpose:** Release order across components, how each deployable ships and what it needs, tags, and a release checklist.

**Confidence note:** verified against git-guidelines.md (Part 2) on 2026-11-23. The code wins (see 16).

---

## Release Order (Maturity-Based Branching)

Per git-guidelines.md, the project follows a **maturity-based branching model**:

```
main → beta → release → production
```

| Branch | Role | Permitted Work |
|--------|------|----------------|
| `main` | Development | Feature development, integration, developer unit testing |
| `beta` | QA / System Testing | System testing against major product claims, defect correction, stabilization |
| `release` | Bundled Release Testing | Builds published for independent integration testing, candidate iteration, final production approval |

**Promotion Rules (from git-guidelines.md):**
1. Develop on `main`
2. Promote `main` → `beta` when ready for system testing
3. Gate promotion on QA results
4. Promote `beta` → `release` after system testing accepted
5. Build and publish release bundle to release website
6. Run candidate testing on `release` (alpha `a`, beta `b`, release-candidate `rc`)
7. Approve production separately (designated final approver)
8. Tag release candidates from `release` branch only
9. Preserve promotable history (reviewed merges/cherry-picks back to upstream)

---

## Component Deployment

### grab-it-api (BCN) — Backend API
| Aspect | Detail |
|--------|--------|
| **Platform** | Supabase / Node.js on Railway/Vercel/Cloud Run |
| **Trigger** | Tag `BCN.0X.Y.00Z` pushed to `release` branch |
| **Pre-deploy** | Migrations applied (additive, idempotent) |
| **Health check** | `/health` endpoint + DB connectivity |
| **Rollback** | Revert tag; migrations are additive so backward compatible |
| **Secrets** | Injected at deploy: `GOOGLE_CLIENT_SECRET`, `SUPABASE_SERVICE_ROLE`, `JWT_SECRET` |

### grab-it-web (WCN) — Web Frontend
| Aspect | Detail |
|--------|--------|
| **Platform** | Vercel / Netlify / Cloudflare Pages |
| **Trigger** | Tag `WCN.0X.Y.00Z` pushed to `release` branch |
| **Build** | `npm run build` → static assets |
| **Env vars** | `VITE_API_URL`, `VITE_GOOGLE_CLIENT_ID` (public) |
| **Rollback** | Previous deployment in platform dashboard |
| **Cache** | CDN with `Cache-Control: immutable` for hashed assets |

### grab-it-android (ACN) — Android App
| Aspect | Detail |
|--------|--------|
| **Platform** | Google Play Console (Internal → Closed → Open → Production) |
| **Trigger** | Tag `ACN.0X.Y.00Z` pushed to `release` branch |
| **Build** | `./gradlew bundleRelease` → AAB |
| **Signing** | Play App Signing (Google manages key) |
| **Version code** | Derived from `00Z` (e.g., `001` → versionCode 1) |
| **Version name** | `0X.Y.00Z` (e.g., `01.0.001`) |
| **Rollback** | Promote previous track artifact |
| **Secrets** | `google-services.json` from CI secret; keystore from Play |

### grab-it-specs (SCN) — Specifications
| Aspect | Detail |
|--------|--------|
| **Platform** | GitHub Pages / Confluence / Notion (published from `release` branch) |
| **Trigger** | Tag `SCN.0X.Y.00Z` pushed to `release` branch |
| **Validation** | Stakeholder review instead of regression testing |
| **Golden candidate** | Final candidate = approved baseline |

---

## Version Format

Per git-guidelines.md: `<prefix>.0X.Y.00Z`

| Component | Prefix | Formula |
|-----------|--------|---------|
| Web App | `WCN` | `W` + `CN` |
| Backend API | `BCN` | `B` + `CN` |
| Android App | `ACN` | `A` + `CN` |
| Specifications | `SCN` | `S` + `CN` |

- `0X` — Major, zero-padded to 2 digits, starts at `01`
- `Y` — Minor (maintenance branch), single digit, starts at `0`
- `00Z` — Patch (weekly build), zero-padded to 3 digits, starts at `001`

**Pre-release labels** (appended to `00Z`):
- `a` — Alpha testing
- `b` — Beta testing
- `rc` — Release-candidate testing
- Iterations: `a2`, `a3`, `b2`, `rc2` (no `1` suffix for first)

**Examples:**
- `WCN.01.0.001` — First weekly web release
- `BCN.01.0.017a` — API alpha candidate for build 017
- `ACN.01.0.017rc2` — Android RC iteration 2 for build 017

---

## Tag Derivation Rules (from git-guidelines.md)

1. **Start at first commit's week** — `001` on ISO week of repo's first commit
2. **No commits, no tag** — Weeks with no commits skipped, no build number consumed
3. **Never tag ongoing week** — Wait until Friday 5:00 PM local
4. **Bundle commits into their ISO week** — Tag points to week's last commit
5. **Only tag weeks without tags** — Never retag or move existing tags
6. **Tags are chronological** — Build numbers increase with ISO week order

**Week boundaries:** ISO-8601 (Monday–Sunday)
**Release date:** Friday of the week (clamped forward if last commit on weekend)

---

## Release Checklist

### Pre-Release (on `main` → `beta` promotion)
- [ ] All planned development complete (WBS/Gantt 100%)
- [ ] Unit tests pass (`main` branch)
- [ ] Code review completed for all changes
- [ ] Lockstep sets verified (04_CHANGE_RULES)
- [ ] Migrations are additive, idempotent, gated
- [ ] No hard `DELETE` on user data
- [ ] Attribution columns not accepted from client
- [ ] `updated_at` bumped on all mutations
- [ ] `synchronized_at` only written by sync
- [ ] Soft delete (`archived_at`) used everywhere
- [ ] Commit scopes valid per git-guidelines
- [ ] Dependencies scanned (`npm audit`, `gradle dependencyCheck`)

### Beta Testing (on `beta` branch)
- [ ] System testing against major product claims
- [ ] Cross-user data isolation verified (two test accounts)
- [ ] Offline-first sync tested (create offline → sync → pull on second device)
- [ ] Concurrent edit conflict resolution tested (LWW)
- [ ] Delete → sync → pull on other client verified
- [ ] Schema migration upgrade path tested (fresh install + upgrade)
- [ ] Performance baseline recorded (sync time, API latency)
- [ ] Security scan (OWASP ZAP / similar)
- [ ] Defects fixed and cherry-picked back to `main`

### Release Candidate (on `release` branch)
- [ ] Build published to release website
- [ ] Alpha testing (`a` candidate) — internal team
- [ ] Beta testing (`b` candidate) — wider internal / trusted users
- [ ] Release-candidate testing (`rc` candidate) — final internal + regression
- [ ] Each candidate: defects fixed → next iteration (`a2`, `b2`, `rc2`)
- [ ] Candidate passes with no remaining bugs requiring fix
- [ ] Designated final approver signs off

### Production Deployment
- [ ] Deploy **exact approved candidate** (tag from `release` branch)
- [ ] Verify health checks pass
- [ ] Verify migrations applied (API)
- [ ] Verify client apps can sync with new API
- [ ] Monitor error rates, latency, sync success rate
- [ ] Rollback plan ready (previous tag)

### Post-Release
- [ ] Tag recorded in git-guidelines.md release tables
- [ ] 00_INDEX.md changelog updated
- [ ] INBOX.md processed (promote proven practices to 16)
- [ ] Retrospective: what surprised you? → add to INBOX.md

---

## Maintenance Releases (Post-Production Defects)

Per git-guidelines.md:
1. Open separate maintenance branch from production baseline
2. Increment Minor `Y`, reset Patch `00Z` to `001`, retain Major `0X`
3. Same controlled development, testing, candidate, approval gates
4. Do not mix into normal development without explicit promotion
5. Fixes that should exist in active development → reviewed merge/cherry-pick to `main`

---

## Environment Variables by Component

### grab-it-api
| Variable | Required | Description |
|----------|----------|-------------|
| `SUPABASE_URL` | Yes | Supabase project URL |
| `SUPABASE_SERVICE_ROLE` | Yes | Service role key (admin) |
| `GOOGLE_CLIENT_ID` | Yes | OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | Yes | OAuth client secret |
| `JWT_SECRET` | Yes | JWT signing key |
| `NODE_ENV` | Yes | `production` \| `staging` \| `development` |
| `RATE_LIMIT_WINDOW_MS` | No | Default 60000 |
| `RATE_LIMIT_MAX` | No | Default per-tier |

### grab-it-web
| Variable | Required | Description |
|----------|----------|-------------|
| `VITE_API_URL` | Yes | Backend API base URL |
| `VITE_GOOGLE_CLIENT_ID` | Yes | OAuth client ID (public) |

### grab-it-android
| Variable | Required | Description |
|----------|----------|-------------|
| `API_URL` | Yes | Backend API base URL (build config) |
| `GOOGLE_CLIENT_ID` | Yes | OAuth client ID |
| `GOOGLE_SERVICES_JSON` | Yes | CI secret (file content) |

---

## Rollback Procedures

| Component | Rollback Method |
|-----------|-----------------|
| **API** | `git checkout previous-tag && deploy` (migrations additive → safe) |
| **Web** | Platform dashboard → "Promote previous deployment" |
| **Android** | Play Console → Promote previous track artifact (Internal/Closed/Open/Production) |
| **Specs** | Revert to previous tag on `release` branch; republish |

**Critical:** Never rollback database migrations. They are additive only. If a migration causes issues, deploy a new migration to fix/mitigate.

---

## Cross-References

| Topic | Document |
|-------|----------|
| Versioning rules | git-guidelines.md (Part 2) |
| Branching model | git-guidelines.md (Branching Models) |
| Lockstep sets for release | 04_CHANGE_RULES |
| Failure stories (migration, tagging) | 06_FAILURE_STORIES #7, #10 |
| Developer workflows (release process) | 14_DEVELOPER_WORKFLOWS |
| Testing (release testing stages) | 11_TESTING |
| Security (secret rotation) | 09_SECURITY |