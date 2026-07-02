import Foundation

public final class CaskPublisher: @unchecked Sendable {
    let shell: any ShellRunner
    public private(set) var lastWrittenCaskURL: URL?

    public init(shell: any ShellRunner) {
        self.shell = shell
    }

    public func publish(cask: String, config: ShipcastConfig) throws {
        guard let tap = config.distribute.homebrewTap else {
            throw ShipcastError.config(
                "distribute.homebrew_tap is not set in shipcast.toml",
                fix: "Add homebrew_tap = \"owner/homebrew-tap\" to the [distribute] section of shipcast.toml"
            )
        }
        let tapOwner = String(tap.split(separator: "/")[0])
        let tapRepoName = String(tap.split(separator: "/")[1])
        let token = slugify(config.app.name)
        let version = config.app.version

        let whoami = try shell.run("gh", args: ["api", "user", "--jq", ".login"], env: nil)
        guard whoami.exitCode == 0 else {
            throw ShipcastError.publish(
                "gh api user failed (exit \(whoami.exitCode)): \(whoami.stderr)",
                fix: "Authenticate the GitHub CLI: `gh auth login`"
            )
        }
        let login = whoami.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownsTap = (login == tapOwner)

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipcast-tap-\(UUID().uuidString)")

        if !ownsTap {
            // Fork the tap under the user's account (idempotent if fork exists)
            _ = try shell.run("gh", args: ["repo", "fork", tap, "--clone=false"], env: nil)
        }

        // Clone the fork if non-owner, or the original tap if owner
        let cloneSource = ownsTap ? tap : "\(login)/\(tapRepoName)"
        let cloneURL = "https://github.com/\(cloneSource).git"
        let clone = try shell.run("git", args: ["clone", "--depth", "1", cloneURL, workDir.path], env: nil)
        guard clone.exitCode == 0 else {
            throw ShipcastError.publish(
                "git clone \(cloneURL) failed (exit \(clone.exitCode)): \(clone.stderr)",
                fix: "Verify the tap repo exists and you can read it: `gh repo view \(tap)`"
            )
        }

        let casksDir = workDir.appendingPathComponent("Casks")
        try FileManager.default.createDirectory(at: casksDir, withIntermediateDirectories: true)
        let caskURL = casksDir.appendingPathComponent("\(token).rb")
        try cask.write(to: caskURL, atomically: true, encoding: .utf8)
        lastWrittenCaskURL = caskURL

        let branch = ownsTap ? "main" : "shipcast/\(token)-\(version)"
        if !ownsTap {
            _ = try shell.run("git", args: ["-C", workDir.path, "checkout", "-b", branch], env: nil)
        }
        let add = try shell.run("git", args: ["-C", workDir.path, "add", "Casks/\(token).rb"], env: nil)
        guard add.exitCode == 0 else {
            throw ShipcastError.publish(
                "git add Casks/\(token).rb failed (exit \(add.exitCode)): \(add.stderr)",
                fix: "Check the tap clone at \(workDir.path) is writable and retry `shipcast release`"
            )
        }
        let commitMessage = ownsTap ? "Update \(token) to \(version)" : "Add \(token) \(version)"
        let commit = try shell.run("git", args: ["-C", workDir.path, "commit", "-m", commitMessage], env: nil)
        guard commit.exitCode == 0 else {
            throw ShipcastError.publish(
                "git commit in tap clone failed (exit \(commit.exitCode)): \(commit.stderr)\(commit.stdout.isEmpty ? "" : "\n\(commit.stdout)")",
                fix: "If the cask is unchanged the version may already be published; otherwise configure git identity (`git config --global user.email ...`) and retry"
            )
        }

        let push = try shell.run("git", args: ["-C", workDir.path, "push", "origin", branch], env: nil)
        guard push.exitCode == 0 else {
            throw ShipcastError.publish(
                "git push to \(cloneURL) failed (exit \(push.exitCode)): \(push.stderr)",
                fix: "Check push permission with `gh auth status`; if you don't own \(tap), Shipcast opens a PR instead — verify your fork exists with `gh repo view \(login)/\(tapRepoName)`"
            )
        }

        if !ownsTap {
            let pr = try shell.run("gh", args: [
                "pr", "create",
                "--repo", tap,
                "--title", "Add \(token) \(version)",
                "--body", "Automated cask update from shipcast release.",
                "--head", "\(login):\(branch)",
            ], env: nil)
            guard pr.exitCode == 0 else {
                throw ShipcastError.publish(
                    "gh pr create against \(tap) failed (exit \(pr.exitCode)): \(pr.stderr)",
                    fix: "Open the PR manually: push branch \(branch) to your fork and run `gh pr create --repo \(tap)`"
                )
            }
        }

        // Leave workDir in /tmp for OS cleanup; test code may need to inspect lastWrittenCaskURL
    }
}
