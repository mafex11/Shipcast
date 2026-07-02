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
