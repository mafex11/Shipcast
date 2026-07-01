# Plan C: Shipcast Cloud + GitHub Action + Launch Assets

**Date:** 2026-07-02  
**Depends On:** Plans A/B (Swift CLI complete)  
**Status:** Ready for execution

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to execute this plan. Do not start implementation without loading one of these skills first.

---

## Goal

Build and deploy the hosted Shipcast service at shipcast.devmafex.com with:
1. **Cloud platform**: Next.js App Router on Vercel serving appcast XML, release API, dashboard with adoption analytics, and landing page
2. **GitHub Action**: Composite action wrapping the CLI for CI/CD release automation
3. **Launch assets**: Getting-started, signing, and action docs; demo GIF script; landing page copy

Exit condition: floatX releases via GitHub Action, appcast served from production, dashboard shows real adoption data, docs live.

---

## Architecture

```
Customer CI (GitHub Actions)
    ├─▶ shipcast/action@v1 (composite)
    │   ├─ brew install CLI
    │   ├─ keychain: import Developer ID cert
    │   ├─ shipcast release (with env vars)
    │   └─ cleanup: delete keychain
    │
    └─▶ POST /api/v1/apps/:app/releases
             │
             ▼
    shipcast.devmafex.com (Vercel)
    ├─ Next.js 14 App Router
    ├─ Neon Postgres (via Prisma)
    ├─ NextAuth GitHub OAuth
    ├─ GET /u/:user/:app/appcast.xml (edge-cached 300s)
    ├─ Dashboard: apps list + per-app analytics
    └─ Landing page
```

---

## Tech Stack

- **Framework:** Next.js 14+ (App Router), TypeScript
- **Database:** Neon Postgres (free tier: 10 GB storage, 100 hours compute/mo)
- **ORM:** Prisma
- **Auth:** NextAuth.js v5 (GitHub OAuth provider)
- **UI:** Tailwind CSS + shadcn/ui components
- **Charts:** Recharts
- **Testing:** Vitest (unit/API route tests), Playwright (E2E smoke tests)
- **Hosting:** Vercel (free tier: 100 GB-hours/mo serverless, 100 GB bandwidth)
- **Domain:** shipcast.devmafex.com (Cloudflare DNS CNAME to Vercel)

---

## Global Constraints

1. **$0 fixed cost:** Vercel free tier (100 GB bandwidth, 100 GB-hours compute), Neon free tier (10 GB storage, 100 hours compute/mo). No paid services.

2. **Security posture:** Service stores ONLY public release metadata (URLs, hashes, signatures, notes). NEVER credentials, private keys, or Apple ID.

3. **Appcast caching:** `GET /u/:user/:app/appcast.xml` is edge-cached 300 seconds (`export const revalidate = 300`).

4. **Analytics retention:** FetchEvent raw rows deleted after 7 days via daily rollup into FetchDaily. Keeps row count bounded for free tier.

5. **API authentication:** Per-user bearer token (`User.apiToken` field, included in `Authorization: Bearer <token>` header). POST /api/v1/apps/:app/releases validates token → User lookup.

6. **Exit contract of POST /api/v1/apps/:app/releases:**
   - **Auth:** Bearer token in `Authorization` header → User lookup
   - **Body:** JSON with `{version, artifact_url, sha256, ed_signature, length, min_system_version?, release_notes_html?, channel="stable"}`
   - **Validation:**
     - App exists and belongs to authenticated user (404/403)
     - (app, version, channel) tuple unique → 409 if duplicate
     - All required fields present → 422 if missing
   - **Response:**
     - 201 Created with `{id: string}` on success
     - 401 Unauthorized if token invalid/missing
     - 403 Forbidden if app belongs to different user
     - 404 Not Found if app doesn't exist
     - 409 Conflict if (app, version, channel) already exists
     - 422 Unprocessable Entity if body validation fails

7. **Exit contract of GET /u/:user/:app/appcast.xml:**
   - **Response:** RSS 2.0 XML with Sparkle namespace
   - **Structure:** Single `<channel>` with `<item>` per Release, ordered newest-first by publishedAt
   - **Required elements per item:**
     - `<title>Version {version}</title>`
     - `<sparkle:version>{version}</sparkle:version>`
     - `<pubDate>{RFC 2822 date}</pubDate>`
     - `<enclosure url="{artifactUrl}" length="{length}" type="application/octet-stream" sparkle:edSignature="{edSignature}"/>`
     - `<sparkle:minimumSystemVersion>{minSystemVersion}</sparkle:minimumSystemVersion>` (if set)
     - `<sparkle:releaseNotesLink>{releaseNotesLink}</sparkle:releaseNotesLink>` (only if releaseNotesHtml exists and hosted)
   - **Side effect:** Fire-and-forget FetchEvent insert (appId, timestamp, version from User-Agent if parseable, uaCoarse)
   - **Caching:** `export const revalidate = 300` (5 minutes edge cache)
   - **Error handling:** 404 if app not found; 200 empty channel if no releases yet

8. **Composite action specification (action/action.yml):**
   - **Inputs:** apple-id, apple-team-id, apple-password, developer-id-p12, p12-password, sparkle-private-key, shipcast-token, github-token (all required)
   - **Steps:**
     1. Install CLI: `brew install mafex11/tap/shipcast`
     2. Create temp keychain:
        ```bash
        security create-keychain -p "$TEMP_PW" build.keychain
        security default-keychain -s build.keychain
        security unlock-keychain -p "$TEMP_PW" build.keychain
        security set-keychain-settings -lut 21600 build.keychain
        ```
     3. Import cert:
        ```bash
        echo "$DEVELOPER_ID_P12" | base64 --decode > cert.p12
        security import cert.p12 -k build.keychain -P "$P12_PASSWORD" -T /usr/bin/codesign
        security set-key-partition-list -S apple-tool:,apple: -s -k "$TEMP_PW" build.keychain
        ```
     4. Run release: `shipcast release` (with env var exports for APPLE_*, SPARKLE_*, SHIPCAST_*, GITHUB_TOKEN)
     5. Cleanup (post step): `security delete-keychain build.keychain && rm -f cert.p12`

---

## Tasks

### Task 1: Scaffold cloud/ Next.js project + Prisma setup

**Files:**
- `/Users/mafex/code/personal/ShipCast/cloud/package.json`
- `/Users/mafex/code/personal/ShipCast/cloud/next.config.js`
- `/Users/mafex/code/personal/ShipCast/cloud/tailwind.config.ts`
- `/Users/mafex/code/personal/ShipCast/cloud/tsconfig.json`
- `/Users/mafex/code/personal/ShipCast/cloud/.env.example`
- `/Users/mafex/code/personal/ShipCast/cloud/app/layout.tsx`
- `/Users/mafex/code/personal/ShipCast/cloud/app/page.tsx` (placeholder)
- `/Users/mafex/code/personal/ShipCast/cloud/prisma/schema.prisma` (empty for now)
- `/Users/mafex/code/personal/ShipCast/cloud/.gitignore`

**Interfaces:**
- **Consumes:** None
- **Produces:** Runnable Next.js app (dev server starts), Prisma initialized

**Steps:**
- [ ] Create `/Users/mafex/code/personal/ShipCast/cloud/` directory
- [ ] Run `cd /Users/mafex/code/personal/ShipCast/cloud && npx create-next-app@latest . --typescript --tailwind --app --no-src-dir --import-alias "@/*"` (accept defaults)
- [ ] Add Prisma dependencies: `cd /Users/mafex/code/personal/ShipCast/cloud && npm install prisma @prisma/client && npx prisma init`
- [ ] Create `.env.example` with keys: `DATABASE_URL`, `NEXTAUTH_URL`, `NEXTAUTH_SECRET`, `GITHUB_ID`, `GITHUB_SECRET`, `CRON_SECRET`
- [ ] Write `next.config.js` with `reactStrictMode: true`, no other overrides
- [ ] Write `.gitignore` to exclude `.env`, `.env.local`, `node_modules`, `.next`
- [ ] Run `npm run dev` → expect dev server starts on port 3000 → PASS
- [ ] Commit: "Scaffold cloud Next.js project with Prisma init"

---

### Task 2: Prisma schema + migration + seed script

**Files:**
- `/Users/mafex/code/personal/ShipCast/cloud/prisma/schema.prisma`
- `/Users/mafex/code/personal/ShipCast/cloud/prisma/seed.ts`
- `/Users/mafex/code/personal/ShipCast/cloud/prisma/migrations/` (generated)
- `/Users/mafex/code/personal/ShipCast/cloud/lib/prisma.ts` (singleton client)

**Interfaces:**
- **Consumes:** Spec §Prisma Schema (verbatim)
- **Produces:** Database schema deployed, seed data with known apiToken for testing

**Steps:**
- [ ] Write `prisma/schema.prisma` verbatim from spec (User, App, Release, FetchEvent, FetchDaily models with exact fields, uniques, indexes)
- [ ] Create `lib/prisma.ts` with singleton PrismaClient pattern (prevents hot-reload exhaustion):
  ```typescript
  import { PrismaClient } from '@prisma/client';
  const globalForPrisma = global as unknown as { prisma: PrismaClient };
  export const prisma = globalForPrisma.prisma || new PrismaClient();
  if (process.env.NODE_ENV !== 'production') globalForPrisma.prisma = prisma;
  ```
- [ ] Set `DATABASE_URL` in `.env` to Neon connection string (create Neon project "shipcast" at neon.tech)
- [ ] Run `npx prisma migrate dev --name init` → expect migration succeeds → PASS
- [ ] Write `prisma/seed.ts`:
  - Create User: `{githubId: 12345, githubLogin: "testuser", apiToken: "test-token-12345"}`
  - Create App: `{slug: "test-app", name: "Test App", userId: <user.id>}`
  - Create 2 Releases for test-app: v1.0.0 and v1.1.0 (valid artifact_url from GitHub Releases format, length, sha256, edSignature placeholders)
- [ ] Add to `package.json` scripts: `"prisma": { "seed": "tsx prisma/seed.ts" }`
- [ ] Install tsx: `npm install -D tsx`
- [ ] Run `npx prisma db seed` → expect seed data created → PASS
- [ ] Query via `npx prisma studio` → verify User/App/Release rows exist → PASS
- [ ] Commit: "Add Prisma schema, migration, and seed script"

---

### Task 3: Appcast XML generation library (pure function + unit tests)

**Files:**
- `/Users/mafex/code/personal/ShipCast/cloud/lib/appcast.ts`
- `/Users/mafex/code/personal/ShipCast/cloud/lib/appcast.test.ts`
- `/Users/mafex/code/personal/ShipCast/cloud/vitest.config.ts`

**Interfaces:**
- **Consumes:** `Release[]` (from Prisma)
- **Produces:** RSS 2.0 XML string (Sparkle-compliant)

**Steps:**
- [ ] Install Vitest: `npm install -D vitest`
- [ ] Create `vitest.config.ts` with alias `@/` → `./`
- [ ] Write `lib/appcast.ts` with function:
  ```typescript
  export function generateAppcastXML(appName: string, releases: Release[]): string {
    // RSS 2.0 boilerplate with xmlns:sparkle
    // Sort releases by publishedAt DESC
    // Map each release to <item> with title, sparkle:version, pubDate (RFC 2822), enclosure (url/length/type/sparkle:edSignature), sparkle:minimumSystemVersion (if set), sparkle:releaseNotesLink (if releaseNotesHtml exists)
    // Return XML string
  }
  ```
- [ ] Write `lib/appcast.test.ts`:
  - Test case: empty releases → valid RSS with empty channel
  - Test case: single release → item with all required fields
  - Test case: multiple releases → items in reverse chronological order
  - Test case: release without minSystemVersion → no sparkle:minimumSystemVersion tag
  - Test case: release without releaseNotesHtml → no sparkle:releaseNotesLink tag
- [ ] Run `npx vitest run` → expect all tests FAIL (not implemented yet) → PASS (expected failure)
- [ ] Implement `generateAppcastXML` function (use template literals for XML, escape HTML entities in releaseNotesHtml if present)
- [ ] Run `npx vitest run` → expect all tests PASS → PASS
- [ ] Create golden file test: save known-good XML to `lib/appcast.golden.xml`, assert output matches
- [ ] Commit: "Add appcast XML generation library with unit tests"

---

### Task 4: Appcast route handler + fetch event logging

**Files:**
- `/Users/mafex/code/personal/ShipCast/cloud/app/u/[user]/[app]/appcast.xml/route.ts`

**Interfaces:**
- **Consumes:** Prisma (User, App, Release queries), appcast lib
- **Produces:** RSS XML response (edge-cached 300s), FetchEvent row (fire-and-forget)

**Steps:**
- [ ] Create directory structure: `mkdir -p app/u/[user]/[app]/appcast.xml`
- [ ] Write route handler `route.ts`:
  ```typescript
  export const revalidate = 300; // 5 min edge cache
  export async function GET(req: Request, { params }: { params: { user: string, app: string } }) {
    // 1. Query App by userId (lookup User.githubLogin = params.user) + slug = params.app
    // 2. If not found → return 404
    // 3. Query Releases for appId, order by publishedAt DESC
    // 4. Generate XML via generateAppcastXML
    // 5. Fire-and-forget FetchEvent insert (try/catch, log error but don't block response):
    //    - Extract version from User-Agent if parseable (Sparkle UA format)
    //    - Insert { appId, timestamp: now, version?, uaCoarse: parsed macOS version }
    // 6. Return Response with Content-Type: application/rss+xml
  }
  ```
- [ ] Write test in `app/u/[user]/[app]/appcast.xml/route.test.ts`:
  - Mock Prisma queries (User, App, Release)
  - Call GET with mocked params
  - Assert response is 200, Content-Type is application/rss+xml, body contains expected `<item>` count
- [ ] Run `npx vitest run` → expect FAIL (not implemented) → PASS
- [ ] Implement route handler
- [ ] Run `npx vitest run` → expect PASS → PASS
- [ ] Manual test: Start dev server, curl `http://localhost:3000/u/testuser/test-app/appcast.xml` → expect RSS XML with seed data releases → PASS
- [ ] Commit: "Add appcast XML route handler with fetch logging"

---

### Task 5: POST /api/v1/apps/:app/releases route (auth + validation)

**Files:**
- `/Users/mafex/code/personal/ShipCast/cloud/app/api/v1/apps/[app]/releases/route.ts`
- `/Users/mafex/code/personal/ShipCast/cloud/app/api/v1/apps/[app]/releases/route.test.ts`

**Interfaces:**
- **Consumes:** Bearer token (Authorization header), JSON body (version, artifact_url, sha256, ed_signature, length, min_system_version?, release_notes_html?, channel)
- **Produces:** 201 with {id}, or 401/403/404/409/422

**Steps:**
- [ ] Create directory: `mkdir -p app/api/v1/apps/[app]/releases`
- [ ] Write route handler `route.ts`:
  ```typescript
  export async function POST(req: Request, { params }: { params: { app: string } }) {
    // 1. Extract Authorization header, parse "Bearer <token>"
    // 2. Query User by apiToken, if not found → return 401
    // 3. Query App by slug = params.app, if not found → return 404
    // 4. Verify app.userId === user.id, else → return 403
    // 5. Parse body (zod schema: version, artifact_url, sha256, ed_signature, length, min_system_version?, release_notes_html?, channel default "stable")
    // 6. Check unique constraint: Release.findFirst({ where: { appId, version, channel } }), if exists → return 409
    // 7. Create Release
    // 8. Return 201 with { id: release.id }
  }
  ```
- [ ] Write test `route.test.ts`:
  - Test: missing Authorization → 401
  - Test: invalid token → 401
  - Test: app doesn't exist → 404
  - Test: app belongs to different user → 403
  - Test: duplicate (app, version, channel) → 409
  - Test: valid request → 201 with id
- [ ] Install zod: `npm install zod`
- [ ] Run `npx vitest run` → expect FAIL → PASS
- [ ] Implement route handler with zod validation
- [ ] Run `npx vitest run` → expect PASS → PASS
- [ ] Commit: "Add POST releases API route with auth and validation"

---

### Task 6: Daily rollup cron route

**Files:**
- `/Users/mafex/code/personal/ShipCast/cloud/app/api/cron/rollup/route.ts`
- `/Users/mafex/code/personal/ShipCast/cloud/vercel.json`

**Interfaces:**
- **Consumes:** FetchEvent table (raw events)
- **Produces:** FetchDaily upserts (aggregated counts), deletes old FetchEvents (>7 days)

**Steps:**
- [ ] Create directory: `mkdir -p app/api/cron/rollup`
- [ ] Write route handler `route.ts`:
  ```typescript
  export async function GET(req: Request) {
    // 1. Verify CRON_SECRET header matches env var, else → return 401
    // 2. SQL via Prisma raw query:
    //    INSERT INTO FetchDaily (appId, date, version, fetchCount)
    //    SELECT appId, DATE(timestamp), version, COUNT(*)
    //    FROM FetchEvent
    //    WHERE timestamp >= CURRENT_DATE - INTERVAL '1 day'
    //      AND timestamp < CURRENT_DATE
    //    GROUP BY appId, DATE(timestamp), version
    //    ON CONFLICT (appId, date, version)
    //    DO UPDATE SET fetchCount = FetchDaily.fetchCount + EXCLUDED.fetchCount
    // 3. Delete old FetchEvents: DELETE FROM FetchEvent WHERE timestamp < CURRENT_DATE - INTERVAL '7 days'
    // 4. Return 200 with { rolledUp: <count>, deleted: <count> }
  }
  ```
- [ ] Write `vercel.json` with cron config:
  ```json
  {
    "crons": [{
      "path": "/api/cron/rollup",
      "schedule": "0 1 * * *"
    }]
  }
  ```
- [ ] Test: Seed FetchEvent rows with timestamps 2 days ago, run handler, verify FetchDaily created and old FetchEvents deleted
- [ ] Commit: "Add daily rollup cron route"

---

### Task 7: NextAuth setup + middleware protecting /dashboard

**Files:**
- `/Users/mafex/code/personal/ShipCast/cloud/lib/auth.ts`
- `/Users/mafex/code/personal/ShipCast/cloud/app/api/auth/[...nextauth]/route.ts`
- `/Users/mafex/code/personal/ShipCast/cloud/middleware.ts`

**Interfaces:**
- **Consumes:** GitHub OAuth (GITHUB_ID, GITHUB_SECRET)
- **Produces:** Session (user GitHub ID + login), protected /dashboard routes

**Steps:**
- [ ] Install NextAuth: `npm install next-auth@beta` (v5)
- [ ] Write `lib/auth.ts`:
  ```typescript
  import NextAuth from "next-auth";
  import GitHub from "next-auth/providers/github";
  export const { handlers, auth, signIn, signOut } = NextAuth({
    providers: [GitHub],
    callbacks: {
      async signIn({ profile }) {
        // Upsert User: githubId = profile.id, githubLogin = profile.login, email = profile.email
        return true;
      },
      async session({ session, token }) {
        // Attach user.githubLogin to session
        return session;
      }
    }
  });
  ```
- [ ] Create route `app/api/auth/[...nextauth]/route.ts`: export handlers
- [ ] Write `middleware.ts`:
  ```typescript
  import { auth } from "@/lib/auth";
  export default auth((req) => {
    if (req.nextUrl.pathname.startsWith("/dashboard") && !req.auth) {
      return Response.redirect(new URL("/api/auth/signin", req.url));
    }
  });
  export const config = { matcher: ["/dashboard/:path*"] };
  ```
- [ ] Set GITHUB_ID and GITHUB_SECRET in `.env` (create GitHub OAuth App at github.com/settings/developers)
- [ ] Test: Visit `/dashboard` → redirects to GitHub OAuth → after auth, redirects back
- [ ] Commit: "Add NextAuth GitHub OAuth with dashboard middleware"

---

### Task 8: Dashboard pages (apps list + per-app analytics)

**Files:**
- `/Users/mafex/code/personal/ShipCast/cloud/app/(auth)/dashboard/page.tsx`
- `/Users/mafex/code/personal/ShipCast/cloud/app/(auth)/dashboard/[app]/page.tsx`
- `/Users/mafex/code/personal/ShipCast/cloud/components/AppCard.tsx`
- `/Users/mafex/code/personal/ShipCast/cloud/components/ReleaseTable.tsx`
- `/Users/mafex/code/personal/ShipCast/cloud/components/AdoptionChart.tsx`

**Interfaces:**
- **Consumes:** Prisma (App, Release, FetchDaily queries), session (user)
- **Produces:** Dashboard UI (apps list, release table, adoption line chart)

**Steps:**
- [ ] Install shadcn/ui: `npx shadcn@latest init` (accept defaults)
- [ ] Add components: `npx shadcn@latest add card button table`
- [ ] Install recharts: `npm install recharts`
- [ ] Create `app/(auth)/dashboard/page.tsx`:
  - Query Apps for current user
  - For each app, compute latest release version and install estimate (avg daily fetchCount from FetchDaily last 7 days)
  - Render grid of AppCard components
- [ ] Create `components/AppCard.tsx`: Display app name, latest version, install count estimate, link to `/dashboard/[app]`
- [ ] Create `app/(auth)/dashboard/[app]/page.tsx`:
  - Query Releases for app, order by publishedAt DESC
  - Query FetchDaily for app (last 30 days), group by date and version
  - Render ReleaseTable and AdoptionChart
  - Display appcast URL with copy button: `https://shipcast.devmafex.com/u/{user}/{app}/appcast.xml`
- [ ] Create `components/ReleaseTable.tsx`: Table with columns (version, date, channel, artifact URL)
- [ ] Create `components/AdoptionChart.tsx`: Line chart (recharts) with x-axis = date, y-axis = fetchCount, lines per version
- [ ] Add "Create App" button on dashboard index → form with slug validation (^[a-z0-9-]+$), creates App row
- [ ] Test: Sign in → see apps list → click app → see releases and chart
- [ ] Commit: "Add dashboard pages with analytics and app management"

---

### Task 9: Landing page

**Files:**
- `/Users/mafex/code/personal/ShipCast/cloud/app/page.tsx`
- `/Users/mafex/code/personal/ShipCast/cloud/components/FeatureGrid.tsx`
- `/Users/mafex/code/personal/ShipCast/cloud/components/PricingTable.tsx`

**Interfaces:**
- **Consumes:** None (static content)
- **Produces:** Marketing landing page

**Steps:**
- [ ] Write `app/page.tsx`:
  - Hero: "Push a tag. Ship a Mac app." tagline, subheading about signed/notarized/auto-updating apps
  - CTA: `brew install mafex11/tap/shipcast` (copy button)
  - Link to GitHub: github.com/mafex11/shipcast
  - FeatureGrid component
  - PricingTable component
- [ ] Create `components/FeatureGrid.tsx`:
  - Grid of 4 features: "Free CLI" (full pipeline open-source), "Hosted Updates" (appcast at shipcast.devmafex.com), "Ad-Hoc Signing" (no Apple cert needed), "Auto Casks" (Homebrew PRs)
- [ ] Create `components/PricingTable.tsx`:
  - Single tier: "Free during beta", "Later: $9/mo per app"
  - Note: CLI always free (MIT)
- [ ] Test: Visit root → see landing page with all sections
- [ ] Commit: "Add landing page with features and pricing"

---

### Task 10: Playwright E2E smoke test

**Files:**
- `/Users/mafex/code/personal/ShipCast/cloud/tests/smoke.spec.ts`
- `/Users/mafex/code/personal/ShipCast/cloud/playwright.config.ts`

**Interfaces:**
- **Consumes:** Seeded database (test user + app + releases), running dev server
- **Produces:** E2E test validating full flow (POST release → GET appcast → parse XML)

**Steps:**
- [ ] Install Playwright: `npm install -D @playwright/test && npx playwright install`
- [ ] Create `playwright.config.ts` with baseURL `http://localhost:3000`
- [ ] Write `tests/smoke.spec.ts`:
  - Test: POST /api/v1/apps/test-app/releases with known apiToken → expect 201
  - Test: GET /u/testuser/test-app/appcast.xml → expect 200, parse XML, assert new release in `<item>`, verify `sparkle:edSignature` attribute present
- [ ] Run `npm run dev` in background
- [ ] Run `npx playwright test` → expect PASS → PASS
- [ ] Commit: "Add Playwright E2E smoke test"

---

### Task 11: GitHub Action composite action + test workflow

**Files:**
- `/Users/mafex/code/personal/ShipCast/action/action.yml`
- `/Users/mafex/code/personal/ShipCast/.github/workflows/test-action.yml`

**Interfaces:**
- **Consumes:** Inputs (apple-id, apple-team-id, apple-password, developer-id-p12, p12-password, sparkle-private-key, shipcast-token, github-token)
- **Produces:** Runs `shipcast release` in CI with cert imported to temp keychain

**Steps:**
- [ ] Create directory: `mkdir -p action`
- [ ] Write `action/action.yml`:
  ```yaml
  name: 'Shipcast Release'
  description: 'Build, sign, notarize, and release Mac apps with Shipcast'
  inputs:
    apple-id: { required: true }
    apple-team-id: { required: true }
    apple-password: { required: true }
    developer-id-p12: { required: true }
    p12-password: { required: true }
    sparkle-private-key: { required: true }
    shipcast-token: { required: true }
    github-token: { required: true }
  runs:
    using: composite
    steps:
      - name: Install Shipcast CLI
        shell: bash
        run: brew install mafex11/tap/shipcast
      
      - name: Create temp keychain
        shell: bash
        run: |
          TEMP_PW=$(uuidgen)
          security create-keychain -p "$TEMP_PW" build.keychain
          security default-keychain -s build.keychain
          security unlock-keychain -p "$TEMP_PW" build.keychain
          security set-keychain-settings -lut 21600 build.keychain
          echo "TEMP_PW=$TEMP_PW" >> $GITHUB_ENV
      
      - name: Import Developer ID certificate
        shell: bash
        run: |
          echo "${{ inputs.developer-id-p12 }}" | base64 --decode > cert.p12
          security import cert.p12 -k build.keychain -P "${{ inputs.p12-password }}" -T /usr/bin/codesign
          security set-key-partition-list -S apple-tool:,apple: -s -k "$TEMP_PW" build.keychain
      
      - name: Run Shipcast release
        shell: bash
        env:
          APPLE_ID: ${{ inputs.apple-id }}
          APPLE_TEAM_ID: ${{ inputs.apple-team-id }}
          APPLE_APP_PASSWORD: ${{ inputs.apple-password }}
          SPARKLE_PRIVATE_KEY: ${{ inputs.sparkle-private-key }}
          SHIPCAST_TOKEN: ${{ inputs.shipcast-token }}
          GITHUB_TOKEN: ${{ inputs.github-token }}
        run: shipcast release
      
      - name: Cleanup
        if: always()
        shell: bash
        run: |
          security delete-keychain build.keychain || true
          rm -f cert.p12
  ```
- [ ] Write test workflow `.github/workflows/test-action.yml`:
  ```yaml
  name: Test Action
  on: [push]
  jobs:
    test:
      runs-on: macos-latest
      steps:
        - uses: actions/checkout@v4
        - uses: ./action
          with:
            apple-id: test@example.com
            apple-team-id: TEST123456
            apple-password: test-password
            developer-id-p12: ${{ secrets.DEVELOPER_ID_P12 }}
            p12-password: ${{ secrets.P12_PASSWORD }}
            sparkle-private-key: test-key
            shipcast-token: test-token
            github-token: ${{ secrets.GITHUB_TOKEN }}
  ```
- [ ] Test: Push to GitHub → workflow runs → expect "Install Shipcast CLI" step succeeds (even if release fails due to test creds)
- [ ] Commit: "Add GitHub Action composite action and test workflow"

---

### Task 12: Documentation + Vercel deploy checklist

**Files:**
- `/Users/mafex/code/personal/ShipCast/docs/getting-started.md`
- `/Users/mafex/code/personal/ShipCast/docs/signing-guide.md`
- `/Users/mafex/code/personal/ShipCast/docs/github-action.md`
- `/Users/mafex/code/personal/ShipCast/docs/deployment-checklist.md`

**Interfaces:**
- **Consumes:** Spec sections (CLI commands, signing paths, action usage)
- **Produces:** User-facing documentation

**Steps:**
- [ ] Write `docs/getting-started.md`:
  - Install: `brew install mafex11/tap/shipcast`
  - Initialize: `shipcast init` (detects project type, creates shipcast.toml)
  - First release: `shipcast release` (walks through ad-hoc vs notarized path)
  - Link to signing-guide.md for notarization setup
- [ ] Write `docs/signing-guide.md`:
  - Ad-hoc signing: what it is, when to use, Gatekeeper implications, cask postflight strategy
  - Notarized signing: Developer ID cert setup, App-Specific Password creation, notarytool flow
  - Sparkle ed25519 key generation: `generate_keys` tool usage, embedding public key in Info.plist
  - Common errors: "code signature invalid" (resources added after signing), "notarization rejected" (hardened runtime not set), "damaged and can't be opened" (quarantine bit on ad-hoc)
- [ ] Write `docs/github-action.md`:
  - Action usage example (copy from spec §GitHub Action)
  - Required secrets table (APPLE_ID, APPLE_TEAM_ID, etc. with "How to get" column)
  - P12 export from Keychain steps: export cert → base64 encode → add to GitHub secrets
  - Trigger on tag push pattern
- [ ] Write `docs/deployment-checklist.md`:
  - Vercel setup: `npm install -g vercel && vercel login`
  - Import project: `vercel link`
  - Set env vars: `vercel env add DATABASE_URL`, `NEXTAUTH_SECRET`, `GITHUB_ID`, `GITHUB_SECRET`, `CRON_SECRET`
  - Deploy: `vercel --prod`
  - Cloudflare DNS: CNAME `shipcast.devmafex.com` → `cname.vercel-dns.com`
  - Neon setup: create project at neon.tech, copy connection string to DATABASE_URL
  - Run migrations: `npx prisma migrate deploy` (in Vercel project settings → "Command and Output Settings")
- [ ] Test: Follow getting-started.md with a fixture app → verify each command works
- [ ] Commit: "Add documentation for getting started, signing, action, and deployment"

---

## Success Criteria

- [ ] `npm run dev` in cloud/ starts Next.js app, visits to / show landing page
- [ ] Seed database has User with `apiToken: "test-token-12345"` and App `test-app` with 2 releases
- [ ] `curl http://localhost:3000/u/testuser/test-app/appcast.xml` returns valid Sparkle RSS XML with 2 `<item>` entries ordered newest-first
- [ ] `curl -X POST http://localhost:3000/api/v1/apps/test-app/releases -H "Authorization: Bearer test-token-12345" -d '{...}' → 201 with release id
- [ ] Duplicate POST (same version/channel) → 409 Conflict
- [ ] Invalid token → 401 Unauthorized
- [ ] App not found → 404 Not Found
- [ ] App belongs to different user → 403 Forbidden
- [ ] FetchEvent logged on appcast fetch (check `npx prisma studio`)
- [ ] Daily rollup cron creates FetchDaily row and deletes old FetchEvents (manual trigger via curl with CRON_SECRET header)
- [ ] GitHub OAuth sign-in → dashboard shows apps list
- [ ] Click app → see release table and adoption chart (mock data from seed)
- [ ] Playwright test passes: POST release → GET appcast → parse XML → assert enclosure with sparkle:edSignature present
- [ ] GitHub Action test workflow runs (even if release fails due to test creds, keychain steps succeed)
- [ ] Docs exist and are readable: getting-started.md, signing-guide.md, github-action.md, deployment-checklist.md
- [ ] Vercel deployment checklist in deployment-checklist.md covers: env vars, Neon setup, Cloudflare CNAME, migration deploy command
- [ ] All commits follow convention: descriptive messages, one logical change per commit

---

## Notes

- **Testing strategy:** Vitest for pure functions (appcast.ts) and API route mocking. Playwright for E2E (POST → GET → XML parse). Manual smoke test with seed data via `npm run dev`.
- **Golden files:** appcast.test.ts should include a golden XML file for regression testing against Sparkle format changes.
- **Error handling in appcast route:** FetchEvent insert is fire-and-forget (try/catch, log but don't block response). If insert fails, appcast still returns 200.
- **Prisma raw queries:** FetchDaily rollup uses `prisma.$executeRaw` for the SQL verbatim from spec. Use parameterized queries to prevent injection.
- **shadcn/ui components:** Use Card, Button, Table from shadcn. Adoption chart uses recharts LineChart with version-colored lines.
- **NextAuth v5:** Use `next-auth@beta` (v5) for App Router compatibility. Session callback attaches githubLogin to session for User lookup.
- **Vercel cron:** vercel.json `crons` array schedules `/api/cron/rollup` daily at 1 AM UTC. Route verifies CRON_SECRET header (env var) to prevent unauthorized calls.
- **Action cleanup:** `if: always()` on cleanup step ensures keychain deletion even if release fails.
- **Action ad-hoc path test:** Test workflow uses ad-hoc signing (no real Developer ID secrets in repo). Manual test with real secrets happens in floatX release.
- **Documentation links:** getting-started.md links to signing-guide.md and github-action.md. All docs reference spec examples.
- **Deployment:** Task 12 produces deployment-checklist.md but does NOT deploy. Deployment happens after Plan C execution completes and floatX dogfoods the action.
