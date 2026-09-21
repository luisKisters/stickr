import Foundation

public enum PackEngine {
    public static let maxMembers = 30
    public static let zSearch = 2.0
    public static let zPack = 1.0

    /// Pinned stickers first in their pinned order, then by times sent, then by similarity. At most 30.
    public static func members(pack: Store.Pack, stickers: [Sticker], ruleResults: [Sticker]) -> [Sticker] {
        let byID = Dictionary(uniqueKeysWithValues: stickers.map { ($0.id, $0) })
        let pinSet = Set(pack.pins)
        let pins = pack.pins.compactMap { byID[$0] }
        let removed = Set(pack.removed)
        let auto = ruleResults.filter { !pinSet.contains($0.id) && !removed.contains($0.id) && byID[$0.id] != nil }
            .compactMap { byID[$0.id] }
            .sorted { $0.sentCount > $1.sentCount }
        return Array((pins + auto).prefix(maxMembers))
    }

    /// WhatsApp keeps still and animated stickers apart. A mixed pack goes in as two packs.
    public static func splitByAnimation(_ members: [Sticker]) -> (still: [Sticker], animated: [Sticker]) {
        (members.filter { !$0.animated }, members.filter { $0.animated })
    }
}
