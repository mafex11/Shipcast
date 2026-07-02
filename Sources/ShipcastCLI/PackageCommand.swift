import ArgumentParser
import Foundation
import ShipcastKit

struct PackageCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "package",
        abstract: "Package signed .app into zip and/or DMG"
    )

    func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let tomlURL = cwd.appendingPathComponent("shipcast.toml")

        do {
            let shell = ProcessShellRunner()
            var config = try ConfigLoader.load(from: tomlURL)
            config = try VersionResolver.resolve(config: config, at: cwd, shell: shell)

            let appURL = cwd
                .appendingPathComponent(".build/release")
                .appendingPathComponent("\(config.app.name).app")

            guard FileManager.default.fileExists(atPath: appURL.path) else {
                throw ShipcastError.generic(
                    "\(appURL.path) not found",
                    fix: "Run: shipcast build && shipcast sign"
                )
            }

            let artifact = BuildArtifact(
                appURL: appURL,
                appName: config.app.name,
                bundleID: config.app.bundleID,
                version: config.app.version
            )

            let signed = SignedArtifact(
                app: artifact,
                resolvedMode: config.sign.mode,
                notarized: false  // Assume already signed
            )

            print("Packaging \(config.app.name)...")
            let packaged = try Packager.package(signed, config: config, shell: shell)

            print("✓ Packaged:")
            print("  Zip: \(packaged.zipURL.path)")
            if let dmgURL = packaged.dmgURL {
                print("  DMG: \(dmgURL.path)")
            }
            print("  SHA256: \(packaged.sha256)")
            print("  Size: \(packaged.lengthBytes) bytes")
        } catch let error as ShipcastError {
            FileHandle.standardError.write(Data((error.render() + "\n").utf8))
            Foundation.exit(error.exitCode)
        }
    }
}
