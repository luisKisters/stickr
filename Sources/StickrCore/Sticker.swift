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

    public init(id: String, path: String, animated: Bool, width: Int, height: Int, byteSize: Int,
                source: String, sentCount: Int, firstSeen: String, caption: String, textInImage: String,
                mood: String, tags: [String], emojis: [String], vector: [Float]?, state: String,
                edited: Bool, model: String, provider: String) {
        self.id = id; self.path = path; self.animated = animated; self.width = width; self.height = height
        self.byteSize = byteSize; self.source = source; self.sentCount = sentCount; self.firstSeen = firstSeen
        self.caption = caption; self.textInImage = textInImage; self.mood = mood; self.tags = tags
        self.emojis = emojis; self.vector = vector; self.state = state; self.edited = edited
        self.model = model; self.provider = provider
    }

    public var docText: String {
        [caption, textInImage, mood, tags.joined(separator: " "), emojis.joined(separator: " ")]
            .filter { !$0.isEmpty }.joined(separator: ". ")
    }
}

public func isAnimatedWebP(_ bytes: Data) -> Bool {
    guard bytes.count > 12, bytes.starts(with: [0x52, 0x49, 0x46, 0x46]) else { return false }
    return bytes.range(of: Data("ANMF".utf8)) != nil || bytes.range(of: Data("ANIM".utf8)) != nil
}
