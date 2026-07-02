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

    public func run(config rawConfig: ShipcastConfig, at root: URL, dryRun: Bool) throws -> ReleaseReport {
        // 0a. Resolve version = "auto" from the latest git tag before anything else
        let config = try VersionResolver.resolve(config: rawConfig, at: root, shell: shell)

        // 0b. Fail fast on missing credentials BEFORE spending minutes building:
        // a hosted push at the end of the pipeline must not be the first thing to notice.
        var hostedToken: String?
        if case .hosted = config.updates.feed, !dryRun {
            guard let token = environment["SHIPCAST_TOKEN"], !token.isEmpty else {
                throw ShipcastError.config(
                    "feed = \"hosted\" but SHIPCAST_TOKEN is not set",
                    fix: "Get a token from the Shipcast dashboard (Settings → API Tokens) and `export SHIPCAST_TOKEN=<token>`, or switch to feed = \"self:<url>\" in shipcast.toml"
                )
            }
            hostedToken = token
        }

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

        let zipName = packaged.zipURL.lastPathComponent

        // 5. GitHub release (respects distribute.github_release)
        let assetURL: URL
        if config.distribute.githubRelease {
            if dryRun {
                // Asset URL is deterministic from repo + tag + zip name — computable in dry-run too
                assetURL = try Self.predictedAssetURL(config: config, zipName: zipName)
            } else {
                assetURL = try GitHubReleaser(shell: shell)
                    .createRelease(config: config, artifacts: packaged, notes: environment["SHIPCAST_NOTES"] ?? "")
            }
        } else {
            // No GitHub release. The appcast/cask still need a download URL; the
            // predicted GitHub URL works only when github_repo is configured.
            let needsAssetURL = config.updates.sparkle || config.distribute.homebrewTap != nil
            if config.distribute.githubRepo != nil {
                assetURL = try Self.predictedAssetURL(config: config, zipName: zipName)
            } else if needsAssetURL {
                throw ShipcastError.config(
                    "github_release = false but the appcast/cask needs a download URL and github_repo is not set",
                    fix: "Set github_repo in [distribute] (the release URL will be predicted from it), enable github_release = true, or disable sparkle/homebrew_tap"
                )
            } else {
                // Nothing downstream needs a remote URL; report the local artifact.
                assetURL = packaged.zipURL
            }
        }

        // 6. Cask
        let cask = CaskGenerator().generate(
            config: config,
            artifacts: packaged,
            releaseURL: assetURL,
            resolvedMode: signed.resolvedMode
        )
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

        // 8. Write last release metadata sidecar BEFORE the cloud push so a failed
        // push can be retried with `shipcast push` (which reads the sidecar).
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

        // 9. Cloud push (only when feed == hosted)
        var pushedToCloud = false
        if case .hosted = config.updates.feed, let entry, !dryRun, let token = hostedToken {
            guard let baseURL = URL(string: environment["SHIPCAST_BASE_URL"] ?? "https://shipcast.devmafex.com") else {
                throw ShipcastError.config(
                    "SHIPCAST_BASE_URL is not a valid URL: \(environment["SHIPCAST_BASE_URL"] ?? "")",
                    fix: "Set SHIPCAST_BASE_URL to a full URL like https://shipcast.devmafex.com or unset it to use the default"
                )
            }

            if let cloudPushFn = cloudPush {
                try cloudPushFn(entry, token, baseURL)
            } else {
                try CloudClient(appSlug: slugify(config.app.name), sha256: packaged.sha256)
                    .push(release: entry, token: token, baseURL: baseURL)
            }
            pushedToCloud = true
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

    /// Deterministic GitHub release asset URL from repo + tag + zip name.
    static func predictedAssetURL(config: ShipcastConfig, zipName: String) throws -> URL {
        guard let repo = config.distribute.githubRepo else {
            throw ShipcastError.config(
                "distribute.github_repo is not set in shipcast.toml",
                fix: "Add github_repo = \"owner/repo\" to the [distribute] section of shipcast.toml"
            )
        }
        let tag = "v\(config.app.version)"
        let escapedZip = zipName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? zipName
        guard let url = URL(string: "https://github.com/\(repo)/releases/download/\(tag)/\(escapedZip)") else {
            throw ShipcastError.config(
                "Cannot construct a valid asset URL from github_repo \"\(repo)\" and artifact \"\(zipName)\"",
                fix: "Check github_repo is \"owner/repo\" with no spaces or special characters"
            )
        }
        return url
    }
}
