import XCTest
@testable import ShipcastKit

final class SwiftPMBuilderTests: XCTestCase {
    func testBuildMiniSwiftPM() throws {
        let fixtureRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/MiniSwiftPM")

        let config = try ConfigLoader.load(from: fixtureRoot.appendingPathComponent("shipcast.toml"))
        let shell = ProcessShellRunner()

        let artifact = try SwiftPMBuilder.build(config: config, at: fixtureRoot, shell: shell)

        XCTAssertEqual(artifact.appName, "MiniSwiftPM")
        XCTAssertEqual(artifact.bundleID, "dev.shipcast.test.miniswiftpm")
        XCTAssertEqual(artifact.version, "1.0.0")
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.appURL.path))

        // Verify .app structure
        let contentsURL = artifact.appURL.appendingPathComponent("Contents")
        XCTAssertTrue(FileManager.default.fileExists(atPath: contentsURL.appendingPathComponent("MacOS/MiniSwiftPM").path))
        // Task 7 uncomments this
        // XCTAssertTrue(FileManager.default.fileExists(atPath: contentsURL.appendingPathComponent("Info.plist").path))
    }
}
