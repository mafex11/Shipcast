import XCTest
@testable import ShipcastKit

final class CaskPublisherTests: XCTestCase {
    private func makeConfig() -> ShipcastConfig {
        var config = ShipcastConfig.fixture()
        config.app.name = "Burnt"
        config.app.version = "1.2.0"
        config.distribute.homebrewTap = "mafex11/homebrew-tap"
        return config
    }

    private let cask = "cask \"burnt\" do\nend\n"

    func testOwnerPushesDirectly() throws {
        let shell = MockShellRunner()
        // gh api user → login matches tap owner
        shell.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "mafex11\n", stderr: ""))
        shell.stub(command: "git", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        try CaskPublisher(shell: shell).publish(cask: cask, config: makeConfig())

        let ghCalls = shell.calls.filter { $0.command == "gh" }
        XCTAssertEqual(ghCalls[0].args, ["api", "user", "--jq", ".login"])
        // No PR when owner
        XCTAssertFalse(shell.calls.contains { $0.command == "gh" && $0.args.first == "pr" })

        let gitArgs = shell.calls.filter { $0.command == "git" }.map(\.args)
        XCTAssertTrue(gitArgs.contains { $0.first == "clone" && $0.contains("https://github.com/mafex11/homebrew-tap.git") })
        XCTAssertTrue(gitArgs.contains { $0.contains("commit") && $0.contains("Update burnt to 1.2.0") })
        XCTAssertTrue(gitArgs.contains { $0.first == "push" || $0.contains("push") })
    }

    func testNonOwnerOpensPR() throws {
        let shell = MockShellRunner()
        shell.stub(command: "gh", args: ["api", "user", "--jq", ".login"],
                   result: ShellResult(exitCode: 0, stdout: "someoneelse\n", stderr: ""))
        shell.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        shell.stub(command: "git", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        try CaskPublisher(shell: shell).publish(cask: cask, config: makeConfig())

        let prCall = shell.calls.first { $0.command == "gh" && $0.args.first == "pr" }
        let pr = try XCTUnwrap(prCall)
        XCTAssertTrue(pr.args.contains("create"))
        XCTAssertTrue(pr.args.contains("--repo"))
        XCTAssertTrue(pr.args.contains("mafex11/homebrew-tap"))
        XCTAssertTrue(pr.args.contains("--title"))
        XCTAssertTrue(pr.args.contains("Add burnt 1.2.0"))
    }

    func testCaskFileWrittenIntoCasksDirectory() throws {
        let shell = MockShellRunner()
        shell.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "mafex11\n", stderr: ""))
        shell.stub(command: "git", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        let publisher = CaskPublisher(shell: shell)
        try publisher.publish(cask: cask, config: makeConfig())
        let written = try String(contentsOf: publisher.lastWrittenCaskURL!, encoding: .utf8)
        XCTAssertEqual(written, cask)
        XCTAssertTrue(publisher.lastWrittenCaskURL!.path.hasSuffix("Casks/burnt.rb"))
    }

    /// Shell wrapper that fails git invocations containing a specific subcommand
    /// (git -C <tmpdir> add/commit/push — the tmpdir is random, so prefix stubs can't target these).
    private final class FailingGitShell: ShellRunner {
        let wrapped: MockShellRunner
        let failingSubcommand: String

        init(failingSubcommand: String) {
            self.failingSubcommand = failingSubcommand
            wrapped = MockShellRunner()
            wrapped.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "mafex11\n", stderr: ""))
            wrapped.stub(command: "git", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        }

        func run(_ command: String, args: [String], env: [String: String]?) throws -> ShellResult {
            if (command as NSString).lastPathComponent == "git", args.contains(failingSubcommand) {
                return ShellResult(exitCode: 1, stdout: "", stderr: "remote: Permission denied")
            }
            return try wrapped.run(command, args: args, env: env)
        }
    }

    func testPushFailureThrowsPublishErrorWithFix() throws {
        let shell = FailingGitShell(failingSubcommand: "push")
        XCTAssertThrowsError(try CaskPublisher(shell: shell).publish(cask: cask, config: makeConfig())) { error in
            guard case ShipcastError.publish(let message, let fix) = error else {
                return XCTFail("expected .publish, got \(error)")
            }
            XCTAssertTrue(message.contains("git push"))
            XCTAssertTrue(message.contains("Permission denied"))
            XCTAssertTrue(fix.contains("gh auth"))
        }
    }

    func testAddFailureThrowsPublishErrorWithStderr() throws {
        let shell = FailingGitShell(failingSubcommand: "add")
        XCTAssertThrowsError(try CaskPublisher(shell: shell).publish(cask: cask, config: makeConfig())) { error in
            guard case ShipcastError.publish(let message, _) = error else {
                return XCTFail("expected .publish, got \(error)")
            }
            XCTAssertTrue(message.contains("git add"))
            XCTAssertTrue(message.contains("Permission denied"))
        }
    }

    func testCommitFailureThrowsPublishErrorWithStderr() throws {
        let shell = FailingGitShell(failingSubcommand: "commit")
        XCTAssertThrowsError(try CaskPublisher(shell: shell).publish(cask: cask, config: makeConfig())) { error in
            guard case ShipcastError.publish(let message, let fix) = error else {
                return XCTFail("expected .publish, got \(error)")
            }
            XCTAssertTrue(message.contains("git commit"))
            XCTAssertTrue(fix.contains("git config"))
        }
    }

    func testMissingTapThrowsConfigError() throws {
        var config = makeConfig()
        config.distribute.homebrewTap = nil
        XCTAssertThrowsError(try CaskPublisher(shell: MockShellRunner()).publish(cask: cask, config: config)) { error in
            guard case ShipcastError.config(_, let fix) = error else {
                return XCTFail("expected .config, got \(error)")
            }
            XCTAssertTrue(fix.contains("homebrew_tap"))
        }
    }
}
