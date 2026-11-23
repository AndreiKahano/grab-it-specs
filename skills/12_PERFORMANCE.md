# 12 — Performance

**Purpose:** Hard limits, hot paths, deliberate inefficiencies to leave alone, expensive operations, and profiling.

**Confidence note:** inferred from db-design-choices.md and architecture on 2026-11-23. The code wins (see 16).

---

## Hard Limits

| Limit | Value | Source | Action at Limit |
|-------|-------|--------|-----------------|
| **Sync batch size** | 500 rows | Client config | Split into multiple pushes |
| **Pull page size** | 1000 rows | API config | Cursor-based pagination |
| **Request body** | 1 MB | API gateway | Reject 413 |
| **SQLite DB size** | 500 MB | Android storage | Warn user; archive old workspaces |
| **Concurrent syncs/user** | 1 | Server mutex | Queue/429 |
| **Rate limit (sync)** | 30/min | API config | 429 RATE_LIMITED |
| **Token lifetime** | 15 min (access) | Auth config | Refresh required |
| **Migration lock timeout** | 30 s | DB | Fail deploy; retry |
| **Query timeout** | 10 s | Postgres | Cancel; log slow query |

---

## Hot Paths

### 1. Sync Push (`POST /api/v1/sync/push`)
**Frequency:** Every user edit (batched)
**Latency budget:** < 500 ms p95
**Operations:**
- JWT verification
- Payload validation (allowlist, UUIDs, enums)
- For each entity: upsert with LWW check
- Response assembly

**Optimization:**
- Batch upserts in single transaction
- Prepared statements for upsert
- Index on `uuid` (already unique)
- Skip unchanged rows (client sends dirty only)

### 2. Sync Pull (`GET /api/v1/sync/pull`)
**Frequency:** App start, background, manual refresh
**Latency budget:** < 2 s p95 (full), < 500 ms (delta)
**Operations:**
- JWT verification
- Scope resolution (user's workspaces)
- Query scoped rows (with `since` cursor for delta)
- Serialize response

**Optimization:**
- **Delta pull essential** — `WHERE updated_at > $since` + cursor
- Composite indexes on `(workspace_uuid, updated_at)` for scoped pulls
- Limit page size; return `cursor` + `maxUpdatedAt`
- Stream response for large datasets

### 3. Scoped List Queries (e.g., `GET /workspaces/{uuid}/notes`)
**Frequency:** UI navigation
**Latency budget:** < 200 ms p95
**Operations:**
- Auth + scope check
- Paginated query with filters
- Response envelope

**Optimization:**
- Index on `(notebook_uuid, archived_at)` for live notes
- Denormalized `workspace_uuid` on `note` for workspace-scoped lists
- Cursor pagination (not offset)

### 4. Authentication (`POST /api/v1/auth/google`, `/auth/refresh`)
**Frequency:** Sign in, token refresh
**Latency budget:** < 300 ms p95
**Operations:**
- Google cert fetch (cached)
- JWT verification
- Supabase user lookup/upsert
- Token minting

**Optimization:**
- Cache Google certs (24h TTL)
- Connection pooling to Supabase
- Async token minting

---

## Deliberate Inefficiencies (Leave Alone)

| Inefficiency | Why We Accept It | When to Revisit |
|--------------|------------------|-----------------|
| **Full pull on first sync** | Simplicity; MVP; rare (once per device) | When >10K rows causes >10s |
| **Row-level LWW (not field-level)** | Simplicity; most rows single-editor | When concurrent edits common on same entity |
| **UUID v4 (random) on server** | Simplicity; `bigint` surrogate handles PK performance | When `uuid` index fragmentation >20% (then UUID v7) |
| **No per-field audit log** | Storage cost; row-level LWW loses history anyway | When compliance requires it |
| **SQLite no partial indexes** | Not supported; enforce in app code | Never (SQLite limitation) |
| **Client clocks trusted for `updated_at`** | NTP usually good; server validates ±30s | When clock skew incidents >1/month |
| **Single `updated_at` per row** | Simplicity; no vector clocks | When field-level conflicts matter |

---

## Expensive Operations

| Operation | Cost | Frequency | Mitigation |
|-----------|------|-----------|------------|
| **Full schema migration** | Table rewrite (SQLite) | Per upgrade | Additive only; prefer new tables; test on real data |
| **Backfill new column** | Full table scan | Per migration | `WHERE new_col IS NULL`; batch in chunks |
| **Delta pull without cursor** | Full table scan | Every sync (MVP) | **Add cursor ASAP** (debt #1) |
| **Cross-workspace query** | Large join | Admin only | Denormalize `workspace_uuid`; restrict to admins |
| **Aggregates on large tables** | Sequential scan | Reports | Materialized views / stored aggregates |
| **Sync conflict resolution** | Row comparison | Concurrent edits | Rare; LWW is O(1) |
| **Natural-key adoption scan** | Index lookup | Pull (rare) | Composite index on natural key |

---

## Profiling & Monitoring

### Key Metrics to Track

| Metric | Target | Alert Threshold |
|--------|--------|-----------------|
| **Sync push latency (p95)** | < 500 ms | > 2 s |
| **Sync pull latency (p95, delta)** | < 500 ms | > 3 s |
| **Sync pull latency (p95, full)** | < 2 s | > 10 s |
| **API error rate** | < 0.1% | > 1% |
| **Auth failure rate** | < 0.5% | > 5% |
| **DB query duration (p95)** | < 100 ms | > 1 s |
| **Migration duration** | < 30 s | > 60 s |
| **Client DB size** | < 100 MB | > 500 MB |

### Profiling Tools

| Component | Tool | Command |
|-----------|------|---------|
| **API (Node.js)** | `clinic.js` / `0x` | `clinic doctor -- node server.js` |
| **Postgres** | `pg_stat_statements` | `SELECT * FROM pg_stat_statements ORDER BY mean_exec_time DESC LIMIT 20;` |
| **Postgres** | `EXPLAIN ANALYZE` | `EXPLAIN ANALYZE SELECT * FROM note WHERE workspace_uuid = '...';` |
| **Android** | Android Studio Profiler | CPU / Memory / Network tabs |
| **Android SQLite** | `sqlite3_analyzer` | `sqlite3_analyzer grab_it.db` |
| **Web** | Chrome DevTools Performance | Record sync flow |
| **Web** | Lighthouse | CI gate for regression |

### Slow Query Detection

```sql
-- Enable pg_stat_statements (Supabase: enabled by default)
-- Top 20 slowest queries by mean time
SELECT query, calls, mean_exec_time, max_exec_time, total_exec_time
FROM pg_stat_statements
ORDER BY mean_exec_time DESC
LIMIT 20;

-- Queries missing indexes (sequential scans on large tables)
SELECT schemaname, tablename, seq_scan, seq_tup_read, idx_scan
FROM pg_stat_user_tables
WHERE seq_scan > 100 AND seq_tup_read > 10000
ORDER BY seq_tup_read DESC;
```

---

## Indexing for Performance

### Server (Postgres) — Already in 07_DATABASE

Critical indexes for sync:
- `idx_note_notebook` on `note(notebook_uuid)` — scoped pulls
- `idx_note_workspace` on `note(workspace_uuid)` — workspace lists (denorm)
- `idx_note_tag_live` partial unique on `note_tag(note_uuid, tag_uuid) WHERE archived_at IS NULL`
- Composite: `(workspace_uuid, updated_at)` for delta pulls

### Client (SQLite)

```sql
-- Live children of parent (covers scoped list + archived filter)
CREATE INDEX idx_note_notebook_live ON note (notebook_uuid, archived_at);

-- Dirty check (push)
CREATE INDEX idx_note_dirty ON note (synchronized_at, updated_at) 
  WHERE synchronized_at IS NULL OR synchronized_at <> updated_at;

-- Workspace-scoped (denorm)
CREATE INDEX idx_note_workspace_live ON note (workspace_uuid, archived_at);
```

---

## Capacity Planning

| Growth Factor | Current | 6 Months | 1 Year | Action |
|---------------|---------|----------|--------|--------|
| **Users** | 100 | 1,000 | 10,000 | Horizontal scale API; read replicas |
| **Notes/user** | 50 | 200 | 500 | Delta pull critical; pagination |
| **Workspaces** | 50 | 500 | 5,000 | Denorm `workspace_uuid` essential |
| **Sync/day/user** | 10 | 50 | 100 | Rate limits; batch pushes |
| **DB size** | 1 GB | 50 GB | 500 GB | Partitioning; archiving old workspaces |

---

## Performance Test Scenarios

| Scenario | Tool | Success Criteria |
|----------|------|------------------|
| **100 concurrent sync pushes** | k6 / Locust | p95 < 500 ms, 0 errors |
| **Delta pull 10K rows** | k6 | < 500 ms, correct cursor |
| **Full pull 50K rows** | k6 | < 2 s, streamed |
| **Migration on 100K rows** | Local + timer | < 30 s, idempotent |
| **Offline create 100 notes → sync** | Android Espresso | < 5 s end-to-end |
| **Concurrent edit 10 clients same note** | Custom script | LWW correct, no data loss |

---

## Cross-References

| Topic | Document |
|-------|----------|
| Architecture (delta pull debt) | 01_ARCHITECTURE debt #1 |
| Database (indexing strategy) | 07_DATABASE |
| API (sync endpoints) | 08_API |
| Testing (performance tests) | 11_TESTING |
| Deployment (migration performance) | 10_DEPLOYMENT |
| Failure stories (slow sync, migration) | 06_FAILURE_STORIES #7, #8 |
| Known limitations (delta pull missing) | 15_KNOWN_LIMITATIONS |