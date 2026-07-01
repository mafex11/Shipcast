# Shipcast Plan B — Release Pipeline (release/doctor/push + Xcode + cask + appcast) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `shipcast release` cuts a full release for burnt with one command — GitHub release created, homebrew cask updated, appcast XML generated and Sparkle-signed — and `shipcast doctor` diagnoses the spec's failure gauntlet (unsigned, quarantined, seal-broken bundles) with actionable fixes.

**Architecture:** All new engine components live in ShipcastKit (Publish/, Push/, Doctor/, Build/XcodeBuilder), consuming Plan A's pinned interfaces (ShipcastConfig, ShellRunner, BuildArtifact, SignedArtifact, PackagedArtifacts, ShipcastError). External tools (xcodebuild, gh, sign_update) are always invoked through ShellRunner so tests mock them with MockShellRunner. CloudClient uses URLSession with URLProtocol-based test mocking. ReleaseCommand in ShipcastCLI orchestrates the full pipeline: build → sign → package → GitHub release → cask → appcast (→ push when feed is hosted).

**Tech Stack:** Swift 6, SwiftPM, swift-argument-parser, XCTest, Foundation URLSession, gh CLI, xcodebuild, Sparkle sign_update

## Global Constraints

- macOS 14+ target; Swift 6; single static binary
- Credentials NEVER read from shipcast.toml (env/Keychain only) — Sparkle key from `SPARKLE_PRIVATE_KEY` env, cloud token from `SHIPCAST_TOKEN` env or `--token`
- Exit codes: 0 ok / 1 generic / 2 config / 3 signing / 4 notarization rejected / 5 publish
- Every error message prints failing command + likely reason + fix
- All engine code in ShipcastKit (UI-free), CLI layer thin
- Zip always via `ditto -c -k --sequesterRsrc --keepParent`
- Ad-hoc deep sign is the FINAL step before zipping
- TDD: write failing test → run test expect FAIL → minimal implementation → run test expect PASS → commit

## Consumed Interfaces (defined by Plan A — use verbatim, never redefine)

- `ShipcastConfig` with `.app.name/.bundleID/.version`, `.distribute.githubRepo/.homebrewTap/.formats`, `.updates.sparkle/.feed` (`FeedKind.hosted/.selfHosted(url:)/.none`), `.permissions: [TCCService]`
- `SignMode` (.auto/.adhoc/.developerID), `ArtifactFormat` (.zip/.dmg)
- `TCCService` (.accessibility="Accessibility", .screenRecording="ScreenCapture", .fullDiskAccess="SystemPolicyAllFiles")
- `BuildArtifact(appURL:appName:bundleID:version:)`
- `SignedArtifact(app:resolvedMode:notarized:)`
- `PackagedArtifacts(zipURL:dmgURL:sha256:lengthBytes:)`
- `ShellRunner.run(_:args:env:) throws -> ShellResult`, `MockShellRunner`, `ShellResult(exitCode:stdout:stderr:)`
- `ShipcastError.config/.signing/.notarization/.publish/.generic` — each `(String, fix: String)` with `.exitCode`
- `SwiftPMBuilder.build(config:at:shell:)`, `Signer.sign(_:config:shell:)`, `Packager.package(_:config:shell:)` (static methods taking an explicit ShellRunner)

## Produced Interfaces (Plan C and CLI consume these)

```swift
public struct XcodeBuilder: Sendable {
    public func build(config: ShipcastConfig, at root: URL) throws -> BuildArtifact
}
public struct CaskGenerator: Sendable {
    public func generate(config: ShipcastConfig, artifacts: PackagedArtifacts, releaseURL: URL) -> String
}
public struct CaskPublisher: Sendable {
    public func publish(cask: String, config: ShipcastConfig) throws
}
public struct GitHubReleaser: Sendable {
    public func createRelease(config: ShipcastConfig, artifacts: PackagedArtifacts, notes: String) throws -> URL
}
public struct SparkleSigner: Sendable {
    public func sign(artifact: URL, privateKeyEnv: String) throws -> String
}
public struct AppcastEntry: Sendable {
    public var version: String
    public var artifactURL: URL
    public var edSignature: String
    public var lengthBytes: Int
    public var minSystemVersion: String?
    public var notesHTML: String?
    public var pubDate: Date
}
public struct AppcastGenerator: Sendable {
    public func generate(releases: [AppcastEntry]) -> String
}
public struct DoctorFinding: Sendable, Equatable {
    public enum Status: Sendable, Equatable { case pass, warn, fail }
    public var check: String
    public var status: Status
    public var reason: String?
    public var fix: String?
}
public struct Doctor: Sendable {
    public func run(appURL: URL, config: ShipcastConfig) -> [DoctorFinding]
}
public struct CloudClient: Sendable {
    public func push(release: AppcastEntry, token: String, baseURL: URL) throws
}
```

---

## Task 0: Test-support alignment with Plan A

Plan A shipped slightly narrower test utilities than this plan's tests assume. Do this first so every later task compiles.

**Files:**
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/TestSupport.swift`
- Modify: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastKit/Shell/MockShellRunner.swift`

**Steps:**

- [ ] Add `ShipcastConfig.fixture()` test helper (this plan's tests call it everywhere)
```swift
// Tests/ShipcastKitTests/TestSupport.swift
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
```

- [ ] Extend MockShellRunner: add a `calls` alias for `invocations`, basename matching (Plan A engines invoke absolute paths like `/usr/bin/codesign`; this plan's stubs and assertions use bare names like `"codesign"`), and an args-prefix-specific stub overload
```swift
// Add to Sources/ShipcastKit/Shell/MockShellRunner.swift
extension MockShellRunner {
    /// Alias used by Plan B tests; same content as `invocations` but with
    /// `command` reduced to its basename so assertions match bare tool names.
    public var calls: [Invocation] {
        invocations.map { inv in
            Invocation(command: (inv.command as NSString).lastPathComponent, args: inv.args, env: inv.env)
        }
    }

    /// Stub keyed by (basename, args prefix): most-specific stub wins.
    public func stub(command: String, args: [String], result: ShellResult) {
        argStubs.append((command: command, argsPrefix: args, result: result))
    }
}
```
Then update `MockShellRunner.run` to resolve stubs in order: (1) an `argStubs` entry whose basename matches `(command as NSString).lastPathComponent` AND whose `argsPrefix` is a prefix of `args`; (2) a plain `stubs[basename]` entry; (3) a plain `stubs[command]` entry (Plan A behavior); else throw. Store `argStubs` as `private var argStubs: [(command: String, argsPrefix: [String], result: ShellResult)] = []`.

- [ ] Run `swift test` — all Plan A tests still pass (Plan A stubbed with full paths; rule 3 preserves that)

- [ ] Commit: `git add -A && git commit -m "Extend MockShellRunner and add config fixture for Plan B tests"`

---

## Task 1: XcodeBuilder + MiniXcode fixture

**Files:**
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/Fixtures/MiniXcode/MiniXcode.xcodeproj/project.pbxproj` (minimal single-target macOS app project checked in as fixture)
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/Fixtures/MiniXcode/MiniXcode/main.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/Fixtures/MiniXcode/MiniXcode/Info.plist`
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastKit/Build/XcodeBuilder.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/XcodeBuildTests.swift`

**Interfaces:**
- Consumes: `ShipcastConfig` (`.app.project == .xcode(project:scheme:)`), `ShellRunner`, `MockShellRunner`, `BuildArtifact`, `ShipcastError.generic`
- Produces: `XcodeBuilder.build(config:at:) throws -> BuildArtifact`

**Steps:**

- [ ] Write failing test asserting XcodeBuilder issues `xcodebuild archive` then `xcodebuild -exportArchive` with an ExportOptions.plist whose `method` is `developer-id` when sign mode is developerID, and returns a BuildArtifact pointing at the exported .app
```swift
// Tests/ShipcastKitTests/XcodeBuildTests.swift
import XCTest
@testable import ShipcastKit

final class XcodeBuildTests: XCTestCase {
    func makeConfig(mode: SignMode) -> ShipcastConfig {
        var config = ShipcastConfig.fixture() // Plan A test helper
        config.app.name = "MiniXcode"
        config.app.bundleID = "dev.mafex.minixcode"
        config.app.version = "1.0.0"
        config.app.project = .xcode(project: "MiniXcode.xcodeproj", scheme: "MiniXcode")
        config.sign.mode = mode
        return config
    }

    func testArchiveAndExportDeveloperID() throws {
        let shell = MockShellRunner()
        shell.stub(command: "xcodebuild", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        let root = URL(fileURLWithPath: "/tmp/shipcast-xcode-test")
        let builder = XcodeBuilder(shell: shell)

        let artifact = try builder.build(config: makeConfig(mode: .developerID), at: root)

        let archiveCall = shell.calls[0]
        XCTAssertEqual(archiveCall.command, "xcodebuild")
        XCTAssertTrue(archiveCall.args.contains("archive"))
        XCTAssertTrue(archiveCall.args.contains("MiniXcode.xcodeproj"))
        XCTAssertTrue(archiveCall.args.contains("MiniXcode")) // scheme

        let exportCall = shell.calls[1]
        XCTAssertTrue(exportCall.args.contains("-exportArchive"))
        let optionsIndex = exportCall.args.firstIndex(of: "-exportOptionsPlist")!
        let plistPath = exportCall.args[optionsIndex + 1]
        let plistData = try Data(contentsOf: URL(fileURLWithPath: plistPath))
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        XCTAssertEqual(plist["method"] as? String, "developer-id")

        XCTAssertEqual(artifact.appName, "MiniXcode")
        XCTAssertEqual(artifact.bundleID, "dev.mafex.minixcode")
        XCTAssertEqual(artifact.version, "1.0.0")
        XCTAssertTrue(artifact.appURL.path.hasSuffix("MiniXcode.app"))
    }

    func testExportMethodMacApplicationForAdhoc() throws {
        let shell = MockShellRunner()
        shell.stub(command: "xcodebuild", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        let builder = XcodeBuilder(shell: shell)
        _ = try builder.build(config: makeConfig(mode: .adhoc), at: URL(fileURLWithPath: "/tmp/shipcast-xcode-test"))

        let exportCall = shell.calls[1]
        let optionsIndex = exportCall.args.firstIndex(of: "-exportOptionsPlist")!
        let plistData = try Data(contentsOf: URL(fileURLWithPath: exportCall.args[optionsIndex + 1]))
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        XCTAssertEqual(plist["method"] as? String, "mac-application")
    }

    func testArchiveFailureThrowsGenericWithFix() throws {
        let shell = MockShellRunner()
        shell.stub(command: "xcodebuild", result: ShellResult(exitCode: 65, stdout: "", stderr: "error: no scheme"))
        let builder = XcodeBuilder(shell: shell)
        XCTAssertThrowsError(try builder.build(config: makeConfig(mode: .adhoc), at: URL(fileURLWithPath: "/tmp/x"))) { error in
            guard case ShipcastError.generic(let message, let fix) = error else {
                return XCTFail("expected .generic, got \(error)")
            }
            XCTAssertTrue(message.contains("xcodebuild archive"))
            XCTAssertTrue(fix.contains("xcodebuild -list"))
        }
    }
}
```

- [ ] Run test, expect FAIL (XcodeBuilder does not exist): `swift test --filter XcodeBuildTests` → compile error `cannot find 'XcodeBuilder' in scope`

- [ ] Implement XcodeBuilder minimally
```swift
// Sources/ShipcastKit/Build/XcodeBuilder.swift
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

        let buildDir = root.appendingPathComponent(".shipcast/build")
        let archivePath = buildDir.appendingPathComponent("\(config.app.name).xcarchive")
        let exportDir = buildDir.appendingPathComponent("export")
        try FileManager.default.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let archiveResult = try shell.run("xcodebuild", args: [
            "archive",
            "-project", project,
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

        let exportResult = try shell.run("xcodebuild", args: [
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
```

- [ ] Run test, expect PASS: `swift test --filter XcodeBuildTests` → `Executed 3 tests, with 0 failures`

- [ ] Create MiniXcode fixture: a minimal macOS app Xcode project (single AppDelegate-free `main.swift` printing nothing, Info.plist with `CFBundleIdentifier dev.mafex.minixcode`, `CFBundleExecutable MiniXcode`). Generate once locally with `xcodegen` or hand-write the pbxproj; commit under `Tests/ShipcastKitTests/Fixtures/MiniXcode/`. Add an integration test gated on Xcode availability:
```swift
// Appended to Tests/ShipcastKitTests/XcodeBuildTests.swift
func testRealXcodeBuildOfMiniXcodeFixture() throws {
    try XCTSkipUnless(
        ProcessInfo.processInfo.environment["SHIPCAST_INTEGRATION"] == "1",
        "Set SHIPCAST_INTEGRATION=1 to run real xcodebuild"
    )
    let fixtureRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures/MiniXcode")
    let builder = XcodeBuilder(shell: ProcessShellRunner()) // Plan A concrete runner
    let artifact = try builder.build(config: makeConfig(mode: .adhoc), at: fixtureRoot)
    XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.appURL.path))
}
```

- [ ] Run full suite, expect PASS (integration test skips without env var): `swift test` → 0 failures

- [ ] Commit: `git add -A && git commit -m "Add XcodeBuilder with archive/export and MiniXcode fixture"`

---

## Task 2: GitHubReleaser (gh CLI via ShellRunner)

**Files:**
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastKit/Publish/GitHubReleaser.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/GitHubReleaserTests.swift`

**Interfaces:**
- Consumes: `ShipcastConfig` (`.distribute.githubRepo`, `.app.name/.version`), `PackagedArtifacts`, `ShellRunner`, `MockShellRunner`, `ShipcastError.publish/.config`
- Produces: `GitHubReleaser.createRelease(config:artifacts:notes:) throws -> URL` (returns the zip asset download URL)

**Steps:**

- [ ] Write failing test
```swift
// Tests/ShipcastKitTests/GitHubReleaserTests.swift
import XCTest
@testable import ShipcastKit

final class GitHubReleaserTests: XCTestCase {
    func makeArtifacts() -> PackagedArtifacts {
        PackagedArtifacts(
            zipURL: URL(fileURLWithPath: "/tmp/Burnt.zip"),
            dmgURL: URL(fileURLWithPath: "/tmp/Burnt-1.2.0.dmg"),
            sha256: "abc123",
            lengthBytes: 12345678
        )
    }

    func makeConfig() -> ShipcastConfig {
        var config = ShipcastConfig.fixture()
        config.app.name = "Burnt"
        config.app.version = "1.2.0"
        config.distribute.githubRepo = "mafex11/burnt"
        return config
    }

    func testCreateReleaseUploadsAssetsAndReturnsAssetURL() throws {
        let shell = MockShellRunner()
        shell.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "https://github.com/mafex11/burnt/releases/tag/v1.2.0\n", stderr: ""))
        let releaser = GitHubReleaser(shell: shell)

        let assetURL = try releaser.createRelease(config: makeConfig(), artifacts: makeArtifacts(), notes: "Fixed bugs")

        let call = shell.calls[0]
        XCTAssertEqual(call.command, "gh")
        XCTAssertEqual(Array(call.args.prefix(3)), ["release", "create", "v1.2.0"])
        XCTAssertTrue(call.args.contains("/tmp/Burnt.zip"))
        XCTAssertTrue(call.args.contains("/tmp/Burnt-1.2.0.dmg"))
        XCTAssertTrue(call.args.contains("--repo"))
        XCTAssertTrue(call.args.contains("mafex11/burnt"))
        XCTAssertTrue(call.args.contains("--notes"))
        XCTAssertTrue(call.args.contains("Fixed bugs"))
        XCTAssertEqual(
            assetURL.absoluteString,
            "https://github.com/mafex11/burnt/releases/download/v1.2.0/Burnt.zip"
        )
    }

    func testNoDMGUploadsZipOnly() throws {
        let shell = MockShellRunner()
        shell.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        var artifacts = makeArtifacts()
        artifacts.dmgURL = nil
        _ = try GitHubReleaser(shell: shell).createRelease(config: makeConfig(), artifacts: artifacts, notes: "")
        XCTAssertFalse(shell.calls[0].args.contains("/tmp/Burnt-1.2.0.dmg"))
    }

    func testGHFailureThrowsPublishErrorWithFix() throws {
        let shell = MockShellRunner()
        shell.stub(command: "gh", result: ShellResult(exitCode: 1, stdout: "", stderr: "HTTP 401: Bad credentials"))
        XCTAssertThrowsError(try GitHubReleaser(shell: shell).createRelease(config: makeConfig(), artifacts: makeArtifacts(), notes: "")) { error in
            guard case ShipcastError.publish(let message, let fix) = error else {
                return XCTFail("expected .publish, got \(error)")
            }
            XCTAssertTrue(message.contains("gh release create"))
            XCTAssertTrue(message.contains("Bad credentials"))
            XCTAssertTrue(fix.contains("gh auth login"))
        }
    }

    func testMissingRepoThrowsConfigError() throws {
        var config = makeConfig()
        config.distribute.githubRepo = nil
        XCTAssertThrowsError(try GitHubReleaser(shell: MockShellRunner()).createRelease(config: config, artifacts: makeArtifacts(), notes: "")) { error in
            guard case ShipcastError.config(_, let fix) = error else {
                return XCTFail("expected .config, got \(error)")
            }
            XCTAssertTrue(fix.contains("github_repo"))
        }
    }
}
```

- [ ] Run test, expect FAIL: `swift test --filter GitHubReleaserTests` → compile error `cannot find 'GitHubReleaser' in scope`

- [ ] Implement GitHubReleaser
```swift
// Sources/ShipcastKit/Publish/GitHubReleaser.swift
import Foundation

public struct GitHubReleaser: Sendable {
    let shell: any ShellRunner

    public init(shell: any ShellRunner) {
        self.shell = shell
    }

    public func createRelease(config: ShipcastConfig, artifacts: PackagedArtifacts, notes: String) throws -> URL {
        guard let repo = config.distribute.githubRepo else {
            throw ShipcastError.config(
                "distribute.github_repo is not set in shipcast.toml",
                fix: "Add github_repo = \"owner/repo\" to the [distribute] section of shipcast.toml"
            )
        }

        let tag = "v\(config.app.version)"
        var args = ["release", "create", tag,
                    "--repo", repo,
                    "--title", "\(config.app.name) \(config.app.version)",
                    "--notes", notes,
                    artifacts.zipURL.path]
        if let dmg = artifacts.dmgURL {
            args.append(dmg.path)
        }

        let result = try shell.run("gh", args: args, env: nil)
        guard result.exitCode == 0 else {
            throw ShipcastError.publish(
                "gh release create \(tag) failed (exit \(result.exitCode)): \(result.stderr)",
                fix: "Check GitHub auth with `gh auth status`; if unauthenticated run `gh auth login`. If the tag already has a release, delete it with `gh release delete \(tag) --repo \(repo)` or bump the version."
            )
        }

        let zipName = artifacts.zipURL.lastPathComponent
        return URL(string: "https://github.com/\(repo)/releases/download/\(tag)/\(zipName)")!
    }
}
```

- [ ] Run test, expect PASS: `swift test --filter GitHubReleaserTests` → `Executed 4 tests, with 0 failures`

- [ ] Commit: `git add -A && git commit -m "Add GitHubReleaser wrapping gh release create"`

---

## Task 3: CaskGenerator (golden-file tests, adhoc + notarized variants)

**Files:**
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastKit/Publish/CaskGenerator.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/CaskTests.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/Fixtures/Golden/burnt-adhoc.rb`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/Fixtures/Golden/burnt-notarized.rb`

**Interfaces:**
- Consumes: `ShipcastConfig` (`.app.name/.bundleID`, `.distribute.githubRepo`, `.permissions`, `.sign.mode`), `PackagedArtifacts`, `TCCService`
- Produces: `CaskGenerator.generate(config:artifacts:releaseURL:) -> String`

**Steps:**

- [ ] Write golden file for the ad-hoc variant (quarantine strip always for adhoc + tccutil reset per declared TCCService + uninstall quit + zap paths)
```ruby
# Tests/ShipcastKitTests/Fixtures/Golden/burnt-adhoc.rb
cask "burnt" do
  version "1.2.0"
  sha256 "abc123"

  url "https://github.com/mafex11/burnt/releases/download/v#{version}/Burnt.zip"
  name "Burnt"
  desc "Burnt for macOS"
  homepage "https://github.com/mafex11/burnt"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Burnt.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/Burnt.app"]

    system_command "/usr/bin/tccutil",
                   args: ["reset", "Accessibility", "dev.mafex.burnt"]
    system_command "/usr/bin/tccutil",
                   args: ["reset", "ScreenCapture", "dev.mafex.burnt"]
  end

  uninstall quit: "dev.mafex.burnt"

  zap trash: [
    "~/Library/Preferences/dev.mafex.burnt.plist",
    "~/Library/Application Support/Burnt",
    "~/Library/Caches/dev.mafex.burnt",
  ]
end
```

- [ ] Write golden file for the notarized variant (no postflight block at all — notarized apps pass Gatekeeper and keep stable cdhash across releases)
```ruby
# Tests/ShipcastKitTests/Fixtures/Golden/burnt-notarized.rb
cask "burnt" do
  version "1.2.0"
  sha256 "abc123"

  url "https://github.com/mafex11/burnt/releases/download/v#{version}/Burnt.zip"
  name "Burnt"
  desc "Burnt for macOS"
  homepage "https://github.com/mafex11/burnt"

  livecheck do
    url :url
    strategy :github_latest
  end

  app "Burnt.app"

  uninstall quit: "dev.mafex.burnt"

  zap trash: [
    "~/Library/Preferences/dev.mafex.burnt.plist",
    "~/Library/Application Support/Burnt",
    "~/Library/Caches/dev.mafex.burnt",
  ]
end
```

- [ ] Write failing golden-file test
```swift
// Tests/ShipcastKitTests/CaskTests.swift
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
}
```

- [ ] Run test, expect FAIL: `swift test --filter CaskTests` → compile error `cannot find 'CaskGenerator' in scope`

- [ ] Implement CaskGenerator
```swift
// Sources/ShipcastKit/Publish/CaskGenerator.swift
import Foundation

public struct CaskGenerator: Sendable {
    public init() {}

    public func generate(config: ShipcastConfig, artifacts: PackagedArtifacts, releaseURL: URL) -> String {
        let token = config.app.name.lowercased()
        let bundleID = config.app.bundleID
        let appName = config.app.name
        let repo = config.distribute.githubRepo ?? ""
        // Cask url interpolates #{version}; swap the literal version segment back out.
        let templatedURL = releaseURL.absoluteString
            .replacingOccurrences(of: "/v\(config.app.version)/", with: "/v#{version}/")

        var lines: [String] = []
        lines.append("cask \"\(token)\" do")
        lines.append("  version \"\(config.app.version)\"")
        lines.append("  sha256 \"\(artifacts.sha256)\"")
        lines.append("")
        lines.append("  url \"\(templatedURL)\"")
        lines.append("  name \"\(appName)\"")
        lines.append("  desc \"\(appName) for macOS\"")
        lines.append("  homepage \"https://github.com/\(repo)\"")
        lines.append("")
        lines.append("  livecheck do")
        lines.append("    url :url")
        lines.append("    strategy :github_latest")
        lines.append("  end")
        lines.append("")
        lines.append("  app \"\(appName).app\"")
        lines.append("")

        if config.sign.mode != .developerID {
            lines.append("  postflight do")
            lines.append("    system_command \"/usr/bin/xattr\",")
            lines.append("                   args: [\"-dr\", \"com.apple.quarantine\", \"#{appdir}/\(appName).app\"]")
            if !config.permissions.isEmpty {
                lines.append("")
                for service in config.permissions {
                    lines.append("    system_command \"/usr/bin/tccutil\",")
                    lines.append("                   args: [\"reset\", \"\(service.rawValue)\", \"\(bundleID)\"]")
                }
            }
            lines.append("  end")
            lines.append("")
        }

        lines.append("  uninstall quit: \"\(bundleID)\"")
        lines.append("")
        lines.append("  zap trash: [")
        lines.append("    \"~/Library/Preferences/\(bundleID).plist\",")
        lines.append("    \"~/Library/Application Support/\(appName)\",")
        lines.append("    \"~/Library/Caches/\(bundleID)\",")
        lines.append("  ]")
        lines.append("end")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
```

- [ ] Run test, expect PASS: `swift test --filter CaskTests` → `Executed 4 tests, with 0 failures`

- [ ] Commit: `git add -A && git commit -m "Add CaskGenerator with adhoc/notarized golden-file tests"`

---

## Task 4: CaskPublisher (direct push vs PR)

**Files:**
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastKit/Publish/CaskPublisher.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/CaskPublisherTests.swift`

**Interfaces:**
- Consumes: `ShipcastConfig` (`.distribute.homebrewTap`, `.app.name/.version`), `ShellRunner`, `MockShellRunner`, `ShipcastError.publish/.config`
- Produces: `CaskPublisher.publish(cask:config:) throws`

**Steps:**

- [ ] Write failing test covering both flows: user owns tap → clone/commit/push; user does not own tap → fork + `gh pr create`
```swift
// Tests/ShipcastKitTests/CaskPublisherTests.swift
import XCTest
@testable import ShipcastKit

final class CaskPublisherTests: XCTestCase {
    private func makeConfig() -> ShipcastConfig {
        var config = ShipcastConfig.fixture()
        config.app.name = "Burnt"
        config.app.version = "1.2.0"
        config.distribute.homebrewTap = "mafex11/homebrew-tap"
        return config
    }

    private let cask = "cask \"burnt\" do\nend\n"

    func testOwnerPushesDirectly() throws {
        let shell = MockShellRunner()
        // gh api user → login matches tap owner
        shell.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "mafex11\n", stderr: ""))
        shell.stub(command: "git", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        try CaskPublisher(shell: shell).publish(cask: cask, config: makeConfig())

        let ghCalls = shell.calls.filter { $0.command == "gh" }
        XCTAssertEqual(ghCalls[0].args, ["api", "user", "--jq", ".login"])
        // No PR when owner
        XCTAssertFalse(shell.calls.contains { $0.command == "gh" && $0.args.first == "pr" })

        let gitArgs = shell.calls.filter { $0.command == "git" }.map(\.args)
        XCTAssertTrue(gitArgs.contains { $0.first == "clone" && $0.contains("https://github.com/mafex11/homebrew-tap.git") })
        XCTAssertTrue(gitArgs.contains { $0.contains("commit") && $0.contains("Update burnt to 1.2.0") })
        XCTAssertTrue(gitArgs.contains { $0.first == "push" || $0.contains("push") })
    }

    func testNonOwnerOpensPR() throws {
        let shell = MockShellRunner()
        shell.stub(command: "gh", args: ["api", "user", "--jq", ".login"],
                   result: ShellResult(exitCode: 0, stdout: "someoneelse\n", stderr: ""))
        shell.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        shell.stub(command: "git", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        try CaskPublisher(shell: shell).publish(cask: cask, config: makeConfig())

        let prCall = shell.calls.first { $0.command == "gh" && $0.args.first == "pr" }
        let pr = try XCTUnwrap(prCall)
        XCTAssertTrue(pr.args.contains("create"))
        XCTAssertTrue(pr.args.contains("--repo"))
        XCTAssertTrue(pr.args.contains("mafex11/homebrew-tap"))
        XCTAssertTrue(pr.args.contains("--title"))
        XCTAssertTrue(pr.args.contains("Add burnt 1.2.0"))
    }

    func testCaskFileWrittenIntoCasksDirectory() throws {
        let shell = MockShellRunner()
        shell.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "mafex11\n", stderr: ""))
        shell.stub(command: "git", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        let publisher = CaskPublisher(shell: shell)
        try publisher.publish(cask: cask, config: makeConfig())
        let written = try String(contentsOf: publisher.lastWrittenCaskURL!, encoding: .utf8)
        XCTAssertEqual(written, cask)
        XCTAssertTrue(publisher.lastWrittenCaskURL!.path.hasSuffix("Casks/burnt.rb"))
    }

    func testPushFailureThrowsPublishErrorWithFix() throws {
        let shell = MockShellRunner()
        shell.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "mafex11\n", stderr: ""))
        shell.stub(command: "git", args: ["push"], result: ShellResult(exitCode: 1, stdout: "", stderr: "remote: Permission denied"))
        shell.stub(command: "git", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        XCTAssertThrowsError(try CaskPublisher(shell: shell).publish(cask: cask, config: makeConfig())) { error in
            guard case ShipcastError.publish(let message, let fix) = error else {
                return XCTFail("expected .publish, got \(error)")
            }
            XCTAssertTrue(message.contains("git push"))
            XCTAssertTrue(fix.contains("gh auth"))
        }
    }

    func testMissingTapThrowsConfigError() throws {
        var config = makeConfig()
        config.distribute.homebrewTap = nil
        XCTAssertThrowsError(try CaskPublisher(shell: MockShellRunner()).publish(cask: cask, config: config)) { error in
            guard case ShipcastError.config(_, let fix) = error else {
                return XCTFail("expected .config, got \(error)")
            }
            XCTAssertTrue(fix.contains("homebrew_tap"))
        }
    }
}
```

- [ ] Run test, expect FAIL: `swift test --filter CaskPublisherTests` → compile error `cannot find 'CaskPublisher' in scope`

- [ ] Implement CaskPublisher
```swift
// Sources/ShipcastKit/Publish/CaskPublisher.swift
import Foundation

public final class CaskPublisher: @unchecked Sendable {
    let shell: any ShellRunner
    public private(set) var lastWrittenCaskURL: URL?

    public init(shell: any ShellRunner) {
        self.shell = shell
    }

    public func publish(cask: String, config: ShipcastConfig) throws {
        guard let tap = config.distribute.homebrewTap else {
            throw ShipcastError.config(
                "distribute.homebrew_tap is not set in shipcast.toml",
                fix: "Add homebrew_tap = \"owner/homebrew-tap\" to the [distribute] section of shipcast.toml"
            )
        }
        let tapOwner = String(tap.split(separator: "/")[0])
        let token = config.app.name.lowercased()
        let version = config.app.version

        let whoami = try shell.run("gh", args: ["api", "user", "--jq", ".login"], env: nil)
        guard whoami.exitCode == 0 else {
            throw ShipcastError.publish(
                "gh api user failed (exit \(whoami.exitCode)): \(whoami.stderr)",
                fix: "Authenticate the GitHub CLI: `gh auth login`"
            )
        }
        let login = whoami.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let ownsTap = (login == tapOwner)

        let workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipcast-tap-\(UUID().uuidString)")
        let cloneSource = ownsTap ? tap : "\(login)/homebrew-tap-fork" // fork created below when needed

        if !ownsTap {
            // Fork the tap under the user's account (idempotent if fork exists)
            _ = try shell.run("gh", args: ["repo", "fork", tap, "--clone=false"], env: nil)
        }

        let cloneURL = "https://github.com/\(ownsTap ? tap : cloneSource).git"
        let clone = try shell.run("git", args: ["clone", "--depth", "1", cloneURL, workDir.path], env: nil)
        guard clone.exitCode == 0 else {
            throw ShipcastError.publish(
                "git clone \(cloneURL) failed (exit \(clone.exitCode)): \(clone.stderr)",
                fix: "Verify the tap repo exists and you can read it: `gh repo view \(tap)`"
            )
        }

        let casksDir = workDir.appendingPathComponent("Casks")
        try FileManager.default.createDirectory(at: casksDir, withIntermediateDirectories: true)
        let caskURL = casksDir.appendingPathComponent("\(token).rb")
        try cask.write(to: caskURL, atomically: true, encoding: .utf8)
        lastWrittenCaskURL = caskURL

        let branch = ownsTap ? "main" : "shipcast/\(token)-\(version)"
        if !ownsTap {
            _ = try shell.run("git", args: ["-C", workDir.path, "checkout", "-b", branch], env: nil)
        }
        _ = try shell.run("git", args: ["-C", workDir.path, "add", "Casks/\(token).rb"], env: nil)
        let commitMessage = ownsTap ? "Update \(token) to \(version)" : "Add \(token) \(version)"
        _ = try shell.run("git", args: ["-C", workDir.path, "commit", "-m", commitMessage], env: nil)

        let push = try shell.run("git", args: ["-C", workDir.path, "push", "origin", branch], env: nil)
        guard push.exitCode == 0 else {
            throw ShipcastError.publish(
                "git push to \(cloneURL) failed (exit \(push.exitCode)): \(push.stderr)",
                fix: "Check push permission with `gh auth status`; if you don't own \(tap), Shipcast opens a PR instead — verify your fork exists with `gh repo view \(login)/\(tap.split(separator: "/")[1])`"
            )
        }

        if !ownsTap {
            let pr = try shell.run("gh", args: [
                "pr", "create",
                "--repo", tap,
                "--title", "Add \(token) \(version)",
                "--body", "Automated cask update from shipcast release.",
                "--head", "\(login):\(branch)",
            ], env: nil)
            guard pr.exitCode == 0 else {
                throw ShipcastError.publish(
                    "gh pr create against \(tap) failed (exit \(pr.exitCode)): \(pr.stderr)",
                    fix: "Open the PR manually: push branch \(branch) to your fork and run `gh pr create --repo \(tap)`"
                )
            }
        }

        try? FileManager.default.removeItem(at: workDir)
    }
}
```

- [ ] Run test, expect PASS: `swift test --filter CaskPublisherTests` → `Executed 5 tests, with 0 failures`

- [ ] Commit: `git add -A && git commit -m "Add CaskPublisher with owner-push and fork-PR flows"`

---

## Task 5: SparkleSigner (sign_update wrapper)

**Files:**
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastKit/Publish/SparkleSigner.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/SparkleSignerTests.swift`

**Interfaces:**
- Consumes: `ShellRunner`, `MockShellRunner`, `ShipcastError.signing/.config`; env var `SPARKLE_PRIVATE_KEY`
- Produces: `SparkleSigner.sign(artifact:privateKeyEnv:) throws -> String` (base64 ed25519 signature)

**Steps:**

- [ ] Write failing test
```swift
// Tests/ShipcastKitTests/SparkleSignerTests.swift
import XCTest
@testable import ShipcastKit

final class SparkleSignerTests: XCTestCase {
    func testSignsArtifactAndReturnsSignature() throws {
        let shell = MockShellRunner()
        // sign_update prints: sparkle:edSignature="BASE64SIG" length="12345"
        shell.stub(command: "sign_update", result: ShellResult(
            exitCode: 0,
            stdout: "sparkle:edSignature=\"MEUCIQDtest+sig==\" length=\"12345\"\n",
            stderr: ""
        ))
        let signer = SparkleSigner(shell: shell, environment: ["SPARKLE_PRIVATE_KEY": "b64privatekey"])

        let signature = try signer.sign(
            artifact: URL(fileURLWithPath: "/tmp/Burnt.zip"),
            privateKeyEnv: "SPARKLE_PRIVATE_KEY"
        )

        XCTAssertEqual(signature, "MEUCIQDtest+sig==")
        let call = shell.calls[0]
        XCTAssertEqual(call.command, "sign_update")
        XCTAssertTrue(call.args.contains("/tmp/Burnt.zip"))
        // Key passed via ephemeral file (-f), never as a bare argv (visible in ps)
        let fIndex = call.args.firstIndex(of: "-f")
        XCTAssertNotNil(fIndex)
    }

    func testMissingEnvVarThrowsConfigErrorWithFix() throws {
        let signer = SparkleSigner(shell: MockShellRunner(), environment: [:])
        XCTAssertThrowsError(try signer.sign(artifact: URL(fileURLWithPath: "/tmp/Burnt.zip"), privateKeyEnv: "SPARKLE_PRIVATE_KEY")) { error in
            guard case ShipcastError.config(let message, let fix) = error else {
                return XCTFail("expected .config, got \(error)")
            }
            XCTAssertTrue(message.contains("SPARKLE_PRIVATE_KEY"))
            XCTAssertTrue(fix.contains("generate_keys"))
        }
    }

    func testSignUpdateFailureThrowsSigningError() throws {
        let shell = MockShellRunner()
        shell.stub(command: "sign_update", result: ShellResult(exitCode: 1, stdout: "", stderr: "Unable to decode private key"))
        let signer = SparkleSigner(shell: shell, environment: ["SPARKLE_PRIVATE_KEY": "garbage"])
        XCTAssertThrowsError(try signer.sign(artifact: URL(fileURLWithPath: "/tmp/Burnt.zip"), privateKeyEnv: "SPARKLE_PRIVATE_KEY")) { error in
            guard case ShipcastError.signing(let message, let fix) = error else {
                return XCTFail("expected .signing, got \(error)")
            }
            XCTAssertTrue(message.contains("sign_update"))
            XCTAssertTrue(fix.contains("SPARKLE_PRIVATE_KEY"))
        }
    }

    func testUnparseableOutputThrowsSigningError() throws {
        let shell = MockShellRunner()
        shell.stub(command: "sign_update", result: ShellResult(exitCode: 0, stdout: "unexpected output", stderr: ""))
        let signer = SparkleSigner(shell: shell, environment: ["SPARKLE_PRIVATE_KEY": "key"])
        XCTAssertThrowsError(try signer.sign(artifact: URL(fileURLWithPath: "/tmp/Burnt.zip"), privateKeyEnv: "SPARKLE_PRIVATE_KEY"))
    }
}
```

- [ ] Run test, expect FAIL: `swift test --filter SparkleSignerTests` → compile error `cannot find 'SparkleSigner' in scope`

- [ ] Implement SparkleSigner
```swift
// Sources/ShipcastKit/Publish/SparkleSigner.swift
import Foundation

public struct SparkleSigner: Sendable {
    let shell: any ShellRunner
    let environment: [String: String]

    public init(shell: any ShellRunner, environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.shell = shell
        self.environment = environment
    }

    public func sign(artifact: URL, privateKeyEnv: String) throws -> String {
        guard let privateKey = environment[privateKeyEnv], !privateKey.isEmpty else {
            throw ShipcastError.config(
                "\(privateKeyEnv) environment variable is not set — Sparkle updates require an ed25519 private key",
                fix: "Generate a key pair once with Sparkle's `generate_keys` tool, embed the public key as SUPublicEDKey in Info.plist, then `export \(privateKeyEnv)=<private key>` (or add it to CI secrets). Never commit the key."
            )
        }

        // Write key to a 0600 temp file so it never appears in argv/ps output.
        let keyFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipcast-sparkle-\(UUID().uuidString).key")
        try privateKey.write(to: keyFile, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: keyFile.path)
        defer { try? FileManager.default.removeItem(at: keyFile) }

        let result = try shell.run("sign_update", args: ["-f", keyFile.path, artifact.path], env: nil)
        guard result.exitCode == 0 else {
            throw ShipcastError.signing(
                "sign_update \(artifact.lastPathComponent) failed (exit \(result.exitCode)): \(result.stderr)",
                fix: "Verify \(privateKeyEnv) contains the private key from `generate_keys` (base64, one line). If sign_update is missing, download Sparkle's distribution tools from https://github.com/sparkle-project/Sparkle/releases"
            )
        }

        // Output shape: sparkle:edSignature="..." length="..."
        guard let range = result.stdout.range(of: #"sparkle:edSignature="([^"]+)""#, options: .regularExpression) else {
            throw ShipcastError.signing(
                "sign_update produced unparseable output: \(result.stdout)",
                fix: "Run `sign_update -f <keyfile> \(artifact.path)` manually and check the output format; Shipcast expects sparkle:edSignature=\"...\""
            )
        }
        let matched = String(result.stdout[range])
        let signature = matched
            .replacingOccurrences(of: "sparkle:edSignature=\"", with: "")
            .replacingOccurrences(of: "\"", with: "")
        return signature
    }
}
```

- [ ] Run test, expect PASS: `swift test --filter SparkleSignerTests` → `Executed 4 tests, with 0 failures`

- [ ] Commit: `git add -A && git commit -m "Add SparkleSigner wrapping sign_update with env-only key handling"`

---

## Task 6: AppcastGenerator (golden-file XML test)

**Files:**
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastKit/Publish/AppcastGenerator.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastKit/Models/AppcastEntry.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/AppcastTests.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/Fixtures/Golden/appcast.xml`

**Interfaces:**
- Consumes: nothing from Plan A beyond Foundation
- Produces: `struct AppcastEntry { version, artifactURL, edSignature, lengthBytes, minSystemVersion: String?, notesHTML: String?, pubDate: Date }`, `AppcastGenerator.generate(releases: [AppcastEntry]) -> String`

**Steps:**

- [ ] Write golden appcast XML (shape verbatim from spec §Shipcast Cloud appcast example)
```xml
<!-- Tests/ShipcastKitTests/Fixtures/Golden/appcast.xml -->
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Burnt Updates</title>
    <description>Release feed for Burnt</description>
    <language>en</language>
    <item>
      <title>Version 1.2.0</title>
      <sparkle:version>1.2.0</sparkle:version>
      <pubDate>Wed, 01 Jul 2026 12:00:00 +0000</pubDate>
      <description><![CDATA[<p>Fixed bugs</p>]]></description>
      <enclosure url="https://github.com/mafex11/burnt/releases/download/v1.2.0/Burnt.zip"
                 length="12345678"
                 type="application/octet-stream"
                 sparkle:edSignature="MEUCIQDtest+sig==" />
      <sparkle:minimumSystemVersion>14.0</sparkle:minimumSystemVersion>
    </item>
    <item>
      <title>Version 1.1.0</title>
      <sparkle:version>1.1.0</sparkle:version>
      <pubDate>Mon, 01 Jun 2026 12:00:00 +0000</pubDate>
      <enclosure url="https://github.com/mafex11/burnt/releases/download/v1.1.0/Burnt.zip"
                 length="12000000"
                 type="application/octet-stream"
                 sparkle:edSignature="OLDSIG==" />
    </item>
  </channel>
</rss>
```

- [ ] Write failing golden-file test (feed title derives from the first entry's app context — pass appName explicitly)
```swift
// Tests/ShipcastKitTests/AppcastTests.swift
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
}
```

- [ ] Run test, expect FAIL: `swift test --filter AppcastTests` → compile error `cannot find 'AppcastGenerator' in scope`

- [ ] Implement AppcastEntry model + AppcastGenerator
```swift
// Sources/ShipcastKit/Models/AppcastEntry.swift
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
```
```swift
// Sources/ShipcastKit/Publish/AppcastGenerator.swift
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
```

- [ ] Run test, expect PASS: `swift test --filter AppcastTests` → `Executed 3 tests, with 0 failures` (if the pubDate strings mismatch, fix the GOLDEN file to the formatter output — the RFC822 shape from the spec is what matters, e.g. `Wed, 01 Jul 2026 12:00:00 +0000`)

- [ ] Commit: `git add -A && git commit -m "Add AppcastGenerator with golden-file Sparkle RSS test"`

---

## Task 7: Doctor checks (deliberately-broken fixture bundles)

**Files:**
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastKit/Doctor/Diagnostics.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/DoctorTests.swift`

**Interfaces:**
- Consumes: `ShipcastConfig` (`.permissions`, `.updates.sparkle`, `.sign.mode`), `ShellRunner` (real for integration checks, mock for unit tests), `TCCService`
- Produces: `struct DoctorFinding { check: String; status: pass/warn/fail; reason: String?; fix: String? }`, `Doctor.run(appURL:config:) -> [DoctorFinding]`

Checks implemented (verbatim from spec §shipcast doctor):
1. Bundle structure: `Contents/Info.plist` exists, `CFBundleIdentifier` present, `CFBundleExecutable` present and the executable file exists
2. Code signature: `codesign --verify --deep --strict <app>` exit 0
3. Gatekeeper: `spctl -a -t exec -vv <app>` contains "accepted"
4. Quarantine: `xattr -l <app>` contains `com.apple.quarantine` → fail for ad-hoc with fix `xattr -dr com.apple.quarantine <app>`
5. Staple (only when Developer ID signed): `xcrun stapler validate <app>` contains "validated"; ad-hoc gets pass "No notarization required (ad-hoc signed)"
6. TCC expectations: report declared `[permissions]` as warn "Not granted (first launch will prompt)" — no sudo DB reads in production
7. Sparkle (when `updates.sparkle == true`): `SUFeedURL` in Info.plist, `SUPublicEDKey` in Info.plist, feed URL reachable (HTTP 200), appcast XML parses, latest enclosure ed25519 signature verifies against public key (CryptoKit `Curve25519.Signing.PublicKey.isValidSignature`)

**Steps:**

- [ ] Write failing tests using deliberately-broken fixture bundles built in setUp (real filesystem, real codesign/xattr — these tools are on every macOS dev machine)
```swift
// Tests/ShipcastKitTests/DoctorTests.swift
import XCTest
@testable import ShipcastKit

final class DoctorTests: XCTestCase {
    var workDir: URL!

    override func setUpWithError() throws {
        workDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("shipcast-doctor-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workDir)
    }

    /// Builds a minimal valid .app bundle: Contents/Info.plist + Contents/MacOS/<name> (a compiled echo stub)
    func makeBundle(name: String, bundleID: String, extraPlist: [String: Any] = [:]) throws -> URL {
        let app = workDir.appendingPathComponent("\(name).app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        // Compile a real Mach-O so codesign works
        let source = workDir.appendingPathComponent("main.swift")
        try "print(\"hi\")".write(to: source, atomically: true, encoding: .utf8)
        let compile = Process()
        compile.executableURL = URL(fileURLWithPath: "/usr/bin/swiftc")
        compile.arguments = [source.path, "-o", macOS.appendingPathComponent(name).path]
        try compile.run(); compile.waitUntilExit()
        var plist: [String: Any] = [
            "CFBundleIdentifier": bundleID,
            "CFBundleExecutable": name,
            "CFBundleShortVersionString": "1.0.0",
        ]
        plist.merge(extraPlist) { _, new in new }
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: app.appendingPathComponent("Contents/Info.plist"))
        return app
    }

    func adhocSign(_ app: URL) throws {
        let sign = Process()
        sign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        sign.arguments = ["--force", "--deep", "--sign", "-", app.path]
        try sign.run(); sign.waitUntilExit()
        XCTAssertEqual(sign.terminationStatus, 0)
    }

    func makeConfig(permissions: [TCCService] = [], sparkle: Bool = false) -> ShipcastConfig {
        var config = ShipcastConfig.fixture()
        config.app.name = "DoctorFixture"
        config.app.bundleID = "dev.mafex.doctorfixture"
        config.sign.mode = .adhoc
        config.permissions = permissions
        config.updates.sparkle = sparkle
        return config
    }

    func finding(_ findings: [DoctorFinding], _ check: String) -> DoctorFinding? {
        findings.first { $0.check == check }
    }

    func testMissingInfoPlistFailsBundleStructure() throws {
        let app = workDir.appendingPathComponent("Broken.app")
        try FileManager.default.createDirectory(at: app.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let findings = Doctor(shell: ProcessShellRunner()).run(appURL: app, config: makeConfig())
        let f = try XCTUnwrap(finding(findings, "App bundle structure"))
        XCTAssertEqual(f.status, .fail)
        XCTAssertTrue(f.reason!.contains("Info.plist"))
    }

    func testUnsignedBundleFailsSignatureCheck() throws {
        let app = try makeBundle(name: "DoctorFixture", bundleID: "dev.mafex.doctorfixture")
        // remove the linker adhoc signature so verify fails
        let strip = Process()
        strip.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        strip.arguments = ["--remove-signature", app.appendingPathComponent("Contents/MacOS/DoctorFixture").path]
        try strip.run(); strip.waitUntilExit()
        let findings = Doctor(shell: ProcessShellRunner()).run(appURL: app, config: makeConfig())
        let f = try XCTUnwrap(finding(findings, "Code signature"))
        XCTAssertEqual(f.status, .fail)
        XCTAssertTrue(f.fix!.contains("codesign --force --deep --sign -"))
    }

    func testQuarantinedBundleFailsWithXattrFix() throws {
        let app = try makeBundle(name: "DoctorFixture", bundleID: "dev.mafex.doctorfixture")
        try adhocSign(app)
        let xattr = Process()
        xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        xattr.arguments = ["-w", "com.apple.quarantine", "0083;00000000;Safari;", app.path]
        try xattr.run(); xattr.waitUntilExit()
        let findings = Doctor(shell: ProcessShellRunner()).run(appURL: app, config: makeConfig())
        let f = try XCTUnwrap(finding(findings, "Quarantine"))
        XCTAssertEqual(f.status, .fail)
        XCTAssertEqual(f.fix, "xattr -dr com.apple.quarantine \(app.path)")
    }

    func testSealBrokenByTouchedResourceFailsSignatureCheck() throws {
        let app = try makeBundle(name: "DoctorFixture", bundleID: "dev.mafex.doctorfixture")
        try adhocSign(app)
        // Break the seal: add a resource AFTER signing (the #1 TCC-revocation cause per spec)
        let resources = app.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        try "sneaky".write(to: resources.appendingPathComponent("late.txt"), atomically: true, encoding: .utf8)
        let findings = Doctor(shell: ProcessShellRunner()).run(appURL: app, config: makeConfig())
        let f = try XCTUnwrap(finding(findings, "Code signature"))
        XCTAssertEqual(f.status, .fail)
        XCTAssertTrue(f.reason!.contains("seal") || f.reason!.contains("modified") || f.reason!.contains("failed"))
        XCTAssertTrue(f.fix!.contains("re-sign"))
    }

    func testHealthyAdhocBundlePassesCoreChecks() throws {
        let app = try makeBundle(name: "DoctorFixture", bundleID: "dev.mafex.doctorfixture")
        try adhocSign(app)
        let findings = Doctor(shell: ProcessShellRunner()).run(appURL: app, config: makeConfig())
        XCTAssertEqual(finding(findings, "App bundle structure")?.status, .pass)
        XCTAssertEqual(finding(findings, "Code signature")?.status, .pass)
        XCTAssertEqual(finding(findings, "Quarantine")?.status, .pass)
        XCTAssertEqual(finding(findings, "Notarization")?.status, .pass) // "No notarization required (ad-hoc signed)"
    }

    func testDeclaredPermissionsReportedAsWarn() throws {
        let app = try makeBundle(name: "DoctorFixture", bundleID: "dev.mafex.doctorfixture")
        try adhocSign(app)
        let findings = Doctor(shell: ProcessShellRunner()).run(appURL: app, config: makeConfig(permissions: [.accessibility, .screenRecording]))
        let f = try XCTUnwrap(finding(findings, "TCC permissions"))
        XCTAssertEqual(f.status, .warn)
        XCTAssertTrue(f.reason!.contains("Accessibility"))
        XCTAssertTrue(f.reason!.contains("ScreenCapture"))
    }

    func testSparkleMissingFeedURLFails() throws {
        let app = try makeBundle(name: "DoctorFixture", bundleID: "dev.mafex.doctorfixture",
                                 extraPlist: ["SUPublicEDKey": "pubkey=="])
        try adhocSign(app)
        let findings = Doctor(shell: ProcessShellRunner()).run(appURL: app, config: makeConfig(sparkle: true))
        let f = try XCTUnwrap(finding(findings, "Sparkle SUFeedURL"))
        XCTAssertEqual(f.status, .fail)
        XCTAssertTrue(f.fix!.contains("SUFeedURL"))
    }
}
```

- [ ] Run test, expect FAIL: `swift test --filter DoctorTests` → compile error `cannot find 'Doctor' in scope`

- [ ] Implement DoctorFinding + Doctor
```swift
// Sources/ShipcastKit/Doctor/Diagnostics.swift
import Foundation
import CryptoKit

public struct DoctorFinding: Sendable, Equatable {
    public enum Status: Sendable, Equatable { case pass, warn, fail }
    public var check: String
    public var status: Status
    public var reason: String?
    public var fix: String?

    public init(check: String, status: Status, reason: String? = nil, fix: String? = nil) {
        self.check = check
        self.status = status
        self.reason = reason
        self.fix = fix
    }
}

public struct Doctor: Sendable {
    let shell: any ShellRunner

    public init(shell: any ShellRunner) {
        self.shell = shell
    }

    public func run(appURL: URL, config: ShipcastConfig) -> [DoctorFinding] {
        var findings: [DoctorFinding] = []
        let plist = loadInfoPlist(appURL: appURL)

        findings.append(checkBundleStructure(appURL: appURL, plist: plist))
        findings.append(checkCodeSignature(appURL: appURL))
        findings.append(checkGatekeeper(appURL: appURL, config: config))
        findings.append(checkQuarantine(appURL: appURL, config: config))
        findings.append(checkNotarization(appURL: appURL, config: config))
        if !config.permissions.isEmpty {
            findings.append(checkTCC(config: config))
        }
        if config.updates.sparkle {
            findings.append(contentsOf: checkSparkle(plist: plist))
        }
        return findings
    }

    func loadInfoPlist(appURL: URL) -> [String: Any] {
        let url = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }

    func checkBundleStructure(appURL: URL, plist: [String: Any]) -> DoctorFinding {
        let plistPath = appURL.appendingPathComponent("Contents/Info.plist").path
        guard FileManager.default.fileExists(atPath: plistPath), !plist.isEmpty else {
            return DoctorFinding(check: "App bundle structure", status: .fail,
                                 reason: "Contents/Info.plist missing or unreadable",
                                 fix: "Rebuild the app: `shipcast build` regenerates the bundle with a valid Info.plist")
        }
        guard plist["CFBundleIdentifier"] is String else {
            return DoctorFinding(check: "App bundle structure", status: .fail,
                                 reason: "CFBundleIdentifier missing from Info.plist",
                                 fix: "Set bundle_id in shipcast.toml [app] and rebuild with `shipcast build`")
        }
        guard let exec = plist["CFBundleExecutable"] as? String,
              FileManager.default.isExecutableFile(atPath: appURL.appendingPathComponent("Contents/MacOS/\(exec)").path)
        else {
            return DoctorFinding(check: "App bundle structure", status: .fail,
                                 reason: "CFBundleExecutable missing or the executable file does not exist",
                                 fix: "Rebuild with `shipcast build`; the executable must live at Contents/MacOS/<CFBundleExecutable>")
        }
        return DoctorFinding(check: "App bundle structure", status: .pass)
    }

    func checkCodeSignature(appURL: URL) -> DoctorFinding {
        guard let result = try? shell.run("codesign", args: ["--verify", "--deep", "--strict", appURL.path], env: nil) else {
            return DoctorFinding(check: "Code signature", status: .fail, reason: "codesign could not be executed",
                                 fix: "Install Xcode command line tools: xcode-select --install")
        }
        if result.exitCode == 0 {
            return DoctorFinding(check: "Code signature", status: .pass)
        }
        let sealBroken = result.stderr.contains("modified") || result.stderr.contains("sealed resource")
        return DoctorFinding(
            check: "Code signature", status: .fail,
            reason: sealBroken
                ? "code seal broken — a file was added or modified after signing: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
                : "codesign --verify --deep --strict failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))",
            fix: "Add all resources BEFORE signing, then re-sign as the final step: codesign --force --deep --sign - \(appURL.path)"
        )
    }

    func checkGatekeeper(appURL: URL, config: ShipcastConfig) -> DoctorFinding {
        guard let result = try? shell.run("spctl", args: ["-a", "-t", "exec", "-vv", appURL.path], env: nil) else {
            return DoctorFinding(check: "Gatekeeper assessment", status: .warn, reason: "spctl could not be executed", fix: nil)
        }
        let combined = result.stdout + result.stderr
        if combined.contains("accepted") {
            return DoctorFinding(check: "Gatekeeper assessment", status: .pass)
        }
        if config.sign.mode == .adhoc {
            return DoctorFinding(check: "Gatekeeper assessment", status: .warn,
                                 reason: "ad-hoc signed apps are always rejected by spctl; users launch via the cask quarantine strip",
                                 fix: "Expected for ad-hoc. Distribute via the generated cask (strips quarantine in postflight) or notarize with a Developer ID cert")
        }
        return DoctorFinding(check: "Gatekeeper assessment", status: .fail,
                             reason: combined.trimmingCharacters(in: .whitespacesAndNewlines),
                             fix: "Notarize the app: `shipcast sign` with APPLE_ID/APPLE_TEAM_ID/APPLE_APP_PASSWORD set, then `xcrun stapler staple \(appURL.path)`")
    }

    func checkQuarantine(appURL: URL, config: ShipcastConfig) -> DoctorFinding {
        guard let result = try? shell.run("xattr", args: ["-l", appURL.path], env: nil) else {
            return DoctorFinding(check: "Quarantine", status: .warn, reason: "xattr could not be executed", fix: nil)
        }
        if result.stdout.contains("com.apple.quarantine") {
            return DoctorFinding(check: "Quarantine", status: .fail,
                                 reason: "com.apple.quarantine attribute present — ad-hoc apps show \"damaged and can't be opened\"",
                                 fix: "xattr -dr com.apple.quarantine \(appURL.path)")
        }
        return DoctorFinding(check: "Quarantine", status: .pass)
    }

    func checkNotarization(appURL: URL, config: ShipcastConfig) -> DoctorFinding {
        if config.sign.mode != .developerID {
            return DoctorFinding(check: "Notarization", status: .pass,
                                 reason: "No notarization required (ad-hoc signed)")
        }
        guard let result = try? shell.run("xcrun", args: ["stapler", "validate", appURL.path], env: nil) else {
            return DoctorFinding(check: "Notarization", status: .fail, reason: "stapler could not be executed",
                                 fix: "Install Xcode command line tools: xcode-select --install")
        }
        if result.exitCode == 0 {
            return DoctorFinding(check: "Notarization", status: .pass)
        }
        return DoctorFinding(check: "Notarization", status: .fail,
                             reason: "notarization ticket not stapled: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))",
                             fix: "xcrun notarytool submit <zip> --apple-id $APPLE_ID --team-id $APPLE_TEAM_ID --password $APPLE_APP_PASSWORD --wait && xcrun stapler staple \(appURL.path)")
    }

    func checkTCC(config: ShipcastConfig) -> DoctorFinding {
        let names = config.permissions.map(\.rawValue).joined(separator: ", ")
        return DoctorFinding(check: "TCC permissions", status: .warn,
                             reason: "Expected: \(names). Status: Not granted (first launch will prompt)",
                             fix: nil)
    }

    func checkSparkle(plist: [String: Any]) -> [DoctorFinding] {
        var findings: [DoctorFinding] = []

        guard let feedString = plist["SUFeedURL"] as? String, let feedURL = URL(string: feedString) else {
            findings.append(DoctorFinding(check: "Sparkle SUFeedURL", status: .fail,
                                          reason: "SUFeedURL missing from Info.plist",
                                          fix: "Add SUFeedURL to Info.plist (shipcast build injects it when [updates] sparkle = true)"))
            return findings
        }
        findings.append(DoctorFinding(check: "Sparkle SUFeedURL", status: .pass))

        guard let publicKeyB64 = plist["SUPublicEDKey"] as? String else {
            findings.append(DoctorFinding(check: "Sparkle SUPublicEDKey", status: .fail,
                                          reason: "SUPublicEDKey missing from Info.plist",
                                          fix: "Run Sparkle's generate_keys and add the public key as SUPublicEDKey in Info.plist"))
            return findings
        }
        findings.append(DoctorFinding(check: "Sparkle SUPublicEDKey", status: .pass))

        // Feed reachability + parse + signature: synchronous fetch with short timeout
        let semaphore = DispatchSemaphore(value: 0)
        var fetched: (data: Data?, status: Int) = (nil, 0)
        let task = URLSession.shared.dataTask(with: feedURL) { data, response, _ in
            fetched = (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10)

        guard fetched.status == 200, let xmlData = fetched.data else {
            findings.append(DoctorFinding(check: "Sparkle feed reachable", status: .fail,
                                          reason: "GET \(feedString) returned HTTP \(fetched.status)",
                                          fix: "Publish a release first (`shipcast release`), or check the feed URL. Self-hosted feeds: verify the file is deployed"))
            return findings
        }
        findings.append(DoctorFinding(check: "Sparkle feed reachable", status: .pass))

        let parser = AppcastParser() // simple XMLParser delegate extracting first enclosure url + edSignature
        guard let latest = parser.parseLatestEnclosure(data: xmlData) else {
            findings.append(DoctorFinding(check: "Appcast XML", status: .fail,
                                          reason: "appcast did not parse or contains no enclosure",
                                          fix: "Regenerate the appcast: `shipcast release` writes valid Sparkle RSS; validate with `xmllint --noout appcast.xml`"))
            return findings
        }
        findings.append(DoctorFinding(check: "Appcast XML", status: .pass))

        findings.append(verifyEdSignature(enclosure: latest, publicKeyB64: publicKeyB64))
        return findings
    }

    func verifyEdSignature(enclosure: (url: URL, edSignature: String), publicKeyB64: String) -> DoctorFinding {
        guard let keyData = Data(base64Encoded: publicKeyB64),
              let sigData = Data(base64Encoded: enclosure.edSignature),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            return DoctorFinding(check: "Ed25519 signature", status: .fail,
                                 reason: "SUPublicEDKey or edSignature is not valid base64/ed25519 material",
                                 fix: "Re-run generate_keys and re-sign the artifact with sign_update; update SUPublicEDKey in Info.plist")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var artifactData: Data?
        URLSession.shared.dataTask(with: enclosure.url) { data, _, _ in
            artifactData = data
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 60)
        guard let artifact = artifactData else {
            return DoctorFinding(check: "Ed25519 signature", status: .warn,
                                 reason: "could not download enclosure to verify signature",
                                 fix: "Check the enclosure URL is publicly downloadable: curl -IL \(enclosure.url.absoluteString)")
        }
        if publicKey.isValidSignature(sigData, for: artifact) {
            return DoctorFinding(check: "Ed25519 signature", status: .pass)
        }
        return DoctorFinding(check: "Ed25519 signature", status: .fail,
                             reason: "enclosure signature does not verify against SUPublicEDKey — updates will be rejected by Sparkle",
                             fix: "Re-sign the artifact with the matching key: sign_update <zip> using the private key whose public half is in Info.plist, then republish the appcast")
    }
}

/// Minimal XMLParser delegate: returns the first <enclosure> url + sparkle:edSignature.
final class AppcastParser: NSObject, XMLParserDelegate {
    private var result: (url: URL, edSignature: String)?

    func parseLatestEnclosure(data: Data) -> (url: URL, edSignature: String)? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() || result != nil else { return nil }
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard result == nil, elementName == "enclosure",
              let urlString = attributeDict["url"], let url = URL(string: urlString),
              let sig = attributeDict["sparkle:edSignature"] else { return }
        result = (url, sig)
        parser.abortParsing()
    }
}
```

- [ ] Run test, expect PASS: `swift test --filter DoctorTests` → `Executed 7 tests, with 0 failures`

- [ ] Commit: `git add -A && git commit -m "Add Doctor with bundle/signature/gatekeeper/quarantine/staple/TCC/Sparkle checks"`

---

## Task 8: Doctor output rendering (✓/✗/! format verbatim)

**Files:**
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastKit/Doctor/DoctorRenderer.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastCLI/Doctor.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/DoctorRendererTests.swift`

**Interfaces:**
- Consumes: `[DoctorFinding]`
- Produces: `DoctorRenderer.render(_ findings: [DoctorFinding]) -> String` and `DoctorRenderer.exitCode(for findings: [DoctorFinding]) -> Int32`; CLI subcommand `shipcast doctor [app-path]`

**Steps:**

- [ ] Write failing test asserting the exact output format from spec §shipcast doctor Output Format
```swift
// Tests/ShipcastKitTests/DoctorRendererTests.swift
import XCTest
@testable import ShipcastKit

final class DoctorRendererTests: XCTestCase {
    func testRendersSpecFormatExactly() {
        let findings: [DoctorFinding] = [
            DoctorFinding(check: "App bundle structure valid", status: .pass),
            DoctorFinding(check: "Code signature valid (ad-hoc)", status: .pass),
            DoctorFinding(check: "Gatekeeper assessment failed", status: .fail,
                          reason: "com.apple.quarantine attribute present",
                          fix: "xattr -dr com.apple.quarantine MyApp.app"),
            DoctorFinding(check: "No notarization required (ad-hoc signed)", status: .pass),
            DoctorFinding(check: "TCC permissions not granted yet", status: .warn,
                          reason: "Expected: Accessibility, ScreenCapture\nStatus: Not granted (first launch will prompt)"),
            DoctorFinding(check: "Sparkle feed reachable", status: .pass),
            DoctorFinding(check: "Appcast XML valid", status: .pass),
            DoctorFinding(check: "Ed25519 signature valid", status: .pass),
        ]
        let expected = """
        ✓ App bundle structure valid
        ✓ Code signature valid (ad-hoc)
        ✗ Gatekeeper assessment failed
          Reason: com.apple.quarantine attribute present
          Fix: xattr -dr com.apple.quarantine MyApp.app
        ✓ No notarization required (ad-hoc signed)
        ! TCC permissions not granted yet
          Expected: Accessibility, ScreenCapture
          Status: Not granted (first launch will prompt)
        ✓ Sparkle feed reachable
        ✓ Appcast XML valid
        ✓ Ed25519 signature valid

        Summary: 1 error, 1 warning. Run fix commands above.
        """
        XCTAssertEqual(DoctorRenderer.render(findings), expected)
    }

    func testAllPassSummary() {
        let findings = [DoctorFinding(check: "App bundle structure valid", status: .pass)]
        XCTAssertTrue(DoctorRenderer.render(findings).hasSuffix("Summary: 0 errors, 0 warnings. All checks passed."))
    }

    func testExitCodes() {
        XCTAssertEqual(DoctorRenderer.exitCode(for: [DoctorFinding(check: "x", status: .pass)]), 0)
        XCTAssertEqual(DoctorRenderer.exitCode(for: [DoctorFinding(check: "x", status: .warn)]), 0)
        XCTAssertEqual(DoctorRenderer.exitCode(for: [DoctorFinding(check: "x", status: .fail)]), 1)
    }
}
```

- [ ] Run test, expect FAIL: `swift test --filter DoctorRendererTests` → compile error `cannot find 'DoctorRenderer' in scope`

- [ ] Implement DoctorRenderer
```swift
// Sources/ShipcastKit/Doctor/DoctorRenderer.swift
import Foundation

public enum DoctorRenderer {
    public static func render(_ findings: [DoctorFinding]) -> String {
        var lines: [String] = []
        for finding in findings {
            switch finding.status {
            case .pass:
                lines.append("✓ \(finding.check)")
            case .fail:
                lines.append("✗ \(finding.check)")
                if let reason = finding.reason {
                    lines.append("  Reason: \(reason)")
                }
                if let fix = finding.fix {
                    lines.append("  Fix: \(fix)")
                }
            case .warn:
                lines.append("! \(finding.check)")
                if let reason = finding.reason {
                    for reasonLine in reason.split(separator: "\n", omittingEmptySubsequences: false) {
                        lines.append("  \(reasonLine)")
                    }
                }
                if let fix = finding.fix {
                    lines.append("  Fix: \(fix)")
                }
            }
        }
        let errors = findings.filter { $0.status == .fail }.count
        let warnings = findings.filter { $0.status == .warn }.count
        lines.append("")
        if errors == 0 && warnings == 0 {
            lines.append("Summary: 0 errors, 0 warnings. All checks passed.")
        } else {
            let errorWord = errors == 1 ? "error" : "errors"
            let warnWord = warnings == 1 ? "warning" : "warnings"
            lines.append("Summary: \(errors) \(errorWord), \(warnings) \(warnWord). Run fix commands above.")
        }
        return lines.joined(separator: "\n")
    }

    public static func exitCode(for findings: [DoctorFinding]) -> Int32 {
        findings.contains { $0.status == .fail } ? 1 : 0
    }
}
```

- [ ] Run test, expect PASS: `swift test --filter DoctorRendererTests` → `Executed 3 tests, with 0 failures`

- [ ] Wire the CLI subcommand
```swift
// Sources/ShipcastCLI/Doctor.swift
import ArgumentParser
import Foundation
import ShipcastKit

struct DoctorCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor",
        abstract: "Diagnose Gatekeeper/TCC/signing failures"
    )

    @Argument(help: "Path to the .app bundle (default: newest .app under .build/release or .shipcast/build)")
    var appPath: String?

    func run() throws {
        let config = try ConfigLoader.load(from: URL(fileURLWithPath: "shipcast.toml"))
        let appURL: URL
        if let appPath {
            appURL = URL(fileURLWithPath: appPath)
        } else {
            // SwiftPM builds land in .build/release (Plan A); Xcode exports in .shipcast/build (Task 1)
            let candidateDirs = [URL(fileURLWithPath: ".build/release"), URL(fileURLWithPath: ".shipcast/build/export")]
            let apps = candidateDirs.flatMap { dir in
                ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [])
                    .filter { $0.pathExtension == "app" }
            }
            guard let newest = apps.max(by: { (lhs, rhs) in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l < r
            }) else {
                throw ShipcastError.config(
                    "No .app found under .build/release or .shipcast/build/export, and no path given",
                    fix: "Run `shipcast build` first, or pass a path: `shipcast doctor /path/to/MyApp.app`"
                )
            }
            appURL = newest
        }
        let findings = Doctor(shell: ProcessShellRunner()).run(appURL: appURL, config: config)
        print(DoctorRenderer.render(findings))
        Foundation.exit(DoctorRenderer.exitCode(for: findings))
    }
}
```
And register in main.swift subcommands list: `DoctorCommand.self`.

- [ ] Run full suite + smoke test, expect PASS: `swift test` → 0 failures; `swift run shipcast doctor --help` prints usage

- [ ] Commit: `git add -A && git commit -m "Add doctor output renderer and CLI subcommand"`

---

## Task 9: CloudClient (URLProtocol-mocked HTTP)

**Files:**
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastKit/Push/CloudClient.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/CloudClientTests.swift`

**Interfaces:**
- Consumes: `AppcastEntry`, `ShipcastError.publish`
- Produces: `CloudClient.push(release:token:baseURL:) throws` — POST `/api/v1/apps/:app/releases` with bearer token and JSON body exactly per spec: `version/artifact_url/sha256/ed_signature/length/min_system_version/release_notes_html/channel`

**Steps:**

- [ ] Write failing test with a URLProtocol mock
```swift
// Tests/ShipcastKitTests/CloudClientTests.swift
import XCTest
@testable import ShipcastKit

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else { fatalError("handler unset") }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class CloudClientTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    var entry: AppcastEntry {
        AppcastEntry(
            version: "1.2.0",
            artifactURL: URL(string: "https://github.com/mafex11/burnt/releases/download/v1.2.0/Burnt.zip")!,
            edSignature: "MEUCIQDtest+sig==",
            lengthBytes: 12_345_678,
            minSystemVersion: "14.0",
            notesHTML: "<p>Fixed bugs</p>",
            pubDate: Date()
        )
    }

    func testPushSendsExactJSONBodyAndBearerToken() throws {
        nonisolated(unsafe) var captured: URLRequest?
        nonisolated(unsafe) var capturedBody: Data?
        MockURLProtocol.handler = { request in
            captured = request
            capturedBody = request.httpBody ?? request.httpBodyStream.map { stream in
                stream.open(); defer { stream.close() }
                var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(buffer, count: read)
                }
                return data
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"id\":\"rel_123\"}".utf8))
        }

        let client = CloudClient(appSlug: "burnt", sha256: "abc123", session: session)
        try client.push(release: entry, token: "sct_secret", baseURL: URL(string: "https://shipcast.devmafex.com")!)

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/apps/burnt/releases")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sct_secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(capturedBody)) as! [String: Any]
        XCTAssertEqual(body["version"] as? String, "1.2.0")
        XCTAssertEqual(body["artifact_url"] as? String, "https://github.com/mafex11/burnt/releases/download/v1.2.0/Burnt.zip")
        XCTAssertEqual(body["sha256"] as? String, "abc123")
        XCTAssertEqual(body["ed_signature"] as? String, "MEUCIQDtest+sig==")
        XCTAssertEqual(body["length"] as? Int, 12_345_678)
        XCTAssertEqual(body["min_system_version"] as? String, "14.0")
        XCTAssertEqual(body["release_notes_html"] as? String, "<p>Fixed bugs</p>")
        XCTAssertEqual(body["channel"] as? String, "stable")
    }

    func test401ThrowsPublishErrorWithTokenFix() throws {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             Data("{\"error\":\"invalid token\"}".utf8))
        }
        let client = CloudClient(appSlug: "burnt", sha256: "abc123", session: session)
        XCTAssertThrowsError(try client.push(release: entry, token: "bad", baseURL: URL(string: "https://shipcast.devmafex.com")!)) { error in
            guard case ShipcastError.publish(let message, let fix) = error else {
                return XCTFail("expected .publish, got \(error)")
            }
            XCTAssertTrue(message.contains("401"))
            XCTAssertTrue(fix.contains("SHIPCAST_TOKEN"))
        }
    }

    func test409DuplicateVersionThrowsPublishError() throws {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!,
             Data("{\"error\":\"version already published\"}".utf8))
        }
        let client = CloudClient(appSlug: "burnt", sha256: "abc123", session: session)
        XCTAssertThrowsError(try client.push(release: entry, token: "sct_secret", baseURL: URL(string: "https://shipcast.devmafex.com")!)) { error in
            guard case ShipcastError.publish(let message, _) = error else {
                return XCTFail("expected .publish, got \(error)")
            }
            XCTAssertTrue(message.contains("409"))
        }
    }
}
```

- [ ] Run test, expect FAIL: `swift test --filter CloudClientTests` → compile error `cannot find 'CloudClient' in scope`

- [ ] Implement CloudClient
```swift
// Sources/ShipcastKit/Push/CloudClient.swift
import Foundation

public struct CloudClient: Sendable {
    let appSlug: String
    let sha256: String
    let session: URLSession

    public init(appSlug: String, sha256: String, session: URLSession = .shared) {
        self.appSlug = appSlug
        self.sha256 = sha256
        self.session = session
    }

    public func push(release: AppcastEntry, token: String, baseURL: URL) throws {
        var request = URLRequest(url: baseURL.appendingPathComponent("api/v1/apps/\(appSlug)/releases"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "version": release.version,
            "artifact_url": release.artifactURL.absoluteString,
            "sha256": sha256,
            "ed_signature": release.edSignature,
            "length": release.lengthBytes,
            "channel": "stable",
        ]
        if let minOS = release.minSystemVersion { body["min_system_version"] = minOS }
        if let notes = release.notesHTML { body["release_notes_html"] = notes }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: (status: Int, body: String, transportError: Error?) = (0, "", nil)
        session.dataTask(with: request) { data, response, error in
            outcome = (
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                data.map { String(decoding: $0, as: UTF8.self) } ?? "",
                error
            )
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let transportError = outcome.transportError {
            throw ShipcastError.publish(
                "POST \(request.url!.absoluteString) failed: \(transportError.localizedDescription)",
                fix: "Check network connectivity and that \(baseURL.host ?? "the host") resolves: curl -I \(baseURL.absoluteString)"
            )
        }
        switch outcome.status {
        case 200, 201:
            return
        case 401, 403:
            throw ShipcastError.publish(
                "POST \(request.url!.absoluteString) returned HTTP \(outcome.status): \(outcome.body)",
                fix: "Your API token is invalid or missing. Get a fresh token from the Shipcast dashboard (Settings → API Tokens) and `export SHIPCAST_TOKEN=<token>` or pass --token"
            )
        case 409:
            throw ShipcastError.publish(
                "POST \(request.url!.absoluteString) returned HTTP 409: version \(release.version) already published",
                fix: "Bump the version (new git tag) and release again; published versions are immutable"
            )
        default:
            throw ShipcastError.publish(
                "POST \(request.url!.absoluteString) returned HTTP \(outcome.status): \(outcome.body)",
                fix: "Retry; if it persists check https://shipcast.devmafex.com status or push later — the GitHub release and cask already succeeded"
            )
        }
    }
}
```

- [ ] Run test, expect PASS: `swift test --filter CloudClientTests` → `Executed 3 tests, with 0 failures`

- [ ] Commit: `git add -A && git commit -m "Add CloudClient POSTing release metadata with bearer auth"`

---

## Task 10: ReleaseCommand + PushCommand wiring + end-to-end + burnt acceptance

**Files:**
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastKit/ReleasePipeline.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastCLI/Release.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Sources/ShipcastCLI/Push.swift`
- Create: `/Users/mafex/code/personal/ShipCast/Tests/ShipcastKitTests/ReleasePipelineTests.swift`

**Interfaces:**
- Consumes: everything — `SwiftPMBuilder.build(config:at:shell:)`, `XcodeBuilder.build(config:at:)`, `Signer.sign(_:config:shell:)`, `Packager.package(_:config:shell:)`, `GitHubReleaser.createRelease(config:artifacts:notes:)`, `CaskGenerator.generate(config:artifacts:releaseURL:)`, `CaskPublisher.publish(cask:config:)`, `SparkleSigner.sign(artifact:privateKeyEnv:)`, `AppcastGenerator.generate(releases:)`, `CloudClient.push(release:token:baseURL:)`
- Produces: `ReleasePipeline.run(config:at:dryRun:) throws -> ReleaseReport`, CLI subcommands `shipcast release [--dry-run] [--feed <kind>] [--notes <text>]` and `shipcast push [--token <token>]`

**Steps:**

- [ ] Write failing pipeline test against the MiniSwiftPM fixture with ALL shell calls mocked
```swift
// Tests/ShipcastKitTests/ReleasePipelineTests.swift
import XCTest
@testable import ShipcastKit

final class ReleasePipelineTests: XCTestCase {
    func makeShell() -> MockShellRunner {
        let shell = MockShellRunner()
        shell.stub(command: "swift", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        shell.stub(command: "codesign", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        shell.stub(command: "security", result: ShellResult(exitCode: 0, stdout: "", stderr: "")) // no Developer ID → adhoc
        shell.stub(command: "ditto", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        shell.stub(command: "shasum", result: ShellResult(exitCode: 0, stdout: "abc123  Burnt.zip\n", stderr: ""))
        shell.stub(command: "gh", args: ["api", "user", "--jq", ".login"],
                   result: ShellResult(exitCode: 0, stdout: "mafex11\n", stderr: ""))
        shell.stub(command: "gh", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        shell.stub(command: "git", result: ShellResult(exitCode: 0, stdout: "", stderr: ""))
        shell.stub(command: "sign_update", result: ShellResult(
            exitCode: 0, stdout: "sparkle:edSignature=\"SIG==\" length=\"999\"\n", stderr: ""))
        return shell
    }

    func makeConfig(feed: ShipcastConfig.FeedKind) -> ShipcastConfig {
        var config = ShipcastConfig.fixture()
        config.app.name = "Burnt"
        config.app.bundleID = "dev.mafex.burnt"
        config.app.version = "1.2.0"
        config.app.project = .swiftpm
        config.sign.mode = .adhoc
        config.distribute.githubRepo = "mafex11/burnt"
        config.distribute.homebrewTap = "mafex11/homebrew-tap"
        config.distribute.formats = [.zip]
        config.updates.sparkle = true
        config.updates.feed = feed
        return config
    }

    var fixtureRoot: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/MiniSwiftPM")
    }

    func testFullPipelineOrderAndReport() throws {
        let shell = makeShell()
        let pipeline = ReleasePipeline(
            shell: shell,
            environment: ["SPARKLE_PRIVATE_KEY": "b64key"]
        )
        let report = try pipeline.run(config: makeConfig(feed: .selfHosted(url: "https://example.com/appcast.xml")), at: fixtureRoot, dryRun: false)

        // Pipeline order: build (swift) → sign (codesign) → package (ditto) → sparkle sign → gh release → cask push
        let commands = shell.calls.map(\.command)
        let swiftIdx = commands.firstIndex(of: "swift")!
        let codesignIdx = commands.lastIndex(of: "codesign")!
        let dittoIdx = commands.lastIndex(of: "ditto")!
        let signUpdateIdx = commands.firstIndex(of: "sign_update")!
        let ghReleaseIdx = shell.calls.firstIndex { $0.command == "gh" && $0.args.first == "release" }!
        XCTAssertLessThan(swiftIdx, codesignIdx)
        XCTAssertLessThan(codesignIdx, dittoIdx)   // adhoc deep sign is FINAL step before zip
        XCTAssertLessThan(dittoIdx, signUpdateIdx)
        XCTAssertLessThan(signUpdateIdx, ghReleaseIdx)

        XCTAssertEqual(report.assetURL.absoluteString,
                       "https://github.com/mafex11/burnt/releases/download/v1.2.0/Burnt.zip")
        XCTAssertEqual(report.edSignature, "SIG==")
        XCTAssertTrue(report.appcastXML.contains("sparkle:edSignature=\"SIG==\""))
        XCTAssertTrue(report.appcastXML.contains("Version 1.2.0"))
        XCTAssertFalse(report.pushedToCloud) // self-hosted feed → no cloud push
        // Self-hosted: appcast written next to artifacts
        XCTAssertTrue(FileManager.default.fileExists(atPath: report.appcastFileURL!.path))
    }

    func testHostedFeedPushesToCloud() throws {
        let shell = makeShell()
        nonisolated(unsafe) var pushed = false
        let pipeline = ReleasePipeline(
            shell: shell,
            environment: ["SPARKLE_PRIVATE_KEY": "b64key", "SHIPCAST_TOKEN": "sct_secret"],
            cloudPush: { _, _, _ in pushed = true }
        )
        let report = try pipeline.run(config: makeConfig(feed: .hosted), at: fixtureRoot, dryRun: false)
        XCTAssertTrue(pushed)
        XCTAssertTrue(report.pushedToCloud)
    }

    func testFeedNoneSkipsSparkleAndCloud() throws {
        let shell = makeShell()
        var config = makeConfig(feed: .none)
        config.updates.sparkle = false
        let pipeline = ReleasePipeline(shell: shell, environment: [:])
        let report = try pipeline.run(config: config, at: fixtureRoot, dryRun: false)
        XCTAssertFalse(shell.calls.contains { $0.command == "sign_update" })
        XCTAssertEqual(report.edSignature, nil)
        XCTAssertFalse(report.pushedToCloud)
    }

    func testDryRunExecutesBuildSignPackageButNoPublish() throws {
        let shell = makeShell()
        let pipeline = ReleasePipeline(shell: shell, environment: ["SPARKLE_PRIVATE_KEY": "b64key"])
        let report = try pipeline.run(config: makeConfig(feed: .hosted), at: fixtureRoot, dryRun: true)
        // Local stages run
        XCTAssertTrue(shell.calls.contains { $0.command == "ditto" })
        // No remote side effects
        XCTAssertFalse(shell.calls.contains { $0.command == "gh" && $0.args.first == "release" })
        XCTAssertFalse(shell.calls.contains { $0.command == "git" && $0.args.contains("push") })
        XCTAssertFalse(report.pushedToCloud)
        // Report still previews the cask and appcast
        XCTAssertTrue(report.caskPreview!.contains("cask \"burnt\""))
        XCTAssertTrue(report.appcastXML.contains("Version 1.2.0"))
    }

    func testPublishFailurePropagatesExitCode5() throws {
        let shell = makeShell()
        shell.stub(command: "gh", args: ["release"], result: ShellResult(exitCode: 1, stdout: "", stderr: "HTTP 401"))
        let pipeline = ReleasePipeline(shell: shell, environment: ["SPARKLE_PRIVATE_KEY": "b64key"])
        XCTAssertThrowsError(try pipeline.run(config: makeConfig(feed: .none), at: fixtureRoot, dryRun: false)) { error in
            XCTAssertEqual((error as? ShipcastError)?.exitCode, 5)
        }
    }
}
```

- [ ] Run test, expect FAIL: `swift test --filter ReleasePipelineTests` → compile error `cannot find 'ReleasePipeline' in scope`

- [ ] Implement ReleasePipeline in ShipcastKit (CLI stays thin)
```swift
// Sources/ShipcastKit/ReleasePipeline.swift
import Foundation

public struct ReleaseReport: Sendable {
    public var assetURL: URL
    public var edSignature: String?
    public var appcastXML: String
    public var appcastFileURL: URL?
    public var caskPreview: String?
    public var pushedToCloud: Bool
}

public struct ReleasePipeline {
    let shell: any ShellRunner
    let environment: [String: String]
    let cloudPush: (AppcastEntry, String, URL) throws -> Void

    public init(
        shell: any ShellRunner,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        cloudPush: ((AppcastEntry, String, URL) throws -> Void)? = nil
    ) {
        self.shell = shell
        self.environment = environment
        self.cloudPush = cloudPush ?? { entry, token, baseURL in
            // sha256 threaded via entry context in the default closure below; overridden in run()
            fatalError("cloudPush default installed in run()")
        }
    }

    public func run(config: ShipcastConfig, at root: URL, dryRun: Bool) throws -> ReleaseReport {
        // 1. Build
        let artifact: BuildArtifact
        switch config.app.project {
        case .xcode:
            artifact = try XcodeBuilder(shell: shell).build(config: config, at: root)
        case .swiftpm, .auto:
            artifact = try SwiftPMBuilder.build(config: config, at: root, shell: shell)
        }

        // 2. Sign (ad-hoc deep sign is the FINAL mutation before packaging)
        let signed = try Signer.sign(artifact, config: config, shell: shell)

        // 3. Package (ditto -c -k --sequesterRsrc --keepParent, sha256, optional DMG)
        let packaged = try Packager.package(signed, config: config, shell: shell)

        // 4. Sparkle ed25519 sign (before publish so the signature ships in the appcast)
        var edSignature: String?
        if config.updates.sparkle {
            edSignature = try SparkleSigner(shell: shell, environment: environment)
                .sign(artifact: packaged.zipURL, privateKeyEnv: "SPARKLE_PRIVATE_KEY")
        }

        // Asset URL is deterministic from repo + tag + zip name — computable in dry-run too
        let tag = "v\(config.app.version)"
        let zipName = packaged.zipURL.lastPathComponent
        let predictedAssetURL = URL(string: "https://github.com/\(config.distribute.githubRepo ?? "")/releases/download/\(tag)/\(zipName)")!

        // 5. GitHub release
        var assetURL = predictedAssetURL
        if !dryRun {
            assetURL = try GitHubReleaser(shell: shell)
                .createRelease(config: config, artifacts: packaged, notes: environment["SHIPCAST_NOTES"] ?? "")
        }

        // 6. Cask
        let cask = CaskGenerator().generate(config: config, artifacts: packaged, releaseURL: assetURL)
        if !dryRun, config.distribute.homebrewTap != nil {
            try CaskPublisher(shell: shell).publish(cask: cask, config: config)
        }

        // 7. Appcast
        var appcastXML = ""
        var appcastFileURL: URL?
        var entry: AppcastEntry?
        if config.updates.sparkle, let signature = edSignature {
            let newEntry = AppcastEntry(
                version: config.app.version,
                artifactURL: assetURL,
                edSignature: signature,
                lengthBytes: packaged.lengthBytes,
                minSystemVersion: "14.0",
                notesHTML: environment["SHIPCAST_NOTES"],
                pubDate: Date()
            )
            entry = newEntry
            appcastXML = AppcastGenerator(appName: config.app.name).generate(releases: [newEntry])

            if case .selfHosted = config.updates.feed {
                let outURL = packaged.zipURL.deletingLastPathComponent().appendingPathComponent("appcast.xml")
                try appcastXML.write(to: outURL, atomically: true, encoding: .utf8)
                appcastFileURL = outURL
            }
        }

        // 8. Cloud push (only when feed == hosted)
        var pushedToCloud = false
        if case .hosted = config.updates.feed, let entry, !dryRun {
            guard let token = environment["SHIPCAST_TOKEN"], !token.isEmpty else {
                throw ShipcastError.config(
                    "feed = \"hosted\" but SHIPCAST_TOKEN is not set",
                    fix: "Get a token from the Shipcast dashboard (Settings → API Tokens) and `export SHIPCAST_TOKEN=<token>`, or switch to feed = \"self:<url>\" in shipcast.toml"
                )
            }
            let baseURL = URL(string: environment["SHIPCAST_BASE_URL"] ?? "https://shipcast.devmafex.com")!
            let push = cloudPushOrDefault(sha256: packaged.sha256, appSlug: config.app.name.lowercased())
            try push(entry, token, baseURL)
            pushedToCloud = true
        }

        return ReleaseReport(
            assetURL: assetURL,
            edSignature: edSignature,
            appcastXML: appcastXML,
            appcastFileURL: appcastFileURL,
            caskPreview: cask,
            pushedToCloud: pushedToCloud
        )
    }

    private func cloudPushOrDefault(sha256: String, appSlug: String) -> (AppcastEntry, String, URL) throws -> Void {
        // Use injected closure when the test provided one; otherwise the real CloudClient
        if isCloudPushInjected {
            return cloudPush
        }
        return { entry, token, baseURL in
            try CloudClient(appSlug: appSlug, sha256: sha256).push(release: entry, token: token, baseURL: baseURL)
        }
    }

    private var isCloudPushInjected: Bool
}
```
NOTE for implementer: the `isCloudPushInjected` flag is set in init (`self.isCloudPushInjected = cloudPush != nil`) and the placeholder `fatalError` default closure is then never reachable — simplify to an optional stored closure `let cloudPush: ((AppcastEntry, String, URL) throws -> Void)?` and branch on nil in `run()`. Keep the public signature `init(shell:environment:cloudPush:)` exactly as tested.

- [ ] Run test, expect PASS: `swift test --filter ReleasePipelineTests` → `Executed 5 tests, with 0 failures`

- [ ] Wire ReleaseCommand and PushCommand in the CLI
```swift
// Sources/ShipcastCLI/Release.swift
import ArgumentParser
import Foundation
import ShipcastKit

struct ReleaseCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "release",
        abstract: "Full pipeline: build + sign + package + GitHub release + cask + appcast"
    )

    @Flag(help: "Run build/sign/package locally and preview cask + appcast, but publish nothing")
    var dryRun = false

    @Option(help: "Override feed: hosted | self:<url> | none")
    var feed: String?

    @Option(help: "Release notes (also read from SHIPCAST_NOTES env)")
    var notes: String?

    func run() throws {
        var config = try ConfigLoader.load(from: URL(fileURLWithPath: "shipcast.toml"))
        if let feed {
            switch feed {
            case "hosted": config.updates.feed = .hosted
            case "none": config.updates.feed = .none
            case let s where s.hasPrefix("self:"): config.updates.feed = .selfHosted(url: String(s.dropFirst(5)))
            default:
                throw ShipcastError.config(
                    "Unknown --feed value: \(feed)",
                    fix: "Use --feed hosted, --feed none, or --feed self:https://example.com/appcast.xml"
                )
            }
        }
        var environment = ProcessInfo.processInfo.environment
        if let notes { environment["SHIPCAST_NOTES"] = notes }

        do {
            let pipeline = ReleasePipeline(shell: ProcessShellRunner(), environment: environment)
            let report = try pipeline.run(config: config, at: URL(fileURLWithPath: "."), dryRun: dryRun)
            if dryRun {
                print("── dry run: nothing published ──")
                print("Would upload to: \(report.assetURL.absoluteString)")
                print("── cask preview ──\n\(report.caskPreview ?? "(no cask)")")
                if !report.appcastXML.isEmpty { print("── appcast preview ──\n\(report.appcastXML)") }
            } else {
                print("✓ Released \(config.app.name) \(config.app.version)")
                print("  Asset: \(report.assetURL.absoluteString)")
                if let appcast = report.appcastFileURL { print("  Appcast: \(appcast.path)") }
                if report.pushedToCloud { print("  Pushed to Shipcast Cloud") }
            }
        } catch let error as ShipcastError {
            FileHandle.standardError.write(Data(error.render().utf8)) // Plan A formatter: command + reason + fix
            Foundation.exit(error.exitCode)
        }
    }
}
```
```swift
// Sources/ShipcastCLI/Push.swift
import ArgumentParser
import Foundation
import ShipcastKit

struct PushCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "push",
        abstract: "POST release metadata to Shipcast Cloud"
    )

    @Option(help: "API token (default: SHIPCAST_TOKEN env)")
    var token: String?

    @Option(help: "Version to push (default: [app] version from shipcast.toml)")
    var version: String?

    func run() throws {
        let config = try ConfigLoader.load(from: URL(fileURLWithPath: "shipcast.toml"))
        guard let resolvedToken = token ?? ProcessInfo.processInfo.environment["SHIPCAST_TOKEN"],
              !resolvedToken.isEmpty else {
            throw ShipcastError.config(
                "No API token: --token not given and SHIPCAST_TOKEN is unset",
                fix: "Get a token from the Shipcast dashboard (Settings → API Tokens), then `export SHIPCAST_TOKEN=<token>` or pass --token <token>"
            )
        }
        // Reads the release metadata sidecar written by the pipeline (.shipcast/last-release.json:
        // version, asset URL, sha256, ed signature, length) so push is re-runnable after a failed upload.
        let sidecarURL = URL(fileURLWithPath: ".shipcast/last-release.json")
        guard let data = try? Data(contentsOf: sidecarURL),
              let meta = try? JSONDecoder().decode(LastReleaseMetadata.self, from: data) else {
            throw ShipcastError.config(
                "No release metadata found at .shipcast/last-release.json",
                fix: "Run `shipcast release` first; push re-sends the metadata from the last release"
            )
        }
        let entry = AppcastEntry(
            version: version ?? meta.version,
            artifactURL: meta.assetURL,
            edSignature: meta.edSignature,
            lengthBytes: meta.lengthBytes,
            minSystemVersion: meta.minSystemVersion,
            notesHTML: meta.notesHTML,
            pubDate: Date()
        )
        let baseURL = URL(string: ProcessInfo.processInfo.environment["SHIPCAST_BASE_URL"] ?? "https://shipcast.devmafex.com")!
        do {
            try CloudClient(appSlug: config.app.name.lowercased(), sha256: meta.sha256)
                .push(release: entry, token: resolvedToken, baseURL: baseURL)
            print("✓ Pushed \(config.app.name) \(entry.version) to Shipcast Cloud")
        } catch let error as ShipcastError {
            FileHandle.standardError.write(Data(error.render().utf8))
            Foundation.exit(error.exitCode)
        }
    }
}

struct LastReleaseMetadata: Codable {
    var version: String
    var assetURL: URL
    var sha256: String
    var edSignature: String
    var lengthBytes: Int
    var minSystemVersion: String?
    var notesHTML: String?
}
```
Also: make ReleasePipeline write `.shipcast/last-release.json` (encode LastReleaseMetadata — move the struct into ShipcastKit/Models so both targets share it) after a successful non-dry-run release, and add a small test in ReleasePipelineTests asserting the sidecar exists and round-trips. Register both subcommands in main.swift: `ReleaseCommand.self, PushCommand.self`.

- [ ] Run full suite, expect PASS: `swift test` → 0 failures; `swift run shipcast release --help` and `swift run shipcast push --help` print usage

- [ ] ACCEPTANCE: dry-run against burnt (real repo at /Users/mafex/code/personal/burnt — standalone SwiftPM menu-bar app, ad-hoc signed). Steps:
  1. `cd /Users/mafex/code/personal/burnt`
  2. Ensure shipcast.toml exists (from Plan A `shipcast init`); verify `[app] name = "Burnt"`, `bundle_id`, `[distribute] github_repo`, `homebrew_tap`, `[updates] sparkle = true`, `feed = "self:https://example.com/appcast.xml"`
  3. `export SPARKLE_PRIVATE_KEY=$(cat ~/path/to/burnt-sparkle-private-key 2>/dev/null || echo "")` — if no key exists yet, generate one with Sparkle's generate_keys
  4. Run: `swift run --package-path /Users/mafex/code/personal/ShipCast shipcast release --dry-run` (burnt build may need DEVELOPER_DIR set — export it if the SwiftPM build step fails)
  5. Verify output: build/sign/package all succeed on the real app, cask preview contains `cask "burnt"`, quarantine-strip postflight, and tccutil resets for burnt's declared permissions; appcast preview contains the correct version and an edSignature
  6. Run `swift run --package-path /Users/mafex/code/personal/ShipCast shipcast doctor .build/release/Burnt.app` and verify the ✓/✗/! gauntlet output renders with a correct summary line
  7. Record any failures as bugs; do NOT publish (no non-dry-run release in this task)

- [ ] Commit: `git add -A && git commit -m "Wire release and push commands with end-to-end pipeline test and burnt dry-run acceptance"`

---

## Done Criteria

- `shipcast release` on burnt performs build → adhoc deep sign (final step) → ditto zip → sparkle sign → GitHub release → cask push → appcast, in that order, with one command
- `shipcast release --dry-run` runs local stages and previews cask + appcast without any remote side effects
- `shipcast doctor` diagnoses unsigned, quarantined, and seal-broken bundles with the spec's exact ✓/✗/! output and actionable fix commands, exit 1 on any failure
- `shipcast push` re-sends the last release's metadata to Shipcast Cloud with bearer auth, failing with exit 2 (no token) or 5 (API error) and doctor-style messages
- Xcode projects build via archive/export with the correct export method per sign mode
- Full test suite green: `swift test` → 0 failures; all shell interactions mocked except the deliberate real-tool Doctor fixtures and env-gated integration tests
