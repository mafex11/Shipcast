import Foundation

public struct BuildArtifact: Sendable {
    public var appURL: URL
    public var appName: String
    public var bundleID: String
    public var version: String

    public init(appURL: URL, appName: String, bundleID: String, version: String) {
        self.appURL = appURL
        self.appName = appName
        self.bundleID = bundleID
        self.version = version
    }
}

public struct SignedArtifact: Sendable {
    public var app: BuildArtifact
    public var resolvedMode: SignMode
    public var notarized: Bool

    public init(app: BuildArtifact, resolvedMode: SignMode, notarized: Bool) {
        self.app = app
        self.resolvedMode = resolvedMode
        self.notarized = notarized
    }
}

public struct PackagedArtifacts: Sendable {
    public var zipURL: URL
    public var dmgURL: URL?
    public var sha256: String
    public var lengthBytes: Int

    public init(zipURL: URL, dmgURL: URL?, sha256: String, lengthBytes: Int) {
        self.zipURL = zipURL
        self.dmgURL = dmgURL
        self.sha256 = sha256
        self.lengthBytes = lengthBytes
    }
}
