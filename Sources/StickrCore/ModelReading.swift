import Foundation

public protocol ModelReading: Sendable {
    var captionModelName: String { get }
    func caption(bytes: Data) async throws -> CaptionResult
    func embed(texts: [String]) async throws -> [[Float]]
    func testConnection(bytes: Data) async throws -> CaptionResult
}
