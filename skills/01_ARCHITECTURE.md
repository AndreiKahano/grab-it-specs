# 01 — Architecture

**Purpose:** The one-paragraph model, components and what each owns, data flows end to end, hard boundaries, decision records, and a ranked debt register. Read this first.

**Confidence note:** inferred from business-logic-v1.0.md, db-design-choices.md, and repo structure on 2026-11-23. The code wins (see 16).

---

## One-Paragraph Model

Grab-it is an offline-first, cross-platform ecosystem (Web, Android) with a central Supabase/Postgres backend. Clients write to local SQLite databases and sync via a REST API to the server. The system uses UUIDs as global identities, soft deletes (`archived_at`), and last-write-wins conflict resolution on `updated_at`. The server stamps attribution columns (`created_by`, action-specific actors) from the authenticated session; clients never supply them. Data is scoped per user — each client holds only the rows its user may see.

---

## Components & Ownership

| Component | Repository | Owns |
|-----------|------------|------|
| **Web Frontend** | `grab-it-web` | Regulatory compliance UI, user-facing features, Google Sign-In integration |
| **Backend API** | `grab-it-api` | Supabase/Postgres communication, sync endpoints, auth validation, server-side attribution stamping |
| **Android App** | `grab-it-android` | Offline-first SQLite storage, sync engine, Google Sign-In, local-first UX |
| **Specifications** | `grab-it-specs` | Business logic, DB design choices, git guidelines, sense-making, skills documents |

---

## Data Flows (End to End)

1. **Auth**: User signs in via Google → ID token sent to API → API validates with Supabase Auth → returns session
2. **Local Write**: User creates/edits data → client writes to local SQLite, bumps `updated_at`, leaves `synchronized_at` stale
3. **Push**: Client sends dirty rows (`synchronized_at IS NULL OR synchronized_at <> updated_at`) to API → API upserts with LWW on `updated_at` (delete wins tie) → server stamps `created_by` from session
4. **Pull**: Client requests scoped dataset → API returns rows (including archived) → client upserts, sets `synchronized_at = updated_at` for clean rows, never overwrites dirty local rows
5. **Delete**: Client sets `archived_at` + bumps `updated_at` → pushes tombstone → server upserts → other clients pull and apply soft delete

---

## Hard Boundaries

| Boundary | Rule |
|----------|------|
| **Client ↔ Server ID spaces** | Server `id bigint` never leaves server; client `INTEGER PRIMARY KEY` never sent. Only `uuid` crosses. |
| **Attribution** | `created_by`, `rated_by`, `approved_by`, etc. set **only by server** from session. Excluded from push allowlist. |
| **Foreign keys** | Server does **not** declare `REFERENCES` on `*_uuid` (allows out-of-order sync). Client SQLite has FKs ON. |
| **Soft delete** | `DELETE` never used for user data. `archived_at` + `updated_at` bump = tombstone that syncs. |
| **Uniqueness** | Partial unique indexes on server (`WHERE archived_at IS NULL`). Archived rows don't block new ones. |
| **Schema evolution** | Additive, idempotent, gated migrations only. Legacy columns tolerated until all clients upgrade. |

---

## Decision Records

### Decision: Offline-first with UUID identity (2026-11-23, architect)
**Status:** accepted
**Context:** Clients must create rows offline without server coordination.
**Choice:** Client-minted UUID v4 as global identity; server-only `bigint` surrogate key.
**Alternatives:** UUID v7 (time-ordered), server-assigned IDs with offline queue.
**Consequences:** Two unique indexes per table; random UUID inserts fragment `uuid` index; UUID v7 can be adopted later without schema change.

### Decision: Last-write-wins on `updated_at` (2026-11-23, architect)
**Status:** accepted
**Context:** Concurrent edits on different clients before sync.
**Choice:** Row-level LWW; delete wins same-second tie.
**Alternatives:** CRDTs, operational transforms, field-level merging.
**Consequences:** Older concurrent edit lost entirely; fast clock wins; no per-field history.

### Decision: Server stamps attribution (2026-11-23, architect)
**Status:** accepted
**Context:** Ownership enforcement ("authors edit only their own notes").
**Choice:** Server sets `created_by` and action-specific actors from authenticated session.
**Alternatives:** Client-supplied with server validation, signed claims.
**Consequences:** Client can't claim authorship; attribution survives account archive.

### Decision: No declared FKs on server (2026-11-23, architect)
**Status:** accepted
**Context:** Child rows may arrive before parents; clients hold partial datasets.
**Choice:** Enforce on client (SQLite FKs ON) + orphan guard on pull + natural-key adoption.
**Alternatives:** Deferred constraints, sync-time validation.
**Consequences:** Server can hold orphans; reads must tolerate missing parents.

---

## Ranked Debt Register

| Rank | Debt | Impact | Effort | Notes |
|------|------|--------|--------|-------|
| 1 | No delta pulls — full scoped dataset re-read every sync | High bandwidth, slow sync at scale | Medium | Add cursor/version-based incremental pull |
| 2 | Row-level LWW loses entire row on conflict | Data loss for concurrent editors | High | Field-level merging or CRDTs for high-value entities |
| 3 | Single `updated_at` timestamp — no edit history | Can't answer "who changed what" | Medium | Append-only audit table for sensitive entities |
| 4 | Client clock skew breaks LWW fairness | Fast clock wins conflicts | Low | NTP sync check; consider hybrid logical clocks |
| 5 | No server-side validation of `updated_at` monotonicity | Malicious/buggy client can force wins | Low | Server should reject `updated_at` < stored value |
| 6 | Partial unique indexes only on server | Client may insert duplicate live rows locally | Medium | Client should mirror partial unique indexes |
| 7 | `synchronized_at` uses `<>` not `>` — format-sensitive | Timestamp format drift breaks dirty check | Low | Normalize to ISO-8601 UTC on both sides |