# 09 — Security

**Purpose:** Threat model, authentication, authorization layers, secrets handling, injection surfaces, debug gates, accepted gaps, and a change checklist.

**Confidence note:** inferred from business-logic-v1.0.md (security layer), db-design-choices.md (attribution), and architecture on 2026-11-23. The code wins (see 16).

---

## Threat Model

| Asset | Threat | Likelihood | Impact | Mitigation |
|-------|--------|------------|--------|------------|
| User data (notes, notebooks) | Unauthorized read | Medium | High | RLS / query scoping; auth on every request |
| User data | Unauthorized write/delete | Medium | High | Attribution stamping; ownership checks |
| User credentials | Theft | Low | Critical | Google Sign-In only; no password storage |
| Session tokens | Hijack | Medium | High | Short-lived access tokens; refresh rotation; HTTPS only |
| Sync protocol | Replay/forge | Medium | High | LWW + server-stamped attribution; idempotent upserts |
| Database | Injection | Low | Critical | Parameterized queries; ORM; no dynamic SQL |
| Admin functions | Privilege escalation | Low | High | Role-based access; audit logs |
| Client storage | Local data theft | Medium | Medium | Encrypted SQLite (SQLCipher); OS keychain for tokens |

**Trust boundaries:**
- Client ↔ Server: TLS 1.2+; mutual auth via JWT
- Server ↔ Database: Supabase managed; RLS policies
- Client local: Encrypted at rest; OS sandbox

---

## Authentication

### Google Sign-In (Only Method)

| Platform | Flow |
|----------|------|
| Web | Google Identity Services → ID token → `POST /api/v1/auth/google` |
| Android | Google Sign-In API → ID token → `POST /api/v1/auth/google` |

**Server verification:**
1. Verify ID token signature (Google certs)
2. Check `aud` = our client ID, `iss` = `accounts.google.com`
3. Check `exp` > now
4. Get/create Supabase user by `sub` (Google user ID)
5. Issue custom JWT (or Supabase session) with `uid` = our `account.uuid`

**Token lifecycle:**
- Access token: 15 min, JWT, `uid` claim
- Refresh token: 30 days, rotating, stored in HTTP-only cookie (web) / EncryptedSharedPreferences (Android)
- Refresh: `POST /api/v1/auth/refresh` → new access + refresh pair
- Revoke: `POST /api/v1/auth/revoke` → blacklist refresh token

---

## Authorization Layers

### 1. Transport (API Gateway / Middleware)
- Verify JWT signature + expiry
- Extract `uid` → attach to request context
- Reject if invalid/expired → `401 UNAUTHENTICATED`

### 2. Resource Scoping (Every Data Query)
- **Row Level Security (RLS)** on Postgres: `USING (auth.uid() = created_by OR auth.uid() IN (SELECT member_uuid FROM workspace_member WHERE workspace_uuid = ...))`
- **Application-level fallback**: Every query filters by user's accessible workspaces
- **Sync pull**: Scoped to user's workspaces/account
- **Sync push**: Ownership verified on upsert (server stamps `created_by`)

### 3. Action Authorization
| Action | Check |
|--------|-------|
| Create note | User is member of notebook's workspace |
| Edit note | `note.created_by = auth.uid()` OR user is workspace admin |
| Delete note | Same as edit (soft delete) |
| Manage workspace | `workspace.owner_uuid = auth.uid()` |
| Manage tags | Workspace member |
| Admin endpoints | `account.role = 'admin'` |

### 4. Attribution as Authorization
- `created_by` stamped by server → proves ownership
- Action-specific actors (`rated_by`, `approved_by`) → proves who did what
- Never accept from client (push allowlist exclusion)

---

## Secrets Handling

| Secret | Where Stored | Rotation | Access |
|--------|--------------|----------|--------|
| Google OAuth client secret | Server env var (`GOOGLE_CLIENT_SECRET`) | 90 days | API only |
| Supabase service role key | Server env var (`SUPABASE_SERVICE_ROLE`) | 90 days | API only (admin ops) |
| JWT signing key | Server env var (`JWT_SECRET`) | 180 days | API only |
| Database password | Supabase managed | N/A | Supabase only |
| Android `google-services.json` | Not in repo; CI secret | Per release | Build only |
| Web `.env.local` | Not in repo; developer machine | N/A | Dev only |

**Rules:**
- **Never commit secrets.** Use `.env.example` with placeholders.
- **CI/CD injects secrets** at deploy time (GitHub Actions secrets, etc.).
- **Rotate on schedule** and after any suspected exposure.
- **No secrets in logs** — middleware scrubs `Authorization` header.

---

## Injection Surfaces

| Surface | Protection |
|---------|------------|
| **SQL** | Parameterized queries only (Postgres `pg` / Kysely / Supabase client); no string interpolation |
| **NoSQL** | N/A (Postgres only) |
| **Command injection** | No `exec`/`spawn` with user input |
| **Path traversal** | No file serving from user paths |
| **XSS (Web)** | React auto-escapes; CSP header; no `dangerouslySetInnerHTML` |
| **Deserialization** | Zod/Joi validation on all inputs; no `eval`/`Function` |
| **Sync payload** | Allowlist columns; strip attribution; validate UUIDs, enums, timestamps |

---

## Debug Gates

| Gate | Production | Staging/Dev |
|------|------------|-------------|
| **Debug endpoints** (`/debug/*`) | **Disabled** (404) | Enabled |
| **Verbose error details** | Generic `INTERNAL_ERROR` | Full stack trace |
| **SQL logging** | Off | On (sampled) |
| **Sync payload logging** | Off (PII risk) | On (scrubbed) |
| **Feature flags** | Controlled rollout | All on |

**Implementation:** `NODE_ENV=production` disables debug routes. Middleware checks env.

---

## Accepted Gaps (Known, Documented, Monitored)

| Gap | Reason | Monitoring | Mitigation |
|-----|--------|------------|------------|
| **No end-to-end encryption** | Complexity; search/indexing needs plaintext | Access logs; anomaly detection | At-rest encryption (Supabase); TLS in transit |
| **Client clock trust for LWW** | Hybrid logical clocks not yet implemented | Clock skew alerts; server `updated_at` validation | NTP check; server rejects future timestamps |
| **No per-field audit log** | Storage cost; row-level LWW loses history | N/A | Debt: append-only audit table for sensitive entities |
| **Refresh token in HTTP-only cookie (web)** | CSRF risk if not SameSite=Strict | CSRF token on mutating endpoints | `SameSite=Strict`; `Secure`; short access token |
| **No device binding** | UX friction (re-auth on new device) | Unusual location alerts | Optional: future 2FA / device trust |
| **RLS policies not on all tables** | Some tables use app-level scoping | Integration tests with two users | Audit: every syncable table has RLS or app filter |

---

## Security Change Checklist

**For every PR touching auth, data access, or sync:**

- [ ] **Auth**: Does it change token handling, verification, or scopes?
- [ ] **Scoping**: Does every new query filter by user's accessible data? (RLS or app-level)
- [ ] **Attribution**: Does it accept `created_by`/`*_by` from client? (Must not)
- [ ] **Soft delete**: Does it use `archived_at`? (No hard `DELETE`)
- [ ] **Validation**: Are all inputs validated (UUID, enum, timestamp, allowlist)?
- [ ] **Secrets**: Any new env var? Documented in `.env.example`? Injected in CI?
- [ ] **Logging**: No PII, tokens, or payloads in logs?
- [ ] **Error messages**: Generic in prod; no stack traces?
- [ ] **Rate limiting**: New endpoint added to limiter config?
- [ ] **CORS/CSP**: Web changes reviewed for headers?
- [ ] **Dependencies**: New dep scanned for vulnerabilities (`npm audit`, `gradle dependencyCheck`)?
- [ ] **Tests**: Integration test with two users (cross-access attempt)?
- [ ] **Documentation**: Updated 08_API, 07_DATABASE, 04_CHANGE_RULES if applicable?

---

## Incident Response (High-Level)

1. **Detect**: Alert on auth failures spike, unusual access patterns, error rate.
2. **Contain**: Revoke refresh tokens; disable API key; block IP.
3. **Investigate**: Correlation ID logs; audit trail (`created_by`, `*_by`).
4. **Remediate**: Patch; rotate secrets; deploy.
5. **Post-mortem**: Add to 06_FAILURE_STORIES; update 15_KNOWN_LIMITATIONS.

---

## Cross-References

| Topic | Document |
|-------|----------|
| Architecture (attribution, soft delete) | 01_ARCHITECTURE |
| Lockstep sets (attribution, soft delete) | 04_CHANGE_RULES #3, #4 |
| Failure stories (ownership bypass, auth) | 06_FAILURE_STORIES #3, #5 |
| Debugging auth/scoping issues | 05_DEBUGGING_PLAYBOOK #5 |
| Database (RLS, attribution columns) | 07_DATABASE |
| API (auth flow, rate limiting, validation) | 08_API |
| Deployment (secret rotation) | 10_DEPLOYMENT |
| Developer workflows (security review) | 14_DEVELOPER_WORKFLOWS |
| Known limitations (E2E encryption, audit log) | 15_KNOWN_LIMITATIONS |