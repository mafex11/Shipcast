# Shipcast — Design Spec

**Date:** 2026-07-01  
**Status:** Approved  
**Author:** Sudhanshu Pandit

---

## Overview & Positioning

Shipcast is a Mac app distribution platform that eliminates the release pipeline hell indie developers face. The pitch: "Push a tag. Get a signed, notarized, auto-updating, brew-installable Mac app. Your certs never leave your machine."

**Market gap:** Microsoft App Center's Sparkle hosting shut down with no commercial replacement. The space is DIY bash scripts and S3 recipes. Existing solutions require deep macOS code-signing expertise, Gatekeeper workarounds, notarization debugging, and Sparkle feed management. Shipcast packages this rare knowledge into a single CLI and optional hosted service.

**Target buyer:** Indie Mac developers already paying Apple $99/yr, plus the 2026 wave of AI-generated Swift apps from developers who can build features but cannot ship them. Shipping is the un-generatable part.

**Business model:** Free MIT-licensed CLI for the full pipeline. Paid tier adds hosted appcast URLs and update-adoption analytics. Free during beta (no billing at launch). Post-beta pricing anchors near $9/mo per app, under the Apple Developer Program $99/yr ≈ $8.25/mo mental anchor.

**Hard constraint:** $0 fixed infrastructure cost. Free tiers only (Vercel, Neon Postgres, Cloudflare DNS). Revenue scales with users, costs don't.

---

## Decision Record

These decisions are locked for v1:

1. **Primary goal:** Real business with $0 fixed infrastructure cost
2. **Domain:** shipcast.devmafex.com (subdomain of devmafex.com; Cloudflare DNS CNAME to Vercel)
3. **v1 scope:** SwiftPM + Xcode projects only. Explicitly NOT Electron/Tauri/Rust bundles in v1
4. **Free/paid split:** CLI is entirely free/MIT (build, sign, notarize, DMG, GitHub release, cask PR, appcast XML generation, self-hosting). Paid tier = hosted appcast URL + analytics dashboard
5. **Beta strategy:** Free during beta. No billing at launch. Collect emails, talk to every user. Lemon Squeezy integration deferred
6. **Credentials:** Shipcast NEVER touches customer Apple credentials. Signing/notarization always run on customer machine or their GitHub Actions with their secrets. Service only receives public release metadata
7. **CLI language:** Swift (ArgumentParser, single static binary)
8. **Hosted architecture:** Single Next.js App Router project on Vercel serves landing + dashboard + API + appcast XML. Neon Postgres free tier + Prisma. GitHub OAuth via NextAuth
9. **Signing paths:** Both notarized (Developer ID + notarytool + staple) AND ad-hoc (quarantine-strip casks + TCC-reset postflight) in v1
10. **GitHub Action:** Thin composite action wrapping the CLI included in v1
11. **Post-beta pricing:** Anchor near $9/mo per app (under Apple $99/yr), annual option. Not finalized; beta learnings decide

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     CUSTOMER MACHINE                         │
│                                                              │
│  ┌──────────────┐         ┌─────────────────────┐          │
│  │ shipcast CLI │────────▶│  Xcode / SwiftPM    │          │
│  │              │         │  (build .app)       │          │
│  └──────┬───────┘         └─────────────────────┘          │
│         │                                                    │
│         ├─▶ codesign (Developer ID or ad-hoc)              │
│         ├─▶ notarytool (if Developer ID)                   │
│         ├─▶ ditto zip / create-dmg                         │
│         ├─▶ sparkle ed25519 sign                           │
│         ├─▶ gh release create (upload to GitHub Releases)  │
│         ├─▶ gh pr create (homebrew cask)                   │
│         └─▶ POST /api/v1/apps/:app/releases (optional)     │
│                              │                               │
└──────────────────────────────┼───────────────────────────────┘
                               │
                               ▼
              ┌────────────────────────────────┐
              │   SHIPCAST CLOUD (Vercel)      │
              │   shipcast.devmafex.com        │
              │                                │
              │  Next.js App Router            │
              │  ┌──────────────────────────┐  │
              │  │ Landing Page             │  │
              │  │ Dashboard (GitHub OAuth) │  │
              │  │ POST /api/v1/.../releases│  │
              │  │ GET /u/:user/:app/       │  │
              │  │     appcast.xml          │  │
              │  └──────────┬───────────────┘  │
              │             │                   │
              │             ▼                   │
              │  ┌──────────────────────────┐  │
              │  │ Neon Postgres (free)     │  │
              │  │ User, App, Release,      │  │
              │  │ FetchEvent, FetchDaily   │  │
              │  └──────────────────────────┘  │
              └────────────────────────────────┘
                               │
                               │ (Sparkle checks daily)
                               ▼
                    ┌──────────────────────┐
                    │  End User Mac Apps   │
                    │  (SUUpdater checks   │
                    │   appcast.xml)       │
                    └──────────────────────┘
```

**Trust boundary:** Customer signs/notarizes on their hardware. Shipcast Cloud stores only public metadata (URLs, hashes, ed25519 signatures, release notes). A breach cannot compromise any customer's app. Kill-switch bounded: if Shipcast dies, `shipcast release --feed self:<url>` regenerates identical appcast for self-hosting.

---

## CLI Specification

### Commands

```
shipcast init       # Interactive setup: detects SwiftPM/Xcode, writes shipcast.toml
shipcast build      # Build .app (swift build or xcodebuild archive/export + icon gen)
shipcast sign       # Sign: ad-hoc OR Developer ID + notarytool + staple (auto-detected)
shipcast package    # Package: .zip (ditto --sequesterRsrc) and/or DMG (create-dmg)
shipcast release    # Full pipeline: build+sign+package + GitHub release + cask PR + appcast
shipcast push       # POST release metadata to Shipcast Cloud (optional, requires --token)
shipcast doctor     # Diagnose Gatekeeper/TCC/signing failures
```

**The money command:** `shipcast release` runs the full pipeline. Other commands are its stages, runnable independently for debugging or custom workflows.

### Configuration: shipcast.toml

```toml
[app]
name = "Burnt"
bundle_id = "dev.mafex.burnt"
version = "auto"                # auto (from git tag) | explicit version string
project = "auto"                # auto | swiftpm | xcode:MyApp.xcodeproj/MyScheme

[sign]
mode = "auto"                   # auto | adhoc | developer-id
# Credentials come from environment variables or Keychain, NEVER from this file

[distribute]
github_release = true
github_repo = "mafex11/burnt"   # owner/repo
homebrew_tap = "mafex11/homebrew-tap"
formats = ["zip", "dmg"]        # zip required for Sparkle; dmg optional

[updates]
sparkle = true
feed = "hosted"                 # hosted (Shipcast Cloud) | self:<url> | none
# ed25519 key from env var SPARKLE_PRIVATE_KEY

[permissions]
# TCC services the app needs (drives ad-hoc cask postflight)
# accessibility = true
# screen_recording = true
# full_disk_access = true
```

### Exit Codes

- `0` — Success
- `1` — Generic failure
- `2` — Configuration error (invalid shipcast.toml, missing required fields)
- `3` — Signing failure (codesign error, certificate not found, broken seal)
- `4` — Notarization rejected by Apple (binary issue, entitlements problem)
- `5` — Publish failure (GitHub API error, cask PR failed)

### Error Handling Philosophy

Every failure prints:
1. The failing command/operation
2. Why it likely failed (common causes)
3. The fix (actionable next step)

Example:
```
Error: Code signing failed
Command: codesign --sign "Developer ID Application: ..." --options runtime MyApp.app
Reason: Certificate not found in keychain
Fix: Import your Developer ID certificate:
      1. Download cert from Apple Developer portal
      2. Double-click .cer file to import to Keychain
      3. Run: security find-identity -v -p codesigning
```

This is doctor-style output for every error, not just `shipcast doctor`. The goal: no 2am Googling.

---

## Signing Engine

The hard-won knowledge extracted from burnt, Yuki, floatX pipelines.

### Auto-Detection Logic

```
IF Developer ID cert in Keychain
   AND APPLE_ID env var set
   AND APPLE_TEAM_ID env var set
   AND APPLE_APP_PASSWORD env var set
THEN
   → Notarized path
ELSE
   → Ad-hoc path
```

Query Keychain: `security find-identity -v -p codesigning | grep "Developer ID Application"`

### Notarized Path

1. **Deep sign with runtime hardening:**
   ```bash
   codesign --force --deep \
            --sign "Developer ID Application: Sudhanshu Pandit (TEAM_ID)" \
            --options runtime \
            --timestamp \
            MyApp.app
   ```

2. **Verify signature:**
   ```bash
   codesign --verify --deep --strict MyApp.app
   spctl -a -t exec -vv MyApp.app
   ```

3. **Create distributable zip:**
   ```bash
   ditto -c -k --sequesterRsrc --keepParent MyApp.app MyApp.zip
   ```
   (Preserves code signature and extended attributes)

4. **Submit for notarization:**
   ```bash
   xcrun notarytool submit MyApp.zip \
         --apple-id "$APPLE_ID" \
         --team-id "$APPLE_TEAM_ID" \
         --password "$APPLE_APP_PASSWORD" \
         --wait
   ```

5. **Staple notarization ticket:**
   ```bash
   xcrun stapler staple MyApp.app
   xcrun stapler validate MyApp.app
   ```

6. **Re-zip stapled app:**
   ```bash
   ditto -c -k --sequesterRsrc --keepParent MyApp.app MyApp-stapled.zip
   ```

### Ad-Hoc Path

Critical for $0 hobbyist distribution. Knowledge from Yuki/burnt.

1. **Build must produce linker signature:**
   Swift build does this automatically. Xcode archives do too.

2. **Add any resources BEFORE final signing:**
   Adding files after signing breaks the code seal. This is the #1 cause of TCC grant revocation on macOS.

3. **Deep ad-hoc sign as FINAL step:**
   ```bash
   codesign --force --deep --sign - MyApp.app
   ```

4. **Verify:**
   ```bash
   codesign --verify --deep --strict MyApp.app
   # Ad-hoc signature will show: signed: yes, but no Developer ID
   ```

5. **Zip:**
   ```bash
   ditto -c -k --sequesterRsrc --keepParent MyApp.app MyApp.zip
   ```

### Ad-Hoc Cask Postflight

Ad-hoc signed apps get quarantine bit from downloads, triggering "damaged and can't be opened" Gatekeeper rejection.

Generated cask includes:
```ruby
postflight do
  # Strip quarantine (allows first launch)
  system_command "/usr/bin/xattr",
                 args: ["-dr", "com.apple.quarantine", "#{appdir}/MyApp.app"]

  # Reset TCC for declared permissions
  # (Ad-hoc rebuilds change cdhash, orphaning old TCC grants)
  system_command "/usr/bin/tccutil",
                 args: ["reset", "Accessibility", "dev.mafex.myapp"]
  system_command "/usr/bin/tccutil",
                 args: ["reset", "ScreenCapture", "dev.mafex.myapp"]
end
```

The TCC reset ensures first-launch permission prompts appear cleanly after updates. Without this, macOS shows no prompt (old cdhash grant orphaned) but silently denies access, appearing as a broken app.

### Sparkle ed25519 Signing

Both signing paths require Sparkle signature for update integrity.

1. **Generate key pair (once per app):**
   ```bash
   # Using Sparkle's generate_keys tool
   ./generate_keys
   # Outputs: public key (embed in Info.plist) + private key (secret)
   ```

2. **Sign release artifact:**
   ```bash
   ./sign_update MyApp.zip
   # Outputs: ed25519 signature string
   ```

3. **Embed in appcast:**
   ```xml
   <enclosure url="..." sparkle:edSignature="..." />
   ```

4. **Embed public key in Info.plist:**
   ```xml
   <key>SUPublicEDKey</key>
   <string>base64-encoded-public-key</string>
   ```

Private key stored in `SPARKLE_PRIVATE_KEY` env var or customer's CI secrets. NEVER in shipcast.toml or committed to git.

### Icon Generation

From 1024px master PNG (required in project root as `icon.png`):

1. **Create iconset structure:**
   ```bash
   mkdir MyApp.iconset
   sips -z 16 16     icon.png --out MyApp.iconset/icon_16x16.png
   sips -z 32 32     icon.png --out MyApp.iconset/icon_16x16@2x.png
   sips -z 32 32     icon.png --out MyApp.iconset/icon_32x32.png
   sips -z 64 64     icon.png --out MyApp.iconset/icon_32x32@2x.png
   sips -z 128 128   icon.png --out MyApp.iconset/icon_128x128.png
   sips -z 256 256   icon.png --out MyApp.iconset/icon_128x128@2x.png
   sips -z 256 256   icon.png --out MyApp.iconset/icon_256x256.png
   sips -z 512 512   icon.png --out MyApp.iconset/icon_256x256@2x.png
   sips -z 512 512   icon.png --out MyApp.iconset/icon_512x512.png
   sips -z 1024 1024 icon.png --out MyApp.iconset/icon_512x512@2x.png
   ```

2. **Compile to .icns:**
   ```bash
   iconutil -c icns MyApp.iconset
   # Outputs: MyApp.icns
   ```

3. **Embed in .app bundle:**
   Copy to `MyApp.app/Contents/Resources/AppIcon.icns` and set in Info.plist `CFBundleIconFile`.

### DMG Creation

Using `create-dmg` (install via Homebrew):

```bash
create-dmg \
  --volname "MyApp Installer" \
  --volicon "MyApp.icns" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "MyApp.app" 200 190 \
  --hide-extension "MyApp.app" \
  --app-drop-link 600 185 \
  "MyApp-1.0.0.dmg" \
  "MyApp.app"
```

DMG is optional (for users who prefer drag-to-Applications vs Homebrew). Sparkle updates use the .zip artifact.

---

## Cask Publishing

Generated cask follows mafex11/homebrew-tap patterns.

### Template

```ruby
cask "myapp" do
  version "1.0.0"
  sha256 "abc123..."

  url "https://github.com/mafex11/myapp/releases/download/v#{version}/MyApp.zip"
  name "MyApp"
  desc "Short description of MyApp"
  homepage "https://github.com/mafex11/myapp"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "MyApp.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/MyApp.app"]
    
    # TCC resets only for ad-hoc signed apps with declared permissions
    system_command "/usr/bin/tccutil",
                   args: ["reset", "Accessibility", "dev.mafex.myapp"]
  end

  uninstall quit: "dev.mafex.myapp"

  zap trash: [
    "~/Library/Preferences/dev.mafex.myapp.plist",
    "~/Library/Application Support/MyApp",
    "~/Library/Caches/dev.mafex.myapp",
  ]
end
```

### Publishing Flow

1. **Compute artifact SHA256:**
   ```bash
   shasum -a 256 MyApp.zip
   ```

2. **Generate cask file** from template, substituting:
   - `version`
   - `sha256`
   - `url` (GitHub Release asset)
   - `bundle_id` (for TCC commands)
   - `permissions` (from shipcast.toml → tccutil reset calls)
   - `zap trash` paths (conventional locations)

3. **Publish:**
   - If user owns the tap repo: direct `git commit && git push`
   - Otherwise: `gh pr create --repo <tap-repo> --title "Add myapp 1.0.0"`

Command: `gh pr create` or direct commit via git commands, depending on repo permissions.

---

## shipcast doctor

The 2am diagnostic command. Runs a gauntlet of checks and prints failures with actionable fixes.

### Checks

1. **App bundle structure:**
   - `MyApp.app/Contents/Info.plist` exists
   - `CFBundleIdentifier` present
   - `CFBundleExecutable` present and executable file exists

2. **Code signature validity:**
   ```bash
   codesign --verify --deep --strict MyApp.app
   # Exit 0 = valid signature
   ```

3. **Gatekeeper assessment:**
   ```bash
   spctl -a -t exec -vv MyApp.app
   # "accepted" = will launch without Gatekeeper rejection
   ```

4. **Quarantine status:**
   ```bash
   xattr -l MyApp.app | grep com.apple.quarantine
   # Present = downloaded, needs clearing for ad-hoc
   ```

5. **Notarization staple (if Developer ID signed):**
   ```bash
   xcrun stapler validate MyApp.app
   # "validated" = notarization ticket attached
   ```

6. **TCC grants for declared permissions:**
   ```bash
   # Read system TCC database (requires sudo or SIP disabled for testing)
   sqlite3 /Library/Application\ Support/com.apple.TCC/TCC.db \
     "SELECT service, allowed FROM access WHERE client='dev.mafex.myapp'"
   ```
   Note: In production, this check only reports expected grants from shipcast.toml `[permissions]`. Actual verification requires user to test the app.

7. **Sparkle configuration (if enabled):**
   - `SUFeedURL` in Info.plist
   - `SUPublicEDKey` in Info.plist
   - Feed URL reachable (HTTP GET returns 200)
   - Appcast XML parses
   - Latest enclosure ed25519 signature verifies against public key

### Output Format

```
✓ App bundle structure valid
✓ Code signature valid (ad-hoc)
✗ Gatekeeper assessment failed
  Reason: com.apple.quarantine attribute present
  Fix: xattr -dr com.apple.quarantine MyApp.app
✓ No notarization required (ad-hoc signed)
! TCC permissions not granted yet
  Expected: Accessibility, ScreenCapture
  Status: Not granted (first launch will prompt)
✓ Sparkle feed reachable
✓ Appcast XML valid
✓ Ed25519 signature valid

Summary: 1 error, 1 warning. Run fix commands above.
```

Every failure includes the exact command to fix it. This is the SEO moat: people googling "app damaged and can't be opened" find Shipcast blog posts saying "run `shipcast doctor`".

---

## Shipcast Cloud

Single Next.js App Router project on Vercel. Cloudflare DNS CNAMEs `shipcast.devmafex.com` to Vercel.

### Tech Stack

- **Framework:** Next.js 14+ (App Router)
- **Hosting:** Vercel (free tier: 100 GB-hours/mo serverless, 100 GB bandwidth, unlimited edge requests)
- **Database:** Neon Postgres (free tier: 1 project, 10 GB storage, 100 hours compute/mo)
- **ORM:** Prisma
- **Auth:** NextAuth.js with GitHub OAuth provider
- **Styling:** Tailwind CSS + shadcn/ui components

### Routes

#### `GET /u/:user/:app/appcast.xml`

**THE product.** Renders Sparkle RSS XML from database Release rows.

- **Caching:** Edge-cached 5 minutes (Vercel `revalidate: 300`)
- **Logging:** Fire-and-forget insert into FetchEvent table (app_id, version, timestamp, coarse user-agent)
- **Response:**
  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
      <title>MyApp Updates</title>
      <description>Release feed for MyApp</description>
      <language>en</language>
      <item>
        <title>Version 1.0.0</title>
        <sparkle:version>1.0.0</sparkle:version>
        <pubDate>Mon, 01 Jul 2026 12:00:00 +0000</pubDate>
        <sparkle:releaseNotesLink>https://...</sparkle:releaseNotesLink>
        <enclosure url="https://github.com/.../MyApp.zip"
                   length="12345678"
                   type="application/octet-stream"
                   sparkle:edSignature="..." />
        <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
      </item>
    </channel>
  </rss>
  ```

Sparkle checks daily per install. Free tier bandwidth is ample: 1 KB appcast × 10,000 active installs × 30 days = 300 MB/mo.

#### `POST /api/v1/apps/:app/releases`

What `shipcast push` calls.

- **Auth:** Bearer token (per-user API token in `Authorization: Bearer <token>`)
- **Body:**
  ```json
  {
    "version": "1.0.0",
    "artifact_url": "https://github.com/mafex11/myapp/releases/download/v1.0.0/MyApp.zip",
    "sha256": "abc123...",
    "ed_signature": "base64-encoded-signature",
    "length": 12345678,
    "min_system_version": "14.0",
    "release_notes_html": "<p>Fixed bugs</p>",
    "channel": "stable"
  }
  ```
- **Validation:**
  - App belongs to authenticated user
  - Version not already published
  - URL reachable (optional pre-check)
- **Response:** `201 Created` with release ID

#### `GET /` — Landing Page

Marketing site:
- Headline: "Push a tag. Ship a Mac app."
- Demo GIF: terminal showing `git tag v1.0.0 && git push --tags` → GitHub Action running → cask PR created
- Feature grid: Free CLI, Hosted updates, Ad-hoc signing, Auto casks
- Pricing table: Free beta, $9/mo post-beta
- CTA: "brew install mafex11/tap/shipcast"

#### `GET /dashboard` — Dashboard

GitHub OAuth required.

- **Apps list:** All apps owned by user, with latest version and install count estimate
- **Per-app view:** `/dashboard/:app`
  - Releases table (version, date, downloads, status)
  - Adoption curve chart (fetches by version over time)
  - Install base estimate: daily appcast fetch count (Sparkle checks ~once daily per install, so daily fetches ≈ active installs)
  - Appcast URL: `https://shipcast.devmafex.com/u/:user/:app/appcast.xml` (copy button)

### Prisma Schema

```prisma
model User {
  id            String   @id @default(cuid())
  githubId      Int      @unique
  githubLogin   String
  email         String?
  apiToken      String   @unique @default(cuid())
  createdAt     DateTime @default(now())
  apps          App[]
}

model App {
  id            String   @id @default(cuid())
  slug          String   // URL-safe name (e.g., "burnt")
  name          String   // Display name (e.g., "Burnt")
  userId        String
  user          User     @relation(fields: [userId], references: [id])
  createdAt     DateTime @default(now())
  releases      Release[]
  fetchEvents   FetchEvent[]
  fetchDailies  FetchDaily[]

  @@unique([userId, slug])
}

model Release {
  id                  String   @id @default(cuid())
  appId               String
  app                 App      @relation(fields: [appId], references: [id])
  version             String
  artifactUrl         String
  sha256              String
  edSignature         String
  length              Int
  minSystemVersion    String?
  releaseNotesHtml    String?
  channel             String   @default("stable") // stable | beta
  publishedAt         DateTime @default(now())

  @@unique([appId, version, channel])
  @@index([appId, publishedAt])
}

model FetchEvent {
  id          String   @id @default(cuid())
  appId       String
  app         App      @relation(fields: [appId], references: [id])
  version     String?  // Version user is checking from (from User-Agent)
  timestamp   DateTime @default(now())
  uaCoarse    String?  // Coarse user-agent (macOS version only)

  @@index([appId, timestamp])
}

model FetchDaily {
  id          String   @id @default(cuid())
  appId       String
  app         App      @relation(fields: [appId], references: [id])
  date        DateTime @db.Date
  version     String
  fetchCount  Int      @default(0)

  @@unique([appId, date, version])
  @@index([appId, date])
}
```

**Free-tier row limit strategy:** FetchEvent is unbounded. Daily cron aggregates FetchEvents into FetchDaily rollups and deletes raw events older than 7 days. This keeps row count manageable: 10 apps × 365 days × 5 versions = ~18k rows/year, well under Neon free tier.

### Analytics Implementation

Daily cron (Vercel Cron or GitHub Action calling API endpoint):
```sql
INSERT INTO FetchDaily (appId, date, version, fetchCount)
SELECT appId, DATE(timestamp), version, COUNT(*)
FROM FetchEvent
WHERE timestamp >= CURRENT_DATE - INTERVAL '1 day'
  AND timestamp < CURRENT_DATE
GROUP BY appId, DATE(timestamp), version
ON CONFLICT (appId, date, version)
DO UPDATE SET fetchCount = FetchDaily.fetchCount + EXCLUDED.fetchCount;

DELETE FROM FetchEvent WHERE timestamp < CURRENT_DATE - INTERVAL '7 days';
```

Dashboard queries FetchDaily for historical trends, FetchEvent for live (last 7 days).

Install base estimate: average of `fetchCount` per day over the last 7 days from FetchDaily. Sparkle checks approximately once daily per install, so daily fetches ≈ active installs. Not precise (no per-device identifier is stored — by design), but directionally useful for trend lines.

---

## GitHub Action

Composite action at `shipcast/action@v1` wrapping the CLI.

### Usage

```yaml
name: Release
on:
  push:
    tags:
      - 'v*'

jobs:
  release:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v4
      
      - uses: shipcast/action@v1
        with:
          apple-id: ${{ secrets.APPLE_ID }}
          apple-team-id: ${{ secrets.APPLE_TEAM_ID }}
          apple-password: ${{ secrets.APPLE_APP_PASSWORD }}
          developer-id-p12: ${{ secrets.DEVELOPER_ID_P12 }}
          p12-password: ${{ secrets.P12_PASSWORD }}
          sparkle-private-key: ${{ secrets.SPARKLE_PRIVATE_KEY }}
          shipcast-token: ${{ secrets.SHIPCAST_TOKEN }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Implementation

Composite action steps:

1. **Install Shipcast CLI:**
   ```bash
   brew install mafex11/tap/shipcast
   ```

2. **Import Developer ID certificate:**
   ```bash
   # Create temporary keychain
   security create-keychain -p "$TEMP_PASSWORD" build.keychain
   security default-keychain -s build.keychain
   security unlock-keychain -p "$TEMP_PASSWORD" build.keychain
   security set-keychain-settings -lut 21600 build.keychain

   # Decode base64 P12 and import
   echo "$DEVELOPER_ID_P12" | base64 --decode > cert.p12
   security import cert.p12 -k build.keychain -P "$P12_PASSWORD" -T /usr/bin/codesign

   # Allow codesign to access key without prompt
   security set-key-partition-list -S apple-tool:,apple: -s -k "$TEMP_PASSWORD" build.keychain
   ```

3. **Run release:**
   ```bash
   export APPLE_ID="${{ inputs.apple-id }}"
   export APPLE_TEAM_ID="${{ inputs.apple-team-id }}"
   export APPLE_APP_PASSWORD="${{ inputs.apple-password }}"
   export SPARKLE_PRIVATE_KEY="${{ inputs.sparkle-private-key }}"
   export SHIPCAST_TOKEN="${{ inputs.shipcast-token }}"
   export GITHUB_TOKEN="${{ inputs.github-token }}"

   shipcast release
   ```

4. **Cleanup (post step):**
   ```bash
   security delete-keychain build.keychain
   rm -f cert.p12
   ```

### Required Secrets

| Secret | Description | How to get |
|--------|-------------|-----------|
| `APPLE_ID` | Apple ID email | Your Apple Developer account email |
| `APPLE_TEAM_ID` | 10-character team ID | developer.apple.com → Membership → Team ID |
| `APPLE_APP_PASSWORD` | App-specific password | appleid.apple.com → Sign-In and Security → App-Specific Passwords |
| `DEVELOPER_ID_P12` | Base64-encoded certificate | Export from Keychain, base64 encode: `base64 -i cert.p12 \| pbcopy` |
| `P12_PASSWORD` | Certificate export password | Password you set when exporting from Keychain |
| `SPARKLE_PRIVATE_KEY` | Ed25519 private key | From `generate_keys` tool (first release only) |
| `SHIPCAST_TOKEN` | API token | Dashboard → Settings → API Tokens |
| `GITHUB_TOKEN` | GitHub PAT | Provided automatically by GitHub Actions |

---

## Repository Layout

```
ShipCast/
  Sources/
    ShipcastCLI/          # ArgumentParser command layer
      Init.swift
      Build.swift
      Sign.swift
      PackageCommand.swift   # named to avoid clash with SwiftPM manifest
      Release.swift
      Push.swift
      Doctor.swift
      main.swift
    ShipcastKit/          # Core engine (UI-free, fully tested)
      Build/
        SwiftPMBuilder.swift
        XcodeBuilder.swift
        IconGenerator.swift
        InfoPlistGenerator.swift
      Sign/
        Signer.swift          # Auto-detection + routing
        AdHocSigner.swift
        DeveloperIDSigner.swift
        Notarizer.swift
      Package/
        Zipper.swift
        DMGCreator.swift
      Publish/
        GitHubReleaser.swift
        CaskGenerator.swift
        CaskPublisher.swift
        AppcastGenerator.swift
      Push/
        CloudClient.swift
      Doctor/
        Diagnostics.swift
      Models/
        Config.swift          # shipcast.toml parsing
        BuildArtifact.swift
        Release.swift
  Tests/
    ShipcastKitTests/
      Fixtures/
        MiniSwiftPM/         # Minimal SwiftPM app for testing
        MiniXcode/           # Minimal Xcode project for testing
      BuildTests.swift
      SignTests.swift       # Sign → verify round-trips
      CaskTests.swift       # Golden file tests
      AppcastTests.swift    # XML generation + Sparkle validation
      DoctorTests.swift     # Deliberate breakage tests
  action/
    action.yml            # Composite GitHub Action definition
  cloud/
    app/                  # Next.js App Router
      (auth)/
        dashboard/
          page.tsx
          [app]/
            page.tsx      # Per-app analytics
      api/
        v1/
          apps/
            [app]/
              releases/
                route.ts  # POST handler
      u/
        [user]/
          [app]/
            appcast.xml/
              route.ts    # GET handler (RSS XML)
      page.tsx            # Landing page
      layout.tsx
    components/
      AppcastViewer.tsx
      ReleaseTable.tsx
      AdoptionChart.tsx
    lib/
      prisma.ts
      auth.ts
    prisma/
      schema.prisma
    public/
      demo.gif
    package.json
    next.config.js
    tailwind.config.js
  docs/
    2026-07-01-shipcast-design.md  # This document
    getting-started.md
    signing-guide.md
    github-action.md
  Package.swift           # Swift package manifest
  README.md
  LICENSE                 # MIT
```

---

## Testing Strategy

### ShipcastKit Unit Tests

All engine code is UI-free and fully unit tested.

**Build tests:**
- Fixture apps (MiniSwiftPM, MiniXcode) build successfully
- Icon generation produces valid .icns
- Info.plist generated with correct keys

**Sign tests:**
- Ad-hoc sign → `codesign --verify` passes
- (Developer ID requires real Apple ID; tested in CI with secrets)
- Signing broken bundles produces expected errors

**Cask tests:**
- Golden file tests: generate cask for fixture app, compare against expected .rb
- Ad-hoc vs notarized paths produce correct postflight blocks
- TCC permissions array correctly translates to tccutil reset commands

**Appcast tests:**
- XML generation produces valid Sparkle RSS
- Ed25519 signature validates against public key
- Multiple releases in correct reverse-chronological order

**Doctor tests:**
- Unsigned bundle → reports signing failure with fix
- Quarantined bundle → reports quarantine with xattr fix command
- Missing Info.plist key → reports configuration error

### Integration Tests

**Notarization:** Dry-run mode for CI. One real end-to-end with Sudhanshu's Apple ID pre-launch.

**Cloud:** Playwright smoke test: push release via API → fetch appcast.xml → parse XML → verify enclosure URL and signature present.

### Acceptance Gate

Before any public launch, **burnt**, **Yuki**, and **floatX** each release through Shipcast. This validates:
- SwiftPM and Xcode projects both work
- Ad-hoc and notarized paths both work
- Homebrew casks install and launch cleanly
- Sparkle updates work end-to-end

---

## Milestones (6 weeks)

### Week 1-2: Core CLI + SwiftPM
- Implement ShipcastKit: Build (SwiftPM), Sign (ad-hoc + Developer ID), Package (zip, DMG)
- CLI commands: init, build, sign, package
- Icon generation, Info.plist embedding
- Unit tests for Build, Sign, Package
- **Deliverable:** burnt releases with `shipcast release --feed none` (local only, no cloud)

### Week 3: Release + Xcode + Doctor
- Implement Release pipeline: GitHub Release creation, cask generation + publishing
- Xcode project support (xcodebuild archive/export)
- Appcast XML generation (Sparkle RSS + ed25519 signing)
- Doctor command v1: signature, Gatekeeper, quarantine, TCC checks
- **Deliverable:** burnt updates cask via Shipcast, Yuki builds with Shipcast

### Week 4: Cloud MVP
- Next.js app: landing page, GitHub OAuth, dashboard skeleton
- API: POST /api/v1/apps/:app/releases, GET /u/:user/:app/appcast.xml
- Prisma schema + Neon Postgres setup
- FetchEvent logging (fire-and-forget)
- **Deliverable:** Yuki on hosted Sparkle feed, updates working end-to-end

### Week 5: GitHub Action + Docs
- Composite action: cert import, shipcast install, cleanup
- Docs: getting-started.md, signing-guide.md, github-action.md
- Demo GIF: terminal + CI logs + cask PR
- **Deliverable:** floatX releases via GitHub Action

### Week 6: Polish + Launch
- Doctor hardening: better error messages, more checks
- Dashboard polish: adoption charts, release table UX
- Landing page copywriting
- Launch sequence:
  1. Sparkle Project discussions (App Center shutdown → Shipcast as solution)
  2. r/swift: "I built a Mac app release pipeline"
  3. Show HN: "Shipcast – Push a tag, ship a Mac app"
  4. X thread with demo GIF
- Beta users: free, collect emails, talk to everyone

---

## Out of Scope for v1

Explicitly deferred to v2+:

- **Electron/Tauri/Rust bundles:** Different build systems, different signing patterns. v1 is SwiftPM/Xcode only
- **Delta updates:** Sparkle supports binary diffs; Shipcast v1 ships full zips only
- **PKG installers:** .app bundles only in v1
- **Mac App Store:** Different signing (Mac App Distribution), sandboxing requirements, App Store Connect API complexity
- **Team seats:** v1 is single-user accounts. Multi-user orgs in v2
- **Windows:** Mac-only distribution in v1
- **Billing:** Free during beta. Lemon Squeezy integration post-beta based on demand

---

## Risks & Mitigations

### Solo Operator Bus Factor

**Risk:** Sudhanshu is the only person who knows the codebase and Apple toolchain nuances.

**Mitigation:**
- Document everything: this spec, inline code comments, docs/ folder
- Dogfood from day 1: burnt, Yuki, floatX all use Shipcast, so bugs surface immediately
- Open-source CLI (MIT): community can fork if needed
- Hosted service is thin (just stores public metadata): low operational complexity

### Apple Toolchain Churn

**Risk:** Apple changes notarytool, Gatekeeper policies, or TCC behavior every macOS release. Past examples: hardened runtime required for notarization (10.14), TCC reset command output format changes (12.0).

**Mitigation:**
- This is actually a moat: each breaking change makes DIY scripts harder, Shipcast more valuable
- Shipcast CLI updates fix Apple changes for all users via `brew upgrade`
- `shipcast doctor` becomes the canonical reference for "why doesn't my app launch on Sequoia"

### Free Tier Limits

**Risk:** Vercel/Neon free tiers hit limits.

**Breakdown:**
- **Neon:** 10 GB storage, 100 hours compute/mo. FetchDaily aggregation keeps row count bounded. 100 apps × 365 days × 5 versions = 182k rows ≈ 100 MB. Plenty of headroom.
- **Vercel:** 100 GB bandwidth/mo. Appcast XML is ~1 KB. 100 GB = 100M fetches/mo = 3.3M fetches/day. For context, 10k active installs checking daily = 10k fetches/day. 330x headroom.
- **Vercel compute:** 100 GB-hours/mo serverless. Appcast route is edge-cached (near-zero compute). POST /releases is rare (only on new releases). Unlikely to hit limit.

**Migration path if needed:**
- Appcast serving moves to Cloudflare Worker (free tier: 100k requests/day, more than enough)
- Database stays on Neon or migrates to Neon paid ($0.50/GB storage, ~$5/mo for 10 GB)
- Cloudflare Workers KV for FetchEvent buffering (1 GB free)

### Sparkle Project Changes

**Risk:** Sparkle appcast format changes, breaking generated XML.

**Mitigation:**
- Sparkle is mature (15+ years old), format stable
- Shipcast unit tests validate against Sparkle appcast expectations
- If Sparkle changes, Shipcast updates once, all users get fix via CLI update

### Free Beta Users Convert Poorly

**Risk:** Free-tier users don't convert to paid when billing launches.

**Mitigation:**
- Collect emails during beta (waitlist → onboard → stay in touch)
- Pricing survey: ask "what would you pay?" before setting price
- Founding user discount: "Beta users lock in $7/mo forever" (vs $9/mo regular)
- Value prop: if users ship even 1 app, they're already paying Apple $99/yr; Shipcast is <10% of that for automated releases
- Churn acceptance: 80% free users churning is fine if 20% convert to $9/mo. 100 beta users → 20 paying = $180/mo = $2160/yr revenue on $0 infrastructure cost = profitable

---

## Trust Boundary

This is the core marketing message and security posture.

**What Shipcast Cloud stores:**
- Release metadata: version, artifact URL (GitHub Releases), sha256 hash, ed25519 signature, release notes
- Public information: app name, bundle ID, GitHub repo

**What Shipcast Cloud NEVER sees:**
- Apple ID credentials
- Developer ID certificates or private keys
- Sparkle ed25519 private keys
- Source code
- .app bundle contents

**Where signing happens:**
- Customer's Mac (via `shipcast` CLI)
- Customer's GitHub Actions runner (via `shipcast/action`, with their secrets)

**Breach impact:**
- An attacker compromising Shipcast Cloud gains: release URLs, hashes, signatures (all public via GitHub Releases anyway)
- An attacker CANNOT: sign malicious updates (no private keys), push updates (ed25519 signature verification fails), access customer source code

**Kill-switch mitigation:**
- If Shipcast Cloud dies, `shipcast release --feed self:https://example.com/appcast.xml` generates identical appcast XML for self-hosting
- Sticky URL problem: SUFeedURL is baked into shipped Info.plists. Users on old versions still point to dead Shipcast Cloud URL
- Mitigation: Cloudflare redirect from `shipcast.devmafex.com/u/:user/:app/appcast.xml` to customer's self-hosted URL (one-time setup, then Shipcast is out of the loop)

**Comparison to alternatives:**
- **Sparkle self-hosting:** Same trust model (all public metadata), but you run the server
- **App Center (RIP):** Microsoft hosted everything, but also stored only public metadata
- **Paid services (none exist anymore):** Would have same trust boundary

**Why this matters:**
- Indie devs are paranoid about handing over Apple credentials (rightly so)
- "Your certs never leave your machine" is the unlock for trust
- Shipcast is infrastructure, not a code-signing service

---

## Appendix: Existing Assets Being Generalized

Shipcast extracts and generalizes release pipeline knowledge from 4 hand-rolled Mac app releases.

### burnt (SwiftPM, ad-hoc signing, menu bar app)

**Assets:**
- `packaging/make-app.sh`: SwiftPM → .app assembly, Info.plist generation, icon embedding
- `packaging/make-icon.sh`: CoreGraphics master → sips iconset ladder → iconutil .icns
- `packaging/make-release.sh`: ditto zip, sha256 computation, sed cask update
- `packaging/vendor-ccusage.sh`: Node.js runtime vendoring pattern (generalized to: embed arbitrary resources before signing)
- Ad-hoc codesign: `codesign --force --deep --sign -` as final step
- Cask: quarantine-strip postflight + auto-launch `open` postflight
- Learning: Resources added after signing break code seal → TCC grants silently revoke

**Generalized to:**
- ShipcastKit Build/SwiftPMBuilder
- ShipcastKit Sign/AdHocSigner
- ShipcastKit Package/IconGenerator
- Cask postflight: quarantine strip

### Yuki (Python, notarized signing, Sparkle updates)

**Assets:**
- `release.sh`: python-build-standalone vendoring, uv export dependencies, deep ad-hoc sign + verify
- `packaging/notarize.sh`: notarytool submit --wait, stapler staple, stapler validate
- `packaging/make_dmg.sh`: create-dmg with window layout, app-drop-link
- `sparkle/sign.sh`: Ed25519 signing wrapper
- `sparkle/appcast.xml.j2`: Jinja2 appcast template (Sparkle RSS format)
- `.github/workflows/release.yml`: Developer ID sign with --options runtime in CI, secrets pattern, softprops/action-gh-release, sed cask update
- Cask: quarantine strip + `tccutil reset Accessibility` for ad-hoc updates
- Learning: Ad-hoc rebuilds change cdhash → old TCC grants orphaned → reset needed

**Generalized to:**
- ShipcastKit Sign/DeveloperIDSigner
- ShipcastKit Sign/Notarizer
- ShipcastKit Package/DMGCreator
- ShipcastKit Publish/AppcastGenerator
- shipcast/action composite action (cert import pattern)
- Cask postflight: TCC resets

### floatX (Swift, embedded resources, LSUIElement)

**Assets:**
- `mac/build-app.sh`: Resource embedding, in-script Info.plist generation, LSUIElement menu-bar app pattern
- Learning: Info.plist key `LSUIElement=true` for menu-bar-only apps (no Dock icon)

**Generalized to:**
- ShipcastKit Build/InfoPlistGenerator (supports LSUIElement, LSBackgroundOnly, etc.)
- shipcast.toml `[app]` section: `launch_mode = "menubar" | "dock" | "background"`

### git-schedule (Rust, GitHub Actions, matrix builds)

**Assets:**
- `.github/workflows/release.yml`: Matrix builds (macOS/Linux/Windows), artifact collection, softprops/action-gh-release
- Learning: tag-triggered release workflow shape — build job matrix uploads artifacts, separate release job collects and publishes

**Generalized to:**
- shipcast/action: single-arch by default, optional matrix configuration in docs

### homebrew-tap (mafex11/homebrew-tap)

**Assets:**
- Cask patterns: postflight (quarantine, TCC, auto-launch), uninstall quit, zap trash paths
- Learning: Conventional zap paths for Preferences, Application Support, Caches

**Generalized to:**
- ShipcastKit Publish/CaskGenerator templates

---

## Conclusion

Shipcast is a real business solving a real pain (Mac app distribution is hard) with $0 fixed cost and rare moat (deep Gatekeeper/TCC/notarization knowledge). The free CLI captures mindshare; the hosted updates + analytics are the revenue layer. Beta launches free to prove demand, validate pricing, and talk to every user. Post-beta: $9/mo per app, anchored under Apple $99/yr, paid annually for retention.

Six weeks to launch. Three apps (burnt, Yuki, floatX) dogfooding from week 2. Launch to Sparkle community, r/swift, Show HN. Talk to every beta user. Revenue starts when billing launches (Lemon Squeezy integration post-beta based on conversion learnings).

The pitch stays simple: "Push a tag. Get a signed, notarized, auto-updating, brew-installable Mac app. Your certs never leave your machine."

Ship it.
