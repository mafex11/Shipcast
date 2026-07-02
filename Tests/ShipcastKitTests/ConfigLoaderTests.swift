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

    func testInvalidProjectValueThrows() {
        let validBase = """
        [app]
        name = "TestApp"
        bundle_id = "dev.test.app"
        version = "1.0.0"
        project = "foo"

        [sign]
        mode = "adhoc"

        [distribute]
        github_release = true
        github_repo = "test/app"
        homebrew_tap = "test/tap"
        formats = ["zip", "dmg"]

        [updates]
        sparkle = false
        feed = "none"
        """
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-project.toml")
        try! validBase.write(to: tempURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ConfigLoader.load(from: tempURL)) { error in
            guard case .config(let msg, let fix) = error as? ShipcastError else {
                XCTFail("Expected ShipcastError.config")
                return
            }
            XCTAssertTrue(msg.contains("Unknown project type") || msg.contains("foo"))
            XCTAssertTrue(fix.contains("auto") && fix.contains("swiftpm"))
        }

        try? FileManager.default.removeItem(at: tempURL)
    }

    func testInvalidSignModeThrows() {
        let validBase = """
        [app]
        name = "TestApp"
        bundle_id = "dev.test.app"
        version = "1.0.0"
        project = "swiftpm"

        [sign]
        mode = "invalid"

        [distribute]
        github_release = true
        github_repo = "test/app"
        homebrew_tap = "test/tap"
        formats = ["zip", "dmg"]

        [updates]
        sparkle = false
        feed = "none"
        """
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-sign.toml")
        try! validBase.write(to: tempURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ConfigLoader.load(from: tempURL)) { error in
            guard case .config(let msg, let fix) = error as? ShipcastError else {
                XCTFail("Expected ShipcastError.config")
                return
            }
            XCTAssertTrue(msg.contains("Unknown sign mode"))
            XCTAssertTrue(fix.contains("adhoc"))
        }

        try? FileManager.default.removeItem(at: tempURL)
    }

    func testInvalidFeedTypeThrows() {
        let validBase = """
        [app]
        name = "TestApp"
        bundle_id = "dev.test.app"
        version = "1.0.0"
        project = "swiftpm"

        [sign]
        mode = "adhoc"

        [distribute]
        github_release = true
        github_repo = "test/app"
        homebrew_tap = "test/tap"
        formats = ["zip", "dmg"]

        [updates]
        sparkle = false
        feed = "invalid"
        """
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("invalid-feed.toml")
        try! validBase.write(to: tempURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try ConfigLoader.load(from: tempURL)) { error in
            guard case .config(let msg, let fix) = error as? ShipcastError else {
                XCTFail("Expected ShipcastError.config")
                return
            }
            XCTAssertTrue(msg.contains("Unknown feed type"))
            XCTAssertTrue(fix.contains("hosted"))
        }

        try? FileManager.default.removeItem(at: tempURL)
    }
}
