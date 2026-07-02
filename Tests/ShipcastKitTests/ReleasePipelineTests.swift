import XCTest
@testable import ShipcastKit

final class ReleasePipelineTests: XCTestCase {
    // Wrapper shell that creates a real zip file when ditto is called
    final class DittoMockShell: ShellRunner {
        let wrapped: MockShellRunner
        var calls: [MockShellRunner.Invocation] { wrapped.calls }

        init(_ wrapped: MockShellRunner) {
            self.wrapped = wrapped
        }

        func stub(command: String, args: [String], result: ShellResult) {
            wrapped.stub(command: command, args: args, result: result)
        }

        func run(_ command: String, args: [String], env: [String: String]?) throws -> ShellResult {
            let basename = (command as NSString).lastPathComponent
            // When ditto is called, create the actual zip file
            if basename == "ditto", args.contains("-c"), args.contains("-k") {
                // Extract the output path (last argument)
                if let zipPath = args.last {
                    try Data("mock zip content".utf8).write(to: URL(fileURLWithPath: zipPath))
                }
            }
            return try wrapped.run(command, args: args, env: env)
        }
    }

    func makeShell() -> DittoMockShell {
        let mock = MockShellRunner()
        mock.stub(command: "swift", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        mock.stub(command: "chmod", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        mock.stub(command: "sips", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        mock.stub(command: "iconutil", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        mock.stub(command: "codesign", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        mock.stub(command: "security", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        mock.stub(command: "ditto", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        mock.stub(command: "shasum", result: ShellResult(exitCode: 0, stdout: "abc123  Burnt.zip\n", stderr: ""))
        mock.stub(command: "gh", args: ["api", "user", "--jq", ".login"],
                   result: ShellResult(exitCode: 0, stdout: "mafex11\n", stderr: ""))
        mock.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        mock.stub(command: "git", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        mock.stub(command: "sign_update", result: ShellResult(
            exitCode: 0, stdout: "sparkle:edSignature=\"SIG==\" length=\"999\"\n", stderr: ""))
        return DittoMockShell(mock)
    }

    func makeConfig(feed: ShipcastConfig.FeedKind) -> ShipcastConfig {
        var config = ShipcastConfig.fixture()
        config.app.name = "Burnt"
        config.app.bundleID = "dev.mafex.burnt"
        config.app.version = "1.2.0"
        config.app.project = .swiftpm
        config.sign.mode = .adhoc
        config.distribute.githubRepo = "mafex11/burnt"
        config.distribute.homebrewTap = "mafex11/homebrew-tap"
        config.distribute.formats = [.zip]
        config.updates.sparkle = true
        config.updates.feed = feed
        return config
    }

    var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/MiniSwiftPM")
    }

    func testFullPipelineOrderAndReport() throws {
        let shell = makeShell()

        // Create mock binary file that SwiftPMBuilder will try to copy
        let buildDir = fixtureRoot.appendingPathComponent(".build/release")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        let mockBinary = buildDir.appendingPathComponent("Burnt")
        try Data("mock binary".utf8).write(to: mockBinary)
        defer { try? FileManager.default.removeItem(at: fixtureRoot.appendingPathComponent(".build")) }

        let pipeline = ReleasePipeline(
            shell: shell,
            environment: ["SPARKLE_PRIVATE_KEY": "b64key"]
        )
        let report = try pipeline.run(config: makeConfig(feed: .selfHosted(url: "https://example.com/appcast.xml")), at: fixtureRoot, dryRun: false)

        // Pipeline order: build (swift) → sign (codesign) → package (ditto) → sparkle sign → gh release → cask push
        let commands = shell.calls.map(\.command)
        let swiftIdx = commands.firstIndex(of: "swift")!
        let codesignIdx = commands.lastIndex(of: "codesign")!
        let dittoIdx = commands.lastIndex(of: "ditto")!
        let signUpdateIdx = commands.firstIndex(of: "sign_update")!
        let ghReleaseIdx = shell.calls.firstIndex { $0.command == "gh" && $0.args.first == "release" }!
        XCTAssertLessThan(swiftIdx, codesignIdx)
        XCTAssertLessThan(codesignIdx, dittoIdx)
        XCTAssertLessThan(dittoIdx, signUpdateIdx)
        XCTAssertLessThan(signUpdateIdx, ghReleaseIdx)

        XCTAssertEqual(report.assetURL.absoluteString,
                       "https://github.com/mafex11/burnt/releases/download/v1.2.0/Burnt.zip")
        XCTAssertEqual(report.edSignature, "SIG==")
        XCTAssertTrue(report.appcastXML.contains("sparkle:edSignature=\"SIG==\""))
        XCTAssertTrue(report.appcastXML.contains("Version 1.2.0"))
        XCTAssertFalse(report.pushedToCloud)
        // Self-hosted: appcast written next to artifacts
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.appcastFileURL!.path))
    }

    func testHostedFeedPushesToCloud() throws {
        let shell = makeShell()

        // Create mock binary
        let buildDir = fixtureRoot.appendingPathComponent(".build/release")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try Data("mock binary".utf8).write(to: buildDir.appendingPathComponent("Burnt"))
        defer { try? FileManager.default.removeItem(at: fixtureRoot.appendingPathComponent(".build")) }

        nonisolated(unsafe) var pushed = false
        let pipeline = ReleasePipeline(
            shell: shell,
            environment: ["SPARKLE_PRIVATE_KEY": "b64key", "SHIPCAST_TOKEN": "sct_secret"],
            cloudPush: { _, _, _ in pushed = true }
        )
        let report = try pipeline.run(config: makeConfig(feed: .hosted), at: fixtureRoot, dryRun: false)
        XCTAssertTrue(pushed)
        XCTAssertTrue(report.pushedToCloud)
    }

    func testFeedNoneSkipsSparkleAndCloud() throws {
        let shell = makeShell()

        // Create mock binary
        let buildDir = fixtureRoot.appendingPathComponent(".build/release")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try Data("mock binary".utf8).write(to: buildDir.appendingPathComponent("Burnt"))
        defer { try? FileManager.default.removeItem(at: fixtureRoot.appendingPathComponent(".build")) }

        var config = makeConfig(feed: .none)
        config.updates.sparkle = false
        let pipeline = ReleasePipeline(shell: shell, environment: [:])
        let report = try pipeline.run(config: config, at: fixtureRoot, dryRun: false)
        XCTAssertFalse(shell.calls.contains { $0.command == "sign_update" })
        XCTAssertEqual(report.edSignature, nil)
        XCTAssertFalse(report.pushedToCloud)
    }

    func testDryRunExecutesBuildSignPackageButNoPublish() throws {
        let shell = makeShell()

        // Create mock binary
        let buildDir = fixtureRoot.appendingPathComponent(".build/release")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try Data("mock binary".utf8).write(to: buildDir.appendingPathComponent("Burnt"))
        defer { try? FileManager.default.removeItem(at: fixtureRoot.appendingPathComponent(".build")) }

        let pipeline = ReleasePipeline(shell: shell, environment: ["SPARKLE_PRIVATE_KEY": "b64key"])
        let report = try pipeline.run(config: makeConfig(feed: .hosted), at: fixtureRoot, dryRun: true)
        // Local stages run
        XCTAssertTrue(shell.calls.contains { $0.command == "ditto" })
        // No remote side effects
        XCTAssertFalse(shell.calls.contains { $0.command == "gh" && $0.args.first == "release" })
        XCTAssertFalse(shell.calls.contains { $0.command == "git" && $0.args.contains("push") })
        XCTAssertFalse(report.pushedToCloud)
        // Report still previews the cask and appcast
        XCTAssertTrue(report.caskPreview!.contains("cask \"burnt\""))
        XCTAssertTrue(report.appcastXML.contains("Version 1.2.0"))
    }

    func testPublishFailurePropagatesExitCode5() throws {
        let shell = makeShell()

        // Create mock binary
        let buildDir = fixtureRoot.appendingPathComponent(".build/release")
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try Data("mock binary".utf8).write(to: buildDir.appendingPathComponent("Burnt"))
        defer { try? FileManager.default.removeItem(at: fixtureRoot.appendingPathComponent(".build")) }

        shell.stub(command: "gh", args: ["release"], result: ShellResult(exitCode: 1, stdout: "", stderr: "HTTP 401"))
        let pipeline = ReleasePipeline(shell: shell, environment: ["SPARKLE_PRIVATE_KEY": "b64key"])
        XCTAssertThrowsError(try pipeline.run(config: makeConfig(feed: .none), at: fixtureRoot, dryRun: false)) { error in
            XCTAssertEqual((error as? ShipcastError)?.exitCode, 5)
        }
    }
}
