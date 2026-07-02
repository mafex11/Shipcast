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
    private var argStubs: [(command: String, argsPrefix: [String], result: ShellResult)] = []
    public private(set) var invocations: [Invocation] = []

    public init() {}

    public func stub(command: String, result: ShellResult) {
        stubs[command] = result
    }

    public func run(_ command: String, args: [String], env: [String: String]?) throws -> ShellResult {
        invocations.append(Invocation(command: command, args: args, env: env))

        let basename = (command as NSString).lastPathComponent

        // Rule 1: Check argStubs for basename match with argsPrefix prefix match
        if let result = argStubs.first(where: { stub in
            stub.command == basename && args.starts(with: stub.argsPrefix)
        })?.result {
            return result
        }

        // Rule 2: Check stubs for basename
        if let result = stubs[basename] {
            return result
        }

        // Rule 3: Check stubs for full path (Plan A behavior)
        if let result = stubs[command] {
            return result
        }

        throw ShipcastError.generic("Command not stubbed: \(command)", fix: "Add stub in test setup")
    }
}

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
