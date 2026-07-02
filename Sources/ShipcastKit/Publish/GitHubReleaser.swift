import Foundation

public struct GitHubReleaser: Sendable {
    let shell: any ShellRunner

    public init(shell: any ShellRunner) {
        self.shell = shell
    }

    public func createRelease(config: ShipcastConfig, artifacts: PackagedArtifacts, notes: String) throws -> URL {
        guard let repo = config.distribute.githubRepo else {
            throw ShipcastError.config(
                "distribute.github_repo is not set in shipcast.toml",
                fix: "Add github_repo = \"owner/repo\" to the [distribute] section of shipcast.toml"
            )
        }

        let tag = "v\(config.app.version)"
        var args = ["release", "create", tag,
                    "--repo", repo,
                    "--title", "\(config.app.name) \(config.app.version)",
                    "--notes", notes,
                    artifacts.zipURL.path]
        if let dmg = artifacts.dmgURL {
            args.append(dmg.path)
        }

        let result = try shell.run("gh", args: args, env: nil)
        guard result.exitCode == 0 else {
            throw ShipcastError.publish(
                "gh release create \(tag) failed (exit \(result.exitCode)): \(result.stderr)",
                fix: "Check GitHub auth with `gh auth status`; if unauthenticated run `gh auth login`. If the tag already has a release, delete it with `gh release delete \(tag) --repo \(repo)` or bump the version."
            )
        }

        let zipName = artifacts.zipURL.lastPathComponent
        return URL(string: "https://github.com/\(repo)/releases/download/\(tag)/\(zipName)")!
    }
}
