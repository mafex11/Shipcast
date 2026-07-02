import Foundation

public struct InfoPlistGenerator {
    public static func generate(for artifact: BuildArtifact, config: ShipcastConfig) throws -> URL {
        let plistURL = artifact.appURL
            .appendingPathComponent("Contents")
            .appendingPathComponent("Info.plist")

        let plist: [String: Any] = [
            "CFBundleIdentifier": artifact.bundleID,
            "CFBundleName": artifact.appName,
            "CFBundleDisplayName": artifact.appName,
            "CFBundleVersion": artifact.version,
            "CFBundleShortVersionString": artifact.version,
            "CFBundleExecutable": artifact.appName,
            "CFBundlePackageType": "APPL",
            "CFBundleInfoDictionaryVersion": "6.0",
            "LSMinimumSystemVersion": "14.0",
            "NSHighResolutionCapable": true,
        ]

        // Add LSUIElement for menu bar apps (deferred to Plan B — this is SwiftPM-only for Plan A)
        // Add Sparkle keys if enabled (deferred to Plan C)

        let data = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .xml,
            options: 0
        )

        try data.write(to: plistURL)

        return plistURL
    }
}
