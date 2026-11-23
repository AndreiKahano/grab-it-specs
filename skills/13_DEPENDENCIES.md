# 13 — Dependencies

**Purpose:** The policy, then each dependency's reason, upgrade traps, and deliberate rejections.

**Confidence note:** inferred from typical stack for this architecture on 2026-11-23. The code wins (see 16).

---

## Dependency Policy

| Rule | Enforcement |
|------|-------------|
| **Minimize dependencies** | Prefer stdlib / platform APIs; justify each external dep |
| **Pin exact versions** | `package-lock.json`, `gradle.lockfile` committed |
| **Scan for vulnerabilities** | `npm audit` / `gradle dependencyCheck` in CI |
| **No transitive surprises** | Review `npm ls` / `gradle dependencies` on add/update |
| **License compliance** | Only MIT, Apache-2.0, BSD-3-Clause, ISC; no GPL/AGPL |
| **Bundle size budget** | Web: < 200 KB gzipped JS; Android: < 5 MB DEX |
| **Upgrade cadence** | Monthly for security; quarterly for features; test full suite |
| **Lockfile updates** | Separate PR; auto-merge if tests pass |

---

## grab-it-api (Node.js / TypeScript)

### Runtime Dependencies

| Package | Version | Reason | Upgrade Traps | License |
|---------|---------|--------|---------------|---------|
| `@supabase/supabase-js` | 2.x | Supabase client (Postgres, Auth, Realtime) | Breaking changes in v3; watch for RLS API changes | MIT |
| `kysely` | 0.27.x | Type-safe SQL query builder | API stable; dialect changes rare | MIT |
| `zod` | 3.23.x | Runtime validation (request/response) | v4 may break schemas; test thoroughly | MIT |
| `jsonwebtoken` | 9.x | JWT sign/verify | Algorithm changes rare; check `jwk` support | MIT |
| `jwks-rsa` | 3.x | Google cert caching for ID token verification | Cache TTL config changed in v3 | MIT |
| `express` | 4.x | HTTP framework | v5 in beta; middleware signature changes | MIT |
| `helmet` | 7.x | Security headers | CSP config changes | MIT |
| `cors` | 2.x | CORS middleware | Stable | MIT |
| `express-rate-limit` | 7.x | Rate limiting | Key generator signature changed in v7 | MIT |
| `pino` | 9.x | Structured logging | v9 changed API; use `pino-pretty` for dev | MIT |
| `uuid` | 9.x | UUID v4/v7 generation | Stable | MIT |
| `date-fns` | 3.x | Date formatting/parsing | v3 ESM only; ensure build handles | MIT |

### Dev Dependencies

| Package | Version | Reason |
|---------|---------|--------|
| `typescript` | 5.x | Type checking |
| `vitest` | 2.x | Unit/integration testing |
| `@types/node` | 20.x | Node types |
| `eslint` | 9.x | Linting |
| `prettier` | 3.x | Formatting |
| `testcontainers` | 10.x | Postgres in tests |
| `supertest` | 7.x | HTTP testing |
| `husky` | 9.x | Git hooks |
| `lint-staged` | 15.x | Pre-commit lint |

---

## grab-it-web (React / TypeScript / Vite)

### Runtime Dependencies

| Package | Version | Reason | Upgrade Traps | License |
|---------|---------|--------|---------------|---------|
| `react` | 18.x | UI framework | v19 concurrent features; test Suspense | MIT |
| `react-dom` | 18.x | DOM renderer | Same as React | MIT |
| `react-router-dom` | 6.x | Routing | v7 stable; loader/action API changes | MIT |
| `@tanstack/react-query` | 5.x | Server state / caching | v5 major; queryKey changes; test invalidation | MIT |
| `axios` | 1.x | HTTP client | Stable; interceptors unchanged | MIT |
| `zod` | 3.23.x | Validation (shared with API) | Same as API | MIT |
| `@google/identity-services` | 1.x | Google Sign-In (Web) | Loaded from CDN; version in script URL | Apache-2.0 |
| `date-fns` | 3.x | Date formatting | Same as API | MIT |
| `clsx` | 2.x | Conditional classNames | Stable | MIT |
| `lucide-react` | 0.4.x | Icons | Tree-shakeable; bundle size grows | ISC |

### Dev Dependencies

| Package | Version | Reason |
|---------|---------|--------|
| `vite` | 5.x | Build tool |
| `typescript` | 5.x | Type checking |
| `vitest` | 2.x | Unit testing |
| `playwright` | 1.4x | E2E testing |
| `eslint` | 9.x | Linting |
| `prettier` | 3.x | Formatting |
| `@vitejs/plugin-react` | 4.x | React plugin |
| `tailwindcss` | 3.x | CSS framework (if used) |
| `postcss` | 8.x | CSS processing |
| `autoprefixer` | 10.x | Vendor prefixes |

---

## grab-it-android (Kotlin / Gradle)

### Runtime Dependencies (build.gradle.kts)

| Dependency | Version | Reason | Upgrade Traps | License |
|------------|---------|--------|---------------|---------|
| `androidx.core:core-ktx` | 1.12+ | Android KTX extensions | API level changes | Apache-2.0 |
| `androidx.lifecycle:lifecycle-viewmodel-ktx` | 2.7+ | ViewModel | SavedStateHandle changes | Apache-2.0 |
| `androidx.room:room-runtime` | 2.6+ | SQLite ORM | Schema export changes; test migrations | Apache-2.0 |
| `androidx.room:room-ktx` | 2.6+ | Room Kotlin extensions | Coroutines API | Apache-2.0 |
| `androidx.datastore:datastore-preferences` | 1.0+ | Encrypted preferences (tokens) | Proto vs preferences | Apache-2.0 |
| `com.google.android.gms:play-services-auth` | 20.7+ | Google Sign-In | Breaking in 21.x; test silently | Apache-2.0 |
| `com.squareup.retrofit2:retrofit` | 2.9+ | HTTP client | Converter factory changes | Apache-2.0 |
| `com.squareup.retrofit2:converter-kotlinx-serialization` | 2.9+ | JSON serialization | Serialization config | Apache-2.0 |
| `org.jetbrains.kotlinx:kotlinx-serialization-json` | 1.6+ | Kotlin serialization | Format changes; test round-trip | Apache-2.0 |
| `org.jetbrains.kotlinx:kotlinx-coroutines-android` | 1.7+ | Coroutines | Structured concurrency | Apache-2.0 |
| `org.jetbrains.kotlinx:kotlinx-datetime` | 0.5+ | Date/time (ISO-8601) | API stabilizing | Apache-2.0 |
| `com.github.ajalt:sqlcipher` | 4.5+ | Encrypted SQLite | Native libs; ABI changes | BSD-3-Clause |
| `androidx.security:security-crypto` | 1.1+ | EncryptedSharedPreferences | Master key rotation | Apache-2.0 |
| `com.google.dagger:hilt-android` | 2.48+ | DI | Generated code changes | Apache-2.0 |
| `androidx.navigation:navigation-fragment-ktx` | 2.7+ | Navigation | Back stack changes | Apache-2.0 |
| `androidx.activity:activity-ktx` | 1.8+ | Activity APIs | Predictive back | Apache-2.0 |

### Dev Dependencies

| Dependency | Version | Reason |
|------------|---------|--------|
| `org.jetbrains.kotlin:kotlin-gradle-plugin` | 1.9+ | Kotlin compiler |
| `com.android.tools.build:gradle` | 8.3+ | Android Gradle Plugin |
| `org.jetbrains.kotlin:kotlin-serialization` | 1.9+ | Serialization compiler plugin |
| `com.google.dagger:hilt-compiler` | 2.48+ | Hilt annotation processor |
| `androidx.room:room-compiler` | 2.6+ | Room annotation processor |
| `androidx.test:rules` | 1.5+ | Test rules |
| `androidx.test.espresso:espresso-core` | 3.5+ | UI testing |
| `org.mockito:mockito-kotlin` | 5.1+ | Mocking |
| `org.junit:junit` | 4.13+ | Unit testing |
| `org.robolectric:robolectric` | 4.11+ | Unit testing with Android APIs |

---

## grab-it-specs (Documentation / Tooling)

### Dev Dependencies

| Package | Version | Reason |
|---------|---------|--------|
| `prettier` | 3.x | Markdown formatting |
| `markdownlint-cli` | 0.41+ | Markdown linting |
| `markdown-link-check` | 3.11+ | Link validation |
| `husky` | 9.x | Git hooks |
| `lint-staged` | 15.x | Pre-commit lint |

---

## Deliberate Rejections (Considered, Not Adopted)

| Dependency | Reason for Rejection | Alternative |
|------------|---------------------|-------------|
| **Firebase Auth** | Vendor lock-in; Google Sign-In direct is simpler | Google Identity Services + custom JWT |
| **Supabase Realtime** | Not needed for sync (pull/push model); adds complexity | Polling + manual refresh |
| **Prisma ORM** | Heavy; migration model conflicts with our additive approach | Kysely (type-safe, no migration tool) |
| **Redux / Zustand** | React Query covers server state; local state minimal | `useState` / `useReducer` + React Query |
| **Apollo Client** | GraphQL not used; REST + React Query sufficient | TanStack Query |
| **Drift (Dart)** | Not Kotlin; Android is Kotlin-first | Room + SQLCipher |
| **ObjectBox** | Proprietary; SQLCipher + Room is standard | Room + SQLCipher |
| **Ktor Client** | Retrofit + Kotlinx Serialization is more mature for REST | Retrofit |
| **Koin** | Hilt is Google-standard; compile-time validation | Hilt |
| **Compose** | Team expertise in Views/XML; migration cost high | Views + ViewBinding (for now) |
| **ExoPlayer** | No media playback in MVP | N/A |
| **WorkManager** | Sync is user-initiated + foreground; no background scheduling needed | Coroutines + lifecycle |

---

## Upgrade Traps by Ecosystem

### Node.js (API + Web)
| Trap | Detection | Mitigation |
|------|-----------|------------|
| **ESM/CJS interop** | Build fails or `require` errors | Use `type: module` consistently; test build |
| **TypeScript `lib` changes** | New globals break compile | Pin `typescript` version; upgrade intentionally |
| **Vite plugin API** | Dev server breaks | Pin `vite`; test dev + build |
| **React 19 concurrent** | Suspense boundaries break | Test all async components; wrap in `<Suspense>` |
| **Zod v4** | Schema parsing changes | Integration test all validators |

### Android
| Trap | Detection | Mitigation |
|------|-----------|------------|
| **AGP 8.x → 9.x** | Build config DSL changes | Read migration guide; test in branch |
| **Kotlin 1.9 → 2.0** | Compiler plugin API changes | Update serialization/Hilt/Room plugins together |
| **Room 2.6 → 2.7** | Schema export format | Run `roomSchemaLocation` task; verify |
| **Play Services Auth 20 → 21** | Sign-in API breaking | Test silent sign-in + UI flow |
| **SQLCipher native libs** | ABI mismatch on new Android | Test on API 24, 30, 34; use `jniLibs` |

---

## Dependency Update Procedure

1. **Monthly (Security):**
   - Run `npm audit fix` / `gradle dependencyCheckUpdate`
   - Create PR with lockfile changes only
   - CI runs full test suite
   - Auto-merge if green

2. **Quarterly (Feature):**
   - Review `npm outdated` / `gradle dependencyUpdates`
   - Pick 1-2 deps with valuable features
   - Update in separate PR with changelog review
   - Manual test + CI

3. **Major Version:**
   - Read migration guide fully
   - Spike in branch (2 days max)
   - If blocked, document in INBOX.md and defer
   - Never skip minor versions (e.g., 18 → 20)

---

## Cross-References

| Topic | Document |
|-------|----------|
| Architecture (tech choices) | 01_ARCHITECTURE |
| Project structure (where deps live) | 02_PROJECT_STRUCTURE |
| Code style (tooling versions) | 03_CODE_STYLE |
| Change rules (lockstep for dep updates) | 04_CHANGE_RULES |
| Testing (dependency testing) | 11_TESTING |
| Deployment (build reproducibility) | 10_DEPLOYMENT |
| Security (vulnerability scanning) | 09_SECURITY |
| Known limitations (rejected deps) | 15_KNOWN_LIMITATIONS |