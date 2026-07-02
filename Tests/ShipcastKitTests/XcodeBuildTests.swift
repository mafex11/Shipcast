import XCTest
@testable import ShipcastKit

final class XcodeBuildTests: XCTestCase {
    func makeConfig(mode: SignMode) -> ShipcastConfig {
        var config = ShipcastConfig.fixture() // Plan A test helper
        config.app.name = "MiniXcode"
        config.app.bundleID = "dev.mafex.minixcode"
        config.app.version = "1.0.0"
        config.app.project = .xcode(project: "MiniXcode.xcodeproj", scheme: "MiniXcode")
        config.sign.mode = mode
        return config
    }

    func testArchiveAndExportDeveloperID() throws {
        let shell = MockShellRunner()
        shell.stub(command: "xcodebuild", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        let root = URL(fileURLWithPath: "/tmp/shipcast-xcode-test")
        let builder = XcodeBuilder(shell: shell)

        let artifact = try builder.build(config: makeConfig(mode: .developerID), at: root)

        let archiveCall = shell.calls[0]
        XCTAssertEqual(archiveCall.command, "xcodebuild")
        XCTAssertTrue(archiveCall.args.contains("archive"))
        XCTAssertTrue(archiveCall.args.contains("MiniXcode.xcodeproj"))
        XCTAssertTrue(archiveCall.args.contains("MiniXcode")) // scheme

        let exportCall = shell.calls[1]
        XCTAssertTrue(exportCall.args.contains("-exportArchive"))
        let optionsIndex = exportCall.args.firstIndex(of: "-exportOptionsPlist")!
        let plistPath = exportCall.args[optionsIndex + 1]
        let plistData = try Data(contentsOf: URL(fileURLWithPath: plistPath))
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        XCTAssertEqual(plist["method"] as? String, "developer-id")

        XCTAssertEqual(artifact.appName, "MiniXcode")
        XCTAssertEqual(artifact.bundleID, "dev.mafex.minixcode")
        XCTAssertEqual(artifact.version, "1.0.0")
        XCTAssertTrue(artifact.appURL.path.hasSuffix("MiniXcode.app"))
    }

    func testExportMethodMacApplicationForAdhoc() throws {
        let shell = MockShellRunner()
        shell.stub(command: "xcodebuild", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        let builder = XcodeBuilder(shell: shell)
        _ = try builder.build(config: makeConfig(mode: .adhoc), at: URL(fileURLWithPath: "/tmp/shipcast-xcode-test"))

        let exportCall = shell.calls[1]
        let optionsIndex = exportCall.args.firstIndex(of: "-exportOptionsPlist")!
        let plistData = try Data(contentsOf: URL(fileURLWithPath: exportCall.args[optionsIndex + 1]))
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        XCTAssertEqual(plist["method"] as? String, "mac-application")
    }

    func testArchiveFailureThrowsGenericWithFix() throws {
        let shell = MockShellRunner()
        shell.stub(command: "xcodebuild", result: ShellResult(exitCode: 65, stdout: "", stderr: "error: no scheme"))
        let builder = XcodeBuilder(shell: shell)
        XCTAssertThrowsError(try builder.build(config: makeConfig(mode: .adhoc), at: URL(fileURLWithPath: "/tmp/x"))) { error in
            guard case ShipcastError.generic(let message, let fix) = error else {
                return XCTFail("expected .generic, got \(error)")
            }
            XCTAssertTrue(message.contains("xcodebuild archive"))
            XCTAssertTrue(fix.contains("xcodebuild -list"))
        }
    }

    func testRealXcodeBuildOfMiniXcodeFixture() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SHIPCAST_INTEGRATION"] == "1",
            "Set SHIPCAST_INTEGRATION=1 to run real xcodebuild"
        )
        let fixtureRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/MiniXcode")
        let builder = XcodeBuilder(shell: ProcessShellRunner()) // Plan A concrete runner
        let artifact = try builder.build(config: makeConfig(mode: .adhoc), at: fixtureRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.appURL.path))
    }
}
