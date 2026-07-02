import XCTest
@testable import ShipcastKit

final class VersionResolverTests: XCTestCase {
    private func makeConfig(version: String) -> ShipcastConfig {
        var config = ShipcastConfig.fixture()
        config.app.version = version
        return config
    }

    func testAutoResolvesFromGitTagStrippingLeadingV() throws {
        let shell = MockShellRunner()
        shell.stub(command: "git", args: [], result: ShellResult(exitCode: 0, stdout: "v2.1.0\n", stderr: ""))

        let resolved = try VersionResolver.resolve(
            config: makeConfig(version: "auto"),
            at: URL(fileURLWithPath: "/tmp/proj"),
            shell: shell
        )

        XCTAssertEqual(resolved.app.version, "2.1.0")
        // git describe must run against the project root
        let call = try XCTUnwrap(shell.calls.first)
        XCTAssertEqual(call.command, "git")
        XCTAssertEqual(call.args, ["-C", "/tmp/proj", "describe", "--tags", "--abbrev=0"])
    }

    func testAutoWithTagWithoutVPrefixKeepsTagVerbatim() throws {
        let shell = MockShellRunner()
        shell.stub(command: "git", result: ShellResult(exitCode: 0, stdout: "2.1.0\n", stderr: ""))

        let resolved = try VersionResolver.resolve(
            config: makeConfig(version: "auto"),
            at: URL(fileURLWithPath: "/tmp/proj"),
            shell: shell
        )
        XCTAssertEqual(resolved.app.version, "2.1.0")
    }

    func testAutoWithNoTagThrowsConfigError() {
        let shell = MockShellRunner()
        shell.stub(command: "git", result: ShellResult(
            exitCode: 128, stdout: "", stderr: "fatal: No names found, cannot describe anything."))

        XCTAssertThrowsError(try VersionResolver.resolve(
            config: makeConfig(version: "auto"),
            at: URL(fileURLWithPath: "/tmp/proj"),
            shell: shell
        )) { error in
            guard case ShipcastError.config(let message, let fix) = error else {
                return XCTFail("expected .config, got \(error)")
            }
            XCTAssertTrue(message.contains("no git tag found"))
            XCTAssertTrue(fix.contains("git tag v1.0.0"))
        }
    }

    func testExplicitVersionUntouchedAndNoGitCall() throws {
        let shell = MockShellRunner() // no stubs: any shell call would throw
        let config = makeConfig(version: "3.4.5")

        let resolved = try VersionResolver.resolve(
            config: config,
            at: URL(fileURLWithPath: "/tmp/proj"),
            shell: shell
        )
        XCTAssertEqual(resolved, config)
        XCTAssertTrue(shell.calls.isEmpty)
    }
}
