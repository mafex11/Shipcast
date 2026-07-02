import Foundation

public struct Notarizer {
    public static func notarize(_ artifact: BuildArtifact, shell: ShellRunner, dryRun: Bool = false, environment: [String: String]? = nil) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // Create zip for notarization
        let zipURL = tempDir.appendingPathComponent("\(artifact.appName).zip")
        let dittoResult = try shell.run(
            "/usr/bin/ditto",
            args: ["-c", "-k", "--sequesterRsrc", "--keepParent", artifact.appURL.path, zipURL.path],
            env: nil
        )

        guard dittoResult.exitCode == 0 else {
            throw ShipcastError.notarization(
                "ditto failed:\n\(dittoResult.stderr)",
                fix: "Check .app bundle is valid"
            )
        }

        if dryRun {
            print("Dry-run mode: skipping notarytool submission")
            return
        }

        // Get credentials from env
        let env = environment ?? ProcessInfo.processInfo.environment
        guard let appleID = env["APPLE_ID"],
              let teamID = env["APPLE_TEAM_ID"],
              let password = env["APPLE_APP_PASSWORD"] else {
            throw ShipcastError.notarization(
                "Missing notarization credentials",
                fix: "Set environment variables:\n  export APPLE_ID=your-apple-id@example.com\n  export APPLE_TEAM_ID=YOUR10CHAR\n  export APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx"
            )
        }

        // Submit for notarization with --wait
        let notarytoolResult = try shell.run(
            "/usr/bin/xcrun",
            args: [
                "notarytool", "submit", zipURL.path,
                "--apple-id", appleID,
                "--team-id", teamID,
                "--password", password,
                "--wait"
            ],
            env: nil
        )

        guard notarytoolResult.exitCode == 0 else {
            throw ShipcastError.notarization(
                "notarytool submission failed:\n\(notarytoolResult.stderr)",
                fix: "Common issues:\n  1. App-specific password expired (regenerate at appleid.apple.com)\n  2. Binary has issues (check Hardened Runtime, entitlements)\n  3. Check log: xcrun notarytool log <submission-id> --apple-id ... --password ..."
            )
        }

        // Staple ticket
        let staplerResult = try shell.run(
            "/usr/bin/xcrun",
            args: ["stapler", "staple", artifact.appURL.path],
            env: nil
        )

        guard staplerResult.exitCode == 0 else {
            throw ShipcastError.notarization(
                "stapler failed:\n\(staplerResult.stderr)",
                fix: "Notarization succeeded but stapling failed. App will work but needs network for first launch."
            )
        }

        // Validate staple
        let validateResult = try shell.run(
            "/usr/bin/xcrun",
            args: ["stapler", "validate", artifact.appURL.path],
            env: nil
        )

        guard validateResult.exitCode == 0 else {
            throw ShipcastError.notarization(
                "stapler validation failed",
                fix: "Staple corrupt. Re-run: shipcast sign"
            )
        }
    }
}
