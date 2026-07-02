import Foundation

/// Resolves `version = "auto"` in shipcast.toml to the latest git tag of the
/// project. Called at the top of the release pipeline and by each standalone
/// CLI command right after ConfigLoader.load, so no stage ever sees "auto".
public struct VersionResolver {
    public static func resolve(config: ShipcastConfig, at root: URL, shell: any ShellRunner) throws -> ShipcastConfig {
        guard config.app.version == "auto" else { return config }

        let result = try shell.run(
            "git",
            args: ["-C", root.path, "describe", "--tags", "--abbrev=0"],
            env: nil
        )
        let tag = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard result.exitCode == 0, !tag.isEmpty else {
            throw ShipcastError.config(
                "version = \"auto\" but no git tag found in \(root.path)",
                fix: "Tag the release (git tag v1.0.0) or set an explicit version in shipcast.toml"
            )
        }

        var resolved = config
        resolved.app.version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return resolved
    }
}
