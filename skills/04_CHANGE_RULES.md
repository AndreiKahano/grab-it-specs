# 04 — Change Rules

**Purpose:** Every lockstep set as numbered file paths with *Miss →* notes, hidden dependencies, high-risk areas, and what to retest.

**Confidence note:** inferred from db-design-choices.md, git-guidelines.md, and architecture on 2026-11-23. The code wins (see 16).

---

## Lockstep Sets

Each set is a group of files across repositories that **must change together**. Changing one without the others breaks the system.

---

### 1. Table Schema (New Syncable Entity)

| Repo | File/Path | Role |
|------|-----------|------|
| `grab-it-specs` | `db-design-choices.md` | Design doc: table, columns, relationships, denormalizations |
| `grab-it-api` | `supabase/migrations/NNNN_description.sql` | Server schema: additive, idempotent, backfill, index |
| `grab-it-api` | `src/routes/<entity>/` | Sync endpoints (push/pull) |
| `grab-it-android` | `data/local/db/entity/<Entity>.kt` | SQLite entity + DAO |
| `grab-it-android` | `data/local/db/migrations/NNNN_description.kt` | Client migration (guarded by `PRAGMA table_info`) |
| `grab-it-android` | `data/sync/<Entity>Sync.kt` | Push dirty, pull scoped, orphan guard, natural-key adoption |
| `grab-it-web` | `src/types/<entity>.ts` | TypeScript types mirroring server |
| `grab-it-web` | `src/lib/api/<entity>.ts` | API client methods |

**Miss →** Schema drift: sync fails with column mismatch, data loss, or crashes.
**Hidden dependency:** All three clients must understand the same column names and types.
**Retest:** Full sync cycle (create offline → push → pull on another client → edit → push → pull).

---

### 2. UUID Identity (Every Syncable Table)

| Repo | File/Path | Role |
|------|-----------|------|
| `grab-it-api` | Migration: `uuid uuid NOT NULL UNIQUE` | Server global identity |
| `grab-it-api` | Migration: `CREATE INDEX idx_<table>_uuid ON <table> (uuid)` | Lookup by uuid |
| `grab-it-android` | Entity: `uuid: String` + `UNIQUE` | Client global identity |
| `grab-it-web` | Type: `uuid: string` | Web global identity |

**Miss →** Missing `uuid` → row can't be synced, identified, or deduplicated. Duplicates proliferate.
**Hidden dependency:** Client mints UUID; server never generates it for syncable tables.
**Retest:** Create row offline on two clients → sync both → verify single row on server (natural-key adoption).

---

### 3. Attribution Columns (Server-Stamped Only)

| Repo | File/Path | Role |
|------|-----------|------|
| `grab-it-api` | Migration: `created_by uuid`, `rated_by uuid`, `approved_by uuid`, etc. | Server-stamped actors |
| `grab-it-api` | Sync endpoint: **exclude** `created_by`, `*_by` from push allowlist | Reject client-supplied values |
| `grab-it-api` | Sync endpoint: set `created_by = auth.uid()` on insert | Stamp from session |
| `grab-it-android` | Entity: `createdBy: String?` (read-only, no setter for push) | Client reads only |
| `grab-it-web` | Type: `created_by: string` (read-only) | Web reads only |

**Miss →** Client sends `created_by` → ownership bypass (anyone claims anything).
**Hidden dependency:** Server must have authenticated session on every sync request.
**Retest:** Attempt to push row with `created_by` set → verify server ignores/overwrites it.

---

### 4. Soft Delete (`archived_at`)

| Repo | File/Path | Role |
|------|-----------|------|
| `grab-it-api` | Migration: `archived_at timestamptz` | Server soft delete column |
| `grab-it-api` | Migration: Partial unique indexes `WHERE archived_at IS NULL` | Uniqueness for live rows only |
| `grab-it-api` | Sync endpoint: include archived rows in pull | Tombstones reach all clients |
| `grab-it-api` | Sync endpoint: gate normal reads on `archived_at IS NULL` | Live queries exclude deleted |
| `grab-it-android` | Entity: `archivedAt: String?` | Client soft delete column |
| `grab-it-android` | Sync: set `archivedAt` + bump `updatedAt` on delete | Tombstone creation |
| `grab-it-android` | DAO: `archivedAt IS NULL` in all live queries | Client respects soft delete |
| `grab-it-web` | Type: `archived_at: string \| null` | Web soft delete column |
| `grab-it-web` | Queries: filter `archived_at === null` for live data | Web respects soft delete |

**Miss →** Hard `DELETE` used → row resurrects on other clients (no tombstone to sync).
**Miss →** Partial unique index missing → archived row blocks new live row with same key.
**Miss →** Pull excludes archived → deletion never reaches other clients.
**Retest:** Delete on client A → sync → verify client B pulls tombstone → verify uniqueness allows new row with same natural key.

---

### 5. Last-Write-Wins on `updated_at`

| Repo | File/Path | Role |
|------|-----------|------|
| `grab-it-api` | Migration: `updated_at timestamptz` | Server change column |
| `grab-it-api` | Sync upsert: `WHERE note.updated_at < EXCLUDED.updated_at OR (delete wins tie)` | LWW logic |
| `grab-it-android` | Entity: `updatedAt: String` | Client change column |
| `grab-it-android` | Edit: **always** bump `updatedAt` to `now()` | Dirty marker |
| `grab-it-android` | Sync: never overwrite dirty row on pull | Protect newer local edit |
| `grab-it-web` | Type: `updated_at: string` | Web change column |
| `grab-it-web` | Edit: bump `updated_at` | Dirty marker |

**Miss →** Client doesn't bump `updated_at` on edit → row never pushes (stale `updated_at` loses LWW).
**Miss →** Server doesn't enforce LWW → stale client overwrites newer data.
**Miss →** Pull overwrites dirty row → newer local edit lost.
**Retest:** Concurrent edit on two clients → sync both → verify newer `updated_at` wins; delete vs edit same second → delete wins.

---

### 6. Dirty Synchronization (`synchronized_at`)

| Repo | File/Path | Role |
|------|-----------|------|
| `grab-it-android` | Entity: `synchronizedAt: String?` | Client-only sync marker |
| `grab-it-android` | Edit: **never** write `synchronizedAt` | Only sync writes it |
| `grab-it-android` | Push: `WHERE synchronizedAt IS NULL OR synchronizedAt <> updatedAt` | Dirty check |
| `grab-it-android` | Push accepted: `synchronizedAt = COALESCE(updatedAt, now())` | Mark clean |
| `grab-it-android` | Pull: write server row with `synchronizedAt = updatedAt` | Mark clean |

**Miss →** Client writes `synchronized_at` on edit → row appears clean → edits never push (silent sync stop).
**Miss →** Push doesn't mark clean → row retries forever.
**Miss →** Pull doesn't mark clean → row re-pushes forever.
**Retest:** Edit → verify `synchronized_at` stale → push → verify `synchronized_at = updated_at` → pull → verify no re-push.

---

### 7. Commit Scopes (Git Guidelines)

| Repo | File/Path | Role |
|------|-----------|------|
| All | Every commit message | `scope: Imperative summary` format |
| `grab-it-specs` | `git-guidelines.md` | Source of truth for scopes |

**Miss →** Wrong scope → changelog noise, missed reviews, broken tooling.
**Retest:** `git log --oneline` → verify all commits have valid scope per git-guidelines.

---

### 8. Release Tags (Weekly Build Numbers)

| Repo | File/Path | Role |
|------|-----------|------|
| All | Tag creation script/CI | Weekly `00Z` from ISO week of first commit |
| `grab-it-specs` | `git-guidelines.md` | Tag derivation rules |

**Miss →** Tag gap → build number drift, confusing history, broken promotion.
**Retest:** Verify tags match ISO week commit history per git-guidelines rules.

---

## High-Risk Areas

| Area | Why Risky | Mitigation |
|------|-----------|------------|
| **Sync engine** | Distributed state, conflict resolution, clock skew | Comprehensive integration tests; chaos testing |
| **Schema migrations** | Additive only, old clients must survive | Test upgrade path with real data; never edit applied migration |
| **Attribution stamping** | Security boundary | Server-only; integration test with malicious payloads |
| **Soft delete + uniqueness** | Partial indexes, archived rows in pull | Test delete → recreate same natural key |
| **Natural-key adoption** | Duplicate UUIDs from two clients | Test concurrent create of "same" record |
| **Orphan guard** | Child before parent in pull | Test pull order permutations |

---

## What to Retest After Any Change

| Change Type | Retest |
|-------------|--------|
| Schema (any table) | Full sync cycle for that entity + related entities |
| Sync endpoint | Push dirty → pull clean → edit → push → pull on second client |
| Auth/attribution | Push with forged `created_by` → verify rejected |
| Soft delete | Delete → sync → pull on other client → verify tombstone → recreate |
| LWW logic | Concurrent edit (two clients) → sync both → verify winner |
| Dirty check | Edit → verify push → verify no re-push → pull → verify clean |
| Migration | Fresh install + upgrade from previous version + real data |
| Commit scope | `git log --oneline -20` → all valid |
| Release tag | Tag script output matches git-guidelines derivation |