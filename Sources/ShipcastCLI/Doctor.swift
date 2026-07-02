import ArgumentParser
import Foundation
import ShipcastKit

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose Gatekeeper/TCC/signing failures"
    )

    @Argument(help: "Path to the .app bundle (default: newest .app under .build/release or .shipcast/build)")
    var appPath: String?

    func run() throws {
        let config = try ConfigLoader.load(from: URL(fileURLWithPath: "shipcast.toml"))
        let appURL: URL
        if let appPath {
            appURL = URL(fileURLWithPath: appPath)
        } else {
            // SwiftPM builds land in .build/release (Plan A); Xcode exports in .shipcast/build (Task 1)
            let candidateDirs = [URL(fileURLWithPath: ".build/release"), URL(fileURLWithPath: ".shipcast/build/export")]
            let apps = candidateDirs.flatMap { dir in
                ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                    .filter { $0.pathExtension == "app" }
            }
            guard let newest = apps.max(by: { (lhs, rhs) in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l < r
            }) else {
                throw ShipcastError.config(
                    "No .app found under .build/release or .shipcast/build/export, and no path given",
                    fix: "Run `shipcast build` first, or pass a path: `shipcast doctor /path/to/MyApp.app`"
                )
            }
            appURL = newest
        }
        let findings = Doctor(shell: ProcessShellRunner()).run(appURL: appURL, config: config)
        print(DoctorRenderer.render(findings))
        Foundation.exit(DoctorRenderer.exitCode(for: findings))
    }
}
