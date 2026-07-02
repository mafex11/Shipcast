import Foundation

struct DeveloperIDSigner {
    static func sign(_ artifact: BuildArtifact, identity: String, shell: ShellRunner) throws {
        // Deep sign with runtime hardening
        let result = try shell.run(
            "/usr/bin/codesign",
            args: [
                "--force", "--deep",
                "--sign", identity,
                "--options", "runtime",
                "--timestamp",
                artifact.appURL.path
            ],
            env: nil
        )

        guard result.exitCode == 0 else {
            throw ShipcastError.signing(
                "codesign --sign \"\(identity)\" --options runtime \(artifact.appURL.path)\n\(result.stderr)",
                fix: "Common fixes:\n  1. Import Developer ID certificate from Apple\n  2. Run: security find-identity -v -p codesigning\n  3. Unlock keychain: security unlock-keychain ~/Library/Keychains/login.keychain-db"
            )
        }

        // Verify signature
        let verifyResult = try shell.run(
            "/usr/bin/codesign",
            args: ["--verify", "--deep", "--strict", artifact.appURL.path],
            env: nil
        )

        guard verifyResult.exitCode == 0 else {
            throw ShipcastError.signing(
                "Signature verification failed",
                fix: "Certificate may be revoked or expired. Check Apple Developer portal"
            )
        }

        // spctl Gatekeeper check
        let spctlResult = try shell.run(
            "/usr/bin/spctl",
            args: ["-a", "-t", "exec", "-vv", artifact.appURL.path],
            env: nil
        )

        if spctlResult.exitCode != 0 {
            throw ShipcastError.signing(
                "Gatekeeper assessment failed:\n\(spctlResult.stderr)",
                fix: "Signature valid but Gatekeeper rejects. Need notarization:\n  Set env: APPLE_ID, APPLE_TEAM_ID, APPLE_APP_PASSWORD\n  shipcast sign  (will auto-notarize)"
            )
        }
    }
}
