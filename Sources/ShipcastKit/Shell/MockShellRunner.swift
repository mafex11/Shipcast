import Foundation

public final class MockShellRunner: ShellRunner, @unchecked Sendable {
    public struct Invocation: Sendable {
        public var command: String
        public var args: [String]
        public var env: [String: String]?

        public init(command: String, args: [String], env: [String: String]?) {
            self.command = command
            self.args = args
            self.env = env
        }
    }

    private var stubs: [String: ShellResult] = [:]
    public private(set) var invocations: [Invocation] = []

    public init() {}

    public func stub(command: String, result: ShellResult) {
        stubs[command] = result
    }

    public func run(_ command: String, args: [String], env: [String: String]?) throws -> ShellResult {
        invocations.append(Invocation(command: command, args: args, env: env))
        guard let result = stubs[command] else {
            throw ShipcastError.generic("Command not stubbed: \(command)", fix: "Add stub in test setup")
        }
        return result
    }
}
