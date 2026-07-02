# Signing Guide

This guide covers both signing paths supported by Shipcast: ad-hoc (free, no certificate) and notarized (requires Apple Developer Program).

## Ad-hoc Signing

### What It Is

Ad-hoc signing creates a valid code signature without a certificate. The app will run on any Mac, but macOS Gatekeeper will show warnings because it's not notarized.

### When to Use

- Internal testing and development
- Distribution to known users who understand how to bypass Gatekeeper
- Apps that don't need App Store or wide public distribution
- You don't have an Apple Developer Program membership ($99/year)

### How It Works

Shipcast automatically uses ad-hoc signing if no Developer ID certificate is found. Just run:

```bash
shipcast release
```

### Gatekeeper Implications

When users download ad-hoc signed apps, macOS applies the **quarantine attribute** and blocks execution with:

```
"MyApp.app" is damaged and can't be opened. You should move it to the Trash.
```

**Workaround**: The generated Homebrew cask includes a `postflight` script that automatically:
1. Strips the quarantine attribute: `xattr -dr com.apple.quarantine MyApp.app`
2. Resets TCC grants on updates (see below)

Users installing via `brew install` won't see Gatekeeper warnings.

### TCC (Privacy) Permissions on Ad-hoc Updates

macOS identifies apps by their **code directory hash (cdhash)**. Ad-hoc rebuilds change the cdhash, causing macOS to:
- Orphan previous TCC grants (Accessibility, Screen Recording, etc.)
- Silently deny access without prompting

**Solution**: The cask `postflight` resets TCC grants on each update:

```ruby
system_command "/usr/bin/tccutil",
               args: ["reset", "Accessibility", "dev.yourname.myapp"]
```

Declare your required permissions in `shipcast.toml`:

```toml
[permissions]
accessibility = true
screen_recording = true
```

Shipcast generates the appropriate `tccutil reset` commands in the cask.

### Common Errors

**"Code signature invalid"**  
**Cause**: Resources added after signing broke the seal.  
**Fix**: Ensure all resources are embedded before running `shipcast sign`. Shipcast handles this automatically in `shipcast release`.

**"The application is damaged"**  
**Cause**: Quarantine attribute on ad-hoc signed app.  
**Fix**: Users installing via Homebrew cask won't see this. For manual installs:
```bash
xattr -dr com.apple.quarantine MyApp.app
```

---

## Notarized Signing

### What It Is

Notarized signing uses a **Developer ID Application certificate** from Apple, signs your app with hardened runtime, and submits it to Apple for security scanning. After approval, macOS Gatekeeper allows the app to run without warnings.

### Prerequisites

1. **Apple Developer Program membership** ($99/year)
2. **Developer ID Application certificate** (see below)
3. **App-specific password** for notarization

### Step 1: Get a Developer ID Certificate

1. Go to [developer.apple.com](https://developer.apple.com)
2. Navigate to **Certificates, Identifiers & Profiles**
3. Create a new certificate: **Developer ID Application**
4. Download the `.cer` file
5. Double-click to import into **Keychain Access**

Verify the certificate is installed:

```bash
security find-identity -v -p codesigning
```

You should see:
```
1) ABC123DEF456 "Developer ID Application: Your Name (TEAM123456)"
```

### Step 2: Create an App-Specific Password

Notarization requires an app-specific password, not your Apple ID password.

1. Go to [appleid.apple.com](https://appleid.apple.com)
2. Sign in
3. Navigate to **Sign-In and Security** → **App-Specific Passwords**
4. Click **Generate an app-specific password**
5. Label it "Shipcast" and copy the generated password (format: `xxxx-xxxx-xxxx-xxxx`)

### Step 3: Set Environment Variables

Export credentials before running `shipcast release`:

```bash
export APPLE_ID="your@email.com"
export APPLE_TEAM_ID="TEAM123456"  # From developer.apple.com → Membership
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

For persistent configuration, add to your shell profile (`~/.zshrc` or `~/.bash_profile`):

```bash
# Shipcast notarization credentials
export APPLE_ID="your@email.com"
export APPLE_TEAM_ID="TEAM123456"
export APPLE_APP_PASSWORD="xxxx-xxxx-xxxx-xxxx"
```

### Step 4: Run Release

```bash
shipcast release
```

Shipcast will:
1. Detect the Developer ID certificate in Keychain
2. Sign with `--options runtime` (hardened runtime)
3. Create a .zip preserving the signature
4. Submit to Apple's notarization service via `notarytool`
5. Wait for approval (typically 1-5 minutes)
6. Staple the notarization ticket to your app
7. Re-zip the stapled app

### Notarization Timeline

- **Typical**: 1-5 minutes
- **Slow times**: 10-15 minutes (high Apple server load)
- **Failure**: Immediate rejection with error log

### Common Notarization Errors

**"The binary is not signed with a valid Developer ID certificate"**  
**Cause**: Certificate expired or revoked.  
**Fix**: Check certificate expiration in Keychain Access. Renew if needed.

**"The executable does not have the hardened runtime enabled"**  
**Cause**: Missing `--options runtime` flag.  
**Fix**: Shipcast handles this automatically. If signing manually, ensure:
```bash
codesign --sign "Developer ID Application: ..." --options runtime MyApp.app
```

**"The signature does not include a secure timestamp"**  
**Cause**: Missing `--timestamp` flag.  
**Fix**: Shipcast includes timestamps. Check network connectivity during signing.

**"The app uses an invalid entitlement"**  
**Cause**: Custom entitlements incompatible with notarization.  
**Fix**: Review entitlements in Xcode. Notarization rejects:
- `com.apple.security.get-task-allow` (debug builds only)
- Sandbox exceptions without justification

---

## Sparkle Update Signing

Both signing paths require **Sparkle ed25519 signing** for update integrity.

### Generate Keys (Once Per App)

Sparkle provides a `generate_keys` tool. Install it:

```bash
brew install sparkle
```

Generate keys:

```bash
./generate_keys
```

Output:
```
Public key (add to Info.plist): base64-encoded-public-key-here
Private key (keep secret): base64-encoded-private-key-here
```

### Add Public Key to Info.plist

In your app's `Info.plist`:

```xml
<key>SUPublicEDKey</key>
<string>base64-encoded-public-key-here</string>
```

### Store Private Key Securely

The private key signs release artifacts. **Never commit it to git.**

For local releases, set as environment variable:

```bash
export SPARKLE_PRIVATE_KEY="base64-encoded-private-key-here"
```

For CI/CD, store in GitHub secrets (see [GitHub Action Guide](github-action.md)).

### Signing Artifacts

Shipcast handles this automatically during `shipcast release`. The ed25519 signature is included in the appcast XML:

```xml
<enclosure url="..." sparkle:edSignature="base64-signature-here" />
```

---

## Verification Commands

### Check Code Signature

```bash
codesign --verify --deep --strict MyApp.app
```

Success: no output. Failure: error message.

### Check Gatekeeper Assessment

```bash
spctl -a -t exec -vv MyApp.app
```

Ad-hoc: `rejected (the code is valid but does not seem to be an app)`  
Notarized: `accepted source=Notarized Developer ID`

### Check Quarantine Status

```bash
xattr -l MyApp.app
```

If `com.apple.quarantine` is present, the app was downloaded and will trigger Gatekeeper.

Remove it:
```bash
xattr -dr com.apple.quarantine MyApp.app
```

### Validate Notarization Staple

```bash
xcrun stapler validate MyApp.app
```

Success: `The validate action worked!`  
Failure: `The staple and validate action failed!`

---

## Which Signing Path Should I Use?

| Factor | Ad-hoc | Notarized |
|--------|--------|-----------|
| **Cost** | Free | $99/year |
| **Setup Time** | 0 minutes | 30 minutes (one-time) |
| **Release Time** | <1 minute | +2-5 minutes (notarization wait) |
| **User Experience** | Requires Homebrew install or manual quarantine removal | Seamless, no warnings |
| **Trust Level** | Users must trust you | Verified by Apple |
| **Distribution** | Friends, beta testers, internal tools | Public, App Store-like trust |

**Recommendation**: Start with ad-hoc for early development. Switch to notarized before public release.
