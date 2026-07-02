import XCTest
@testable import ShipcastKit

final class GitHubReleaserTests: XCTestCase {
    func makeArtifacts() -> PackagedArtifacts {
        PackagedArtifacts(
            zipURL: URL(fileURLWithPath: "/tmp/Burnt.zip"),
            dmgURL: URL(fileURLWithPath: "/tmp/Burnt-1.2.0.dmg"),
            sha256: "abc123",
            lengthBytes: 12345678
        )
    }

    func makeConfig() -> ShipcastConfig {
        var config = ShipcastConfig.fixture()
        config.app.name = "Burnt"
        config.app.version = "1.2.0"
        config.distribute.githubRepo = "mafex11/burnt"
        return config
    }

    func testCreateReleaseUploadsAssetsAndReturnsAssetURL() throws {
        let shell = MockShellRunner()
        shell.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "https://github.com/mafex11/burnt/releases/tag/v1.2.0\n", stderr: ""))
        let releaser = GitHubReleaser(shell: shell)

        let assetURL = try releaser.createRelease(config: makeConfig(), artifacts: makeArtifacts(), notes: "Fixed bugs")

        let call = shell.calls[0]
        XCTAssertEqual(call.command, "gh")
        XCTAssertEqual(Array(call.args.prefix(3)), ["release", "create", "v1.2.0"])
        XCTAssertTrue(call.args.contains("/tmp/Burnt.zip"))
        XCTAssertTrue(call.args.contains("/tmp/Burnt-1.2.0.dmg"))
        XCTAssertTrue(call.args.contains("--repo"))
        XCTAssertTrue(call.args.contains("mafex11/burnt"))
        XCTAssertTrue(call.args.contains("--notes"))
        XCTAssertTrue(call.args.contains("Fixed bugs"))
        XCTAssertEqual(
            assetURL.absoluteString,
            "https://github.com/mafex11/burnt/releases/download/v1.2.0/Burnt.zip"
        )
    }

    func testNoDMGUploadsZipOnly() throws {
        let shell = MockShellRunner()
        shell.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        var artifacts = makeArtifacts()
        artifacts.dmgURL = nil
        _ = try GitHubReleaser(shell: shell).createRelease(config: makeConfig(), artifacts: artifacts, notes: "")
        XCTAssertFalse(shell.calls[0].args.contains("/tmp/Burnt-1.2.0.dmg"))
    }

    func testGHFailureThrowsPublishErrorWithFix() throws {
        let shell = MockShellRunner()
        shell.stub(command: "gh", result: ShellResult(exitCode: 1, stdout: "", stderr: "HTTP 401: Bad credentials"))
        XCTAssertThrowsError(try GitHubReleaser(shell: shell).createRelease(config: makeConfig(), artifacts: makeArtifacts(), notes: "")) { error in
            guard case ShipcastError.publish(let message, let fix) = error else {
                return XCTFail("expected .publish, got \(error)")
            }
            XCTAssertTrue(message.contains("gh release create"))
            XCTAssertTrue(message.contains("Bad credentials"))
            XCTAssertTrue(fix.contains("gh auth login"))
        }
    }

    func testMissingRepoThrowsConfigError() throws {
        var config = makeConfig()
        config.distribute.githubRepo = nil
        XCTAssertThrowsError(try GitHubReleaser(shell: MockShellRunner()).createRelease(config: config, artifacts: makeArtifacts(), notes: "")) { error in
            guard case ShipcastError.config(_, let fix) = error else {
                return XCTFail("expected .config, got \(error)")
            }
            XCTAssertTrue(fix.contains("github_repo"))
        }
    }
}
