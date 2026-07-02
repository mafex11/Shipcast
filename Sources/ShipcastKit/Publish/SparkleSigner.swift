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
