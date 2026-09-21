import Foundation
import XCTest
@testable import StickrCore

/// Returns prepared answers without touching the network.
final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var responses: [(Int, Data)] = []
    nonisolated(unsafe) static var seenRequests: [URLRequest] = []
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.seenRequests.append(request)
        let (status, data) = Self.responses.isEmpty ? (500, Data("{}".utf8)) : Self.responses.removeFirst()
        let http = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: http, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

func mockSession() -> URLSession {
    let conf = URLSessionConfiguration.ephemeral
    conf.protocolClasses = [MockURLProtocol.self]
    return URLSession(configuration: conf)
}

func chatResponseJSON(caption: String) -> Data {
    let content: [String: Any] = ["caption": caption, "text_in_image": "", "mood": "calm",
        "tags": ["a", "b", "c", "d"], "emojis": ["🙂"]]
    let json = try! JSONSerialization.data(withJSONObject: content)
    return try! JSONSerialization.data(withJSONObject: [
        "choices": [["message": ["content": String(data: json, encoding: .utf8)!]]],
        "provider": "fake-provider",
        "usage": ["cost": 0.0001],
    ])
}

func resetMock() {
    MockURLProtocol.responses = []
    MockURLProtocol.seenRequests = []
}

func embeddingsJSON(count: Int, dim: Int = 3) -> Data {
    try! JSONSerialization.data(withJSONObject: [
        "data": (0..<count).map { _ in ["embedding": Array(repeating: 0.5, count: dim)] as [String: Any] },
    ])
}
