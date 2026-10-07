import Foundation

struct PackUpdate: Codable, Sendable {
    let name: String
    let added: Int
    let removed: Int
    let current: Bool
}

struct RefreshSummary: Codable, Sendable {
    let added: Int
    let updates: [PackUpdate]
}

enum AppRefresh {
    static func run(store: Store, forcePackCheck: Bool = false) async throws -> RefreshSummary {
        let scan = try LibraryScanner().scan(store: store)
        if scan.added > 0, let client = try client(store: store) {
            _ = try await Indexer(store: store, client: client).readAll(retryFailed: true) { _, _ in }
        }
        if scan.added > 0 || forcePackCheck, let client = try client(store: store) {
            for var pack in try store.allPacks() where !pack.rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let all = try store.allStickers()
                let vector = try await client.embed(texts: [pack.rule]).first ?? []
                let matches = SearchEngine(stickers: all.filter { $0.vector != nil }, searchZ: PackEngine.zSearch, packZ: PackEngine.zPack)
                    .zCut(query: vector, z: PackEngine.zPack, cap: PackEngine.maxMembers)
                pack.members = PackEngine.members(pack: pack, stickers: all, ruleResults: matches).map(\.id)
                try store.savePack(pack)
            }
        }
        let updates = try statuses(store: store)
        let encoded = String(data: try JSONEncoder().encode(updates.filter { !$0.current }), encoding: .utf8) ?? "[]"
        try store.setSetting("pending_updates", encoded)
        try store.setSetting("last_checked", ISO8601DateFormatter().string(from: Date()))
        return RefreshSummary(added: scan.added, updates: updates)
    }

    static func statuses(store: Store) throws -> [PackUpdate] {
        let stickers = Dictionary(uniqueKeysWithValues: try store.allStickers().map { ($0.id, $0) })
        var result: [PackUpdate] = []
        for pack in try store.allPacks() {
            let members = pack.members.compactMap { stickers[$0] }.filter { PackExport.limitProblems($0) == nil }
            let split = PackEngine.splitByAnimation(members)
            for (name, group) in [(pack.name, split.still), ("\(pack.name) animated", split.animated)] where group.count >= 3 {
                let ids = group.map(\.id)
                let installed = try store.lastInstall(pack: name)?.members ?? []
                let old = Set(installed), fresh = Set(ids)
                result.append(PackUpdate(name: name, added: fresh.subtracting(old).count,
                                         removed: old.subtracting(fresh).count,
                                         current: !installed.isEmpty && installed == ids))
            }
        }
        return result
    }

    private static func client(store: Store) throws -> ModelClient? {
        guard let key = StickrKeychain.read() else { return nil }
        return ModelClient(
            baseURL: URL(string: try store.setting("base_url") ?? "https://openrouter.ai/api/v1")!, key: key,
            captionModel: try store.setting("caption_model") ?? "z-ai/glm-5.3-flash",
            embedModel: try store.setting("embed_model") ?? "baai/bge-m3",
            routing: try store.setting("routing") ?? "baseten-first")
    }
}
