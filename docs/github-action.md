# GitHub Action Guide

Automate Mac app releases with the Shipcast GitHub Action. Every tagged commit triggers a full release pipeline in CI.

## Basic Usage

Create `.github/workflows/release.yml`:

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
      
      - uses: mafex11/shipcast/action@v1
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

## How It Works

The action:
1. Installs Shipcast CLI via Homebrew
2. Creates a temporary keychain
3. Imports your Developer ID certificate from a base64-encoded P12
4. Runs `shipcast release` with your credentials as environment variables
5. Cleans up the keychain and certificate file (even if the release fails)

## Required Secrets

Add these secrets in your GitHub repository: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

| Secret Name | Description | How to Get |
|-------------|-------------|------------|
| `APPLE_ID` | Apple ID email | Your Apple Developer account email |
| `APPLE_TEAM_ID` | 10-character team ID | [developer.apple.com](https://developer.apple.com) → **Membership** → Team ID |
| `APPLE_APP_PASSWORD` | App-specific password | [appleid.apple.com](https://appleid.apple.com) → **Sign-In and Security** → **App-Specific Passwords** → Generate (format: `xxxx-xxxx-xxxx-xxxx`) |
| `DEVELOPER_ID_P12` | Base64-encoded Developer ID certificate | See [Exporting P12](#exporting-p12-from-keychain) below |
| `P12_PASSWORD` | Password for the P12 file | Password you set when exporting from Keychain |
| `SPARKLE_PRIVATE_KEY` | Ed25519 private key for Sparkle updates | From `generate_keys` tool (see [Signing Guide](signing-guide.md#sparkle-update-signing)) |
| `SHIPCAST_TOKEN` | Shipcast API token | [shipcast.devmafex.com/dashboard](https://shipcast.devmafex.com/dashboard) → Settings → API Tokens |
| `GITHUB_TOKEN` | GitHub token for releases | **Automatically provided by GitHub Actions** (no setup needed) |

## Exporting P12 from Keychain

Your Developer ID certificate must be exported as a `.p12` file and base64-encoded for use in CI.

### Step 1: Export from Keychain

1. Open **Keychain Access** (Applications → Utilities)
2. Select **login** keychain in the sidebar
3. Find your **Developer ID Application** certificate
4. Right-click → **Export "Developer ID Application: Your Name"**
5. Save as `cert.p12`
6. **Set a strong password** when prompted (you'll add this as `P12_PASSWORD` secret)

### Step 2: Base64 Encode

In Terminal:

```bash
base64 -i cert.p12 | pbcopy
```

This copies the base64-encoded certificate to your clipboard.

### Step 3: Add to GitHub Secrets

1. Go to your repository on GitHub
2. **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Name: `DEVELOPER_ID_P12`
5. Value: Paste the base64 string from clipboard
6. Click **Add secret**

### Step 4: Add P12 Password

1. Create another secret named `P12_PASSWORD`
2. Value: The password you set when exporting the P12
3. Click **Add secret**

### Step 5: Clean Up

Delete the local `cert.p12` file:

```bash
rm cert.p12
```

**Security Note**: The P12 file contains your private key. Never commit it to git or share it publicly.

## Trigger a Release

Tag a commit and push:

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions will:
1. Build your app
2. Sign with Developer ID + notarization
3. Create GitHub Release with .zip and .dmg
4. Update or create Homebrew cask PR
5. Push release metadata to Shipcast Cloud (if `SHIPCAST_TOKEN` is set)

Check progress: **Actions** tab in your GitHub repository.

## Ad-hoc Signing in CI

The action supports notarized signing only. For ad-hoc signing, omit the action secrets (except `GITHUB_TOKEN`), and `shipcast release` will fall back to ad-hoc mode.

However, ad-hoc builds in CI are uncommon because the workflow requires a Developer ID certificate to prove ownership for GitHub Releases and Homebrew casks.

## Customization

### Custom Trigger Patterns

Trigger on pre-release tags:

```yaml
on:
  push:
    tags:
      - 'v*-beta*'
```

Trigger on specific branches:

```yaml
on:
  push:
    branches:
      - main
```

### Manual Workflow Dispatch

Add manual trigger for testing:

```yaml
on:
  push:
    tags:
      - 'v*'
  workflow_dispatch:
```

Trigger manually: **Actions** → **Release** → **Run workflow**

### Matrix Builds (Multiple Apps)

If your repository contains multiple apps:

```yaml
jobs:
  release:
    runs-on: macos-latest
    strategy:
      matrix:
        app: [app1, app2]
    steps:
      - uses: actions/checkout@v4
      - run: cd ${{ matrix.app }}
      - uses: mafex11/shipcast/action@v1
        with:
          # ... secrets
```

### Environment-Specific Secrets

Use GitHub environments for staging vs production:

```yaml
jobs:
  release:
    runs-on: macos-latest
    environment: production
    steps:
      # ... action steps use environment-scoped secrets
```

## Troubleshooting

### "security: SecKeychainItemImport: The specified item already exists in the keychain"

**Cause**: Previous workflow run didn't clean up the keychain.  
**Fix**: The action includes `if: always()` on cleanup. This error shouldn't occur. If it does, check that the cleanup step ran.

### "error: Code signing failed: No signing certificate found"

**Cause**: P12 import failed or incorrect password.  
**Fix**:
1. Verify `DEVELOPER_ID_P12` is valid base64
2. Verify `P12_PASSWORD` matches the export password
3. Re-export and re-encode the P12

### "error: Notarization failed: Invalid credentials"

**Cause**: Wrong Apple ID, Team ID, or App-Specific Password.  
**Fix**:
1. Verify `APPLE_ID` is correct
2. Verify `APPLE_TEAM_ID` (10 characters, all caps)
3. Regenerate App-Specific Password at [appleid.apple.com](https://appleid.apple.com)

### "error: GitHub Release creation failed: Resource not accessible by integration"

**Cause**: `GITHUB_TOKEN` lacks permissions.  
**Fix**: Add permissions to the workflow:

```yaml
permissions:
  contents: write  # Required for creating releases
```

### Check Full Logs

GitHub Actions logs include `shipcast release` output. Expand the **Run Shipcast release** step to see:
- Build output
- Signing verification
- Notarization status
- GitHub Release URL
- Homebrew cask PR link

## Best Practices

1. **Test locally first**: Run `shipcast release` on your machine before setting up CI
2. **Use workflow_dispatch for testing**: Add manual trigger to test the action without pushing tags
3. **Rotate App-Specific Passwords**: Regenerate annually or after any security incident
4. **Monitor workflow failures**: Enable email notifications in **Settings** → **Notifications** → **Actions**
5. **Keep secrets minimal**: Only store what's necessary; rotate regularly

## Next Steps

- **View releases in dashboard**: [shipcast.devmafex.com/dashboard](https://shipcast.devmafex.com/dashboard)
- **Monitor update adoption**: Check version rollout in the dashboard analytics
- **Self-host the cloud service**: See [Deployment Checklist](deployment-checklist.md)
