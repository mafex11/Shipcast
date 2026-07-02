import Foundation

struct AdHocSigner {
    static func sign(_ artifact: BuildArtifact, shell: ShellRunner) throws {
        // Deep ad-hoc sign: codesign --force --deep --sign -
        let result = try shell.run(
            "/usr/bin/codesign",
            args: ["--force", "--deep", "--sign", "-", artifact.appURL.path],
            env: nil
        )

        guard result.exitCode == 0 else {
            throw ShipcastError.signing(
                "codesign --force --deep --sign - \(artifact.appURL.path)",
                fix: "Ad-hoc signing should never fail. Check:\n  1. .app bundle structure is valid\n  2. All resources added BEFORE signing\n  3. Run: codesign --verify --deep \(artifact.appURL.path)"
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
                "Signature verification failed after ad-hoc signing",
                fix: "Bundle structure may be corrupted. Try:\n  swift package clean\n  shipcast build"
            )
        }
    }
}
