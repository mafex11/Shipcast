import Foundation
import CryptoKit

public struct Packager {
    public static func package(_ signed: SignedArtifact, config: ShipcastConfig, shell: ShellRunner) throws -> PackagedArtifacts {
        let outputDir = signed.app.appURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()  // from .build/release to .build
            .appendingPathComponent("shipcast-output")

        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

        // Always create zip (required for Sparkle updates)
        let zipURL = outputDir.appendingPathComponent("\(signed.app.appName).zip")

        // Remove existing zip
        if FileManager.default.fileExists(atPath: zipURL.path) {
            try FileManager.default.removeItem(at: zipURL)
        }

        // ditto zip with --sequesterRsrc --keepParent
        let dittoResult = try shell.run(
            "/usr/bin/ditto",
            args: ["-c", "-k", "--sequesterRsrc", "--keepParent", signed.app.appURL.path, zipURL.path],
            env: nil
        )

        guard dittoResult.exitCode == 0 else {
            throw ShipcastError.generic(
                "ditto zip failed:\n\(dittoResult.stderr)",
                fix: "Check .app bundle is valid and signed"
            )
        }

        // Compute SHA256
        let zipData = try Data(contentsOf: zipURL)
        let hash = SHA256.hash(data: zipData)
        let sha256 = hash.compactMap { String(format: "%02x", $0) }.joined()
        let lengthBytes = zipData.count

        // DMG creation (if requested)
        var dmgURL: URL? = nil
        if config.distribute.formats.contains(.dmg) {
            dmgURL = try createDMG(for: signed.app, outputDir: outputDir, shell: shell)
        }

        return PackagedArtifacts(
            zipURL: zipURL,
            dmgURL: dmgURL,
            sha256: sha256,
            lengthBytes: lengthBytes
        )
    }

    private static func createDMG(for artifact: BuildArtifact, outputDir: URL, shell: ShellRunner) throws -> URL {
        let dmgURL = outputDir.appendingPathComponent("\(artifact.appName).dmg")

        // Remove existing DMG
        if FileManager.default.fileExists(atPath: dmgURL.path) {
            try FileManager.default.removeItem(at: dmgURL)
        }

        // Check if create-dmg is installed and get its path
        let whichResult = try shell.run("/usr/bin/which", args: ["create-dmg"], env: nil)
        guard whichResult.exitCode == 0 else {
            throw ShipcastError.generic(
                "create-dmg not found",
                fix: "Install via Homebrew:\n  brew install create-dmg"
            )
        }

        // Extract path from which output (trim whitespace and newlines)
        let createDMGPath = whichResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !createDMGPath.isEmpty else {
            throw ShipcastError.generic(
                "create-dmg path is empty",
                fix: "Install via Homebrew:\n  brew install create-dmg"
            )
        }

        // Create DMG with create-dmg
        let createDMGResult = try shell.run(
            createDMGPath,
            args: [
                "--volname", "\(artifact.appName) Installer",
                "--window-pos", "200", "120",
                "--window-size", "800", "400",
                "--icon-size", "100",
                "--icon", "\(artifact.appName).app", "200", "190",
                "--hide-extension", "\(artifact.appName).app",
                "--app-drop-link", "600", "185",
                dmgURL.path,
                artifact.appURL.path
            ],
            env: nil
        )

        // create-dmg exits 2 if DMG already exists but was recreated, which is fine
        guard createDMGResult.exitCode == 0 || createDMGResult.exitCode == 2 else {
            throw ShipcastError.generic(
                "create-dmg failed:\n\(createDMGResult.stderr)",
                fix: "Check .app bundle path and create-dmg installation"
            )
        }

        return dmgURL
    }
}
