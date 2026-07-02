import Foundation

public struct LastReleaseMetadata: Codable, Sendable {
    public var version: String
    public var assetURL: URL
    public var sha256: String
    public var edSignature: String
    public var lengthBytes: Int
    public var minSystemVersion: String?
    public var notesHTML: String?

    public init(version: String, assetURL: URL, sha256: String, edSignature: String,
                lengthBytes: Int, minSystemVersion: String?, notesHTML: String?) {
        self.version = version
        self.assetURL = assetURL
        self.sha256 = sha256
        self.edSignature = edSignature
        self.lengthBytes = lengthBytes
        self.minSystemVersion = minSystemVersion
        self.notesHTML = notesHTML
    }
}
