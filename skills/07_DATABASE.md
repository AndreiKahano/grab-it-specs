# 07 — Database

**Purpose:** Identity strategy, constraints, deletes, table map, migration strategy, integrity invariants, dangerous operations, and indexing.

**Confidence note:** verified against db-design-choices.md on 2026-11-23. The code wins (see 16).

---

## Identity Strategy

| Aspect | Choice | Rationale |
|--------|--------|-----------|
| **Global identity** | Client-minted UUID v4 (`uuid` column) | Works offline; no coordination; same meaning everywhere |
| **Server surrogate key** | `id bigint GENERATED ALWAYS AS IDENTITY` | Small, ordered PK index; arrival order; never shared |
| **Client surrogate key** | `INTEGER PRIMARY KEY` (local rowid) | Never synced; local joins only |
| **Foreign keys** | `*_uuid` columns (parent's UUID) | Cross-machine reference; no declared FK on server |
| **Attribution** | `created_by uuid`, `<action>_by uuid` | Server-stamped from session; never client-supplied |

**Key rule:** The creating client mints the `uuid`. Every relationship stores the parent's `uuid`. The reference means the same thing on every machine.

---

## Constraints

### Server (Postgres)

| Constraint | Applied | Notes |
|------------|---------|-------|
| `PRIMARY KEY (id)` | Yes | Server-only surrogate |
| `UNIQUE (uuid)` | Yes | Global identity |
| `NOT NULL` on `uuid`, `created_at`, `updated_at` | Yes | Required for sync |
| `REFERENCES` on `*_uuid` | **No** (mostly) | See §3 in db-design-choices.md |
| Partial unique indexes | Yes | `WHERE archived_at IS NULL` for live uniqueness |
| `CHECK` on enums | Yes | Closed vocabularies |
| `GENERATED ALWAYS` on `id` | Yes | Rejects client-supplied `id` |

### Client (SQLite)

| Constraint | Applied | Notes |
|------------|---------|-------|
| `PRIMARY KEY (id)` | Yes | Local rowid |
| `UNIQUE (uuid)` | Yes | Global identity |
| `NOT NULL` on `uuid`, `created_at`, `updated_at` | Yes | Required for sync |
| `FOREIGN KEY` on `*_uuid` | **Yes** | `PRAGMA foreign_keys = ON` |
| `CHECK` on enums | Yes | `TEXT` + `CHECK (val IN (...))` |

**Why no server FKs:** Child may arrive before parent; clients hold partial datasets; soft deletes never remove parents; re-parenting without constraint rebuild.

**Where integrity enforced instead:**
1. Client: SQLite FKs ON
2. Orphan guard on pull: skip if parent UUID unknown, retry next sync
3. Natural-key adoption: if pulled row matches local on natural key, update local instead of inserting duplicate

---

## Deletes

**Soft delete only.** `archived_at timestamptz` (server) / `TEXT` ISO-8601 (client).

| Rule | Implementation |
|------|----------------|
| Delete = set `archived_at` + bump `updated_at` | Tombstone syncs like any edit |
| Real `DELETE` | **Never** on user data — leaves nothing to sync |
| Gate normal reads | `WHERE archived_at IS NULL` |
| Pull includes archived | Tombstones reach all clients |
| Uniqueness | Partial unique indexes `WHERE archived_at IS NULL` |
| Aggregates | Exclude archived rows |
| Mass unarchive | **Never** — every unarchived row comes back on every client |

---

## Table Map (Core Entities)

Based on db-design-choices.md samples. Extend per spec.

| Table | Purpose | Key Columns | Parent | Syncable |
|-------|---------|-------------|--------|----------|
| `account` | User identity | `id`, `uuid`, `email`, `created_at` | — | Yes (owner only) |
| `credential` | Secrets (hashed) | `id`, `uuid`, `account_uuid`, `provider`, `secret_hash` | `account` | Yes (owner only) |
| `workspace` | Top-level container | `id`, `uuid`, `name`, `owner_uuid`, `created_at`, `updated_at`, `archived_at` | — | Yes (members) |
| `notebook` | Note container | `id`, `uuid`, `workspace_uuid`, `title`, `rank`, `created_by`, `created_at`, `updated_at`, `archived_at` | `workspace` | Yes (members) |
| `note` | Content | `id`, `uuid`, `notebook_uuid`, `title`, `body`, `rank`, `created_by`, `created_at`, `updated_at`, `archived_at` | `notebook` | Yes (members) |
| `tag` | Categorization | `id`, `uuid`, `workspace_uuid`, `name`, `color`, `created_by`, `created_at`, `updated_at`, `archived_at` | `workspace` | Yes (members) |
| `note_tag` | Link: note ↔ tag | `id`, `uuid`, `note_uuid`, `tag_uuid`, `rank`, `created_by`, `created_at`, `updated_at`, `archived_at` | `note`, `tag` | Yes (members) |
| `feature` | Settings as rows | `id`, `uuid`, `name`, `value`, `created_at`, `updated_at` | — | Yes (admins) |

**Denormalization columns** (see db-design-choices.md §8):
- `note.workspace_uuid` — read shortcut (avoids `note → notebook → workspace`)
- `note_tag.rank` — data on placement
- `jsonb` document columns for variable-shape content

---

## Migration Strategy

**Principles:** Additive, idempotent, gated. Old clients must survive.

### Server Migration Template

```sql
BEGIN;

-- 1. Add column (idempotent)
ALTER TABLE public.note ADD COLUMN IF NOT EXISTS is_pinned boolean NOT NULL DEFAULT false;
ALTER TABLE public.note ADD COLUMN IF NOT EXISTS workspace_uuid uuid;

-- 2. Backfill from existing data (touch only unfilled rows)
UPDATE public.note n
SET    workspace_uuid = nb.workspace_uuid
FROM   public.notebook nb
WHERE  nb.uuid = n.notebook_uuid
  AND  n.workspace_uuid IS NULL;

-- 3. Index the new lookup path
CREATE INDEX IF NOT EXISTS idx_note_workspace ON public.note (workspace_uuid);

COMMIT;
```

### Client Migration (SQLite)

```sql
-- Guard each step in code (no ADD COLUMN IF NOT EXISTS)
-- Run only when PRAGMA table_info(note) has no 'is_pinned' column.
ALTER TABLE note ADD COLUMN is_pinned INTEGER NOT NULL DEFAULT 0;

-- Run only when it has no 'workspace_uuid' column.
ALTER TABLE note ADD COLUMN workspace_uuid TEXT;
CREATE INDEX IF NOT EXISTS idx_note_workspace ON note (workspace_uuid);
```

### Rules

1. **Apply migration before deploying code that reads it.** Never edit an applied script; write a new one.
2. **Additive first, removal later.** Add and backfill, mark old column legacy, drop in separate migration after all clients upgrade.
3. **Tolerate old clients.** Drop columns they still send that server no longer has; ignore their `NULL`s for unknown columns.
4. **Client upgrades are re-entrant chain** (`if (oldVersion < N) migrateN()`), additive only. SQLite table rebuilds are riskiest; prefer new tables.
5. **Run every migration on fresh installs AND upgrades.** Test upgrade path with real data.
6. **When new change column added, backfill from `created_at`** so existing rows read as clean instead of being pushed all over again.

---

## Integrity Invariants

| Invariant | Enforced By | Violation → |
|-----------|-------------|-------------|
| Every syncable row has `uuid` | `NOT NULL UNIQUE` on both sides | Sync fails, duplicates |
| `updated_at` bumped on every edit | Client code + server LWW check | Stale wins, data loss |
| `synchronized_at` only written by sync | Client code review + lint | Silent sync stop |
| `created_by` set by server only | Push allowlist exclusion | Ownership bypass |
| Soft delete used (`archived_at`) | Code review + no `DELETE` in sync paths | Row resurrection |
| Partial unique indexes on live rows | Migration + schema review | Archived blocks new live |
| Orphan guard on pull | Pull handler | Orphans accumulate |
| Natural-key adoption on pull | Pull handler | Duplicate logical records |
| Migration idempotent | CI: run twice on clean DB | Deploy retry fails |
| Server `id` never synced | Push allowlist + client schema | ID collision, enumeration |

---

## Dangerous Operations

| Operation | Danger | Mitigation |
|-----------|--------|------------|
| **Hard `DELETE` on user data** | Row resurrects on other clients | Ban in code review; lint rule |
| **Dropping column before all clients upgrade** | Old clients crash sending it | Legacy period; drop in separate migration |
| **Changing `uuid` of existing row** | Breaks all references, sync | Immutable — never update `uuid` |
| **Server accepting `created_by` from client** | Ownership bypass | Push allowlist exclusion; test |
| **Not bumping `updated_at` on edit** | Row never pushes (silent) | Code review checklist; unit test |
| **Writing `synchronized_at` on edit** | Row appears clean, never pushes | Sync-engine-only column; lint |
| **Declared FK on server `*_uuid`** | Child-before-parent fails | No REFERENCES; enforce on client |
| **Mirroring `*_uuid` → local `*_id`** | Translation drift, rebuild breaks | Keep uuid-native; no mirror |
| **Running non-idempotent migration** | Deploy retry fails | CI runs migrations twice |
| **Mass unarchive** | All clients resurrect all deleted | Never; individual unarchive only |

---

## Indexing Strategy

### Server (Postgres)

| Index | Table | Columns | Type | Purpose |
|-------|-------|---------|------|---------|
| `*_pkey` | All | `id` | PK | Surrogate key (ordered, small) |
| `*_uuid_key` | All | `uuid` | Unique | Global identity lookup |
| `idx_<table>_<parent>_uuid` | Child tables | `<parent>_uuid` | B-tree | Scoped pulls, joins |
| `idx_<table>_<parent>_live` | Child tables | `<parent>_uuid, archived_at` | B-tree | Live children of parent |
| `idx_<link>_live` | Link tables | `(<a>_uuid, <b>_uuid)` | Unique partial | Live uniqueness per pair |
| `idx_<table>_workspace` | Denorm tables | `workspace_uuid` | B-tree | Workspace-scoped queries |
| `idx_<table>_created_by` | Owned tables | `created_by` | B-tree | User-scoped queries |

**Naming:** `idx_<table>_<column>[_live]`

### Client (SQLite)

| Index | Table | Columns | Purpose |
|-------|-------|---------|---------|
| `PRIMARY KEY` | All | `id` | Local rowid |
| `UNIQUE (uuid)` | All | `uuid` | Global identity |
| `idx_<table>_<parent>_live` | Child tables | `<parent>_uuid, archived_at` | Live children of parent |
| `idx_<link>_live` | Link tables | `(<a>_uuid, <b>_uuid)` | Live uniqueness (partial not supported; enforce in code) |

**Note:** SQLite doesn't support partial indexes. Enforce live uniqueness in application code (check before insert).

---

## Attribution Columns

| Column | Meaning | Set By | Synced |
|--------|---------|--------|--------|
| `created_by` | Author account UUID | Server (session) on insert | Yes (read-only) |
| `created_at` | Creation time | Client | Yes |
| `updated_at` | Last change (change column) | Client on every edit | Yes |
| `archived_at` | Soft-delete time | Client | Yes |
| `rated_by`, `approved_by`, ... | Action-specific actor | Server (session) | Yes (read-only) |
| `submitted_at`, `published_at`, `locked_at`, ... | Lifecycle steps | Client or server by rule | Yes |

**Rules:**
- Server stamps actor columns; never accepts from client (excluded from push allowlist).
- Stored as `uuid`, not FK — account may be outside client dataset; attribution survives account archive.
- Action-specific actors instead of generic `updated_by` — "who approved?" matters; "who last touched?" overwritten by sync.
- `timestamptz` server / ISO-8601 UTC client — compares correctly across time zones.

---

## Change Column (`updated_at`) Protocol

| Event | Client Action | Server Action |
|-------|---------------|---------------|
| Local create | `created_at = now()`, `updated_at = now()` | Insert with client's `updated_at` |
| Local edit | `updated_at = now()` (bump) | LWW: only write if `server.updated_at < client.updated_at` |
| Local delete | `archived_at = now()`, `updated_at = now()` | LWW: delete wins same-second tie |
| Push accepted | `synchronized_at = COALESCE(updated_at, now())` | — |
| Pull received | `synchronized_at = server.updated_at` (mark clean) | — |
| Server manual edit | — | **Must** bump `updated_at` or client push may overwrite |

**Two rules that must never break:**
1. Every local mutation bumps `updated_at`.
2. Only sync writes `synchronized_at`.

Break either → that row silently stops syncing.

---

## Enum Handling

| Platform | Implementation |
|----------|----------------|
| Postgres | `CREATE TYPE note_status AS ENUM ('draft', 'published', 'archived');` |
| SQLite | `status TEXT CHECK (status IN ('draft', 'published', 'archived'))` |
| TypeScript | `type NoteStatus = 'draft' | 'published' | 'archived';` |
| Kotlin | `enum class NoteStatus { DRAFT, PUBLISHED, ARCHIVED }` |

**Rule:** Validate in UI. Old client can accept value server rejects. Add new enum values additively; never remove.

---

## Settings as Rows

```sql
CREATE TABLE IF NOT EXISTS public.feature (
  id          bigint GENERATED ALWAYS AS IDENTITY NOT NULL,
  uuid        uuid NOT NULL UNIQUE,
  name        text NOT NULL UNIQUE,  -- e.g., 'max_notes_per_notebook'
  value       jsonb NOT NULL,        -- e.g., '100' or '{"limit": 100, "unit": "count"}'
  created_at  timestamptz,
  updated_at  timestamptz,
  CONSTRAINT feature_pkey PRIMARY KEY (id)
);
```

**Why:** Change settings without schema change. Syncable. Auditable.

---

## Cross-References

| Topic | Document |
|-------|----------|
| Architecture decisions | 01_ARCHITECTURE |
| Lockstep sets for schema changes | 04_CHANGE_RULES #1 |
| Failure stories (DELETE, FK, migration, etc.) | 06_FAILURE_STORIES #1, #4, #6, #7 |
| Debugging schema/sync issues | 05_DEBUGGING_PLAYBOOK #1, #3, #4, #6 |
| Migration deployment | 10_DEPLOYMENT |
| Performance (indexing, delta pulls) | 12_PERFORMANCE |