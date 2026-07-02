import ArgumentParser
import Foundation
import ShipcastKit

struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Initialize shipcast.toml for current project"
    )

    func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let tomlURL = cwd.appendingPathComponent("shipcast.toml")

        if FileManager.default.fileExists(atPath: tomlURL.path) {
            print("shipcast.toml already exists")
            return
        }

        // Detect project type
        let hasPackageSwift = FileManager.default.fileExists(
            atPath: cwd.appendingPathComponent("Package.swift").path
        )

        let projectType = hasPackageSwift ? "swiftpm" : "auto"

        print("Enter app name: ", terminator: "")
        fflush(stdout)
        guard let appName = readLine()?.trimmingCharacters(in: .whitespaces), !appName.isEmpty else {
            let error = ShipcastError.config("App name required", fix: "Enter a valid app name")
            FileHandle.standardError.write(Data((error.render() + "\n").utf8))
            Foundation.exit(error.exitCode)
        }

        print("Enter bundle ID (e.g., com.yourname.appname): ", terminator: "")
        fflush(stdout)
        guard let bundleID = readLine()?.trimmingCharacters(in: .whitespaces), !bundleID.isEmpty else {
            let error = ShipcastError.config("Bundle ID required", fix: "Enter a valid bundle ID")
            FileHandle.standardError.write(Data((error.render() + "\n").utf8))
            Foundation.exit(error.exitCode)
        }

        let template = """
        [app]
        name = "\(appName)"
        bundle_id = "\(bundleID)"
        version = "auto"
        project = "\(projectType)"

        [sign]
        mode = "auto"

        [distribute]
        github_release = true
        github_repo = "yourname/\(appName.lowercased())"
        homebrew_tap = "yourname/homebrew-tap"
        formats = ["zip", "dmg"]

        [updates]
        sparkle = true
        feed = "hosted"

        [permissions]
        # Uncomment the permissions your app needs:
        # accessibility = true
        # screen_recording = true
        # full_disk_access = true
        """

        try template.write(to: tomlURL, atomically: true, encoding: .utf8)
        print("✓ Created shipcast.toml")
        print("  Edit the file to customize your configuration")
    }
}
