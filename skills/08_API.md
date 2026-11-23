# 08 — API

**Purpose:** The response envelope, route inventory with auth, how to add an endpoint, existing validators, versioning, and common mistakes.

**Confidence note:** inferred from architecture, db-design-choices.md, and git-guidelines.md on 2026-11-23. The code wins (see 16).

---

## Response Envelope

### Success
```json
{
  "data": { ... } | [ ... ],
  "meta": {
    "cursor": "opaque-string-for-next-page",
    "maxUpdatedAt": "2026-11-23T10:00:00Z"
  }
}
```

### Error
```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human-readable description",
    "details": { "field": "value" } | null
  }
}
```

### Error Codes
| Code | HTTP | Meaning |
|------|------|---------|
| `UNAUTHENTICATED` | 401 | Missing/invalid/expired token |
| `FORBIDDEN` | 403 | Authenticated but not authorized |
| `NOT_FOUND` | 404 | Resource doesn't exist or not in scope |
| `VALIDATION_ERROR` | 400 | Request body/query invalid |
| `CONFLICT` | 409 | LWW would lose data (rare; usually LWW resolves silently) |
| `RATE_LIMITED` | 429 | Too many requests |
| `INTERNAL_ERROR` | 500 | Bug / unexpected failure |

---

## Route Inventory (Planned)

All routes prefixed with `/api/v1`. Auth required unless noted.

| Method | Path | Scope | Auth | Description |
|--------|------|-------|------|-------------|
| `POST` | `/auth/google` | `auth` | None | Exchange Google ID token for session |
| `POST` | `/auth/refresh` | `auth` | Refresh token | Rotate access/refresh tokens |
| `GET` | `/workspaces` | `workspace` | Access token | List user's workspaces |
| `POST` | `/workspaces` | `workspace` | Access token | Create workspace |
| `GET` | `/workspaces/{uuid}` | `workspace` | Access token | Get workspace |
| `PATCH` | `/workspaces/{uuid}` | `workspace` | Access token | Update workspace |
| `DELETE` | `/workspaces/{uuid}` | `workspace` | Access token | Soft delete workspace |
| `GET` | `/workspaces/{uuid}/notebooks` | `notebook` | Access token | List notebooks in workspace |
| `POST` | `/workspaces/{uuid}/notebooks` | `notebook` | Access token | Create notebook |
| `GET` | `/notebooks/{uuid}` | `notebook` | Access token | Get notebook |
| `PATCH` | `/notebooks/{uuid}` | `notebook` | Access token | Update notebook |
| `DELETE` | `/notebooks/{uuid}` | `notebook` | Access token | Soft delete notebook |
| `GET` | `/notebooks/{uuid}/notes` | `note` | Access token | List notes in notebook |
| `POST` | `/notebooks/{uuid}/notes` | `note` | Access token | Create note |
| `GET` | `/notes/{uuid}` | `note` | Access token | Get note |
| `PATCH` | `/notes/{uuid}` | `note` | Access token | Update note |
| `DELETE` | `/notes/{uuid}` | `note` | Access token | Soft delete note |
| `GET` | `/tags` | `tag` | Access token | List tags in workspace |
| `POST` | `/tags` | `tag` | Access token | Create tag |
| `PATCH` | `/tags/{uuid}` | `tag` | Access token | Update tag |
| `DELETE` | `/tags/{uuid}` | `tag` | Access token | Soft delete tag |
| `POST` | `/sync/push` | `sync` | Access token | Push dirty rows (batch) |
| `GET` | `/sync/pull` | `sync` | Access token | Pull scoped dataset (with `since` cursor) |
| `GET` | `/sync/status` | `sync` | Access token | Get sync status (counts, last sync) |

---

## Sync Endpoints Detail

### Push: `POST /api/v1/sync/push`

**Request:**
```json
{
  "entities": {
    "note": [
      { "uuid": "...", "notebook_uuid": "...", "title": "...", "body": "...", "rank": 0, "created_at": "...", "updated_at": "...", "archived_at": null }
    ],
    "notebook": [ ... ],
    "tag": [ ... ],
    "note_tag": [ ... ]
  }
}
```

**Rules:**
- Client sends only dirty rows (`synchronized_at IS NULL OR synchronized_at <> updated_at`).
- Server validates `uuid` format, required fields, enum values.
- Server **strips** `created_by`, `*_by`, `submitted_at`, `published_at`, `locked_at` from payload.
- Server sets `created_by = auth.uid()` on insert.
- Server upserts with LWW: `WHERE server.updated_at < client.updated_at OR (delete wins tie)`.
- Response: `{ "data": { "accepted": ["uuid1", "uuid2"], "rejected": [{"uuid": "...", "reason": "stale"}], "serverTime": "..." } }`

### Pull: `GET /api/v1/sync/pull?scope=workspace&uuid={workspace_uuid}&since={cursor}`

**Query params:**
- `scope`: `workspace` | `notebook` | `account` (default: `workspace`)
- `uuid`: scope identifier (workspace UUID, notebook UUID, or omitted for account)
- `since`: opaque cursor from previous pull (for delta pulls — MVP may omit)

**Response:**
```json
{
  "data": {
    "note": [ { "uuid": "...", "notebook_uuid": "...", "title": "...", "updated_at": "...", "archived_at": "...", ... } ],
    "notebook": [ ... ],
    "tag": [ ... ],
    "note_tag": [ ... ]
  },
  "meta": {
    "cursor": "next-cursor",
    "maxUpdatedAt": "2026-11-23T10:00:00Z"
  }
}
```

**Rules:**
- Returns rows scoped to authenticated user (RLS or query filter).
- **Includes archived rows** (tombstones) so deletions sync.
- Client upserts, sets `synchronized_at = updated_at` for clean rows.
- Client **never overwrites dirty row** (`local.updated_at > server.updated_at` → skip).
- Orphan guard: if parent UUID unknown locally, skip and retry next sync.
- Natural-key adoption: if incoming row matches local on natural key (e.g., `(note_uuid, tag_uuid)`), update local row instead of inserting.

---

## How to Add an Endpoint

1. **Specs**: Document in `db-design-choices.md` or new spec — route, auth, request/response, error cases.
2. **API**: Add route handler in `src/routes/<resource>/`.
3. **API**: Add validation (Zod/Joi) for body, query, params.
4. **API**: Add RLS policy or query filter for user scoping.
5. **API**: Write integration test (happy path + auth + validation + scoping).
6. **Web**: Add TypeScript types in `src/types/`.
7. **Web**: Add API client method in `src/lib/api/`.
8. **Android**: Add Retrofit interface + DTO + repository method.
9. **All**: Update 04_CHANGE_RULES if new lockstep set.
10. **Commit**: `grab-it-api/<feature>: Add <resource> <action> endpoint`

---

## Existing Validators

| Validator | Where | Rules |
|-----------|-------|-------|
| **Auth** | Middleware | Verify Supabase JWT; extract `auth.uid()`; attach to request |
| **UUID** | All params/body | Must be valid UUID v4 (or v7 later) |
| **Enum** | Body fields | Must match Postgres enum / SQLite CHECK |
| **Timestamp** | `created_at`, `updated_at`, `archived_at` | ISO-8601 UTC; `updated_at` ≤ `now() + 30s` |
| **Scoping** | All data routes | Row's workspace/account must match authenticated user |
| **Push allowlist** | `/sync/push` | Only permitted columns; strip `created_by`, `*_by`, lifecycle timestamps |
| **Rate limit** | All | Per-user sliding window (configurable) |

---

## Versioning

- **URL versioning**: `/api/v1/`, `/api/v2/`
- **Breaking changes** → new major version (`v2`).
- **Non-breaking** (add field, add endpoint) → same version.
- **Deprecation**: `Sunset` header + 90-day notice before removal.
- **Client compatibility**: Server supports `N-1` client version minimum.

---

## Common Mistakes

| Mistake | Consequence | Prevention |
|---------|-------------|------------|
| **Accepting `created_by` from client** | Ownership bypass | Push allowlist exclusion; integration test |
| **Not scoping query to user** | Data leak | RLS policies + integration test with two users |
| **Returning `id` (server surrogate)** | Client may try to use it | Never include `id` in response; only `uuid` |
| **Hard `DELETE` in endpoint** | Row resurrects on other clients | Soft delete only; code review checklist |
| **Missing `updated_at` in response** | Client can't mark clean | Always return `updated_at` on upsert/pull |
| **Not including archived in pull** | Deletions don't sync | Pull query: no `archived_at IS NULL` filter |
| **LWW not enforced on push** | Stale client overwrites newer | `WHERE server.updated_at < client.updated_at` |
| **Push without idempotency** | Retry creates duplicates | Upsert on `uuid`; LWW makes it idempotent |
| **No correlation ID in logs** | Can't trace request across services | Middleware generates + attaches |
| **Exposing internal errors** | Info leak | Map to generic `INTERNAL_ERROR`; log details server-side |

---

## Authentication Flow

1. **Web/Android**: Google Sign-In → get ID token.
2. **Client**: `POST /api/v1/auth/google` with `{ id_token: "..." }`.
3. **API**: Verify ID token with Google; create/get Supabase user; issue custom JWT (or use Supabase session).
4. **API**: Return `{ access_token, refresh_token, expires_in }`.
5. **Client**: Store tokens; send `Authorization: Bearer <access_token>` on all requests.
6. **API**: Middleware verifies JWT; extracts `auth.uid()`; attaches to request.
7. **Token refresh**: `POST /api/v1/auth/refresh` with refresh token → new access/refresh pair.

---

## Rate Limiting

| Tier | Limit | Window | Scope |
|------|-------|--------|-------|
| Auth endpoints | 10 | 1 min | IP |
| Sync push | 30 | 1 min | User |
| Sync pull | 60 | 1 min | User |
| CRUD endpoints | 120 | 1 min | User |
| Admin | 300 | 1 min | User |

Exceed → `429 RATE_LIMITED` with `Retry-After` header.

---

## Cross-References

| Topic | Document |
|-------|----------|
| Architecture (data flows) | 01_ARCHITECTURE |
| Lockstep sets (new endpoint) | 04_CHANGE_RULES #1 |
| Failure stories (auth, scoping, LWW) | 06_FAILURE_STORIES #3, #5, #8 |
| Debugging API issues | 05_DEBUGGING_PLAYBOOK #5 |
| Database (RLS, scoping) | 07_DATABASE |
| Security (auth, attribution) | 09_SECURITY |
| Deployment (versioning) | 10_DEPLOYMENT |
| Developer workflows (adding endpoint) | 14_DEVELOPER_WORKFLOWS |