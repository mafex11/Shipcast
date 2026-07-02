import XCTest
@testable import ShipcastKit

final class ErrorRenderingTests: XCTestCase {
    func testExitCodes() {
        XCTAssertEqual(ShipcastError.config("test", fix: "fix").exitCode, 2)
        XCTAssertEqual(ShipcastError.signing("test", fix: "fix").exitCode, 3)
        XCTAssertEqual(ShipcastError.notarization("test", fix: "fix").exitCode, 4)
        XCTAssertEqual(ShipcastError.publish("test", fix: "fix").exitCode, 5)
        XCTAssertEqual(ShipcastError.generic("test", fix: "fix").exitCode, 1)
    }

    func testErrorRendering() {
        let error = ShipcastError.signing(
            "codesign --sign 'Developer ID' MyApp.app",
            fix: "Import certificate:\n1. Download from Apple Developer\n2. Double-click .cer"
        )
        let rendered = error.render()
        XCTAssertTrue(rendered.contains("Error: Code signing failed"))
        XCTAssertTrue(rendered.contains("Command: codesign"))
        XCTAssertTrue(rendered.contains("Fix: Import certificate"))
    }
}
