import Foundation
import Accelerate

public struct SearchEngine: Sendable {
    public let stickers: [Sticker]
    public let searchZ: Double      // 2.0: a hit must stand out from the whole library
    public let packZ: Double        // 1.0: packs cast a wider net

    public init(stickers: [Sticker], searchZ: Double = 2.0, packZ: Double = 1.0) {
        self.stickers = stickers; self.searchZ = searchZ; self.packZ = packZ
    }

    public static func cosine(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        return vDSP.dot(a, b) / max(1e-12, vDSP.dot(a, a).squareRoot() * vDSP.dot(b, b).squareRoot())
    }

    /// Mean and standard deviation over the whole library for this query, then a z-score cut.
    public func zCut(query vector: [Float], z: Double, cap: Int) -> [Sticker] {
        var scored: [(Sticker, Float)] = []
        for s in stickers {
            if let v = s.vector { scored.append((s, SearchEngine.cosine(vector, v))) }
        }
        if scored.isEmpty { return [] }
        let values = scored.map { $0.1 }
        let mean = values.reduce(Float(0), +) / Float(values.count)
        let sq = values.reduce(Float(0)) { $0 + ($1 - mean) * ($1 - mean) }
        let stdDev = sq.squareRoot() / Float(max(1, values.count - 1)).squareRoot()
        let denom = max(1e-6, stdDev)
        let cut = scored.filter { entry in (Double(entry.1 - mean) / Double(denom)) >= z }
        let sorted = cut.sorted { left, right in
            if left.1 != right.1 { return left.1 > right.1 }
            return left.0.sentCount > right.0.sentCount
        }
        return Array(sorted.prefix(cap)).map { $0.0 }
    }
}
