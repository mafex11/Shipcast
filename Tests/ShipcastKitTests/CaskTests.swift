import XCTest
@testable import ShipcastKit

final class CaskTests: XCTestCase {
    private func golden(_ name: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Golden/\(name)")
        return try String(contentsOf: url, encoding: .utf8)
    }

    private func makeConfig(mode: SignMode, permissions: [TCCService]) -> ShipcastConfig {
        var config = ShipcastConfig.fixture()
        config.app.name = "Burnt"
        config.app.bundleID = "dev.mafex.burnt"
        config.app.version = "1.2.0"
        config.sign.mode = mode
        config.distribute.githubRepo = "mafex11/burnt"
        config.permissions = permissions
        return config
    }

    private var artifacts: PackagedArtifacts {
        PackagedArtifacts(
            zipURL: URL(fileURLWithPath: "/tmp/Burnt.zip"),
            dmgURL: nil,
            sha256: "abc123",
            lengthBytes: 12345678
        )
    }

    private var releaseURL: URL {
        URL(string: "https://github.com/mafex11/burnt/releases/download/v1.2.0/Burnt.zip")!
    }

    func testAdhocCaskMatchesGolden() throws {
        let config = makeConfig(mode: .adhoc, permissions: [.accessibility, .screenRecording])
        let cask = CaskGenerator().generate(config: config, artifacts: artifacts, releaseURL: releaseURL)
        XCTAssertEqual(cask, try golden("burnt-adhoc.rb"))
    }

    func testNotarizedCaskMatchesGolden() throws {
        let config = makeConfig(mode: .developerID, permissions: [.accessibility, .screenRecording])
        let cask = CaskGenerator().generate(config: config, artifacts: artifacts, releaseURL: releaseURL)
        XCTAssertEqual(cask, try golden("burnt-notarized.rb"))
    }

    func testAdhocWithNoPermissionsStillStripsQuarantine() throws {
        let config = makeConfig(mode: .adhoc, permissions: [])
        let cask = CaskGenerator().generate(config: config, artifacts: artifacts, releaseURL: releaseURL)
        XCTAssertTrue(cask.contains("com.apple.quarantine"))
        XCTAssertFalse(cask.contains("tccutil"))
    }

    func testFullDiskAccessMapsToSystemPolicyAllFiles() throws {
        let config = makeConfig(mode: .adhoc, permissions: [.fullDiskAccess])
        let cask = CaskGenerator().generate(config: config, artifacts: artifacts, releaseURL: releaseURL)
        XCTAssertTrue(cask.contains(#"args: ["reset", "SystemPolicyAllFiles", "dev.mafex.burnt"]"#))
    }

    func testAutoModeResolvedToDeveloperIDHasNoPostflight() throws {
        // mode = "auto" in the config, but signing resolved to Developer ID + notarized:
        // the cask must NOT strip quarantine or reset TCC (that would wipe grants each update)
        let config = makeConfig(mode: .auto, permissions: [.accessibility, .screenRecording])
        let cask = CaskGenerator().generate(
            config: config, artifacts: artifacts, releaseURL: releaseURL, resolvedMode: .developerID)
        XCTAssertFalse(cask.contains("postflight"))
        XCTAssertFalse(cask.contains("com.apple.quarantine"))
        XCTAssertFalse(cask.contains("tccutil"))
        XCTAssertEqual(cask, try golden("burnt-notarized.rb"))
    }

    func testAutoModeResolvedToAdhocKeepsPostflight() throws {
        let config = makeConfig(mode: .auto, permissions: [.accessibility, .screenRecording])
        let cask = CaskGenerator().generate(
            config: config, artifacts: artifacts, releaseURL: releaseURL, resolvedMode: .adhoc)
        XCTAssertEqual(cask, try golden("burnt-adhoc.rb"))
    }

    func testCaskTokenUsesSlugifiedName() throws {
        var config = makeConfig(mode: .adhoc, permissions: [])
        config.app.name = "My App"
        let cask = CaskGenerator().generate(config: config, artifacts: artifacts, releaseURL: releaseURL)
        XCTAssertTrue(cask.hasPrefix("cask \"my-app\" do"))
    }
}

final class SlugifyTests: XCTestCase {
    func testLowercasesAndHyphenatesWhitespace() {
        XCTAssertEqual(slugify("My App"), "my-app")
        XCTAssertEqual(slugify("My   Cool App"), "my-cool-app")
    }

    func testStripsUnsafeCharacters() {
        XCTAssertEqual(slugify("Burnt!"), "burnt")
        XCTAssertEqual(slugify("Café App"), "caf-app")
        XCTAssertEqual(slugify("app_2.0"), "app20")
    }

    func testTrimsLeadingAndTrailingHyphens() {
        XCTAssertEqual(slugify("  My App  "), "my-app")
        XCTAssertEqual(slugify("-weird-"), "weird")
    }

    func testSimpleNameUnchanged() {
        XCTAssertEqual(slugify("burnt"), "burnt")
        XCTAssertEqual(slugify("Burnt"), "burnt")
    }
}
