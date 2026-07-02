@testable import ShipcastKit

extension ShipcastConfig {
    static func fixture() -> ShipcastConfig {
        ShipcastConfig(
            app: .init(name: "Fixture", bundleID: "dev.test.fixture", version: "1.0.0", project: .swiftpm),
            sign: .init(mode: .adhoc),
            distribute: .init(githubRelease: false, githubRepo: nil, homebrewTap: nil, formats: [.zip]),
            updates: .init(sparkle: false, feed: .none),
            permissions: []
        )
    }
}
