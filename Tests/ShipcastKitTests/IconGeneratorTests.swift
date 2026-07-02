import XCTest
@testable import ShipcastKit

final class IconGeneratorTests: XCTestCase {
    func testGenerateICNS() throws {
        let fixtureRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/MiniSwiftPM")

        let iconPNG = fixtureRoot.appendingPathComponent("icon.png")
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let outputICNS = tempDir.appendingPathComponent("AppIcon.icns")
        let shell = ProcessShellRunner()

        try IconGenerator.generateICNS(from: iconPNG, to: outputICNS, shell: shell)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputICNS.path))

        // Verify it's a valid ICNS (magic bytes)
        let data = try Data(contentsOf: outputICNS)
        XCTAssertGreaterThan(data.count, 4)
        let magic = String(data: data.prefix(4), encoding: .ascii)
        XCTAssertEqual(magic, "icns")
    }
}
