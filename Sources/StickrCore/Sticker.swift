import Foundation

public struct Sticker: Codable, Sendable, Identifiable {
    public var id: String            // sha256 of the file bytes, so duplicates collapse
    public var path: String
    public var animated: Bool
    public var width: Int
    public var height: Int
    public var byteSize: Int
    public var source: String        // favorite | sent | received
    public var sentCount: Int
    public var firstSeen: String
    public var caption: String
    public var textInImage: String
    public var mood: String
    public var tags: [String]
    public var emojis: [String]
    public var vector: [Float]?
    public var state: String         // waiting | read | failed
    public var edited: Bool
    public var model: String
    public var provider: String

    public var docText: String {
        [caption, textInImage, mood, tags.joined(separator: " "), emojis.joined(separator: " ")]
            .filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

public func isAnimatedWebP(_ bytes: Data) -> Bool {
    guard bytes.count > 12, bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) else { return false }
    return bytes.range(of: Data("ANMF".utf8)) != nil || bytes.range(of: Data("ANIM".utf8)) != nil
}
