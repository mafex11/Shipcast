import ArgumentParser
import Foundation
import ShipcastKit

struct Sign: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "sign",
        abstract: "Sign .app bundle (ad-hoc or Developer ID + notarize)"
    )

    func run() throws {
        let cwd = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let tomlURL = cwd.appendingPathComponent("shipcast.toml")

        do {
            let shell = ProcessShellRunner()
            var config = try ConfigLoader.load(from: tomlURL)
            config = try VersionResolver.resolve(config: config, at: cwd, shell: shell)

            // Find built .app in .build/release
            let appURL = cwd
                .appendingPathComponent(".build/release")
                .appendingPathComponent("\(config.app.name).app")

            guard FileManager.default.fileExists(atPath: appURL.path) else {
                throw ShipcastError.signing(
                    "\(appURL.path) not found",
                    fix: "Run: shipcast build"
                )
            }

            let artifact = BuildArtifact(
                appURL: appURL,
                appName: config.app.name,
                bundleID: config.app.bundleID,
                version: config.app.version
            )

            print("Signing \(config.app.name)...")
            let signed = try Signer.sign(artifact, config: config, shell: shell)

            print("✓ Signed: \(signed.resolvedMode)")
            if signed.notarized {
                print("  Notarized and stapled")
            }
        } catch let error as ShipcastError {
            FileHandle.standardError.write(Data((error.render() + "\n").utf8))
            Foundation.exit(error.exitCode)
        }
    }
}
