import XCTest
@testable import ShipcastKit

final class EndToEndTests: XCTestCase {
    func testFullPipelineMiniSwiftPM() throws {
        let fixtureRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/MiniSwiftPM")

        let config = try ConfigLoader.load(from: fixtureRoot.appendingPathComponent("shipcast.toml"))
        let shell = ProcessShellRunner()

        // Build
        let artifact = try SwiftPMBuilder.build(config: config, at: fixtureRoot, shell: shell)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.appURL.path))

        // Sign
        let signed = try Signer.sign(artifact, config: config, shell: shell)
        XCTAssertEqual(signed.resolvedMode, .adhoc)

        // Package
        let packaged = try Packager.package(signed, config: config, shell: shell)
        XCTAssertTrue(FileManager.default.fileExists(atPath: packaged.zipURL.path))
        XCTAssertEqual(packaged.sha256.count, 64)
        XCTAssertGreaterThan(packaged.lengthBytes, 0)

        print("✓ End-to-end test passed")
        print("  Zip: \(packaged.zipURL.path)")
        print("  SHA256: \(packaged.sha256)")
    }
}
