import Foundation

public final class ProcessShellRunner: ShellRunner, @unchecked Sendable {
    public init() {}

    public func run(_ command: String, args: [String], env: [String: String]?) throws -> ShellResult {
        let process = Process()

        // If command is not an absolute path, resolve via /usr/bin/env for PATH lookup
        let (executableURL, arguments): (URL, [String])
        if command.hasPrefix("/") {
            executableURL = URL(fileURLWithPath: command)
            arguments = args
        } else {
            executableURL = URL(fileURLWithPath: "/usr/bin/env")
            arguments = [command] + args
        }

        process.executableURL = executableURL
        process.arguments = arguments

        if let env = env {
            var environment = ProcessInfo.processInfo.environment
            for (key, value) in env {
                environment[key] = value
            }
            process.environment = environment
        }

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()

        // Drain both pipes concurrently while the process runs. Reading only
        // after waitUntilExit() deadlocks once a chatty command (e.g. xcodebuild)
        // fills the 64KB pipe buffer and blocks on write.
        let stdoutHandle = stdoutPipe.fileHandleForReading
        let stderrHandle = stderrPipe.fileHandleForReading
        var stdoutData = Data()
        var stderrData = Data()
        let group = DispatchGroup()
        let lock = NSLock()
        group.enter()
        DispatchQueue.global().async {
            let data = stdoutHandle.readDataToEndOfFile()
            lock.lock(); stdoutData = data; lock.unlock()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            let data = stderrHandle.readDataToEndOfFile()
            lock.lock(); stderrData = data; lock.unlock()
            group.leave()
        }

        process.waitUntilExit()
        group.wait()

        return ShellResult(
            exitCode: process.terminationStatus,
            stdout: String(data: stdoutData, encoding: .utf8) ?? "",
            stderr: String(data: stderrData, encoding: .utf8) ?? ""
        )
    }
}
