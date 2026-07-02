import Foundation

public struct SwiftPMBuilder {
    public static func build(config: ShipcastConfig, at projectRoot: URL, shell: ShellRunner) throws -> BuildArtifact {
        let buildDir = projectRoot.appendingPathComponent(".build/release")

        // Run swift build -c release
        let buildResult = try shell.run(
            "/usr/bin/swift",
            args: ["build", "-c", "release", "--package-path", projectRoot.path],
            env: nil
        )

        guard buildResult.exitCode == 0 else {
            throw ShipcastError.generic(
                "swift build failed:\n\(buildResult.stderr)",
                fix: "Check build errors above. Common fixes:\n  swift package clean\n  swift package resolve"
            )
        }

        // Assemble .app bundle
        let appName = config.app.name
        let appURL = buildDir.appendingPathComponent("\(appName).app")
        let contentsURL = appURL.appendingPathComponent("Contents")
        let macosURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

        let fm = FileManager.default

        // Clean previous build
        if fm.fileExists(atPath: appURL.path) {
            try fm.removeItem(at: appURL)
        }

        // Create bundle structure
        try fm.createDirectory(at: macosURL, withIntermediateDirectories: true)
        try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

        // Copy binary
        let binarySource = buildDir.appendingPathComponent(appName)
        let binaryDest = macosURL.appendingPathComponent(appName)
        try fm.copyItem(at: binarySource, to: binaryDest)

        // Make executable
        let chmodResult = try shell.run("/bin/chmod", args: ["+x", binaryDest.path], env: nil)
        guard chmodResult.exitCode == 0 else {
            throw ShipcastError.generic("Failed to make binary executable", fix: "Check file permissions")
        }

        return BuildArtifact(
            appURL: appURL,
            appName: appName,
            bundleID: config.app.bundleID,
            version: config.app.version
        )
    }
}
