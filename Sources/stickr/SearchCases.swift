import Foundation
import StickrCore

/// Runs every case in tests/search_cases.json against a folder of webp stickers with the real models.
/// Exits 0 when every case passes. Used by the release checks, needs the OpenRouter key.
func runSearchCases(dir: URL, casesFile: URL, searchZOverride: Double?, storeURL: URL?, showScores: Bool = false) async throws -> Int {
    let fixed = storeURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("cases-\(UUID().uuidString).sqlite")
    let store = try Store(url: fixed)
    let files = try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        .filter { $0.pathExtension == "webp" }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
    guard !files.isEmpty else { throw Store.StoreError("No webp stickers in \(dir.path)") }
    for (i, f) in files.enumerated() {
        let bytes = try Data(contentsOf: f)
        let id = "case\(i)"
        if try store.sticker(id: id) != nil { continue }
        let size = LibraryScanner.webpSize(bytes) ?? (512, 512)
        try store.save(Sticker(id: id, path: f.path, animated: isAnimatedWebP(bytes),
            width: size.0, height: size.1, byteSize: bytes.count, source: "favorite", sentCount: 0,
            firstSeen: ISO8601DateFormatter().string(from: Date()),
            caption: "", textInImage: "", mood: "", tags: [], emojis: [], vector: nil,
            state: "waiting", edited: false, model: "", provider: ""))
    }
    let key = try loadKey(nil)
    let client = try client(store: store, key: key)
    let all0 = try store.allStickers()
    if !(try store.stickers(state: "waiting")).isEmpty || all0.contains(where: { $0.vector == nil }) {
        var stats = try await Indexer(store: store, client: client).readAll() { _, _ in }
        if (try store.allStickers()).contains(where: { $0.vector == nil }) {
            stats = try await Indexer(store: store, client: client).readAll(retryFailed: true) { _, _ in }
        }
        print("read \(stats.read) of \(files.count) stickers, \(stats.failed) failed")
        guard stats.failed == 0 else { return 1 }
    } else {
        print("using the measured store at \(fixed.path)")
    }

    let data = try Data(contentsOf: casesFile)
    guard let cases = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw Store.StoreError("cannot read \(casesFile.path)")
    }
    let all = try store.allStickers()
    let withVec = all.filter { $0.vector != nil }
    guard !withVec.isEmpty else { print("no vectors"); return 1 }
    var failures = 0
    for c in cases["search"] as? [[String: Any]] ?? [] {
        let query = c["q"] as! String
        let expect = (c["expect"] as? [Int]) ?? []
        let requireEmpty = (c["max_results"] as? Int) == 0
        let vector = try await client.embed(texts: [query])[0]
        let z = requireEmpty ? 99.0 : (searchZOverride ?? ((cases["search_z"] as? Double) ?? 2.0))
        let engine = SearchEngine(stickers: withVec, searchZ: z, packZ: z)
        let hits = engine.zCut(query: vector, z: z, cap: 15)
        let resultIDs = hits.map { (Int($0.id.dropFirst(4)) ?? -1) + 1 }
        let ok = (!requireEmpty || hits.isEmpty) &&
            (requireEmpty || expect.allSatisfy { e in hits.prefix(5).contains { (Int($0.id.dropFirst(4)) ?? -1) + 1 == e } })
        print("\(ok ? "PASS" : "FAIL") search \(query) -> top \(resultIDs.map(String.init).joined(separator: " "))")
        if showScores {
            let scored = withVec.map { ($0, SearchEngine.cosine(vector, $0.vector!)) }.sorted { $0.1 > $1.1 }.prefix(8)
            for (s, score) in scored { print("   rank \(s.id) \(score)") }
        }
        if !ok { failures += 1 }
    }
    for c in cases["packs"] as? [[String: Any]] ?? [] {
        let rule = c["rule"] as! String
        let expect = (c["expect_at_least"] as? [Int]) ?? []
        let forbid = (c["forbid"] as? [Int]) ?? []
        let vector = try await client.embed(texts: [rule])[0]
        let z = searchZOverride ?? ((cases["pack_z"] as? Double) ?? 1.0)
        let engine = SearchEngine(stickers: withVec, searchZ: z, packZ: z)
        let hits = engine.zCut(query: vector, z: z, cap: PackEngine.maxMembers)
        let found = expect.filter { e in hits.contains { (Int($0.id.dropFirst(4)) ?? -1) + 1 == e } }
        let bad = hits.filter { h in forbid.contains((Int(h.id.dropFirst(4)) ?? -1) + 1) }.map { (Int($0.id.dropFirst(4)) ?? -1) + 1 }
        let ok = found.count >= expect.count && bad.isEmpty
        print("\(ok ? "PASS" : "FAIL") pack \(rule) -> \(hits.count) members, \(found.count)/\(expect.count) expected found\(showScores ? ": " + hits.map { (Int($0.id.dropFirst(4)) ?? -1) + 1 }.map(String.init).joined(separator: " ") : "")")
        if !ok { failures += 1 }
    }
    return failures == 0 ? 0 : 1
}
