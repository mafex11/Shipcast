import Foundation

/// URL- and Homebrew-safe slug from an app name: lowercase, whitespace
/// collapsed to single hyphens, everything outside [a-z0-9-] stripped.
public func slugify(_ name: String) -> String {
    let lowered = name.lowercased()
    var out = ""
    var lastWasHyphen = true // suppress leading hyphens
    for scalar in lowered.unicodeScalars {
        if CharacterSet.whitespacesAndNewlines.contains(scalar) || scalar == "-" {
            if !lastWasHyphen {
                out.append("-")
                lastWasHyphen = true
            }
        } else if (scalar >= "a" && scalar <= "z") || (scalar >= "0" && scalar <= "9") {
            out.unicodeScalars.append(scalar)
            lastWasHyphen = false
        }
        // else: drop the character entirely
    }
    while out.hasSuffix("-") { out.removeLast() }
    return out
}
