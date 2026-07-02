import ArgumentParser
import Foundation
import ShipcastKit

struct Build: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "build",
        abstract: "Build .app bundle"
    )

    func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let tomlURL = cwd.appendingPathComponent("shipcast.toml")

        guard FileManager.default.fileExists(atPath: tomlURL.path) else {
            let error = ShipcastError.config(
                "shipcast.toml not found",
                fix: "Run: shipcast init"
            )
            FileHandle.standardError.write(Data((error.render() + "\n").utf8))
            Foundation.exit(error.exitCode)
        }

        do {
            let config = try ConfigLoader.load(from: tomlURL)
            let shell = ProcessShellRunner()

            print("Building \(config.app.name)...")

            guard case .swiftpm = config.app.project else {
                throw ShipcastError.generic(
                    "Only SwiftPM projects supported in Plan A",
                    fix: "Xcode support coming in Plan B"
                )
            }

            let artifact = try SwiftPMBuilder.build(config: config, at: cwd, shell: shell)

            print("✓ Built: \(artifact.appURL.path)")
            print("  Bundle ID: \(artifact.bundleID)")
            print("  Version: \(artifact.version)")
        } catch let error as ShipcastError {
            FileHandle.standardError.write(Data((error.render() + "\n").utf8))
            Foundation.exit(error.exitCode)
        }
    }
}
