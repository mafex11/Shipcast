import Foundation

public enum ShipcastError: Error {
    case config(String, fix: String)
    case signing(String, fix: String)
    case notarization(String, fix: String)
    case publish(String, fix: String)
    case generic(String, fix: String)

    public var exitCode: Int32 {
        switch self {
        case .config: return 2
        case .signing: return 3
        case .notarization: return 4
        case .publish: return 5
        case .generic: return 1
        }
    }
}

extension ShipcastError {
    public func render() -> String {
        let (title, command, fix) = switch self {
        case .config(let cmd, let f): ("Configuration error", cmd, f)
        case .signing(let cmd, let f): ("Code signing failed", cmd, f)
        case .notarization(let cmd, let f): ("Notarization rejected", cmd, f)
        case .publish(let cmd, let f): ("Publish failed", cmd, f)
        case .generic(let cmd, let f): ("Error", cmd, f)
        }
        return """
        Error: \(title)
        Command: \(command)
        Fix: \(fix)
        """
    }
}
