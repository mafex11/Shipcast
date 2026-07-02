import Foundation
import TOMLDecoder

public struct ConfigLoader {
    public static func load(from url: URL) throws -> ShipcastConfig {
        let data = try Data(contentsOf: url)
        let decoder = TOMLDecoder()

        do {
            let rawConfig = try decoder.decode(RawConfig.self, from: data)
            return try rawConfig.toShipcastConfig()
        } catch let error as ShipcastError {
            throw error
        } catch {
            throw ShipcastError.config(
                "Failed to parse \(url.path)",
                fix: "Check TOML syntax:\n  shipcast init  (to regenerate)\n  Validate at toml-lang.org"
            )
        }
    }
}

// Internal raw TOML representation
private struct RawConfig: Decodable {
    struct App: Decodable {
        var name: String
        var bundle_id: String
        var version: String
        var project: String
    }

    struct Sign: Decodable {
        var mode: String
    }

    struct Distribute: Decodable {
        var github_release: Bool
        var github_repo: String?
        var homebrew_tap: String?
        var formats: [String]
    }

    struct Updates: Decodable {
        var sparkle: Bool
        var feed: String
    }

    struct Permissions: Decodable {
        var accessibility: Bool?
        var screen_recording: Bool?
        var full_disk_access: Bool?
    }

    var app: App
    var sign: Sign
    var distribute: Distribute
    var updates: Updates
    var permissions: Permissions?

    func toShipcastConfig() throws -> ShipcastConfig {
        let projectKind: ShipcastConfig.ProjectKind
        if app.project == "auto" {
            projectKind = .auto
        } else if app.project == "swiftpm" {
            projectKind = .swiftpm
        } else if app.project.hasPrefix("xcode:") {
            let parts = app.project.dropFirst(6).split(separator: "/", maxSplits: 1)
            guard parts.count == 2 else {
                throw ShipcastError.config(
                    "Invalid xcode project format: \(app.project)",
                    fix: "Use format: xcode:MyApp.xcodeproj/MyScheme"
                )
            }
            projectKind = .xcode(project: String(parts[0]), scheme: String(parts[1]))
        } else {
            throw ShipcastError.config(
                "Unknown project type: \(app.project)",
                fix: "Valid values: auto, swiftpm, xcode:Project.xcodeproj/Scheme"
            )
        }

        guard let signMode = SignMode(rawValue: sign.mode) else {
            throw ShipcastError.config(
                "Unknown sign mode: \(sign.mode)",
                fix: "Valid values: auto, adhoc, developer-id"
            )
        }

        let formats = try distribute.formats.map { formatStr -> ArtifactFormat in
            guard let format = ArtifactFormat(rawValue: formatStr) else {
                throw ShipcastError.config(
                    "Unknown format: \(formatStr)",
                    fix: "Valid values: zip, dmg"
                )
            }
            return format
        }

        let feedKind: ShipcastConfig.FeedKind
        if updates.feed == "hosted" {
            feedKind = .hosted
        } else if updates.feed == "none" {
            feedKind = .none
        } else if updates.feed.hasPrefix("self:") {
            feedKind = .selfHosted(url: String(updates.feed.dropFirst(5)))
        } else {
            throw ShipcastError.config(
                "Unknown feed type: \(updates.feed)",
                fix: "Valid values: hosted, self:<url>, none"
            )
        }

        var tccServices: [TCCService] = []
        if let perms = permissions {
            if perms.accessibility == true { tccServices.append(.accessibility) }
            if perms.screen_recording == true { tccServices.append(.screenRecording) }
            if perms.full_disk_access == true { tccServices.append(.fullDiskAccess) }
        }

        return ShipcastConfig(
            app: .init(
                name: app.name,
                bundleID: app.bundle_id,
                version: app.version,
                project: projectKind
            ),
            sign: .init(mode: signMode),
            distribute: .init(
                githubRelease: distribute.github_release,
                githubRepo: distribute.github_repo,
                homebrewTap: distribute.homebrew_tap,
                formats: formats
            ),
            updates: .init(sparkle: updates.sparkle, feed: feedKind),
            permissions: tccServices
        )
    }
}
