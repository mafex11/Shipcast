import XCTest
@testable import ShipcastKit

final class InfoPlistGeneratorTests: XCTestCase {
    func testGenerateInfoPlist() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appURL = tempDir.appendingPathComponent("Test.app")
        let contentsURL = appURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)

        let artifact = BuildArtifact(
            appURL: appURL,
            appName: "TestApp",
            bundleID: "dev.test.app",
            version: "1.0.0"
        )

        let config = ShipcastConfig(
            app: .init(name: "TestApp", bundleID: "dev.test.app", version: "1.0.0", project: .swiftpm),
            sign: .init(mode: .adhoc),
            distribute: .init(githubRelease: false, githubRepo: nil, homebrewTap: nil, formats: [.zip]),
            updates: .init(sparkle: false, feed: .none),
            permissions: []
        )

        let plistURL = try InfoPlistGenerator.generate(for: artifact, config: config)

        XCTAssertTrue(FileManager.default.fileExists(atPath: plistURL.path))

        let plist = try PropertyListSerialization.propertyList(
            from: Data(contentsOf: plistURL),
            options: [],
            format: nil
        ) as! [String: Any]

        XCTAssertEqual(plist["CFBundleIdentifier"] as? String, "dev.test.app")
        XCTAssertEqual(plist["CFBundleName"] as? String, "TestApp")
        XCTAssertEqual(plist["CFBundleVersion"] as? String, "1.0.0")
        XCTAssertEqual(plist["CFBundleShortVersionString"] as? String, "1.0.0")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "TestApp")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "14.0")
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
    }
}
