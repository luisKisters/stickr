import Foundation

public struct CaptionResult: Codable, Sendable {
    public var caption: String
    public var textInImage: String
    public var mood: String
    public var tags: [String]
    public var emojis: [String]
    public var provider: String
    public var seconds: Double
    public var cost: Double
}

/// Talks to OpenRouter or any OpenAI-compatible server. Retries 429 and 5xx four times with a growing pause.
public struct ModelClient: ModelReading {
    public var baseURL: URL
    public var key: String
    public var captionModel: String
    public var captionModelName: String { captionModel }
    public var embedModel: String
    public var routing: String    // baseten-first | baseten | ""
    var session: URLSession

    public init(baseURL: URL = URL(string: "https://openrouter.ai/api/v1")!, key: String,
                captionModel: String = "z-ai/glm-5.3-flash", embedModel: String = "baai/bge-m3", routing: String = "baseten-first",
                session: URLSession = .shared) {
        self.baseURL = baseURL; self.key = key; self.captionModel = captionModel
        self.embedModel = embedModel; self.routing = routing; self.session = session
    }

    nonisolated(unsafe) public static let routes: [String: [String: Any]] = [
        "baseten-first": ["order": ["baseten"], "allow_fallbacks": true],
        "baseten": ["only": ["baseten"]],
    ]
    public static let systemPrompt = "You describe chat stickers for a search index. Answer in English. caption: one plain sentence on what is shown. text_in_image: the exact visible text, or an empty string. mood: one word. tags: 4 to 8 lowercase words for the feelings and situations in which someone sends this sticker. emojis: 1 to 3 emoji a person would type to find this sticker."
    nonisolated(unsafe) public static let schema: [String: Any] = [
        "type": "object", "additionalProperties": false,
        "required": ["caption", "text_in_image", "mood", "tags", "emojis"],
        "properties": [
            "caption": ["type": "string"], "text_in_image": ["type": "string"], "mood": ["type": "string"],
            "tags": ["type": "array", "items": ["type": "string"]],
            "emojis": ["type": "array", "items": ["type": "string"]],
        ],
    ]

    public struct HTTPError: Error, Sendable { public let status: Int; public let message: String }

    func request(_ path: String, body: [String: Any], tries: Int = 4) async throws -> [String: Any] {
        let t0 = Date()
        var lastError = HTTPError(status: 0, message: "no try")
        for n in 0..<max(1, tries) {
            if n > 0 { try await Task.sleep(nanoseconds: UInt64((1.5 * pow(2, Double(n - 1)) + Double.random(in: 0...0.5)) * 1_000_000_000)) }
            do {
                let data = try await requestOnce(path, body: body)
                let seconds = Date().timeIntervalSince(t0)
                return try parse(data, seconds: seconds)
            } catch let e as HTTPError {
                if e.status == 429 || e.status >= 500 { lastError = e; continue }
                throw e
            } catch let e as URLError where e.code == .timedOut || e.code == .cannotConnectToHost || e.code == .networkConnectionLost {
                lastError = HTTPError(status: 503, message: e.localizedDescription); continue
            }
        }
        throw lastError
    }

    func requestOnce(_ path: String, body: [String: Any]) async throws -> Data {
        var req = URLRequest(url: baseURL.appendingPathComponent(path), timeoutInterval: 90)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, resp) = try await session.data(for: req)
        let statusCode = (resp as? HTTPURLResponse)?.statusCode ?? 0
        if statusCode >= 400 {
            let message = (try? JSONSerialization.jsonObject(with: data))
                .flatMap { $0 as? [String: Any] }
                .flatMap { $0["error"] as? [String: Any] }
                .flatMap { $0["message"] as? String } ?? "Request failed"
            throw HTTPError(status: statusCode, message: message)
        }
        return data
    }

    func parse(_ data: Data, seconds: Double) throws -> [String: Any] {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HTTPError(status: 0, message: "The service sent an answer this app cannot read.")
        }
        if let error = dict["error"] as? [String: Any] {
            let status = (error["code"] as? Int) ?? ((error["code"] as? String).flatMap(Int.init) ?? 0)
            throw HTTPError(status: status, message: error["message"] as? String ?? "Request failed")
        }
        var out = dict
        out["__seconds"] = seconds
        return out
    }

    public func caption(bytes webp: Data) async throws -> CaptionResult {
        let dataURL = "data:image/webp;base64,\(webp.base64EncodedString())"
        var body: [String: Any] = [
            "model": captionModel,
            "reasoning": ["effort": "low"],
            "max_tokens": 1200,
            "response_format": ["type": "json_schema", "json_schema": ["name": "sticker", "strict": true, "schema": Self.schema]],
            "messages": [
                ["role": "system", "content": Self.systemPrompt],
                ["role": "user", "content": [["type": "image_url", "image_url": ["url": dataURL]]]],
            ],
        ]
        if let route = Self.routes[routing], !route.isEmpty { body["provider"] = route }
        let d = try await request("chat/completions", body: body)
        guard let choices = d["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw HTTPError(status: 0, message: "The model did not answer.")
        }
        let j = try JSONSerialization.jsonObject(with: Data(content.utf8)) as? [String: Any] ?? [:]
        let usage = d["usage"] as? [String: Any] ?? [:]
        return CaptionResult(
            caption: j["caption"] as? String ?? "",
            textInImage: j["text_in_image"] as? String ?? "",
            mood: j["mood"] as? String ?? "",
            tags: { let t = (j["tags"] as? [Any])?.compactMap { $0 as? String } ?? []; return Array(t.prefix(8)) }(),
            emojis: { let e = j["emojis"] as? [String] ?? []; return Array(e.prefix(3)) }(),
            provider: d["provider"] as? String ?? "",
            seconds: d["__seconds"] as? Double ?? 0,
            cost: usage["cost"] as? Double ?? 0)
    }

    public func embed(texts: [String]) async throws -> [[Float]] {
        let d = try await request("embeddings", body: ["model": embedModel, "input": texts])
        guard let data = d["data"] as? [[String: Any]] else {
            throw HTTPError(status: 0, message: "The embeddings endpoint did not answer.")
        }
        return data.compactMap { item in
            (item["embedding"] as? [Any])?.compactMap { ($0 as? NSNumber)?.floatValue }
        }
    }

    public enum ConnectionProblem: Error, Sendable {
        case badKey, noCredit, unknownProvider, other(String)
    }
    /// One real request for the test connection button. Maps the plain failure messages from the walkthrough.
    public func testConnection(bytes: Data) async throws -> CaptionResult {
        do {
            return try await caption(bytes: bytes)
        } catch let e as HTTPError {
            if e.status == 401 { throw ConnectionProblem.badKey }
            if e.status == 402 { throw ConnectionProblem.noCredit }
            if e.status == 404 { throw ConnectionProblem.unknownProvider }
            throw ConnectionProblem.other(e.message)
        }
    }
}
