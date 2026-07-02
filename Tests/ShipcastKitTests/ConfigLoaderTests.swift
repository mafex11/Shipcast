import XCTest
@testable import ShipcastKit

final class ConfigLoaderTests: XCTestCase {
    func testLoadValidConfig() throws {
        let fixtureURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/valid-shipcast.toml")

        let config = try ConfigLoader.load(from: fixtureURL)

        XCTAssertEqual(config.app.name, "TestApp")
        XCTAssertEqual(config.app.bundleID, "dev.test.app")
        XCTAssertEqual(config.app.version, "1.0.0")
        XCTAssertEqual(config.app.project, .swiftpm)
        XCTAssertEqual(config.sign.mode, .adhoc)
        XCTAssertEqual(config.distribute.formats, [.zip, .dmg])
        XCTAssertEqual(config.permissions.count, 1)
        XCTAssertEqual(config.permissions[0], .accessibility)
    }

    func testMissingRequiredFieldThrows() {
        let invalidTOML = """
        [app]
        name = "Test"
        """
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid.toml")
        try! invalidTOML.write(to: tempURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ConfigLoader.load(from: tempURL)) { error in
            guard case .config(let msg, let fix) = error as? ShipcastError else {
                XCTFail("Expected ShipcastError.config")
                return
            }
            XCTAssertTrue(msg.contains("parse"))
            XCTAssertTrue(fix.contains("syntax"))
        }

        try? FileManager.default.removeItem(at: tempURL)
    }
}
