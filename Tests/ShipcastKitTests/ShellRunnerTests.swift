import XCTest
@testable import ShipcastKit

final class ShellRunnerTests: XCTestCase {
    func testMockShellRunnerRecordsInvocations() {
        let mock = MockShellRunner()
        mock.stub(command: "echo", result: ShellResult(exitCode: 0, stdout: "hello", stderr: ""))

        let result = try! mock.run("echo", args: ["test"], env: [:])

        XCTAssertEqual(result.stdout, "hello")
        XCTAssertEqual(mock.invocations.count, 1)
        XCTAssertEqual(mock.invocations[0].command, "echo")
        XCTAssertEqual(mock.invocations[0].args, ["test"])
    }

    func testMockShellRunnerThrowsIfNotStubbed() {
        let mock = MockShellRunner()
        XCTAssertThrowsError(try mock.run("unknown", args: [], env: [:]))
    }

    func testProcessShellRunnerExecutesRealCommand() throws {
        let runner = ProcessShellRunner()
        let result = try runner.run("/bin/echo", args: ["hello"], env: [:])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertEqual(result.stdout.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines), "hello")
    }

    func testProcessShellRunnerCapturesNonZeroExit() throws {
        let runner = ProcessShellRunner()
        let result = try runner.run("/bin/sh", args: ["-c", "exit 42"], env: [:])
        XCTAssertEqual(result.exitCode, 42)
    }
}
