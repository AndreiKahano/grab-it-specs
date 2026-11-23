# 16 — Engineering Principles

**Purpose:** Numbered, quotable rules, each with its reasoning, evidence, and source story. End with "trust the code over any document, including this one". Later principles are appended after it.

**Confidence note:** synthesized from all prior documents on 2026-11-23. The code wins.

---

## Principle 1: Offline-First Means Client Authority
**Rule:** The client is the source of truth for creation. The server never assigns IDs for syncable entities.

**Reasoning:** Users create data offline. Waiting for server round-trip breaks UX. Client-minted UUIDs work everywhere without coordination.

**Evidence:** db-design-choices.md §3 — "The creating client mints the `uuid`, and every relationship stores the parent's `uuid`."

**Source story:** Incident 4 (06_FAILURE_STORIES) — Declared FK on server blocked child-before-parent sync. Removing server FKs restored offline-first guarantee.

---

## Principle 2: Soft Delete Is Not Optional
**Rule:** Never hard `DELETE` user data. Use `archived_at` + `updated_at` bump. The tombstone must sync.

**Reasoning:** Hard delete leaves nothing to sync. Other clients push the row back. Soft delete creates a tombstone that travels like any edit.

**Evidence:** db-design-choices.md §5 — "A real `DELETE` leaves nothing to sync, so the other clients would push the row straight back."

**Source story:** Incident 1 (06_FAILURE_STORIES) — Hard delete caused "deleted notes come back." Soft delete fixed it permanently.

---

## Principle 3: Attribution Is a Security Boundary
**Rule:** `created_by`, `*_by`, lifecycle timestamps — server stamps only. Client never supplies them.

**Reasoning:** These columns enforce ownership ("authors edit only their own notes"). Client-supplied values let anyone claim anything.

**Evidence:** db-design-choices.md §4 — "The server stamps the actor columns and never accepts them from a client."

**Source story:** Incident 3 (06_FAILURE_STORIES) — Client sent forged `created_by` → ownership bypass. Push allowlist exclusion fixed it.

---

## Principle 4: Last-Write-Wins on `updated_at` — Delete Wins Ties
**Rule:** Conflict resolution: newer `updated_at` wins. Same second: delete wins.

**Reasoning:** Most rows have one natural editor. Row-level LWW needs only one timestamp. SQLite has 1-second precision, so edit+delete in same second share a stamp — delete must win.

**Evidence:** db-design-choices.md §6 — Server upsert `WHERE note.updated_at < EXCLUDED.updated_at OR (delete wins tie)`.

**Source story:** Incident 2 (06_FAILURE_STORIES) — Clock skew made fast clock win. Server timestamp validation added.

---

## Principle 5: Dirty Check Uses `synchronized_at` — Only Sync Writes It
**Rule:** `synchronized_at IS NULL OR synchronized_at <> updated_at` = dirty. Edits bump `updated_at` only. Sync writes `synchronized_at = updated_at` on success.

**Reasoning:** Two rules that must never break: (1) every local mutation bumps `updated_at`, (2) only sync writes `synchronized_at`. Break either → row silently stops syncing.

**Evidence:** db-design-choices.md §6 — "Two rules that must never break: every local mutation bumps `updated_at`, and only sync writes `synchronized_at`."

**Source story:** Incident 5 (06_FAILURE_STORIES) — Developer wrote `synchronized_at` on edit → row appeared clean → edits never pushed. Silent sync stop.

---

## Principle 6: No Declared Foreign Keys on Server `*_uuid`
**Rule:** Server does not declare `REFERENCES` on UUID foreign keys. Enforce on client (SQLite FKs ON); guard on pull; adopt by natural key.

**Reasoning:** Child may arrive before parent; clients hold partial datasets; soft deletes never remove parents; re-parenting without constraint rebuild.

**Evidence:** db-design-choices.md §3 — "Most server foreign keys are not declared... because a child batch that arrives before its parent fails."

**Source story:** Incident 4 (06_FAILURE_STORIES) — Declared FK blocked offline child-before-parent. Dropping FKs + orphan guard + natural-key adoption fixed it.

---

## Principle 7: Migrations Are Additive, Idempotent, Gated
**Rule:** Never edit applied migration. Write new one. `IF NOT EXISTS`, `WHERE col IS NULL`, run twice in CI.

**Reasoning:** Old clients must survive. Deploy retries must succeed. Schema evolves while multiple client versions run.

**Evidence:** db-design-choices.md §9 — "Apply the migration before deploying code that reads it. Never edit an applied script; write a new one."

**Source story:** Incident 7 (06_FAILURE_STORIES) — Non-idempotent migration failed on deploy retry. Idempotent pattern fixed it.

---

## Principle 8: Lockstep Sets Change Together
**Rule:** Schema, sync endpoints, client models, migrations — all change in one atomic commit per repo. Cross-repo changes split but coordinated.

**Reasoning:** Changing one without others breaks sync. Schema drift → data loss, crashes, silent corruption.

**Evidence:** 04_CHANGE_RULES — 8 lockstep sets with numbered file paths and *Miss →* notes.

**Source story:** Incident 10 (06_FAILURE_STORIES) — Cross-repo commit with wrong scope missed API review. Lockstep sets + commit scopes prevent this.

---

## Principle 9: Commit Scopes Route Reviews
**Rule:** Every commit: `product/feature: Imperative summary`. Generic scopes (`ui:`, `api:`) forbidden when product scope fits.

**Reasoning:** Scopes tell reviewers *what* is affected. Wrong scope → missed review → bugs in beta.

**Evidence:** git-guidelines.md Part 1 — "Choose the most specific scope that still describes the whole commit."

**Source story:** Incident 10 (06_FAILURE_STORIES) — `ui:` scope hid API change. Reviewer missed it. Bug shipped.

---

## Principle 10: Version Tags Derive from Commit History
**Rule:** Weekly `00Z` from ISO week of first commit. No commits = no tag. Never tag ongoing week. Tags chronological.

**Reasoning:** Build numbers reflect actual development timeline. Gaps don't consume numbers. Predictable, auditable.

**Evidence:** git-guidelines.md Part 2 — "Build `001` anchored to ISO week of each repo's first commit... weeks with no commits are skipped."

**Source story:** 2026-07-04 retroactive tag reconstruction — tags now match real history, not tagging start date.

---

## Principle 11: Test the Lockstep Sets, Not Just Lines
**Rule:** Coverage % doesn't matter. Every scenario in 11_TESTING "What Must Be Tested" has a test. Failure stories have regression tests.

**Reasoning:** Lockstep sets cause most incidents. Line coverage misses cross-repo invariants.

**Evidence:** 11_TESTING — "A scenario in 'What Must Be Tested' without a test is a gap, regardless of coverage %."

**Source story:** Multiple incidents (06_FAILURE_STORIES) — Unit tests passed, integration failed. Lockstep tests catch these.

---

## Principle 12: Deliberate Inefficiencies Are Documented
**Rule:** If we accept a known inefficiency (full pull, row-level LWW, UUID v4), it's in 12_PERFORMANCE with "when to revisit."

**Reasoning:** Hidden tech debt surprises later. Explicit acceptance forces future review.

**Evidence:** 12_PERFORMANCE — "Deliberate Inefficiencies (Leave Alone)" table with trigger conditions.

**Source story:** 01_ARCHITECTURE debt register — Each debt item has trigger to revisit.

---

## Principle 13: Security Checklist on Every Data Touch
**Rule:** PR changing auth, scoping, sync, or attribution passes 09_SECURITY checklist.

**Reasoning:** Data leaks and ownership bypasses are existential. Checklist catches omissions.

**Evidence:** 09_SECURITY — "Security Change Checklist" with 13 items.

**Source story:** Incident 3 (06_FAILURE_STORIES) — Forged `created_by` bypassed ownership. Checklist item "Attribution: Does it accept `created_by` from client?" would catch it.

---

## Principle 14: Debug with Correlation IDs
**Rule:** Every sync cycle generates correlation ID. Logs across all components include it. Search by ID = full trace.

**Reasoning:** Distributed debugging without correlation is guesswork. Sync spans client → API → DB.

**Evidence:** 05_DEBUGGING_PLAYBOOK — "Correlation ID in all logs. Generate per sync cycle; search across components."

**Source story:** Multiple debugging sessions — Without correlation ID, matching client push to server log to DB query took hours.

---

## Principle 15: Add What Surprised You to INBOX.md
**Rule:** Every workflow ends with "add what surprised you to INBOX.md." Stale skills are worse than none.

**Reasoning:** Surprises reveal gaps in docs, tests, or understanding. INBOX captures them for the next refresh.

**Evidence:** handoff.md — "During any other task, if you notice a document is wrong, fix it in the same change, or add an inbox entry."

**Source story:** This document itself — Generated from handoff.md, each workflow ended with INBOX reminder.

---

## Principle 16: Trust the Code Over Any Document, Including This One
**Rule:** A document that disagrees with the code is a bug. The code wins.

**Reasoning:** Documents drift. Code runs. When in doubt, read the implementation.

**Evidence:** Every skill document header — "**Confidence note:** ... The code wins (see 16)."

**Source story:** handoff.md — "The code wins. A document that disagrees with the code is a bug."

---

*End of principles. Later principles are appended after this line.*