import Foundation

public protocol ShellRunner: Sendable {
    @discardableResult
    func run(_ command: String, args: [String], env: [String: String]?) throws -> ShellResult
}

public struct ShellResult: Sendable {
    public var exitCode: Int32
    public var stdout: String
    public var stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}
