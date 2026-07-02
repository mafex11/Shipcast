import Foundation
import CryptoKit

public struct DoctorFinding: Sendable, Equatable {
    public enum Status: Sendable, Equatable { case pass, warn, fail }
    public var check: String
    public var status: Status
    public var reason: String?
    public var fix: String?

    public init(check: String, status: Status, reason: String? = nil, fix: String? = nil) {
        self.check = check
        self.status = status
        self.reason = reason
        self.fix = fix
    }
}

public struct Doctor: Sendable {
    let shell: any ShellRunner

    public init(shell: any ShellRunner) {
        self.shell = shell
    }

    public func run(appURL: URL, config: ShipcastConfig) -> [DoctorFinding] {
        var findings: [DoctorFinding] = []
        let plist = loadInfoPlist(appURL: appURL)

        findings.append(checkBundleStructure(appURL: appURL, plist: plist))
        findings.append(checkCodeSignature(appURL: appURL))
        findings.append(checkGatekeeper(appURL: appURL, config: config))
        findings.append(checkQuarantine(appURL: appURL, config: config))
        findings.append(checkNotarization(appURL: appURL, config: config))
        if !config.permissions.isEmpty {
            findings.append(checkTCC(config: config))
        }
        if config.updates.sparkle {
            findings.append(contentsOf: checkSparkle(plist: plist))
        }
        return findings
    }

    func loadInfoPlist(appURL: URL) -> [String: Any] {
        let url = appURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return [:] }
        return plist
    }

    func checkBundleStructure(appURL: URL, plist: [String: Any]) -> DoctorFinding {
        let plistPath = appURL.appendingPathComponent("Contents/Info.plist").path
        guard FileManager.default.fileExists(atPath: plistPath), !plist.isEmpty else {
            return DoctorFinding(check: "App bundle structure", status: .fail,
                                 reason: "Contents/Info.plist missing or unreadable",
                                 fix: "Rebuild the app: `shipcast build` regenerates the bundle with a valid Info.plist")
        }
        guard plist["CFBundleIdentifier"] is String else {
            return DoctorFinding(check: "App bundle structure", status: .fail,
                                 reason: "CFBundleIdentifier missing from Info.plist",
                                 fix: "Set bundle_id in shipcast.toml [app] and rebuild with `shipcast build`")
        }
        guard let exec = plist["CFBundleExecutable"] as? String,
              FileManager.default.isExecutableFile(atPath: appURL.appendingPathComponent("Contents/MacOS/\(exec)").path)
        else {
            return DoctorFinding(check: "App bundle structure", status: .fail,
                                 reason: "CFBundleExecutable missing or the executable file does not exist",
                                 fix: "Rebuild with `shipcast build`; the executable must live at Contents/MacOS/<CFBundleExecutable>")
        }
        return DoctorFinding(check: "App bundle structure", status: .pass)
    }

    func checkCodeSignature(appURL: URL) -> DoctorFinding {
        guard let result = try? shell.run("codesign", args: ["--verify", "--deep", "--strict", appURL.path], env: nil) else {
            return DoctorFinding(check: "Code signature", status: .fail, reason: "codesign could not be executed",
                                 fix: "Install Xcode command line tools: xcode-select --install")
        }
        if result.exitCode == 0 {
            return DoctorFinding(check: "Code signature", status: .pass)
        }
        let sealBroken = result.stderr.contains("modified") || result.stderr.contains("sealed resource")
        return DoctorFinding(
            check: "Code signature", status: .fail,
            reason: sealBroken
                ? "code seal broken — a file was added or modified after signing: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))"
                : "codesign --verify --deep --strict failed: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))",
            fix: "Add all resources BEFORE signing, then re-sign as the final step: codesign --force --deep --sign - \(appURL.path)"
        )
    }

    func checkGatekeeper(appURL: URL, config: ShipcastConfig) -> DoctorFinding {
        guard let result = try? shell.run("spctl", args: ["-a", "-t", "exec", "-vv", appURL.path], env: nil) else {
            return DoctorFinding(check: "Gatekeeper assessment", status: .warn, reason: "spctl could not be executed", fix: nil)
        }
        let combined = result.stdout + result.stderr
        if combined.contains("accepted") {
            return DoctorFinding(check: "Gatekeeper assessment", status: .pass)
        }
        if config.sign.mode == .adhoc {
            return DoctorFinding(check: "Gatekeeper assessment", status: .warn,
                                 reason: "ad-hoc signed apps are always rejected by spctl; users launch via the cask quarantine strip",
                                 fix: "Expected for ad-hoc. Distribute via the generated cask (strips quarantine in postflight) or notarize with a Developer ID cert")
        }
        return DoctorFinding(check: "Gatekeeper assessment", status: .fail,
                             reason: combined.trimmingCharacters(in: .whitespacesAndNewlines),
                             fix: "Notarize the app: `shipcast sign` with APPLE_ID/APPLE_TEAM_ID/APPLE_APP_PASSWORD set, then `xcrun stapler staple \(appURL.path)`")
    }

    func checkQuarantine(appURL: URL, config: ShipcastConfig) -> DoctorFinding {
        guard let result = try? shell.run("xattr", args: ["-l", appURL.path], env: nil) else {
            return DoctorFinding(check: "Quarantine", status: .warn, reason: "xattr could not be executed", fix: nil)
        }
        if result.stdout.contains("com.apple.quarantine") {
            return DoctorFinding(check: "Quarantine", status: .fail,
                                 reason: "com.apple.quarantine attribute present — ad-hoc apps show \"damaged and can't be opened\"",
                                 fix: "xattr -dr com.apple.quarantine \(appURL.path)")
        }
        return DoctorFinding(check: "Quarantine", status: .pass)
    }

    func checkNotarization(appURL: URL, config: ShipcastConfig) -> DoctorFinding {
        if config.sign.mode != .developerID {
            return DoctorFinding(check: "Notarization", status: .pass,
                                 reason: "No notarization required (ad-hoc signed)")
        }
        guard let result = try? shell.run("xcrun", args: ["stapler", "validate", appURL.path], env: nil) else {
            return DoctorFinding(check: "Notarization", status: .fail, reason: "stapler could not be executed",
                                 fix: "Install Xcode command line tools: xcode-select --install")
        }
        if result.exitCode == 0 {
            return DoctorFinding(check: "Notarization", status: .pass)
        }
        return DoctorFinding(check: "Notarization", status: .fail,
                             reason: "notarization ticket not stapled: \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))",
                             fix: "xcrun notarytool submit <zip> --apple-id $APPLE_ID --team-id $APPLE_TEAM_ID --password $APPLE_APP_PASSWORD --wait && xcrun stapler staple \(appURL.path)")
    }

    func checkTCC(config: ShipcastConfig) -> DoctorFinding {
        let names = config.permissions.map(\.rawValue).joined(separator: ", ")
        return DoctorFinding(check: "TCC permissions", status: .warn,
                             reason: "Expected: \(names). Status: Not granted (first launch will prompt)",
                             fix: nil)
    }

    func checkSparkle(plist: [String: Any]) -> [DoctorFinding] {
        var findings: [DoctorFinding] = []

        guard let feedString = plist["SUFeedURL"] as? String, let feedURL = URL(string: feedString) else {
            findings.append(DoctorFinding(check: "Sparkle SUFeedURL", status: .fail,
                                          reason: "SUFeedURL missing from Info.plist",
                                          fix: "Add SUFeedURL to Info.plist (shipcast build injects it when [updates] sparkle = true)"))
            return findings
        }
        findings.append(DoctorFinding(check: "Sparkle SUFeedURL", status: .pass))

        guard let publicKeyB64 = plist["SUPublicEDKey"] as? String else {
            findings.append(DoctorFinding(check: "Sparkle SUPublicEDKey", status: .fail,
                                          reason: "SUPublicEDKey missing from Info.plist",
                                          fix: "Run Sparkle's generate_keys and add the public key as SUPublicEDKey in Info.plist"))
            return findings
        }
        findings.append(DoctorFinding(check: "Sparkle SUPublicEDKey", status: .pass))

        // Feed reachability + parse + signature: synchronous fetch with short timeout
        let semaphore = DispatchSemaphore(value: 0)
        var fetched: (data: Data?, status: Int) = (nil, 0)
        let task = URLSession.shared.dataTask(with: feedURL) { data, response, _ in
            fetched = (data, (response as? HTTPURLResponse)?.statusCode ?? 0)
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + 10)

        guard fetched.status == 200, let xmlData = fetched.data else {
            findings.append(DoctorFinding(check: "Sparkle feed reachable", status: .fail,
                                          reason: "GET \(feedString) returned HTTP \(fetched.status)",
                                          fix: "Publish a release first (`shipcast release`), or check the feed URL. Self-hosted feeds: verify the file is deployed"))
            return findings
        }
        findings.append(DoctorFinding(check: "Sparkle feed reachable", status: .pass))

        let parser = AppcastParser() // simple XMLParser delegate extracting first enclosure url + edSignature
        guard let latest = parser.parseLatestEnclosure(data: xmlData) else {
            findings.append(DoctorFinding(check: "Appcast XML", status: .fail,
                                          reason: "appcast did not parse or contains no enclosure",
                                          fix: "Regenerate the appcast: `shipcast release` writes valid Sparkle RSS; validate with `xmllint --noout appcast.xml`"))
            return findings
        }
        findings.append(DoctorFinding(check: "Appcast XML", status: .pass))

        findings.append(verifyEdSignature(enclosure: latest, publicKeyB64: publicKeyB64))
        return findings
    }

    func verifyEdSignature(enclosure: (url: URL, edSignature: String), publicKeyB64: String) -> DoctorFinding {
        guard let keyData = Data(base64Encoded: publicKeyB64),
              let sigData = Data(base64Encoded: enclosure.edSignature),
              let publicKey = try? Curve25519.Signing.PublicKey(rawRepresentation: keyData) else {
            return DoctorFinding(check: "Ed25519 signature", status: .fail,
                                 reason: "SUPublicEDKey or edSignature is not valid base64/ed25519 material",
                                 fix: "Re-run generate_keys and re-sign the artifact with sign_update; update SUPublicEDKey in Info.plist")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var artifactData: Data?
        URLSession.shared.dataTask(with: enclosure.url) { data, _, _ in
            artifactData = data
            semaphore.signal()
        }.resume()
        _ = semaphore.wait(timeout: .now() + 60)
        guard let artifact = artifactData else {
            return DoctorFinding(check: "Ed25519 signature", status: .warn,
                                 reason: "could not download enclosure to verify signature",
                                 fix: "Check the enclosure URL is publicly downloadable: curl -IL \(enclosure.url.absoluteString)")
        }
        if publicKey.isValidSignature(sigData, for: artifact) {
            return DoctorFinding(check: "Ed25519 signature", status: .pass)
        }
        return DoctorFinding(check: "Ed25519 signature", status: .fail,
                             reason: "enclosure signature does not verify against SUPublicEDKey — updates will be rejected by Sparkle",
                             fix: "Re-sign the artifact with the matching key: sign_update <zip> using the private key whose public half is in Info.plist, then republish the appcast")
    }
}

/// Minimal XMLParser delegate: returns the first <enclosure> url + sparkle:edSignature.
final class AppcastParser: NSObject, XMLParserDelegate {
    private var result: (url: URL, edSignature: String)?

    func parseLatestEnclosure(data: Data) -> (url: URL, edSignature: String)? {
        let parser = XMLParser(data: data)
        parser.delegate = self
        guard parser.parse() || result != nil else { return nil }
        return result
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        guard result == nil, elementName == "enclosure",
              let urlString = attributeDict["url"], let url = URL(string: urlString),
              let sig = attributeDict["sparkle:edSignature"] else { return }
        result = (url, sig)
        parser.abortParsing()
    }
}
