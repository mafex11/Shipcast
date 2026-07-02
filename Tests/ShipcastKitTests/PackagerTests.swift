import XCTest
@testable import ShipcastKit

final class PackagerTests: XCTestCase {
    func testPackageZip() throws {
        let fixtureRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/MiniSwiftPM")

        let config = try ConfigLoader.load(from: fixtureRoot.appendingPathComponent("shipcast.toml"))
        var modifiedConfig = config
        modifiedConfig.distribute.formats = [.zip]  // zip only

        let shell = ProcessShellRunner()
        let artifact = try SwiftPMBuilder.build(config: modifiedConfig, at: fixtureRoot, shell: shell)
        let signed = try Signer.sign(artifact, config: modifiedConfig, shell: shell)

        let packaged = try Packager.package(signed, config: modifiedConfig, shell: shell)

        XCTAssertTrue(FileManager.default.fileExists(atPath: packaged.zipURL.path))
        XCTAssertNil(packaged.dmgURL)
        XCTAssertEqual(packaged.sha256.count, 64)  // SHA256 hex length
        XCTAssertGreaterThan(packaged.lengthBytes, 0)

        // Verify zip contains app
        let unzipDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: unzipDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: unzipDir) }

        let unzipResult = try shell.run(
            "/usr/bin/unzip",
            args: ["-q", packaged.zipURL.path, "-d", unzipDir.path],
            env: nil
        )
        XCTAssertEqual(unzipResult.exitCode, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: unzipDir.appendingPathComponent("MiniSwiftPM.app").path))
    }

    func testPackageDMG() throws {
        // Skip if create-dmg not installed
        let whichResult = try? ProcessShellRunner().run("/usr/bin/which", args: ["create-dmg"], env: nil)
        guard whichResult?.exitCode == 0 else {
            throw XCTSkip("create-dmg not installed")
        }

        let fixtureRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/MiniSwiftPM")

        let config = try ConfigLoader.load(from: fixtureRoot.appendingPathComponent("shipcast.toml"))
        var modifiedConfig = config
        modifiedConfig.distribute.formats = [.zip, .dmg]

        let shell = ProcessShellRunner()
        let artifact = try SwiftPMBuilder.build(config: modifiedConfig, at: fixtureRoot, shell: shell)
        let signed = try Signer.sign(artifact, config: modifiedConfig, shell: shell)

        let packaged = try Packager.package(signed, config: modifiedConfig, shell: shell)

        XCTAssertTrue(FileManager.default.fileExists(atPath: packaged.zipURL.path))
        XCTAssertNotNil(packaged.dmgURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packaged.dmgURL!.path))
    }
}
