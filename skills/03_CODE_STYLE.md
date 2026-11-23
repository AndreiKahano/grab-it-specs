# 03 — Code Style

**Purpose:** Comment philosophy (the why, at the line), tooling, naming, error handling, logging, preferred patterns, anti-patterns with the cost that banned each, and commit conventions.

**Confidence note:** inferred from git-guidelines.md and db-design-choices.md on 2026-11-23. The code wins (see 16).

---

## Comment Philosophy

- **Write the *why*, not the *what*.** The code shows what; comments explain reasoning, constraints, and "scar tissue."
- **Comment at the line** for non-obvious decisions: `// Miss → what happens` beside the guard that prevents it.
- **No commented-out code.** Delete it; git history has it.
- **Document invariants** at the top of the file/module: "This module assumes X, guarantees Y."
- **Decision records** go in 01_ARCHITECTURE.md, not in code comments.

---

## Tooling

| Language/Platform | Formatter | Linter | Notes |
|-------------------|-----------|--------|-------|
| TypeScript (web) | Prettier | ESLint | `npm run format`, `npm run lint` |
| Kotlin (Android) | ktlint | detekt | `./gradlew ktlintFormat`, `./gradlew detekt` |
| SQL (migrations) | pgFormatter | — | Run before commit |
| Markdown (specs) | Prettier | markdownlint | `npm run format:md` |

**Pre-commit hooks** should run format + lint for staged files. CI fails on format/lint violations.

---

## Naming Conventions

| Construct | Convention | Example |
|-----------|------------|---------|
| Tables (Postgres/SQLite) | `snake_case`, singular | `note`, `note_tag` |
| Columns | `snake_case` | `notebook_uuid`, `updated_at` |
| Primary key (server) | `id` (`bigint`) | `note.id` |
| Global identity | `uuid` | `note.uuid` |
| Foreign key (uuid) | `<parent>_uuid` | `note.notebook_uuid` |
| Attribution | `created_by`, `<action>_by` | `rated_by`, `approved_by` |
| Timestamps | `*_at` (`timestamptz`/ISO-8601) | `created_at`, `archived_at` |
| Soft delete | `archived_at` | `note.archived_at` |
| Sync marker (client) | `synchronized_at` | `note.synchronized_at` |
| Indexes | `idx_<table>_<col>[_live]` | `idx_note_notebook_live` |
| TypeScript types | `PascalCase` | `Note`, `NoteTag` |
| TypeScript interfaces | `PascalCase` (no `I` prefix) | `NoteRepository` |
| Kotlin classes | `PascalCase` | `NoteDao`, `SyncEngine` |
| Kotlin functions | `camelCase` | `pushDirtyNotes()` |
| Constants | `UPPER_SNAKE_CASE` | `MAX_SYNC_BATCH_SIZE` |
| Git scopes | `product/subsystem:` | `grab-it-api/sync:` |

---

## Error Handling

| Principle | Rule |
|-----------|------|
| **Fail fast** | Validate inputs at boundaries; crash early with context |
| **No silent failures** | Every `catch` logs or rethrows; `Miss →` comment on guard |
| **Error types** | Domain errors (expected) vs. bugs (unexpected). Domain errors return typed results; bugs throw. |
| **Server errors** | Return standard envelope: `{ error: { code, message, details? } }` |
| **Client errors** | Show user-friendly message; log technical details for debugging |
| **Sync errors** | Distinguish: network (retry), conflict (LWW resolved), validation (fix data), auth (re-auth) |
| **Database errors** | Unique violation → natural-key adoption; FK violation → orphan guard retry |

---

## Logging

| Level | When | Format |
|-------|------|--------|
| `ERROR` | Bugs, data loss, auth failures, sync crashes | `timestamp level [correlation_id] message {context}` |
| `WARN` | Recoverable issues: retry, fallback, deprecated path | Same |
| `INFO` | Key lifecycle: sync start/end, auth, migrations | Same |
| `DEBUG` | Verbose: SQL, payloads, state transitions | Same (sampling in prod) |

- **Correlation ID**: Generate per request/sync cycle; pass through all logs.
- **No PII in logs**: Never log tokens, passwords, personal data.
- **Structured logging**: JSON in production; pretty in development.

---

## Preferred Patterns

| Pattern | Where | Why |
|---------|-------|-----|
| **Repository pattern** | Data access (all platforms) | Testable, swappable, encapsulates sync logic |
| **Result/Either type** | Domain operations | Explicit success/failure, no exceptions for control flow |
| **Immutable data** | State, DTOs, entities | Predictable, thread-safe, easier sync |
| **Single source of truth** | Schema in migrations; types generated from it | Prevents drift (see 04_CHANGE_RULES) |
| **Additive migrations** | Schema evolution | Zero-downtime, old clients survive |
| **Scoped pulls** | Sync | Privacy, bandwidth, partial datasets |
| **Orphan guard + natural-key adoption** | Pull | Handles out-of-order, duplicate UUIDs |
| **Partial unique indexes** | Soft delete uniqueness | Archived rows don't block new ones |

---

## Anti-Patterns (Banned)

| Anti-Pattern | Cost That Banned It |
|--------------|---------------------|
| **Hard `DELETE` on user data** | Row resurrects on other clients; no tombstone to sync |
| **Client sends `created_by`/`*_by`** | Ownership bypass; anyone can claim anything |
| **Declared FKs on server `*_uuid`** | Child-before-parent batch fails; partial client datasets break |
| **Mirroring `*_uuid` → local `*_id`** | Second copy of every relationship; translation drift; breaks on rebuild |
| **Overwriting dirty row on pull** | Newer local edit lost; ties must go to server |
| **Not bumping `updated_at` on local edit** | Row never pushes; silent sync stop |
| **Writing `synchronized_at` on local edit** | Row appears clean; edits never push |
| **Server accepts `updated_at` from client without LWW check** | Stale client overwrites newer server data |
| **UUID v4 primary key on server** | Page splits, fragmentation; use `bigint` surrogate + UUID v7 later |
| **Schema removal before all clients upgrade** | Old clients crash sending dropped columns |
| **Commit without scope** | Changelog noise; reviewers can't triage |
| **Ticket number as commit summary** | Future developer can't understand *what* or *why* |
| **One commit doing multiple things** | Bisect breaks; revert reverts too much |

---

## Commit Conventions

**Source of truth:** `grab-it-specs/git-guidelines.md` (Part 1).

### Required Format
```
scope: Imperative summary
```

### Scope Rules
- Use product/feature scope: `grab-it-api/sync:`, `grab-it-web/auth:`, `grab-it-android/sync:`
- Cross-feature: `grab-it-api:`, `grab-it-web:`, `grab-it-android:`
- Specs: `grab-it-specs/<feature>:` or `grab-it-specs/design:`
- General only when product scope doesn't fit: `db:`, `config:`, `ci:`, `deps:`

### Summary Rules
- Imperative mood: "If applied, this commit will — [summary]"
- Sentence case, no period, ≤50 chars
- Describes **what**, not what you did
- Spec changes: `Define`, `Clarify`, `Revise`, `Deprecate` (the spec change, not implementation)

### Full Structure
```
scope: Imperative summary

Why this change was necessary and what problem it solves. Wrap at 72 chars.

Fixes #1234 — Short description of the ticket
See-also #1201 — Related prior change
```

### Breaking Changes
```
scope:! Imperative summary

BREAKING CHANGE: Description of what breaks and migration path.
```

---

## Code Review Checklist

- [ ] Scope follows conventions
- [ ] Summary passes one-sentence test (see git-guidelines)
- [ ] No silent failures (`Miss →` comments on guards)
- [ ] Attribution columns not accepted from client
- [ ] `updated_at` bumped on every local mutation
- [ ] `synchronized_at` only written by sync, never by edit
- [ ] Soft delete used (`archived_at`), no hard `DELETE`
- [ ] Migration is additive, idempotent, gated
- [ ] Lockstep set updated (04_CHANGE_RULES)
- [ ] Tests cover happy path + error cases
- [ ] No PII in logs