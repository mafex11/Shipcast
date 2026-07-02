import XCTest
@testable import ShipcastKit

final class SparkleSignerTests: XCTestCase {
    func testSignsArtifactAndReturnsSignature() throws {
        let shell = MockShellRunner()
        // sign_update prints: sparkle:edSignature="BASE64SIG" length="12345"
        shell.stub(command: "sign_update", result: ShellResult(
            exitCode: 0,
            stdout: "sparkle:edSignature=\"MEUCIQDtest+sig==\" length=\"12345\"\n",
            stderr: ""
        ))
        let signer = SparkleSigner(shell: shell, environment: ["SPARKLE_PRIVATE_KEY": "b64privatekey"])

        let signature = try signer.sign(
            artifact: URL(fileURLWithPath: "/tmp/Burnt.zip"),
            privateKeyEnv: "SPARKLE_PRIVATE_KEY"
        )

        XCTAssertEqual(signature, "MEUCIQDtest+sig==")
        let call = shell.calls[0]
        XCTAssertEqual(call.command, "sign_update")
        XCTAssertTrue(call.args.contains("/tmp/Burnt.zip"))
        // Key passed via ephemeral file (-f), never as a bare argv (visible in ps)
        let fIndex = call.args.firstIndex(of: "-f")
        XCTAssertNotNil(fIndex)
    }

    func testMissingEnvVarThrowsConfigErrorWithFix() throws {
        let signer = SparkleSigner(shell: MockShellRunner(), environment: [:])
        XCTAssertThrowsError(try signer.sign(artifact: URL(fileURLWithPath: "/tmp/Burnt.zip"), privateKeyEnv: "SPARKLE_PRIVATE_KEY")) { error in
            guard case ShipcastError.config(let message, let fix) = error else {
                return XCTFail("expected .config, got \(error)")
            }
            XCTAssertTrue(message.contains("SPARKLE_PRIVATE_KEY"))
            XCTAssertTrue(fix.contains("generate_keys"))
        }
    }

    func testSignUpdateFailureThrowsSigningError() throws {
        let shell = MockShellRunner()
        shell.stub(command: "sign_update", result: ShellResult(exitCode: 1, stdout: "", stderr: "Unable to decode private key"))
        let signer = SparkleSigner(shell: shell, environment: ["SPARKLE_PRIVATE_KEY": "garbage"])
        XCTAssertThrowsError(try signer.sign(artifact: URL(fileURLWithPath: "/tmp/Burnt.zip"), privateKeyEnv: "SPARKLE_PRIVATE_KEY")) { error in
            guard case ShipcastError.signing(let message, let fix) = error else {
                return XCTFail("expected .signing, got \(error)")
            }
            XCTAssertTrue(message.contains("sign_update"))
            XCTAssertTrue(fix.contains("SPARKLE_PRIVATE_KEY"))
        }
    }

    func testUnparseableOutputThrowsSigningError() throws {
        let shell = MockShellRunner()
        shell.stub(command: "sign_update", result: ShellResult(exitCode: 0, stdout: "unexpected output", stderr: ""))
        let signer = SparkleSigner(shell: shell, environment: ["SPARKLE_PRIVATE_KEY": "key"])
        XCTAssertThrowsError(try signer.sign(artifact: URL(fileURLWithPath: "/tmp/Burnt.zip"), privateKeyEnv: "SPARKLE_PRIVATE_KEY"))
    }
}
