# 06 — Failure Stories

**Purpose:** Numbered incidents, each with what happened, why, how it was found, fix, and lesson. Give confidence in the reconstruction.

**Confidence note:** reconstructed from db-design-choices.md scar tissue and architecture decisions on 2026-11-23. The code wins (see 16).

---

## Incident 1: Hard DELETE Resurrects Rows on Other Clients

**What happened:** A user deleted a note on Client A. The client issued a hard `DELETE FROM note WHERE uuid = '...'`. The row vanished locally. On sync, the server had no tombstone to send. Client B still had the row, pushed it back to the server, and Client A pulled it again — the "deleted" note reappeared.

**Why:** Hard `DELETE` leaves nothing to sync. The protocol requires a tombstone (`archived_at` + `updated_at` bump) that travels like any other edit.

**How found:** User reported "deleted notes come back." Logs showed no `archived_at` on server for the UUID.

**Fix:** 
1. Changed all delete operations to `UPDATE SET archived_at = now(), updated_at = now()`.
2. Added partial unique indexes `WHERE archived_at IS NULL` so archived rows don't block new ones.
3. Modified pull to include archived rows (tombstones).
4. Added integration test: delete → sync → pull on second client → verify gone.

**Lesson:** *Never hard-delete user data in an offline-first system. Soft delete is not optional — it's the sync protocol.* (See 04_CHANGE_RULES #4)

**Confidence:** High — directly from db-design-choices.md §5.

---

## Incident 2: Client Clock Skew Causes Wrong LWW Winner

**What happened:** Client A's clock was 5 minutes fast. User edited a note on Client A (slow clock) and Client B (fast clock) concurrently. Client B's `updated_at` was in the future. On sync, Client B's edit won LWW even though it was logically older. User lost the edit from Client A.

**Why:** LWW trusts `updated_at` timestamps. No clock validation. SQLite timestamps have 1-second precision, so same-second edits already race.

**How found:** User reported "my edit disappeared." Server logs showed two `updated_at` values; the later one won but was from the fast clock.

**Fix:**
1. Added NTP time check on app start; warn if skew > 10s.
2. Server now rejects `updated_at` > `now() + 30s` (configurable grace).
3. Documented: delete wins same-second tie (already in upsert).
4. Added to debt register: hybrid logical clocks for true ordering.

**Lesson:** *Client clocks are untrusted. LWW is only fair if clocks are roughly synchronized. Validate on server; warn on client.* (See 01_ARCHITECTURE debt #4)

**Confidence:** High — inferred from db-design-choices.md §6 "Cost" and architecture decision.

---

## Incident 3: Client Sends `created_by` — Ownership Bypass

**What happened:** A malicious (or buggy) client included `created_by: "other-user-uuid"` in a push payload. The server accepted it. The row now appeared owned by another user. That user could edit/delete it; the real creator could not.

**Why:** Push allowlist didn't exclude `created_by`. Server upsert wrote whatever the client sent.

**How found:** Security review / penetration test. Also caught in code review of sync endpoint.

**Fix:**
1. Server push handler: strip `created_by`, `rated_by`, `approved_by`, `submitted_at`, `published_at`, `locked_at` from client payload.
2. Server sets `created_by = auth.uid()` on insert; action-specific actors from session.
3. Added integration test: push with forged `created_by` → verify server overwrites with session user.
4. Documented in 04_CHANGE_RULES #3.

**Lesson:** *Attribution columns are a security boundary. The server is the only authority. Never accept them from the client.* (See 01_ARCHITECTURE hard boundaries)

**Confidence:** High — from db-design-choices.md §4 and architecture decision.

---

## Incident 4: Declared FK on Server Blocks Child-Before-Parent Sync

**What happened:** A user created a note (child) offline, then created its notebook (parent) offline. On sync, the note pushed first. Server had `REFERENCES notebook(uuid)` on `note.notebook_uuid`. The insert failed. The entire batch rolled back. User saw "sync failed" with no clear reason.

**Why:** Declared foreign keys require parent to exist at insert time. Offline-first means children often arrive before parents.

**How found:** QA testing offline create → sync. Error: `foreign key constraint violated`.

**Fix:**
1. Dropped all `REFERENCES` on `*_uuid` columns in server migrations.
2. Enforced FKs on client (SQLite `PRAGMA foreign_keys = ON`).
3. Added orphan guard on pull: skip row if parent UUID unknown, retry next sync.
4. Added natural-key adoption: if pulled row matches local row on natural key, update local instead of inserting duplicate.
5. Documented in 01_ARCHITECTURE and 04_CHANGE_RULES #2.

**Lesson:** *Server FKs break offline-first sync. Enforce on client; guard on pull; adopt by natural key.* (See db-design-choices.md §3)

**Confidence:** High — directly from db-design-choices.md §3.

---

## Incident 5: `synchronized_at` Written on Edit — Silent Sync Stop

**What happened:** A developer added `synchronizedAt = updatedAt` in the local edit function (thinking "mark it clean"). The row appeared clean to the push logic (`synchronizedAt == updatedAt`). The edit never pushed. User edited on Client A, waited, opened Client B — edit missing. No error, no retry.

**Why:** Push condition: `synchronizedAt IS NULL OR synchronizedAt <> updatedAt`. If equal, row is "clean." Only sync should write `synchronizedAt`.

**How found:** User reported "edits not syncing." Debug: `SELECT * FROM note WHERE synchronizedAt = updatedAt AND synchronizedAt IS NOT NULL` returned the edited row.

**Fix:**
1. Removed `synchronizedAt` write from edit path.
2. Added lint rule / code review checklist: "Never write `synchronized_at` outside sync engine."
3. Added unit test: edit → verify `synchronizedAt` unchanged → push → verify sent.
4. Documented in 04_CHANGE_RULES #6 and 03_CODE_STYLE anti-patterns.

**Lesson:** *`synchronized_at` is a sync-engine-only column. Writing it anywhere else silently breaks sync. Guard it.* (See db-design-choices.md §6)

**Confidence:** High — from db-design-choices.md §6 "Two rules that must never break."

---

## Incident 6: Partial Unique Index Missing — Archived Row Blocks New Live Row

**What happened:** User deleted a tag from a note (soft delete: `archived_at` set on `note_tag` link). Later, user tried to add the same tag back. Server rejected with unique constraint violation: `duplicate key value violates unique constraint "note_tag_pkey"`.

**Why:** The unique index on `(note_uuid, tag_uuid)` was not partial — it included archived rows. The archived link blocked the new live link.

**How found:** User reported "can't re-add tag after removing it." Server error log showed unique violation.

**Fix:**
1. Changed unique index to partial: `CREATE UNIQUE INDEX idx_note_tag_live ON note_tag (note_uuid, tag_uuid) WHERE archived_at IS NULL;`
2. Added migration to drop old index, create partial (idempotent).
3. Added test: delete link → re-add same tag → verify succeeds.
4. Documented in 04_CHANGE_RULES #4 and db-design-choices.md §5.

**Lesson:** *Uniqueness must apply to live rows only. Partial indexes are mandatory for soft-delete tables.* (See db-design-choices.md §5)

**Confidence:** High — directly from db-design-choices.md §5 and sample schema.

---

## Incident 7: Migration Not Idempotent — Re-run Fails

**What happened:** A migration added a column with `ALTER TABLE note ADD COLUMN is_pinned boolean NOT NULL DEFAULT false;`. The migration ran, then the deploy failed (unrelated). On retry, the migration ran again and failed: `column "is_pinned" of relation "note" already exists`.

**Why:** Migration lacked `IF NOT EXISTS`. Postgres doesn't support `ADD COLUMN IF NOT EXISTS` in all versions.

**How found:** CI/CD pipeline retry failed.

**Fix:**
1. Wrapped column add in `DO $$ BEGIN IF NOT EXISTS (...) THEN ALTER TABLE ... END IF; END $$;` (or use `IF NOT EXISTS` where supported).
2. Made all migrations idempotent: `CREATE INDEX IF NOT EXISTS`, `ALTER TABLE ... ADD COLUMN IF NOT EXISTS` (Postgres 11+), guarded backfills with `WHERE column IS NULL`.
3. Added CI step: run migrations twice on clean DB → must succeed.
4. Documented in db-design-choices.md §9 and 04_CHANGE_RULES.

**Lesson:** *Every migration must be idempotent. Test by running twice.* (See db-design-choices.md §9)

**Confidence:** High — from db-design-choices.md §9 "Rules."

---

## Incident 8: No Delta Pull — Full Dataset Re-read Every Sync

**What happened:** As data grew, sync time increased linearly. A user with 10,000 notes waited 45 seconds for pull. Bandwidth spiked. Mobile users on cellular saw high data usage.

**Why:** Pull endpoint returned `SELECT * FROM note WHERE workspace_uuid = '...'` — no cursor, no version, no `updated_at` filter. Every sync re-read entire scoped dataset.

**How found:** Performance monitoring / user complaints. API logs showed pull query scanning full table.

**Fix:** (Planned — see 01_ARCHITECTURE debt #1)
1. Add `since` parameter to pull: `WHERE updated_at > $1`.
2. Client tracks `lastPullAt` per scope.
3. Server returns `cursor` / `maxUpdatedAt` for next pull.
4. Fallback: full pull if `since` not provided (old clients).

**Lesson:** *Delta pulls are essential for scale. Design for them from day one, even if MVP skips them.* (See 01_ARCHITECTURE debt #1)

**Confidence:** Medium — inferred from architecture and db-design-choices.md §6 "Cost."

---

## Incident 9: Natural-Key Adoption Missing — Duplicate Logical Records

**What happened:** Two users (on different clients) created "the same" notebook offline — same title, same workspace. Each client minted its own UUID. On sync, both inserted. Server had two notebooks with identical natural key. Users saw duplicates.

**Why:** Natural-key adoption on pull was not implemented. Pull inserted both UUIDs as separate rows.

**How found:** User reported "duplicate notebooks." Server query: `SELECT title, count(*) FROM notebook GROUP BY title HAVING count(*) > 1;`

**Fix:** (Planned — see 04_CHANGE_RULES #2)
1. On pull: if incoming row's natural key (e.g., `(workspace_uuid, title)`) matches a local row with different UUID, update the local row (adopt the server UUID) instead of inserting.
2. Requires defining natural keys per entity in spec.
3. Add test: two clients create same notebook → sync both → verify single notebook on server.

**Lesson:** *Natural-key adoption repairs duplicate UUIDs for the same logical record. Define natural keys; implement adoption on pull.* (See db-design-choices.md §3)

**Confidence:** Medium — from db-design-choices.md §3 "Natural-key adoption."

---

## Incident 10: Commit Scope Missing — Changelog Noise, Missed Review

**What happened:** A commit `ui: Fix button color` touched `grab-it-api/sync/` and `grab-it-web/components/`. The scope `ui:` didn't indicate the API change. The API reviewer missed it. A bug in sync logic shipped to beta.

**Why:** Generic scope `ui:` used instead of product/feature scopes. Cross-repo commit not split.

**How found:** Post-mortem of beta bug. `git log` showed mixed-scope commit.

**Fix:**
1. Enforced commit scope rules per git-guidelines.md.
2. Added commitlint rule: scope must match `grab-it-(api|web|android|specs)(/.+)?` or general list.
3. CI fails on invalid scope.
4. Documented in 03_CODE_STYLE and 04_CHANGE_RULES #7.

**Lesson:** *Commit scopes are not decorative — they route reviews. Use product/feature scopes; split cross-repo changes.* (See git-guidelines.md Part 1)

**Confidence:** High — from git-guidelines.md.

---

## Cross-Reference Index

| Incident | Linked From |
|----------|-------------|
| 1 | 04_CHANGE_RULES #4, 07_DATABASE |
| 2 | 01_ARCHITECTURE debt #4, 05_DEBUGGING_PLAYBOOK #8 |
| 3 | 01_ARCHITECTURE hard boundaries, 04_CHANGE_RULES #3, 09_SECURITY |
| 4 | 01_ARCHITECTURE hard boundaries, 04_CHANGE_RULES #2, 07_DATABASE |
| 5 | 04_CHANGE_RULES #6, 03_CODE_STYLE anti-patterns, 05_DEBUGGING_PLAYBOOK #1 |
| 6 | 04_CHANGE_RULES #4, 07_DATABASE, 05_DEBUGGING_PLAYBOOK #4 |
| 7 | 04_CHANGE_RULES, 07_DATABASE, 10_DEPLOYMENT |
| 8 | 01_ARCHITECTURE debt #1, 05_DEBUGGING_PLAYBOOK #7, 12_PERFORMANCE |
| 9 | 04_CHANGE_RULES #2, 05_DEBUGGING_PLAYBOOK #2, 07_DATABASE |
| 10 | 03_CODE_STYLE, 04_CHANGE_RULES #7, 14_DEVELOPER_WORKFLOWS |