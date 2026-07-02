import Foundation

public struct AppcastEntry: Sendable {
    public var version: String
    public var artifactURL: URL
    public var edSignature: String
    public var lengthBytes: Int
    public var minSystemVersion: String?
    public var notesHTML: String?
    public var pubDate: Date

    public init(version: String, artifactURL: URL, edSignature: String, lengthBytes: Int,
                minSystemVersion: String?, notesHTML: String?, pubDate: Date) {
        self.version = version
        self.artifactURL = artifactURL
        self.edSignature = edSignature
        self.lengthBytes = lengthBytes
        self.minSystemVersion = minSystemVersion
        self.notesHTML = notesHTML
        self.pubDate = pubDate
    }
}
