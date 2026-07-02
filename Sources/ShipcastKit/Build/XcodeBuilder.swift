import Foundation

public struct XcodeBuilder: Sendable {
    let shell: any ShellRunner

    public init(shell: any ShellRunner) {
        self.shell = shell
    }

    public func build(config: ShipcastConfig, at root: URL) throws -> BuildArtifact {
        guard case .xcode(let project, let scheme) = config.app.project else {
            throw ShipcastError.config(
                "XcodeBuilder invoked for non-Xcode project",
                fix: "Set project = \"xcode:MyApp.xcodeproj/MyScheme\" in shipcast.toml [app]"
            )
        }

        // xcodebuild runs from the caller's working directory, not `root`, so a
        // relative project path must be resolved against root when it exists there.
        let resolvedProject = root.appendingPathComponent(project).path
        let projectPath = (!project.hasPrefix("/") && FileManager.default.fileExists(atPath: resolvedProject))
            ? resolvedProject
            : project

        let buildDir = root.appendingPathComponent(".shipcast/build")
        let archivePath = buildDir.appendingPathComponent("\(config.app.name).xcarchive")
        let exportDir = buildDir.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let archiveResult = try shell.run("/usr/bin/xcodebuild", args: [
            "archive",
            "-project", projectPath,
            "-scheme", scheme,
            "-configuration", "Release",
            "-archivePath", archivePath.path,
            "CODE_SIGN_IDENTITY=-",
            "CODE_SIGNING_REQUIRED=NO",
        ], env: nil)
        guard archiveResult.exitCode == 0 else {
            throw ShipcastError.generic(
                "xcodebuild archive failed (exit \(archiveResult.exitCode)): \(archiveResult.stderr)",
                fix: "Run `xcodebuild -list -project \(project)` to verify the scheme name, then `xcodebuild archive -project \(project) -scheme \(scheme)` to see the full error"
            )
        }

        let method = config.sign.mode == .developerID ? "developer-id" : "mac-application"
        let exportOptions: [String: Any] = ["method": method, "destination": "export"]
        let optionsURL = buildDir.appendingPathComponent("ExportOptions.plist")
        let optionsData = try PropertyListSerialization.data(fromPropertyList: exportOptions, format: .xml, options: 0)
        try optionsData.write(to: optionsURL)

        let exportResult = try shell.run("/usr/bin/xcodebuild", args: [
            "-exportArchive",
            "-archivePath", archivePath.path,
            "-exportPath", exportDir.path,
            "-exportOptionsPlist", optionsURL.path,
        ], env: nil)
        guard exportResult.exitCode == 0 else {
            throw ShipcastError.generic(
                "xcodebuild -exportArchive failed (exit \(exportResult.exitCode)): \(exportResult.stderr)",
                fix: "Inspect \(optionsURL.path); for developer-id method your Developer ID cert must be in the Keychain (`security find-identity -v -p codesigning`)"
            )
        }

        return BuildArtifact(
            appURL: exportDir.appendingPathComponent("\(config.app.name).app"),
            appName: config.app.name,
            bundleID: config.app.bundleID,
            version: config.app.version
        )
    }
}
