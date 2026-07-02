import XCTest
@testable import ShipcastKit

final class AppcastTests: XCTestCase {
    private func date(_ iso: String) -> Date {
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: iso)!
    }

    private var entries: [AppcastEntry] {
        [
            AppcastEntry(
                version: "1.1.0",
                artifactURL: URL(string: "https://github.com/mafex11/burnt/releases/download/v1.1.0/Burnt.zip")!,
                edSignature: "OLDSIG==",
                lengthBytes: 12_000_000,
                minSystemVersion: nil,
                notesHTML: nil,
                pubDate: date("2026-06-01T12:00:00Z")
            ),
            AppcastEntry(
                version: "1.2.0",
                artifactURL: URL(string: "https://github.com/mafex11/burnt/releases/download/v1.2.0/Burnt.zip")!,
                edSignature: "MEUCIQDtest+sig==",
                lengthBytes: 12_345_678,
                minSystemVersion: "14.0",
                notesHTML: "<p>Fixed bugs</p>",
                pubDate: date("2026-07-01T12:00:00Z")
            ),
        ]
    }

    func testGeneratedXMLMatchesGolden() throws {
        let goldenURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/Golden/appcast.xml")
        let golden = try String(contentsOf: goldenURL, encoding: .utf8)
        let xml = AppcastGenerator(appName: "Burnt").generate(releases: entries)
        XCTAssertEqual(xml, golden)
    }

    func testReleasesSortedReverseChronological() throws {
        // Input above is oldest-first; output must be newest-first
        let xml = AppcastGenerator(appName: "Burnt").generate(releases: entries)
        let first = xml.range(of: "Version 1.2.0")!.lowerBound
        let second = xml.range(of: "Version 1.1.0")!.lowerBound
        XCTAssertLessThan(first, second)
    }

    func testXMLParses() throws {
        let xml = AppcastGenerator(appName: "Burnt").generate(releases: entries)
        let parser = XMLParser(data: Data(xml.utf8))
        XCTAssertTrue(parser.parse(), "generated appcast must be well-formed XML")
    }

    func testXMLEscapesSpecialCharacters() throws {
        let specialEntries = [
            AppcastEntry(
                version: "1.0<beta>",
                artifactURL: URL(string: "https://example.com/file?v=1&type=test")!,
                edSignature: "sig\"with'quotes",
                lengthBytes: 1000,
                minSystemVersion: "14.0 & 15.0",
                notesHTML: nil,
                pubDate: date("2026-07-01T12:00:00Z")
            ),
        ]
        let xml = AppcastGenerator(appName: "News & Weather").generate(releases: specialEntries)

        XCTAssertTrue(xml.contains("News &amp; Weather"))
        XCTAssertTrue(xml.contains("1.0&lt;beta&gt;"))
        XCTAssertTrue(xml.contains("v=1&amp;type=test"))
        XCTAssertTrue(xml.contains("sig&quot;with&apos;quotes"))
        XCTAssertTrue(xml.contains("14.0 &amp; 15.0"))

        let parser = XMLParser(data: Data(xml.utf8))
        XCTAssertTrue(parser.parse(), "appcast with escaped special characters must be well-formed XML")
    }
}
