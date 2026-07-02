import ArgumentParser
import Foundation
import ShipcastKit

struct ReleaseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Full pipeline: build + sign + package + GitHub release + cask + appcast"
    )

    @Flag(help: "Run build/sign/package locally and preview cask + appcast, but publish nothing")
    var dryRun = false

    @Option(help: "Override feed: hosted | self:<url> | none")
    var feed: String?

    @Option(help: "Release notes (also read from SHIPCAST_NOTES env)")
    var notes: String?

    func run() throws {
        do {
            var config = try ConfigLoader.load(from: URL(fileURLWithPath: "shipcast.toml"))
            if let feed {
                switch feed {
                case "hosted": config.updates.feed = .hosted
                case "none": config.updates.feed = .none
                case let s where s.hasPrefix("self:"): config.updates.feed = .selfHosted(url: String(s.dropFirst(5)))
                default:
                    throw ShipcastError.config(
                        "Unknown --feed value: \(feed)",
                        fix: "Use --feed hosted, --feed none, or --feed self:https://example.com/appcast.xml"
                    )
                }
            }
            var environment = ProcessInfo.processInfo.environment
            if let notes { environment["SHIPCAST_NOTES"] = notes }

            let shell = ProcessShellRunner()
            let root = URL(fileURLWithPath: ".")
            // Resolve version = "auto" up front so status output shows the real version
            // (the pipeline re-resolves internally, which is a no-op after this).
            config = try VersionResolver.resolve(config: config, at: root, shell: shell)

            let pipeline = ReleasePipeline(shell: shell, environment: environment)
            let report = try pipeline.run(config: config, at: root, dryRun: dryRun)
            if dryRun {
                print("── dry run: nothing published ──")
                print("Would upload to: \(report.assetURL.absoluteString)")
                print("── cask preview ──\n\(report.caskPreview ?? "(no cask)")")
                if !report.appcastXML.isEmpty { print("── appcast preview ──\n\(report.appcastXML)") }
            } else {
                print("✓ Released \(config.app.name) \(config.app.version)")
                print("  Asset: \(report.assetURL.absoluteString)")
                if let appcast = report.appcastFileURL { print("  Appcast: \(appcast.path)") }
                if report.pushedToCloud { print("  Pushed to Shipcast Cloud") }
            }
        } catch let error as ShipcastError {
            FileHandle.standardError.write(Data((error.render() + "\n").utf8))
            Foundation.exit(error.exitCode)
        }
    }
}
