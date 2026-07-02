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
