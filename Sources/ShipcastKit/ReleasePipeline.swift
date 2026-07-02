import Foundation

public struct ReleaseReport: Sendable {
    public var assetURL: URL
    public var edSignature: String?
    public var appcastXML: String
    public var appcastFileURL: URL?
    public var caskPreview: String?
    public var pushedToCloud: Bool
}

public struct ReleasePipeline {
    let shell: any ShellRunner
    let environment: [String: String]
    let cloudPush: ((AppcastEntry, String, URL) throws -> Void)?

    public init(
        shell: any ShellRunner,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cloudPush: ((AppcastEntry, String, URL) throws -> Void)? = nil
    ) {
        self.shell = shell
        self.environment = environment
        self.cloudPush = cloudPush
    }

    public func run(config: ShipcastConfig, at root: URL, dryRun: Bool) throws -> ReleaseReport {
        // 1. Build
        let artifact: BuildArtifact
        switch config.app.project {
        case .xcode:
            artifact = try XcodeBuilder(shell: shell).build(config: config, at: root)
        case .swiftpm, .auto:
            artifact = try SwiftPMBuilder.build(config: config, at: root, shell: shell)
        }

        // 2. Sign (ad-hoc deep sign is the FINAL mutation before packaging)
        let signed = try Signer.sign(artifact, config: config, shell: shell, environment: environment)

        // 3. Package (ditto -c -k --sequesterRsrc --keepParent, sha256, optional DMG)
        let packaged = try Packager.package(signed, config: config, shell: shell)

        // 4. Sparkle ed25519 sign (before publish so the signature ships in the appcast)
        var edSignature: String?
        if config.updates.sparkle {
            edSignature = try SparkleSigner(shell: shell, environment: environment)
                .sign(artifact: packaged.zipURL, privateKeyEnv: "SPARKLE_PRIVATE_KEY")
        }

        // Asset URL is deterministic from repo + tag + zip name — computable in dry-run too
        let tag = "v\(config.app.version)"
        let zipName = packaged.zipURL.lastPathComponent
        let predictedAssetURL = URL(string: "https://github.com/\(config.distribute.githubRepo ?? "")/releases/download/\(tag)/\(zipName)")!

        // 5. GitHub release
        var assetURL = predictedAssetURL
        if !dryRun {
            assetURL = try GitHubReleaser(shell: shell)
                .createRelease(config: config, artifacts: packaged, notes: environment["SHIPCAST_NOTES"] ?? "")
        }

        // 6. Cask
        let cask = CaskGenerator().generate(config: config, artifacts: packaged, releaseURL: assetURL)
        if !dryRun, config.distribute.homebrewTap != nil {
            try CaskPublisher(shell: shell).publish(cask: cask, config: config)
        }

        // 7. Appcast
        var appcastXML = ""
        var appcastFileURL: URL?
        var entry: AppcastEntry?
        if config.updates.sparkle, let signature = edSignature {
            let newEntry = AppcastEntry(
                version: config.app.version,
                artifactURL: assetURL,
                edSignature: signature,
                lengthBytes: packaged.lengthBytes,
                minSystemVersion: "14.0",
                notesHTML: environment["SHIPCAST_NOTES"],
                pubDate: Date()
            )
            entry = newEntry
            appcastXML = AppcastGenerator(appName: config.app.name).generate(releases: [newEntry])

            if case .selfHosted = config.updates.feed {
                let outURL = packaged.zipURL.deletingLastPathComponent().appendingPathComponent("appcast.xml")
                try appcastXML.write(to: outURL, atomically: true, encoding: .utf8)
                appcastFileURL = outURL
            }
        }

        // 8. Cloud push (only when feed == hosted)
        var pushedToCloud = false
        if case .hosted = config.updates.feed, let entry, !dryRun {
            guard let token = environment["SHIPCAST_TOKEN"], !token.isEmpty else {
                throw ShipcastError.config(
                    "feed = \"hosted\" but SHIPCAST_TOKEN is not set",
                    fix: "Get a token from the Shipcast dashboard (Settings → API Tokens) and `export SHIPCAST_TOKEN=<token>`, or switch to feed = \"self:<url>\" in shipcast.toml"
                )
            }
            let baseURL = URL(string: environment["SHIPCAST_BASE_URL"] ?? "https://shipcast.devmafex.com")!

            if let cloudPushFn = cloudPush {
                try cloudPushFn(entry, token, baseURL)
            } else {
                try CloudClient(appSlug: config.app.name.lowercased(), sha256: packaged.sha256)
                    .push(release: entry, token: token, baseURL: baseURL)
            }
            pushedToCloud = true
        }

        // 9. Write last release metadata sidecar
        if !dryRun, let entry {
            let sidecarDir = root.appendingPathComponent(".shipcast")
            try FileManager.default.createDirectory(at: sidecarDir, withIntermediateDirectories: true)
            let sidecarURL = sidecarDir.appendingPathComponent("last-release.json")
            let meta = LastReleaseMetadata(
                version: entry.version,
                assetURL: entry.artifactURL,
                sha256: packaged.sha256,
                edSignature: entry.edSignature,
                lengthBytes: entry.lengthBytes,
                minSystemVersion: entry.minSystemVersion,
                notesHTML: entry.notesHTML
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(meta)
            try data.write(to: sidecarURL)
        }

        return ReleaseReport(
            assetURL: assetURL,
            edSignature: edSignature,
            appcastXML: appcastXML,
            appcastFileURL: appcastFileURL,
            caskPreview: cask,
            pushedToCloud: pushedToCloud
        )
    }
}
