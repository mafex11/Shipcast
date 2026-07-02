import XCTest
@testable import ShipcastKit

final class SignerTests: XCTestCase {
    func testAdHocSign() throws {
        let fixtureRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/MiniSwiftPM")

        let config = try ConfigLoader.load(from: fixtureRoot.appendingPathComponent("shipcast.toml"))
        let shell = ProcessShellRunner()
        let artifact = try SwiftPMBuilder.build(config: config, at: fixtureRoot, shell: shell)

        let signed = try Signer.sign(artifact, config: config, shell: shell)

        XCTAssertEqual(signed.resolvedMode, .adhoc)
        XCTAssertFalse(signed.notarized)

        // Verify signature
        let verifyResult = try shell.run(
            "/usr/bin/codesign",
            args: ["--verify", "--deep", "--strict", signed.app.appURL.path],
            env: nil
        )
        XCTAssertEqual(verifyResult.exitCode, 0, "Signature verification failed: \(verifyResult.stderr)")
    }

    func testAutoDetectionWithoutCert() throws {
        let mock = MockShellRunner()
        mock.stub(command: "/usr/bin/security", result: ShellResult(
            exitCode: 0,
            stdout: "0 valid identities found",
            stderr: ""
        ))

        let artifact = BuildArtifact(
            appURL: URL(fileURLWithPath: "/tmp/Test.app"),
            appName: "Test",
            bundleID: "dev.test",
            version: "1.0.0"
        )

        let config = ShipcastConfig(
            app: .init(name: "Test", bundleID: "dev.test", version: "1.0.0", project: .swiftpm),
            sign: .init(mode: .auto),
            distribute: .init(githubRelease: false, githubRepo: nil, homebrewTap: nil, formats: [.zip]),
            updates: .init(sparkle: false, feed: .none),
            permissions: []
        )

        // Should default to ad-hoc
        mock.stub(command: "/usr/bin/codesign", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))

        let signed = try Signer.sign(artifact, config: config, shell: mock)
        XCTAssertEqual(signed.resolvedMode, .adhoc)
    }
}
