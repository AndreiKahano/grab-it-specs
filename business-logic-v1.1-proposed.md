# Business Logic v1.1 (Proposed)

> Development of a Web-based community giveaway platform using Next.js and Supabase for students and local residents

- Allowed Platforms: Web, Android

## Project Details

- Company/Startup/Team Name: localgrabs
- Project Code Name: grab-it
- Project Short Code: grabit
- Short Description: A community platform where people post free items for pickup and discover what is available nearby.
- Long Description: grab-it lets people give away items they no longer need — books, clothes, school supplies, furniture, surplus food — and lets nearby students and residents find and claim them. All listings are created by users, pinned to an approximate pickup area, and expire automatically. The platform offers no credits, money, or convertible rewards. Rules are enforced through community-guideline hits and moderator action, not visible reputation. It stores minimal data, keeps no per-user activity trails, and earns revenue mainly from local sponsorship slots. Data resale is the last option and only with consent.

## Positioning & Differentiation

| Dimension | grab-it | Freecycle / Buy Nothing | Facebook Marketplace | Craigslist |
|-----------|---------|------------------------|---------------------|------------|
| **Cost** | Free, no ads in feed | Free, email-based | Free, ad-heavy | Free, ad-heavy |
| **Privacy** | Blurred locations, no trails | Public email threads | Public profiles | Anonymous email |
| **Moderation** | Community hits + moderators | Volunteer admins | Algorithmic + reports | Flagging only |
| **Rewards** | None (intrinsic only) | None | None | None |
| **Mobile** | Native Android + PWA | No | Yes | No |
| **Offline** | Read/write offline | No | No | No |
| **Data resale** | Opt-in only, last resort | N/A | Core business | Core business |

**Core value props:**
- **Givers:** Clear space fast, no haggling, no strangers at door until confirmed
- **Seekers:** Find useful items nearby, no competition, no fees
- **Community:** Self-governed, privacy-respecting, locally sustainable

## User Levels

> Note: Modify/rename the list of users based on the actual users that you expect to use the system.

| User Level | Description |
|------------|-------------|
| A. System Administrator | Maintains/overrides system/server configurations, runs data-retention purge jobs, performs regular backups. |
| B. Administrator | Manages general settings (categories, guidelines, retention limits), generates periodic aggregated analytics and reports. |
| C. Moderator | Reviews reported listings, removes content violating community guidelines, applies guideline hits. |
| D. Contributor | Logged-in users who post free items, claim items, mark items as given, report violations, manage consent. |
| E. Guest | Users who do not log in; view limited nearby listings with approximate locations only. |

## System Requirements (MVP)

1. **Auth** — Users authenticate via Google Sign-In; consent managed per Data Privacy Act.
2. **Post Listing** — Users post a free item with photo, title, category, description, approximate pickup area (barangay-level), and expiry time (1–168 hours).
3. **Browse & Search** — Users browse, search, and filter nearby items in list and map views using blurred locations (barangay centroid ±500m).
4. **Claim Flow** — Users claim an item; giver confirms claim before exact pickup location is revealed.
5. **Manage Listings** — Users edit, mark as given, or delete own listings; listings auto-expire at set time.
6. **Report & Moderate** — Users report listings violating guidelines; moderators/admins review, remove content, apply guideline hits (3 hits = auto-suspend).
7. **Admin & Compliance** — Admins manage categories, guidelines, retention limits; view aggregated analytics (threshold ≥10 users); run purge jobs; manage sponsorship slots.

## Required Solution Layers

1. **Security & Privacy by Design** — Data Privacy Act compliance, location protection (blurring), retention limits (default 30 days post-expiry), no per-user trails, aggregation thresholds (≥10), consent for any data resale.
2. **Offline-First Sync** — Clients write to local SQLite; sync via API to Supabase/Postgres. UUID identity, soft deletes, last-write-wins on `updated_at`. Server stamps attribution (`created_by`) from session.
3. **Community Governance** — Guideline hits (3 = suspend), moderator review queue, transparent removal reasons, appeal via admin.

## MVP Features and Access

> See the User Levels table for reference.

| Feature | Access | Notes |
|---------|--------|-------|
| 1. Browse and search nearby items (blurred locations) | A,B,C,D,E | Guest sees list/map; no claim, no exact location |
| 2. Google Sign-In and consent management | A,B,C,D | Consent granular: analytics, sponsorship, data resale |
| 3. Post, edit, mark as given, delete own listings | A,B,C,D | Photo ≤3, category required, expiry 1–168h, barangay pickup |
| 4. Claim items, confirm pickup, report listings | A,B,C,D | Claim → giver confirms → exact location shared; report categories defined |
| 5. Review reports, remove listings, apply guideline hits | A,B,C | Moderator queue; 3 hits = 7-day suspend; admin can override |
| 6. Aggregated analytics and guideline/retention settings | A,B | Threshold ≥10 users; no per-user trails; retention 1–90 days |
| 7. Server configuration, backups, data purge jobs | A | Purge: expired + retention period; backup: daily Supabase PITR |

## Listing Categories (Fixed for MVP)

| Category | Examples |
|----------|----------|
| Books & School Supplies | Textbooks, notebooks, stationery |
| Clothing & Accessories | Shirts, shoes, bags, uniforms |
| Furniture & Appliances | Chairs, tables, fans, microwaves |
| Food & Pantry | Canned goods, rice, snacks (non-perishable preferred) |
| Electronics & Gadgets | Phones, laptops, cables, power banks |
| Home & Decor | Curtains, rugs, organizers, plants |
| Sports & Outdoors | Balls, rackets, yoga mats, tents |
| Others | Miscellaneous items not above |

## Claim Flow (Detailed)

1. Seeker taps **Claim** on listing → status becomes `claimed`, seeker locked in.
2. Giver receives notification → taps **Confirm** or **Decline**.
3. On **Confirm**: exact pickup address + contact info revealed to seeker; listing status `confirmed`.
4. On **Decline**: listing returns to `available`; seeker notified.
5. Seeker picks up → either party taps **Mark Given** → listing status `given`, auto-archives after 24h.
6. No-show / dispute → either party reports → moderator reviews.

## Notification Triggers (MVP)

| Trigger | Channel | Recipient |
|---------|---------|-----------|
| New claim on your listing | Push + in-app | Giver |
| Claim confirmed / declined | Push + in-app | Seeker |
| Listing expiring in 2h | Push + in-app | Giver |
| Report received on your listing | In-app | Giver |
| Guideline hit applied | Push + in-app | Contributor |
| Moderation decision | Push + in-app | Reporter + reported |

## Image Handling (MVP)

- Max 3 photos per listing, ≤5 MB each, JPEG/WebP.
- Uploaded to Supabase Storage (private bucket); signed URLs for display.
- Client-side resize to max 1920px before upload.
- Blurred thumbnail generated server-side for map/list views.

## Map & Location (MVP)

- **Approximate location:** Barangay centroid ±500m jitter (consistent per listing).
- **Exact location:** Shared only after claim confirmation.
- **Map view:** Leaflet (Web) / Google Maps SDK (Android) with clustered markers.
- **Search radius:** Default 5 km, adjustable 1–20 km.

## Report Categories (MVP)

| Category | Description |
|----------|-------------|
| Prohibited item | Weapons, drugs, alcohol, recalled products |
| Misleading | Wrong category, false condition, bait-and-switch |
| Spam / Duplicate | Same item posted repeatedly |
| Safety concern | Unsafe pickup location, harassment |
| Expired / Not available | Item already given but not marked |
| Other | Free text (moderator reviews) |

## Guideline Hits System

- 1st hit: Warning + guideline link
- 2nd hit: 24-hour posting suspension
- 3rd hit: 7-day posting suspension + moderator review
- Hits expire after 90 days of clean activity
- Admin can override / clear hits

## Consent Management (MVP)

| Consent Type | Default | Granularity |
|--------------|---------|-------------|
| Analytics aggregation | Opt-in | Per purpose |
| Sponsorship notifications | Opt-in | Per sponsor |
| Data resale (future) | Opt-out | Explicit per request |

## Data Retention & Purge (MVP)

| Data | Retention | Purge Trigger |
|------|-----------|---------------|
| Active listings | Until expiry + 24h | Auto-expire job |
| Given/archived listings | 30 days post-expiry | Daily purge job |
| Reports & moderation logs | 90 days | Daily purge job |
| Aggregated analytics | Indefinite | Never (anonymized) |
| User consent records | Indefinite | Never |
| Soft-deleted rows | 90 days | Daily purge job |

## Sponsorship Slots (MVP)

- 1 sponsored slot per 20 organic listings in feed/map.
- Sponsor provides: image, headline, link (external).
- No tracking pixels; click-through counted server-side.
- Admin manages sponsors, pricing, scheduling.

## Non-Goals (Explicitly Out of Scope for MVP)

- User-to-user messaging (use claim flow + contact reveal)
- Ratings / reviews / reputation scores
- Favorites / watchlists / saved searches
- In-app payments / donations / tips
- Multi-language (English + Filipino only)
- Advanced analytics dashboards
- API for third parties
- Webhooks / integrations
- Native iOS app (PWA covers iOS)

## Success Metrics (MVP Launch)

| Metric | Target (Month 3) |
|--------|------------------|
| Weekly active contributors | ≥500 |
| Listings posted / week | ≥1,000 |
| Claim confirmation rate | ≥70% |
| Report rate | ≤2% of listings |
| Moderator queue SLA | ≤24h |
| Crash-free sessions | ≥99.5% |
| Sync success rate | ≥99% |

## Notes

- Listings are time-limited and auto-expire; expired content is purged per the retention limit.
- Exact pickup locations are shared only after the giver confirms a claim.
- No credits, points, money, or convertible rewards; no visible reputation scores.
- Analytics are shown only as aggregates above a minimum threshold (≥10 users); no per-user trails are stored.
- Revenue direction: local sponsorship slots first; data resale is the last option and requires explicit consent.
- The Android client mirrors the web features and uses the same Supabase-backed API.
- Offline-first: users can browse cached listings, create/edit claims offline; sync on reconnect.
- All timestamps ISO-8601 UTC; client clocks validated ±30s on sync.