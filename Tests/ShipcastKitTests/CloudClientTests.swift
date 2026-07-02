import XCTest
@testable import ShipcastKit

final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else { fatalError("handler unset") }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

final class CloudClientTests: XCTestCase {
    var session: URLSession!

    override func setUp() {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    var entry: AppcastEntry {
        AppcastEntry(
            version: "1.2.0",
            artifactURL: URL(string: "https://github.com/mafex11/burnt/releases/download/v1.2.0/Burnt.zip")!,
            edSignature: "MEUCIQDtest+sig==",
            lengthBytes: 12_345_678,
            minSystemVersion: "14.0",
            notesHTML: "<p>Fixed bugs</p>",
            pubDate: Date()
        )
    }

    func testPushSendsExactJSONBodyAndBearerToken() throws {
        nonisolated(unsafe) var captured: URLRequest?
        nonisolated(unsafe) var capturedBody: Data?
        MockURLProtocol.handler = { request in
            captured = request
            capturedBody = request.httpBody ?? request.httpBodyStream.map { stream in
                stream.open(); defer { stream.close() }
                var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let read = stream.read(&buffer, maxLength: buffer.count)
                    if read <= 0 { break }
                    data.append(buffer, count: read)
                }
                return data
            }
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data("{\"id\":\"rel_123\"}".utf8))
        }

        let client = CloudClient(appSlug: "burnt", sha256: "abc123", session: session)
        try client.push(release: entry, token: "sct_secret", baseURL: URL(string: "https://shipcast.devmafex.com")!)

        let request = try XCTUnwrap(captured)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.path, "/api/v1/apps/burnt/releases")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sct_secret")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

        let body = try JSONSerialization.jsonObject(with: XCTUnwrap(capturedBody)) as! [String: Any]
        XCTAssertEqual(body["version"] as? String, "1.2.0")
        XCTAssertEqual(body["artifact_url"] as? String, "https://github.com/mafex11/burnt/releases/download/v1.2.0/Burnt.zip")
        XCTAssertEqual(body["sha256"] as? String, "abc123")
        XCTAssertEqual(body["ed_signature"] as? String, "MEUCIQDtest+sig==")
        XCTAssertEqual(body["length"] as? Int, 12_345_678)
        XCTAssertEqual(body["min_system_version"] as? String, "14.0")
        XCTAssertEqual(body["release_notes_html"] as? String, "<p>Fixed bugs</p>")
        XCTAssertEqual(body["channel"] as? String, "stable")
    }

    func test401ThrowsPublishErrorWithTokenFix() throws {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: nil, headerFields: nil)!,
             Data("{\"error\":\"invalid token\"}".utf8))
        }
        let client = CloudClient(appSlug: "burnt", sha256: "abc123", session: session)
        XCTAssertThrowsError(try client.push(release: entry, token: "bad", baseURL: URL(string: "https://shipcast.devmafex.com")!)) { error in
            guard case ShipcastError.publish(let message, let fix) = error else {
                return XCTFail("expected .publish, got \(error)")
            }
            XCTAssertTrue(message.contains("401"))
            XCTAssertTrue(fix.contains("SHIPCAST_TOKEN"))
        }
    }

    func test409DuplicateVersionThrowsPublishError() throws {
        MockURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 409, httpVersion: nil, headerFields: nil)!,
             Data("{\"error\":\"version already published\"}".utf8))
        }
        let client = CloudClient(appSlug: "burnt", sha256: "abc123", session: session)
        XCTAssertThrowsError(try client.push(release: entry, token: "sct_secret", baseURL: URL(string: "https://shipcast.devmafex.com")!)) { error in
            guard case ShipcastError.publish(let message, _) = error else {
                return XCTFail("expected .publish, got \(error)")
            }
            XCTAssertTrue(message.contains("409"))
        }
    }
}
