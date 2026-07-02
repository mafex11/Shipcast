import Foundation

public struct ShipcastConfig: Sendable, Equatable {
    public struct App: Sendable, Equatable {
        public var name: String
        public var bundleID: String
        public var version: String
        public var project: ProjectKind

        public init(name: String, bundleID: String, version: String, project: ProjectKind) {
            self.name = name
            self.bundleID = bundleID
            self.version = version
            self.project = project
        }
    }

    public enum ProjectKind: Sendable, Equatable {
        case auto
        case swiftpm
        case xcode(project: String, scheme: String)
    }

    public struct Sign: Sendable, Equatable {
        public var mode: SignMode

        public init(mode: SignMode) {
            self.mode = mode
        }
    }

    public struct Distribute: Sendable, Equatable {
        public var githubRelease: Bool
        public var githubRepo: String?
        public var homebrewTap: String?
        public var formats: [ArtifactFormat]

        public init(githubRelease: Bool, githubRepo: String?, homebrewTap: String?, formats: [ArtifactFormat]) {
            self.githubRelease = githubRelease
            self.githubRepo = githubRepo
            self.homebrewTap = homebrewTap
            self.formats = formats
        }
    }

    public struct Updates: Sendable, Equatable {
        public var sparkle: Bool
        public var feed: FeedKind

        public init(sparkle: Bool, feed: FeedKind) {
            self.sparkle = sparkle
            self.feed = feed
        }
    }

    public enum FeedKind: Sendable, Equatable {
        case hosted
        case selfHosted(url: String)
        case none
    }

    public var app: App
    public var sign: Sign
    public var distribute: Distribute
    public var updates: Updates
    public var permissions: [TCCService]

    public init(
        app: App,
        sign: Sign,
        distribute: Distribute,
        updates: Updates,
        permissions: [TCCService]
    ) {
        self.app = app
        self.sign = sign
        self.distribute = distribute
        self.updates = updates
        self.permissions = permissions
    }
}

public enum SignMode: String, Sendable, Equatable {
    case auto
    case adhoc
    case developerID = "developer-id"
}

public enum ArtifactFormat: String, Sendable, Equatable {
    case zip
    case dmg
}

public enum TCCService: String, Sendable, Equatable {
    case accessibility = "Accessibility"
    case screenRecording = "ScreenCapture"
    case fullDiskAccess = "SystemPolicyAllFiles"
}
