import Foundation

public struct CloudClient: Sendable {
    let appSlug: String
    let sha256: String
    let session: URLSession

    public init(appSlug: String, sha256: String, session: URLSession = .shared) {
        self.appSlug = appSlug
        self.sha256 = sha256
        self.session = session
    }

    public func push(release: AppcastEntry, token: String, baseURL: URL) throws {
        guard !appSlug.isEmpty else {
            throw ShipcastError.publish(
                "App slug is empty — cannot build the release endpoint URL",
                fix: "Check app.name in shipcast.toml contains at least one letter or digit"
            )
        }
        // appendingPathComponent percent-encodes, so this never produces an invalid URL
        let endpoint = baseURL.appendingPathComponent("api/v1/apps/\(appSlug)/releases")
        var request = URLRequest(url: endpoint)
        let endpointString = endpoint.absoluteString
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "version": release.version,
            "artifact_url": release.artifactURL.absoluteString,
            "sha256": sha256,
            "ed_signature": release.edSignature,
            "length": release.lengthBytes,
            "channel": "stable",
        ]
        if let minOS = release.minSystemVersion { body["min_system_version"] = minOS }
        if let notes = release.notesHTML { body["release_notes_html"] = notes }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var outcome: (status: Int, body: String, transportError: Error?) = (0, "", nil)
        session.dataTask(with: request) { data, response, error in
            outcome = (
                (response as? HTTPURLResponse)?.statusCode ?? 0,
                data.map { String(decoding: $0, as: UTF8.self) } ?? "",
                error
            )
            semaphore.signal()
        }.resume()
        semaphore.wait()

        if let transportError = outcome.transportError {
            throw ShipcastError.publish(
                "POST \(endpointString) failed: \(transportError.localizedDescription)",
                fix: "Check network connectivity and that \(baseURL.host ?? "the host") resolves: curl -I \(baseURL.absoluteString)"
            )
        }
        switch outcome.status {
        case 200, 201:
            return
        case 401, 403:
            throw ShipcastError.publish(
                "POST \(endpointString) returned HTTP \(outcome.status): \(outcome.body)",
                fix: "Your API token is invalid or missing. Get a fresh token from the Shipcast dashboard (Settings → API Tokens) and `export SHIPCAST_TOKEN=<token>` or pass --token"
            )
        case 404:
            throw ShipcastError.publish(
                "POST \(endpointString) returned HTTP 404: app \"\(appSlug)\" not found",
                fix: "Create the app in the dashboard and check the slug matches"
            )
        case 409:
            throw ShipcastError.publish(
                "POST \(endpointString) returned HTTP 409: version \(release.version) already published",
                fix: "Bump the version (new git tag) and release again; published versions are immutable"
            )
        case 422:
            throw ShipcastError.publish(
                "POST \(endpointString) returned HTTP 422 (invalid payload): \(outcome.body)",
                fix: "The release metadata failed server validation — check the response details; if the CLI and cloud versions differ, update shipcast"
            )
        default:
            throw ShipcastError.publish(
                "POST \(endpointString) returned HTTP \(outcome.status): \(outcome.body)",
                fix: "Retry; if it persists check https://shipcast.devmafex.com status or push later — the GitHub release and cask already succeeded"
            )
        }
    }
}
