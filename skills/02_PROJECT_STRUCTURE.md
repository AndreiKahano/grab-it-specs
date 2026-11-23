# 02 — Project Structure

**Purpose:** Annotated tree, where new code goes and must not go, and naming conventions that carry meaning.

**Confidence note:** inferred from repo layout and db-design-choices.md on 2026-11-23. The code wins (see 16).

---

## Repository Tree

```
grab-it-ecosystem/
├── AGENTS.md                          # Root agent instructions (points to per-repo AGENTS.md)
├── handoff.md                         # This skills generation guide
├── grab-it-specs/                     # Specifications repository (SCN)
│   ├── AGENTS.md                      # "Contains the product ecosystem specifications for grab-it."
│   ├── business-logic-v1.0.md         # Business requirements, user levels, MVP features
│   ├── db-design-choices.md           # Offline-first DB design (source of truth for 07_DATABASE)
│   ├── git-guidelines.md              # Commit message standard + versioning (source for 03, 10, 14)
│   ├── sense-making.md                # Environmental scanning instructions
│   ├── README.md
│   └── skills/                        # Generated skills documents (this folder)
│       ├── 00_INDEX.md
│       ├── INBOX.md
│       ├── 01_ARCHITECTURE.md
│       ├── 02_PROJECT_STRUCTURE.md
│       ├── 03_CODE_STYLE.md
│       ├── 04_CHANGE_RULES.md
│       ├── 05_DEBUGGING_PLAYBOOK.md
│       ├── 06_FAILURE_STORIES.md
│       ├── 07_DATABASE.md
│       ├── 08_API.md
│       ├── 09_SECURITY.md
│       ├── 10_DEPLOYMENT.md
│       ├── 11_TESTING.md
│       ├── 12_PERFORMANCE.md
│       ├── 13_DEPENDENCIES.md
│       ├── 14_DEVELOPER_WORKFLOWS.md
│       ├── 15_KNOWN_LIMITATIONS.md
│       └── 16_ENGINEERING_PRINCIPLES.md
├── grab-it-web/                       # Web frontend (WCN)
│   ├── AGENTS.md                      # "Front-end web application containing the regulatory compliance for grab-it."
│   ├── README.md
│   └── (source code — structure TBD)
├── grab-it-api/                       # Backend API (BCN)
│   ├── AGENTS.md                      # "The back-end web application that is used to communicate between the Supabase database API and the web/Android clients for grab-it."
│   ├── README.md
│   └── (source code — structure TBD)
└── grab-it-android/                   # Android app (ACN)
    ├── AGENTS.md                      # "The Android application for grab-it."
    ├── README.md
    └── (source code — structure TBD)
```

---

## Where New Code Goes

| Repository | Area | Convention |
|------------|------|------------|
| `grab-it-specs` | New skill document | `skills/NN_TOPIC.md` (append, never renumber) |
| `grab-it-specs` | New decision record | In relevant skill doc (01, 04, 07, 08, 09, 16) |
| `grab-it-specs` | New spec (requirements/design/schema) | Root level `*.md` with descriptive name |
| `grab-it-web` | New feature | `src/features/<feature>/` (colocate components, hooks, types) |
| `grab-it-web` | Shared UI | `src/components/ui/`, `src/lib/` |
| `grab-it-web` | API client | `src/lib/api/` (generated from OpenAPI if possible) |
| `grab-it-api` | New endpoint | `src/routes/<resource>/` (RESTful, versioned) |
| `grab-it-api` | Database migration | `supabase/migrations/` (additive, idempotent, gated) |
| `grab-it-api` | Shared types | `src/types/` (mirror client types) |
| `grab-it-android` | New feature | `feature/<feature>/` (modular, offline-first) |
| `grab-it-android` | Database (SQLite) | `data/local/db/` (DAO, entities, migrations) |
| `grab-it-android` | Sync engine | `data/sync/` (push, pull, conflict resolution) |
| `grab-it-android` | Auth | `data/auth/` (Google Sign-In, token management) |

---

## Where Code Must Not Go

| Location | Reason |
|----------|--------|
| `grab-it-specs/skills/` root (non-NN_ files) | Only numbered skill docs belong here |
| `grab-it-api` client-facing code | API is server-only; shared types in `src/types/` |
| `grab-it-web` direct Supabase calls | All data access via `grab-it-api` |
| `grab-it-android` server `id` values | Client has own `INTEGER PRIMARY KEY`; never send/receive server `id` |
| Any repo: `node_modules/`, `build/`, `dist/`, `.gradle/`, `target/` | Generated artifacts — gitignored |
| Any repo: secrets, `.env.local`, `google-services.json` | Never committed — use secret management |

---

## Naming Conventions That Carry Meaning

| Convention | Meaning | Example |
|------------|---------|---------|
| `*_uuid` column | Global identity (UUID v4), crosses client/server | `note_uuid`, `notebook_uuid` |
| `id` column | Server-only `bigint` surrogate (never synced) | `note.id` |
| `*_at` column | `timestamptz` (server) / ISO-8601 UTC (client) | `created_at`, `updated_at`, `archived_at` |
| `archived_at` | Soft delete timestamp (non-null = deleted) | `note.archived_at` |
| `synchronized_at` | Client-only sync marker (clean when = `updated_at`) | `note.synchronized_at` |
| `created_by` | Server-stamped actor `uuid` (from session) | `note.created_by` |
| `*_by` columns | Action-specific server-stamped actors | `rated_by`, `approved_by` |
| `scope:` in commits | Product/subsystem affected (see git-guidelines) | `grab-it-api/sync:`, `grab-it-web/auth:` |
| `WCN.`, `BCN.`, `ACN.`, `SCN.` | Release tag prefixes per product | `WCN.01.0.001` |
| `idx_<table>_<col>` | Index naming pattern | `idx_note_notebook` |
| `idx_<table>_<col>_live` | Partial unique index on live rows | `idx_note_tag_live` |

---

## Lockstep Sets (Cross-Repo)

| Set | Files | Miss → |
|-----|-------|--------|
| **Table schema** | `grab-it-api` migration + `grab-it-android` SQLite CREATE + `grab-it-web` TypeScript types | Schema drift → sync fails, data loss |
| **UUID identity** | All repos: `uuid` column on every syncable table | Missing `uuid` → can't sync, duplicates |
| **Attribution columns** | Server stamps `created_by`; clients exclude from push | Client sends `created_by` → ownership bypass |
| **Soft delete** | All repos: `archived_at` + `updated_at` bump | Hard `DELETE` → row resurrects on other clients |
| **LWW on `updated_at`** | Server upsert `WHERE updated_at < EXCLUDED.updated_at` | Client doesn't bump `updated_at` → stale wins |
| **Dirty check** | Client: `synchronized_at IS NULL OR synchronized_at <> updated_at` | Client writes `synchronized_at` on edit → row stops syncing |
| **Commit scopes** | All repos follow git-guidelines.md scopes | Wrong scope → changelog noise, missed reviews |
| **Release tags** | All repos: weekly `00Z` from ISO week of first commit | Tag gap → build number drift, confusing history |

---

## Adding a New Syncable Entity

1. **Specs**: Add to `db-design-choices.md` (table design, relationships, denormalizations)
2. **API**: Create migration in `supabase/migrations/` (additive, idempotent, backfill, index)
3. **API**: Add sync endpoints (push/pull for entity, scoped to user)
4. **Android**: Add SQLite table + DAO + entity + migration (guard with `PRAGMA table_info`)
5. **Android**: Add to sync engine (push dirty, pull scoped, orphan guard, natural-key adoption)
6. **Web**: Add TypeScript types mirroring server schema
7. **Web**: Add API client methods + UI components
8. **All**: Verify lockstep set in 04_CHANGE_RULES