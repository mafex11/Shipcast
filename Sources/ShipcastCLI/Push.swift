import ArgumentParser
import Foundation
import ShipcastKit

struct PushCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "push",
        abstract: "POST release metadata to Shipcast Cloud"
    )

    @Option(help: "API token (default: SHIPCAST_TOKEN env)")
    var token: String?

    @Option(help: "Version to push (default: [app] version from shipcast.toml)")
    var version: String?

    func run() throws {
        do {
            let config = try ConfigLoader.load(from: URL(fileURLWithPath: "shipcast.toml"))
            guard let resolvedToken = token ?? ProcessInfo.processInfo.environment["SHIPCAST_TOKEN"],
                  !resolvedToken.isEmpty else {
                throw ShipcastError.config(
                    "No API token: --token not given and SHIPCAST_TOKEN is unset",
                    fix: "Get a token from the Shipcast dashboard (Settings → API Tokens), then `export SHIPCAST_TOKEN=<token>` or pass --token <token>"
                )
            }
            // Reads the release metadata sidecar written by the pipeline (.shipcast/last-release.json:
            // version, asset URL, sha256, ed signature, length) so push is re-runnable after a failed upload.
            let sidecarURL = URL(fileURLWithPath: ".shipcast/last-release.json")
            guard let data = try? Data(contentsOf: sidecarURL),
                  let meta = try? JSONDecoder().decode(LastReleaseMetadata.self, from: data) else {
                throw ShipcastError.config(
                    "No release metadata found at .shipcast/last-release.json",
                    fix: "Run `shipcast release` first; push re-sends the metadata from the last release"
                )
            }
            let entry = AppcastEntry(
                version: version ?? meta.version,
                artifactURL: meta.assetURL,
                edSignature: meta.edSignature,
                lengthBytes: meta.lengthBytes,
                minSystemVersion: meta.minSystemVersion,
                notesHTML: meta.notesHTML,
                pubDate: Date()
            )
            guard let baseURL = URL(string: ProcessInfo.processInfo.environment["SHIPCAST_BASE_URL"] ?? "https://shipcast.devmafex.com") else {
                throw ShipcastError.config(
                    "SHIPCAST_BASE_URL is not a valid URL: \(ProcessInfo.processInfo.environment["SHIPCAST_BASE_URL"] ?? "")",
                    fix: "Set SHIPCAST_BASE_URL to a full URL like https://shipcast.devmafex.com or unset it to use the default"
                )
            }
            try CloudClient(appSlug: slugify(config.app.name), sha256: meta.sha256)
                .push(release: entry, token: resolvedToken, baseURL: baseURL)
            print("✓ Pushed \(config.app.name) \(entry.version) to Shipcast Cloud")
        } catch let error as ShipcastError {
            FileHandle.standardError.write(Data((error.render() + "\n").utf8))
            Foundation.exit(error.exitCode)
        }
    }
}
