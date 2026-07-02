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
