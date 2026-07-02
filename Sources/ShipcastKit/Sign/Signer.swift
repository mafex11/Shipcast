import Foundation

public struct Signer {
    public static func sign(_ artifact: BuildArtifact, config: ShipcastConfig, shell: ShellRunner) throws -> SignedArtifact {
        let resolvedMode: SignMode
        let notarized: Bool

        switch config.sign.mode {
        case .auto:
            resolvedMode = try detectSignMode(shell: shell)
        case .adhoc:
            resolvedMode = .adhoc
        case .developerID:
            resolvedMode = .developerID
        }

        switch resolvedMode {
        case .adhoc:
            try AdHocSigner.sign(artifact, shell: shell)
            notarized = false

        case .developerID:
            let identity = try findDeveloperIDIdentity(shell: shell)
            try DeveloperIDSigner.sign(artifact, identity: identity, shell: shell)

            // Notarization check deferred to Task 10
            notarized = false

        case .auto:
            fatalError("Should be resolved by detectSignMode")
        }

        return SignedArtifact(
            app: artifact,
            resolvedMode: resolvedMode,
            notarized: notarized
        )
    }

    private static func detectSignMode(shell: ShellRunner, environment: [String: String] = ProcessInfo.processInfo.environment) throws -> SignMode {
        // Auto-detection logic from spec §Signing Engine
        // IF Developer ID cert + env vars → notarized, ELSE → ad-hoc

        let identityResult = try shell.run(
            "/usr/bin/security",
            args: ["find-identity", "-v", "-p", "codesigning"],
            env: nil
        )

        let hasDeveloperID = identityResult.stdout.contains("Developer ID Application")

        let hasNotarizationEnv = environment["APPLE_ID"] != nil
            && environment["APPLE_TEAM_ID"] != nil
            && environment["APPLE_APP_PASSWORD"] != nil

        if hasDeveloperID && hasNotarizationEnv {
            return .developerID
        } else {
            return .adhoc
        }
    }

    private static func findDeveloperIDIdentity(shell: ShellRunner) throws -> String {
        let result = try shell.run(
            "/usr/bin/security",
            args: ["find-identity", "-v", "-p", "codesigning"],
            env: nil
        )

        // Parse: "  1) ABC123... "Developer ID Application: Name (TEAMID)""
        let lines = result.stdout.split(separator: "\n")
        for line in lines {
            if line.contains("Developer ID Application") {
                if let start = line.firstIndex(of: "\""), let end = line.lastIndex(of: "\"") {
                    return String(line[line.index(after: start)..<end])
                }
            }
        }

        throw ShipcastError.signing(
            "No Developer ID certificate found",
            fix: "Import your Developer ID certificate:\n  1. Download from developer.apple.com\n  2. Double-click .cer file\n  3. Verify: security find-identity -v -p codesigning"
        )
    }
}
