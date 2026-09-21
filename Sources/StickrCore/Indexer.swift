import Foundation

public struct ReadStats: Sendable {
    public var read = 0
    public var failed = 0
    public var skipped = 0
}

/// Reads captions and then meaning vectors. Three caption requests run at the same time.
/// Results are saved one sticker at a time, so a stop and a later run continue where this run stopped.
public final class Indexer: @unchecked Sendable {
    let store: Store
    let client: any ModelReading
    var paused = false
    let lock = NSLock()

    public init(store: Store, client: any ModelReading) {
        self.store = store; self.client = client
    }

    public func setPaused(_ p: Bool) { lock.lock(); paused = p; lock.unlock() }
    public func isPaused() -> Bool { lock.lock(); defer { lock.unlock() }; return paused }

    func nextBatch(_ limit: Int, retryFailed: Bool) throws -> [Sticker] {
        let waiting = try store.stickers(state: "waiting")
        let failed = retryFailed ? try store.stickers(state: "failed") : []
        return Array((failed + waiting).prefix(limit))
    }

    public func readAll(limit: Int = Int.max, retryFailed: Bool = false,
                        onSticker: @escaping @Sendable (Sticker, String) -> Void) async throws -> ReadStats {
        let queue = try nextBatch(limit, retryFailed: retryFailed).filter { !$0.edited }
        var stats = ReadStats()
        // Three caption requests at a time, in order, so a stop loses nothing.
        for batch in queue.chunked(into: 3) {
            try await withThrowingTaskGroup(of: Sticker.self) { group in
                for sticker in batch {
                    group.addTask { [client, store, self] in
                        if self.isPaused() { return sticker }
                        var s = sticker
                        do {
                            let r = try await client.caption(bytes: try Data(contentsOf: URL(fileURLWithPath: s.path)))
                            s.caption = r.caption; s.textInImage = r.textInImage; s.mood = r.mood
                            s.tags = r.tags; s.emojis = r.emojis; s.state = "read"
                            s.model = client.captionModelName; s.provider = r.provider
                            try store.save(s)
                            try store.addCost(r.cost)
                            onSticker(s, "read")
                        } catch {
                            s.state = "failed"
                            try? store.save(s)
                            onSticker(s, "failed")
                        }
                        return s
                    }
                }
                for try await done in group {
                    if done.state == "read" { stats.read += 1 }
                    if done.state == "failed" { stats.failed += 1 }
                }
            }
        }
        // Meaning vectors in batches of up to 64 texts, after the captions.
        let all = try store.allStickers().filter { $0.state == "read" && $0.vector == nil }
        for batch in all.chunked(into: 64) {
            let vectors = try await client.embed(texts: batch.map { $0.docText })
            for (i, v) in vectors.enumerated() where i < batch.count {
                var s = batch[i]; s.vector = v
                try store.save(s)
                onSticker(s, "vector")
            }
        }
        return stats
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
