import Foundation

public struct AppcastGenerator: Sendable {
    let appName: String

    public init(appName: String) {
        self.appName = appName
    }

    public func generate(releases: [AppcastEntry]) -> String {
        let rfc822 = DateFormatter()
        rfc822.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        rfc822.locale = Locale(identifier: "en_US_POSIX")
        rfc822.timeZone = TimeZone(identifier: "UTC")

        let sorted = releases.sorted { $0.pubDate > $1.pubDate }

        var lines: [String] = []
        lines.append("<?xml version=\"1.0\" encoding=\"utf-8\"?>")
        lines.append("<rss version=\"2.0\" xmlns:sparkle=\"http://www.andymatuschak.org/xml-namespaces/sparkle\">")
        lines.append("  <channel>")
        lines.append("    <title>\(appName) Updates</title>")
        lines.append("    <description>Release feed for \(appName)</description>")
        lines.append("    <language>en</language>")
        for entry in sorted {
            lines.append("    <item>")
            lines.append("      <title>Version \(entry.version)</title>")
            lines.append("      <sparkle:version>\(entry.version)</sparkle:version>")
            lines.append("      <pubDate>\(rfc822.string(from: entry.pubDate))</pubDate>")
            if let notes = entry.notesHTML {
                lines.append("      <description><![CDATA[\(notes)]]></description>")
            }
            lines.append("      <enclosure url=\"\(entry.artifactURL.absoluteString)\"")
            lines.append("                 length=\"\(entry.lengthBytes)\"")
            lines.append("                 type=\"application/octet-stream\"")
            lines.append("                 sparkle:edSignature=\"\(entry.edSignature)\" />")
            if let minOS = entry.minSystemVersion {
                lines.append("      <sparkle:minimumSystemVersion>\(minOS)</sparkle:minimumSystemVersion>")
            }
            lines.append("    </item>")
        }
        lines.append("  </channel>")
        lines.append("</rss>")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
