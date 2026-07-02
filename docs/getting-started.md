# Getting Started with Shipcast

Shipcast automates the entire Mac app release pipeline: build, sign, notarize, package, and distribute through GitHub Releases and Homebrew.

## Installation

Install via Homebrew:

```bash
brew install mafex11/tap/shipcast
```

Verify installation:

```bash
shipcast --version
```

## Initialize Your Project

Navigate to your Mac app project directory and run:

```bash
shipcast init
```

This will prompt you for:
- **App name**: Display name of your application
- **Bundle ID**: Reverse-DNS identifier (e.g., `com.yourname.appname`)

The command auto-detects your project type (SwiftPM or Xcode) and creates a `shipcast.toml` configuration file:

```toml
[app]
name = "MyApp"
bundle_id = "com.yourname.myapp"
version = "auto"          # Reads version from git tags
project = "auto"          # Auto-detects SwiftPM or Xcode

[sign]
mode = "auto"             # Ad-hoc or Developer ID (auto-detected)

[distribute]
github_release = true
github_repo = "yourname/myapp"
homebrew_tap = "yourname/homebrew-tap"
formats = ["zip", "dmg"]

[updates]
sparkle = true
feed = "hosted"           # Uses Shipcast Cloud for appcast hosting

[permissions]
# Uncomment TCC permissions your app needs:
# accessibility = true
# screen_recording = true
# full_disk_access = true
```

## Your First Release

### Option 1: Ad-hoc Signing (Free, No Apple Developer Account Required)

For local testing or internal distribution:

```bash
shipcast release
```

This will:
1. Build your .app bundle
2. Ad-hoc sign it (no certificate needed)
3. Package as .zip and .dmg
4. Create a GitHub Release with artifacts
5. Generate or update your Homebrew cask
6. Generate Sparkle appcast XML for auto-updates

Users install via:
```bash
brew install yourname/tap/myapp
```

**Note**: Ad-hoc signed apps trigger Gatekeeper warnings. The generated cask includes a `postflight` script that strips the quarantine attribute and resets TCC grants on updates.

### Option 2: Notarized Signing (Recommended for Public Distribution)

For Gatekeeper-approved distribution, you need:
- Apple Developer Program membership ($99/year)
- Developer ID Application certificate
- App-specific password

Set environment variables:
```bash
export APPLE_ID="your@email.com"
export APPLE_TEAM_ID="YOUR_TEAM_ID"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

Then run:
```bash
shipcast release
```

Shipcast auto-detects the Developer ID certificate in your Keychain and switches to notarized mode. This will:
1. Build and sign with Developer ID + hardened runtime
2. Submit to Apple for notarization (typically 1-5 minutes)
3. Staple the notarization ticket to your app
4. Package and distribute

See [Signing Guide](signing-guide.md) for detailed setup instructions.

## Environment Variables

| Variable | Description | Required For |
|----------|-------------|--------------|
| `APPLE_ID` | Apple ID email | Notarization |
| `APPLE_TEAM_ID` | 10-character team ID | Notarization |
| `APPLE_APP_PASSWORD` | App-specific password | Notarization |
| `SPARKLE_PRIVATE_KEY` | Ed25519 private key for Sparkle | Auto-updates |
| `SHIPCAST_TOKEN` | API token from Shipcast dashboard | Hosted appcast |
| `GITHUB_TOKEN` | GitHub personal access token | GitHub Releases |
| `SHIPCAST_BASE_URL` | Override default API endpoint | Self-hosting |

## Individual Commands

For debugging or custom workflows, you can run pipeline stages separately:

```bash
shipcast build      # Build .app only
shipcast sign       # Sign existing .app
shipcast package    # Create .zip and .dmg
shipcast push       # Upload release metadata to Shipcast Cloud
shipcast doctor     # Diagnose signing and Gatekeeper issues
```

## Next Steps

- **For notarized signing setup**: See [Signing Guide](signing-guide.md)
- **For GitHub Actions CI/CD**: See [GitHub Action Guide](github-action.md)
- **For self-hosting the web service**: See [Deployment Checklist](deployment-checklist.md)

## Troubleshooting

Run diagnostics on your built app:

```bash
shipcast doctor
```

This checks:
- App bundle structure
- Code signature validity
- Gatekeeper assessment
- Quarantine status
- Notarization staple (if Developer ID signed)
- Sparkle configuration

Every failure includes the exact command to fix it.
