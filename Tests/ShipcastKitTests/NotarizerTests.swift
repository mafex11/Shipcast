import XCTest
@testable import ShipcastKit

final class NotarizerTests: XCTestCase {
    func testDryRunMode() throws {
        let mock = MockShellRunner()

        // Stub ditto zip
        mock.stub(command: "/usr/bin/ditto", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))

        let artifact = BuildArtifact(
            appURL: URL(fileURLWithPath: "/tmp/Test.app"),
            appName: "Test",
            bundleID: "dev.test",
            version: "1.0.0"
        )

        // Dry-run should NOT call notarytool
        XCTAssertNoThrow(try Notarizer.notarize(artifact, shell: mock, dryRun: true))

        // Verify ditto was called but not notarytool
        XCTAssertTrue(mock.invocations.contains { $0.command == "/usr/bin/ditto" })
        XCTAssertFalse(mock.invocations.contains { $0.command.contains("notarytool") })
    }

    func testNotarizationWithCredentials() throws {
        let mock = MockShellRunner()

        // Stub ditto zip
        mock.stub(command: "/usr/bin/ditto", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))

        // Stub notarytool submit
        mock.stub(command: "/usr/bin/xcrun", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))

        let artifact = BuildArtifact(
            appURL: URL(fileURLWithPath: "/tmp/Test.app"),
            appName: "Test",
            bundleID: "dev.test",
            version: "1.0.0"
        )

        let environment = [
            "APPLE_ID": "test@example.com",
            "APPLE_TEAM_ID": "ABC123XYZ1",
            "APPLE_APP_PASSWORD": "xxxx-xxxx-xxxx-xxxx"
        ]

        XCTAssertNoThrow(try Notarizer.notarize(artifact, shell: mock, dryRun: false, environment: environment))

        // Verify all steps were called
        XCTAssertTrue(mock.invocations.contains { $0.command == "/usr/bin/ditto" })
        XCTAssertTrue(mock.invocations.contains { inv in
            inv.command == "/usr/bin/xcrun" && inv.args.contains("notarytool")
        })
        XCTAssertTrue(mock.invocations.contains { inv in
            inv.command == "/usr/bin/xcrun" && inv.args.contains("stapler")
        })
    }

    func testMissingCredentialsThrows() throws {
        let mock = MockShellRunner()
        mock.stub(command: "/usr/bin/ditto", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))

        let artifact = BuildArtifact(
            appURL: URL(fileURLWithPath: "/tmp/Test.app"),
            appName: "Test",
            bundleID: "dev.test",
            version: "1.0.0"
        )

        let environment: [String: String] = [:]

        XCTAssertThrowsError(try Notarizer.notarize(artifact, shell: mock, dryRun: false, environment: environment)) { error in
            guard let shipcastError = error as? ShipcastError else {
                XCTFail("Expected ShipcastError")
                return
            }
            if case .notarization = shipcastError {
                // Expected
            } else {
                XCTFail("Expected notarization error")
            }
        }
    }

    func testDittoFailureThrows() throws {
        let mock = MockShellRunner()
        mock.stub(command: "/usr/bin/ditto", result: ShellResult(
            exitCode: 1,
            stdout: "",
            stderr: "ditto: error opening /tmp/Test.app"
        ))

        let artifact = BuildArtifact(
            appURL: URL(fileURLWithPath: "/tmp/Test.app"),
            appName: "Test",
            bundleID: "dev.test",
            version: "1.0.0"
        )

        let environment = [
            "APPLE_ID": "test@example.com",
            "APPLE_TEAM_ID": "ABC123XYZ1",
            "APPLE_APP_PASSWORD": "xxxx-xxxx-xxxx-xxxx"
        ]

        XCTAssertThrowsError(try Notarizer.notarize(artifact, shell: mock, dryRun: false, environment: environment)) { error in
            guard let shipcastError = error as? ShipcastError else {
                XCTFail("Expected ShipcastError")
                return
            }
            if case .notarization(_, _) = shipcastError {
                // Expected
            } else {
                XCTFail("Expected notarization error")
            }
        }
    }

    func testNotarytoolFailureThrows() throws {
        let mock = MockShellRunner()
        mock.stub(command: "/usr/bin/ditto", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        mock.stub(command: "/usr/bin/xcrun", result: ShellResult(
            exitCode: 1,
            stdout: "",
            stderr: "notarytool: submission failed"
        ))

        let artifact = BuildArtifact(
            appURL: URL(fileURLWithPath: "/tmp/Test.app"),
            appName: "Test",
            bundleID: "dev.test",
            version: "1.0.0"
        )

        let environment = [
            "APPLE_ID": "test@example.com",
            "APPLE_TEAM_ID": "ABC123XYZ1",
            "APPLE_APP_PASSWORD": "xxxx-xxxx-xxxx-xxxx"
        ]

        XCTAssertThrowsError(try Notarizer.notarize(artifact, shell: mock, dryRun: false, environment: environment)) { error in
            guard let shipcastError = error as? ShipcastError else {
                XCTFail("Expected ShipcastError")
                return
            }
            if case .notarization(_, _) = shipcastError {
                // Expected
            } else {
                XCTFail("Expected notarization error")
            }
        }
    }
}
