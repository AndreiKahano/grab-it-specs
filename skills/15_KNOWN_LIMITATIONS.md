# 15 — Known Limitations

**Purpose:** Gaps ordered by how likely they are to surprise: drift, deferred features, architectural constraints, security weaknesses, bugs, and a ranked list of redesign candidates.

**Confidence note:** inferred from architecture, db-design-choices.md, and failure stories on 2026-11-23. The code wins (see 16).

---

## Limitations by Surprise Likelihood

### 1. No Delta Pull — Full Dataset Re-read Every Sync (HIGH)
**What:** Pull endpoint returns entire scoped dataset; no `since` cursor support yet.
**Impact:** Sync time grows linearly with data size. 10K notes → ~2s pull; 100K → ~20s.
**Workaround:** None for MVP. Users wait.
**Fix planned:** Add `since` cursor parameter + composite index on `(workspace_uuid, updated_at)`.
**Debt ref:** 01_ARCHITECTURE debt #1, 12_PERFORMANCE
**Surprise scenario:** User with 5 years of notes opens app on new device → 60s+ first sync.

---

### 2. Row-Level LWW Loses Entire Row on Conflict (HIGH)
**What:** Concurrent edits on different clients → newer `updated_at` wins completely; older edit lost.
**Impact:** Data loss for collaborative editing. No merge, no field-level resolution.
**Workaround:** Warn users "someone else edited this"; last write wins.
**Fix planned:** Field-level merging or CRDTs for high-value entities (notes).
**Debt ref:** 01_ARCHITECTURE debt #2, 06_FAILURE_STORIES #2
**Surprise scenario:** Two users edit same note offline → sync → one user's paragraph disappears.

---

### 3. No Per-Field Audit Log (MEDIUM)
**What:** Only `created_by` and `updated_at` tracked. No history of who changed what, when.
**Impact:** Can't answer "who changed the title?" or "when was this deleted?" for compliance.
**Workaround:** None. Row-level LWW overwrites history.
**Fix planned:** Append-only audit table for sensitive entities (notes, tags, workspace membership).
**Debt ref:** 01_ARCHITECTURE debt #3, 09_SECURITY accepted gaps
**Surprise scenario:** Compliance audit asks for edit trail → we have none.

---

### 4. Client Clock Skew Breaks LWW Fairness (MEDIUM)
**What:** LWW trusts client `updated_at`. Fast clock → wins conflicts it should lose.
**Impact:** Unfair conflict resolution; data loss for users with correct clocks.
**Workaround:** Server rejects `updated_at > now() + 30s`; client NTP check on start.
**Fix planned:** Hybrid logical clocks (HLC) for true causal ordering.
**Debt ref:** 01_ARCHITECTURE debt #4, 06_FAILURE_STORIES #2
**Surprise scenario:** User's phone clock 5 min fast → their edits always win → colleague's work lost.

---

### 5. No Server-Side `updated_at` Monotonicity Check (MEDIUM)
**What:** Server accepts client `updated_at` without verifying it's ≥ stored value.
**Impact:** Malicious/buggy client can force win by sending future timestamp.
**Workaround:** Server rejects >30s future; but past-but-newer-than-stored accepted.
**Fix planned:** Server enforces `client.updated_at >= server.updated_at` on push.
**Debt ref:** 01_ARCHITECTURE debt #5
**Surprise scenario:** Compromised client sends `updated_at: 2099` → owns all their rows forever.

---

### 6. Partial Unique Indexes Only on Server (MEDIUM)
**What:** SQLite doesn't support partial indexes. Client can insert duplicate live rows locally.
**Impact:** Local duplicates → sync conflict → LWW resolves but one lost silently.
**Workaround:** App-level check before insert (`WHERE archivedAt IS NULL`).
**Fix planned:** Enforce in DAO layer; test thoroughly.
**Debt ref:** 01_ARCHITECTURE debt #6, 07_DATABASE
**Surprise scenario:** Race condition in UI → two live tags with same name → sync picks one.

---

### 7. `synchronized_at` Uses `<>` Not `>` — Format-Sensitive (LOW)
**What:** Dirty check: `synchronizedAt IS NULL OR synchronizedAt <> updatedAt`. String comparison.
**Impact:** Timestamp format drift (ISO-8601 vs milliseconds) breaks dirty detection.
**Workaround:** Normalize to ISO-8601 UTC on both sides; test format consistency.
**Fix planned:** Use `>` with normalized timestamps; add format validation.
**Debt ref:** 01_ARCHITECTURE debt #7
**Surprise scenario:** Android update changes timestamp format → all rows appear clean → edits stop syncing.

---

### 8. No End-to-End Encryption (LOW)
**What:** Data encrypted at rest (Supabase, SQLCipher) and in transit (TLS), but server sees plaintext.
**Impact:** Server admin / breach → all user data readable.
**Workaround:** None for MVP. Documented in 09_SECURITY accepted gaps.
**Fix planned:** Client-side encryption for sensitive fields (future).
**Debt ref:** 09_SECURITY accepted gaps
**Surprise scenario:** Legal request for user data → we can decrypt everything.

---

### 9. No Device Binding / 2FA (LOW)
**What:** Refresh token in HTTP-only cookie (web) / EncryptedSharedPreferences (Android). No device trust.
**Impact:** Stolen refresh token → full account access until rotation (30 days).
**Workaround:** Short access tokens (15 min); refresh rotation; `SameSite=Strict`.
**Fix planned:** Optional 2FA / device trust (future).
**Debt ref:** 09_SECURITY accepted gaps
**Surprise scenario:** User's laptop stolen → attacker uses refresh token for 30 days.

---

### 10. RLS Policies Not on All Tables (LOW)
**What:** Some tables rely on application-level scoping instead of Postgres RLS.
**Impact:** Bug in app filter → data leak. RLS is defense-in-depth.
**Workaround:** Integration tests with two users verify isolation.
**Fix planned:** Add RLS to all syncable tables.
**Debt ref:** 09_SECURITY accepted gaps, 07_DATABASE
**Surprise scenario:** New endpoint forgets scope filter → User A sees User B's data.

---

### 11. Migration Rollback Not Supported (LOW)
**What:** Migrations are additive only. No down migrations.
**Impact:** Can't rollback schema; must deploy forward fix.
**Workaround:** Test thoroughly on staging; additive design minimizes need.
**Fix planned:** Never needed if additive discipline held.
**Debt ref:** 07_DATABASE, 10_DEPLOYMENT
**Surprise scenario:** Migration causes performance regression → must write new migration to fix.

---

### 12. Single-Region Deployment (LOW)
**What:** API and DB in one region. No multi-region failover.
**Impact:** Region outage → total downtime.
**Workaround:** Supabase managed HA; but single region.
**Fix planned:** Multi-region when user base justifies cost.
**Debt ref:** 10_DEPLOYMENT
**Surprise scenario:** AWS us-east-1 outage → grab-it down for hours.

---

## Deferred Features (Not Bugs, Not Yet Built)

| Feature | Why Deferred | Trigger to Build |
|---------|--------------|------------------|
| **Delta pull** | MVP scope | Sync time > 5s for typical user |
| **Field-level merge** | Complexity | Collaborative editing demand |
| **Audit log** | Storage cost | Compliance requirement |
| **Hybrid logical clocks** | Complexity | Clock skew incidents > 1/month |
| **E2E encryption** | Search/indexing needs plaintext | High-value data / regulation |
| **2FA / device trust** | UX friction | Account takeover incidents |
| **Multi-region** | Cost | Global user base + SLA |
| **Push notifications** | Not in MVP | User engagement need |
| **Offline search** | SQLite FTS complexity | Large local datasets |
| **Shared workspaces (real-time)** | Realtime not in sync model | Collaboration demand |

---

## Architectural Constraints (By Design)

| Constraint | Reason | Consequence |
|------------|--------|-------------|
| **Offline-first** | Core requirement | No server-assigned IDs; no synchronous validation; eventual consistency |
| **UUID v4 identity** | Works offline | Random index inserts; fragmentation (mitigated by `bigint` surrogate) |
| **Soft delete only** | Sync protocol | Storage grows; archived rows never auto-purged |
| **Row-level LWW** | Simplicity | Field-level conflicts lose data |
| **No server FKs** | Child-before-parent sync | Orphans possible; reads must tolerate missing parents |
| **Client-minted UUIDs** | Offline creation | Duplicate UUIDs for same logical record (natural-key adoption fixes) |
| **Single `updated_at`** | Simplicity | No per-field history; no vector clocks |
| **Additive migrations only** | Zero-downtime, old clients | Schema debt accumulates; legacy columns linger |

---

## Ranked Redesign Candidates

| Rank | Candidate | Trigger | Effort | Risk |
|------|-----------|---------|--------|------|
| 1 | **Delta pull with cursors** | Sync latency | Medium | Low |
| 2 | **Server `updated_at` monotonicity enforcement** | Security | Low | Low |
| 3 | **Field-level merge for notes** | Data loss reports | High | Medium |
| 4 | **Hybrid logical clocks** | Clock skew incidents | High | Medium |
| 5 | **Append-only audit table** | Compliance | Medium | Low |
| 6 | **RLS on all tables** | Defense in depth | Medium | Low |
| 7 | **Client-side encryption (sensitive fields)** | Regulation | High | High |
| 8 | **Multi-region active-active** | SLA / growth | Very High | High |
| 9 | **CRDT for collaborative entities** | Real-time collab | Very High | High |
| 10 | **Automated schema drift detection** | Drift incidents | Medium | Low |

---

## Cross-References

| Limitation | Source Document |
|------------|-----------------|
| Delta pull | 01_ARCHITECTURE debt #1, 12_PERFORMANCE |
| Row-level LWW | 01_ARCHITECTURE debt #2, 06_FAILURE_STORIES #2 |
| Audit log | 01_ARCHITECTURE debt #3, 09_SECURITY |
| Clock skew | 01_ARCHITECTURE debt #4, 06_FAILURE_STORIES #2 |
| `updated_at` validation | 01_ARCHITECTURE debt #5 |
| Partial unique indexes | 01_ARCHITECTURE debt #6, 07_DATABASE |
| `synchronized_at` format | 01_ARCHITECTURE debt #7 |
| E2E encryption | 09_SECURITY accepted gaps |
| Device binding | 09_SECURITY accepted gaps |
| RLS coverage | 09_SECURITY accepted gaps, 07_DATABASE |
| Migration rollback | 07_DATABASE, 10_DEPLOYMENT |
| Single region | 10_DEPLOYMENT |