import Foundation

public struct CaskGenerator: Sendable {
    public init() {}

    /// - Parameter resolvedMode: the signing mode actually used (from
    ///   SignedArtifact.resolvedMode). With mode = "auto" the configured mode says
    ///   nothing about whether the app was notarized; branching the postflight on
    ///   the configured mode would wipe TCC grants for notarized apps on every
    ///   update. Defaults to the configured mode for call sites without a
    ///   SignedArtifact.
    public func generate(config: ShipcastConfig, artifacts: PackagedArtifacts, releaseURL: URL, resolvedMode: SignMode? = nil) -> String {
        let effectiveMode = resolvedMode ?? config.sign.mode
        let token = slugify(config.app.name)
        let bundleID = config.app.bundleID
        let appName = config.app.name
        let repo = config.distribute.githubRepo ?? ""
        // Cask url interpolates #{version}; swap the literal version segment back out.
        let templatedURL = releaseURL.absoluteString
            .replacingOccurrences(of: "/v\(config.app.version)/", with: "/v#{version}/")

        var lines: [String] = []
        lines.append("cask \"\(token)\" do")
        lines.append("  version \"\(config.app.version)\"")
        lines.append("  sha256 \"\(artifacts.sha256)\"")
        lines.append("")
        lines.append("  url \"\(templatedURL)\"")
        lines.append("  name \"\(appName)\"")
        lines.append("  desc \"\(appName) for macOS\"")
        lines.append("  homepage \"https://github.com/\(repo)\"")
        lines.append("")
        lines.append("  livecheck do")
        lines.append("    url :url")
        lines.append("    strategy :github_latest")
        lines.append("  end")
        lines.append("")
        lines.append("  app \"\(appName).app\"")
        lines.append("")

        if effectiveMode != .developerID {
            lines.append("  postflight do")
            lines.append("    system_command \"/usr/bin/xattr\",")
            lines.append("                   args: [\"-dr\", \"com.apple.quarantine\", \"#{appdir}/\(appName).app\"]")
            if !config.permissions.isEmpty {
                lines.append("")
                for service in config.permissions {
                    lines.append("    system_command \"/usr/bin/tccutil\",")
                    lines.append("                   args: [\"reset\", \"\(service.rawValue)\", \"\(bundleID)\"]")
                }
            }
            lines.append("  end")
            lines.append("")
        }

        lines.append("  uninstall quit: \"\(bundleID)\"")
        lines.append("")
        lines.append("  zap trash: [")
        lines.append("    \"~/Library/Preferences/\(bundleID).plist\",")
        lines.append("    \"~/Library/Application Support/\(appName)\",")
        lines.append("    \"~/Library/Caches/\(bundleID)\",")
        lines.append("  ]")
        lines.append("end")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
