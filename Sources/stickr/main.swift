import Foundation
import StickrCore

func storeURL() -> URL {
    URL(fileURLWithPath: NSString(string: "~/Library/Application Support/Stickr/stickr.sqlite").expandingTildeInPath)
}

func openStore() throws -> Store { try Store(url: storeURL()) }

func loadKey(_ flag: String?) throws -> String {
    if let flag, !flag.isEmpty { return flag }
    if let env = ProcessInfo.processInfo.environment["STICKR_KEY"] ?? ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"] { return env }
    let store = try openStore()
    if let saved = try store.setting("key") { return saved }
    FileHandle.standardError.write("No OpenRouter key. Use --key, the STICKR_KEY environment variable, or set it once in the app.\n".data(using: .utf8)!)
    exit(2)
}

func client(store: Store, key: String) throws -> ModelClient {
    let base = try store.setting("base_url") ?? "https://openrouter.ai/api/v1"
    return ModelClient(
        baseURL: URL(string: base) ?? URL(string: "https://openrouter.ai/api/v1")!,
        key: key,
        captionModel: try store.setting("caption_model") ?? "z-ai/glm-5.3-flash",
        embedModel: try store.setting("embed_model") ?? "baai/bge-m3",
        routing: try store.setting("routing") ?? "baseten-first")
}

func readAllStickers(_ store: Store) throws -> [Sticker] { try store.allStickers() }

func awaitEmbed(_ c: ModelClient, _ texts: [String]) async throws -> [Float] {
    try await c.embed(texts: texts).first ?? []
}

func packRuleResults(store: Store, rule: String, all: [Sticker], key: String) async throws -> [Sticker] {
    let c = try client(store: store, key: key)
    let vector = try await awaitEmbed(c, [rule])
    let withVec = all.filter { $0.vector != nil }
    guard !withVec.isEmpty else { return [] }
    let engine = SearchEngine(stickers: withVec, searchZ: PackEngine.zSearch, packZ: PackEngine.zPack)
    return engine.zCut(query: vector, z: PackEngine.zPack, cap: PackEngine.maxMembers)
}

func librarySearch(store: Store, query: String, z: Double) async throws -> [Sticker] {
    let all = try readAllStickers(store).filter { $0.vector != nil }
    guard !all.isEmpty else { throw Store.StoreError("No sticker is read yet. Run: stickr read") }
    let key = try loadKey(nil)
    let c = try client(store: store, key: key)
    let vector = try await awaitEmbed(c, [query])
    let engine = SearchEngine(stickers: all, searchZ: z, packZ: z)
    return engine.zCut(query: vector, z: z, cap: 15)
}

func printResults(_ list: [Sticker]) {
    if list.isEmpty { print("No sticker fits that."); return }
    for (i, s) in list.enumerated() {
        print("\(i + 1). \(s.id.prefix(12)) \(s.animated ? "(animated)" : "") \(s.caption)")
        print("   emoji: \(s.emojis.joined(separator: " "))   tags: \(s.tags.joined(separator: ", "))")
    }
}

func wordFallback(_ all: [Sticker], query: String) -> [Sticker] {
    let stop = Set("we you he she it they the a an to of for and or is are am be i me my your need want with that this when about so too very in on at ich du wir der die das ein eine und ist zu mit".split(separator: " ").map(String.init))
    let words = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { $0.count > 1 && !stop.contains(String($0)) }
    guard !words.isEmpty else { return [] }
    var scored: [(Sticker, Double)] = []
    for s in all {
        let hay = (s.caption + " " + s.textInImage + " " + s.mood).lowercased()
        let tags = s.tags.joined(separator: " ").lowercased()
        var score = 0.0
        for w in words {
            if tags.contains(w) { score += 1 } else if hay.contains(w) { score += 0.8 }
        }
        scored.append((s, score / Double(words.count)))
    }
    let hits = scored.filter { $0.1 >= 0.4 }
    let sorted = hits.sorted { $0.1 > $1.1 }
    return Array(sorted.prefix(15)).map { $0.0 }
}

func stickerJSON(_ s: Sticker) -> String {
    let dict: [String: Any] = [
        "id": s.id, "path": s.path, "animated": s.animated, "width": s.width, "height": s.height,
        "byte_size": s.byteSize, "source": s.source, "sent_count": s.sentCount, "first_seen": s.firstSeen,
        "caption": s.caption, "text_in_image": s.textInImage, "mood": s.mood, "tags": s.tags,
        "emojis": s.emojis, "vector": s.vector != nil, "state": s.state, "edited": s.edited,
        "model": s.model, "provider": s.provider,
    ]
    let data = try! JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted, .sortedKeys])
    return String(data: data, encoding: .utf8) ?? "{}"
}

func run() async throws {
    let store = try openStore()
    guard let command = args.first else {
        print("stickr: scan | list | read | show <id> | edit <id> | find <text> | cost | test-connection | pack add|list|show|build|pin|remove|install|status")
        exit(1)
    }
    let rest = Array(args.dropFirst())

    switch command {
    case "scan":
        let scanner = try LibraryScanner()
        let r = try scanner.scan(store: store)
        print("\(r.added) new, \(r.known) known, \(r.gone) gone. \(r.sentBumped) sent entries.")
    case "list":
        let all = try readAllStickers(store)
        if flags["json"] != nil {
            print("[\(all.map { stickerJSON($0) }.joined(separator: ","))]")
        } else {
            print("\(all.count) stickers. \(all.filter { $0.state == "read" }.count) read.")
        }
    case "read":
        let c = try client(store: store, key: try loadKey((flags["key"] ?? "")))
        let indexer = Indexer(store: store, client: c)
        let stats = try await indexer.readAll(
            limit: { let l = flags["limit"] ?? ""; return l.isEmpty ? Int.max : (Int(l) ?? 40) }(),
            retryFailed: flags["retry-failed"] != nil) { _, _ in }
        let (_, spent) = try store.monthCost()
        print("read \(stats.read), failed \(stats.failed). Spent this month: $\(String(format: "%.4f", spent))")
    case "show":
        guard let id = rest.first, let s = try store.sticker(id: id) ?? (try readAllStickers(store).first { $0.id.hasPrefix(id) }) else {
            print("No sticker with this id."); exit(1)
        }
        print(stickerJSON(s))
    case "edit":
        guard let id = rest.first, var s = try store.sticker(id: id) ?? (try readAllStickers(store).first { $0.id.hasPrefix(id) }) else {
            print("No sticker with this id."); exit(1)
        }
        var kv: [String: [String]] = [:]
        i = 1
        while i < rest.count - 1 {
            kv[rest[i]] = [rest[i + 1]]; i += 2
        }
        if let c = kv["--caption"]?.first { s.caption = c }
        if let m = kv["--mood"]?.first { s.mood = m }
        if let t = kv["--tags"]?.first { s.tags = t.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) } }
        if let e = kv["--emojis"]?.first { s.emojis = e.split(separator: " ").map(String.init).prefix(3).map { $0 } }
        if let x = kv["--text"]?.first { s.textInImage = x }
        s.edited = true
        try store.save(s)
        print("saved.")
    case "find":
        guard !rest.isEmpty else { print("stickr find <text>"); exit(1) }
        let query = rest.joined(separator: " ")
        let all = try readAllStickers(store)
        do {
            printResults(try await librarySearch(store: store, query: query, z: Double(flags["z"] ?? "") ?? 2.0))
        } catch {
            FileHandle.standardError.write("No connection. Showing word matches only.\n".data(using: .utf8)!)
            printResults(wordFallback(all, query: query))
        }
    case "cost":
        let (_, spent) = try store.monthCost()
        print("Spent this month: $\(String(format: "%.4f", spent))")
    case "test-connection":
        let c = try client(store: store, key: try loadKey((flags["key"] ?? "")))
        do {
            let sample = try readAllStickers(store).first
            let r = try await c.testConnection(bytes: sample.map { try Data(contentsOf: URL(fileURLWithPath: $0.path)) } ?? Data())
            print("\(r.caption)")
            print("\(r.provider) answered in \(String(format: "%.1f", r.seconds)) s. This sticker cost $\(String(format: "%.5f", r.cost)).")
        } catch ModelClient.ConnectionProblem.badKey {
            FileHandle.standardError.write("OpenRouter does not accept this key.\n".data(using: .utf8)!)
            exit(1)
        } catch ModelClient.ConnectionProblem.noCredit {
            FileHandle.standardError.write("This key has no credit left.\n".data(using: .utf8)!)
            exit(1)
        } catch ModelClient.ConnectionProblem.unknownProvider {
            FileHandle.standardError.write("This provider does not serve this model.\n".data(using: .utf8)!)
            exit(1)
        } catch ModelClient.ConnectionProblem.other(let m) {
            FileHandle.standardError.write("No answer: \(m)\n".data(using: .utf8)!)
            exit(1)
        }
    case "pack":
        try await pack(store: store, rest: rest)
    default:
        print("Unknown command: \(command)"); exit(1)
    }
}

func pack(store: Store, rest: [String]) async throws {
    let all = try readAllStickers(store)
    let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    guard let action = rest.first else { print("stickr pack add|list|show|build|pin|remove|install|status"); exit(1) }
    let rest2 = Array(rest.dropFirst())
    switch action {
    case "add":
        guard let name = rest2.first else { print("stickr pack add <name> <rule sentence>"); exit(1) }
        let rule = rest2.dropFirst().joined(separator: " ")
        try store.savePack(Store.Pack(name: name, rule: rule))
        print("Pack \(name) saved.")
    case "list":
        for p in try store.allPacks() { print("\(p.name) | \(p.rule) | \(p.members.count) members") }
    case "show":
        guard let name = rest2.first, let p = try store.pack(name: name) else { print("No pack with this name."); exit(1) }
        print("Pack \(p.name), rule: \(p.rule)")
        for (i, id) in p.members.enumerated() {
            let s = byID[id]
            print("\(i + 1). \(id.prefix(12)) \(s?.animated == true ? "(animated)" : "") \(s?.caption ?? "")\(p.pins.contains(id) ? " [pinned]" : "")")
        }
    case "build":
        guard let name = rest2.first, let p = try store.pack(name: name) else { print("No pack with this name."); exit(1) }
        let key = try loadKey(nil)
        let ruleResults = p.rule.isEmpty ? [] : try await packRuleResults(store: store, rule: p.rule, all: all, key: key)
        var p2 = p
        p2.members = PackEngine.members(pack: p, stickers: all, ruleResults: ruleResults).map { $0.id }
        try store.savePack(p2)
        print("\(p2.members.count) members.")
    case "pin":
        guard let name = rest2.first, let id = rest2.dropFirst().first, var p = try store.pack(name: name) else { print("stickr pack pin <name> <id>"); exit(1) }
        let full = byID.first { $0.key.hasPrefix(id) }?.key ?? id
        if !p.pins.contains(full) { p.pins.append(full) }
        try store.savePack(p)
        print("pinned.")
    case "remove":
        guard let name = rest2.first, let id = rest2.dropFirst().first, var p = try store.pack(name: name) else { print("stickr pack remove <name> <id>"); exit(1) }
        let full = byID.first { $0.key.hasPrefix(id) }?.key ?? id
        p.removed.append(full); p.pins.removeAll { $0 == full }
        try store.savePack(p)
        print("removed.")
    case "install":
        guard let name = rest2.first, let p = try store.pack(name: name) else { print("stickr pack install <name>"); exit(1) }
        let members = p.members.compactMap { byID[$0] }
        let bad = members.compactMap { s -> (Sticker, String)? in PackExport.limitProblems(s).map { (s, $0) } }
        let ok = members.filter { PackExport.limitProblems($0) == nil }
        let (still, animated) = PackEngine.splitByAnimation(ok)
        var parts: [(data: Data, count: Int)] = []
        if still.count >= 3 { parts.append((try PackExport.packJSON(name: name, members: still, animated: false), still.count)) }
        if animated.count >= 3 { parts.append((try PackExport.packJSON(name: name + " animated", members: animated, animated: true), animated.count)) }
        guard !parts.isEmpty else { throw Store.StoreError("This pack has fewer than 3 stickers that fit the WhatsApp limits.") }
        for part in parts {
            _ = try WhatsAppInstall.install(packJSON: part.data)
            try store.recordInstall(pack: name, members: p.members, waPackID: PackExport.slug(name))
            print("Handed \(part.count) stickers to WhatsApp. Confirm the dialog there.")
        }
        for (s, why) in bad { print("Left out \(s.id.prefix(12)): \(why)") }
    case "status":
        guard let name = rest2.first, let p = try store.pack(name: name) else { print("No pack with this name."); exit(1) }
        guard let install = try store.lastInstall(pack: name) else { print("not installed"); return }
        if install.members == p.members { print("current") }
        else {
            let added = Set(p.members).subtracting(install.members).count
            let gone = Set(install.members).subtracting(p.members).count
            print("changed: \(added) added, \(gone) removed")
        }
    default:
        print("Unknown pack action: \(action)"); exit(1)
    }
}

nonisolated(unsafe) var args = Array(CommandLine.arguments.dropFirst())
nonisolated(unsafe) var flags: [String: String] = [:]
nonisolated(unsafe) var positional: [String] = []
nonisolated(unsafe) var i = 0
while i < args.count {
    let a = args[i]
    if a == "--key", i + 1 < args.count { flags["key"] = args[i + 1]; i += 2 }
    else if a == "--limit", i + 1 < args.count { flags["limit"] = args[i + 1]; i += 2 }
    else if a == "--z", i + 1 < args.count { flags["z"] = args[i + 1]; i += 2 }
    else if a == "--retry-failed" { flags["retry-failed"] = "true"; i += 1 }
    else if a == "--json" { flags["json"] = "true"; i += 1 }
    else { positional.append(a); i += 1 }
}
args = positional


let sema = DispatchSemaphore(value: 0)
Task.detached {
    do { try await run() } catch let e as Store.StoreError {
        FileHandle.standardError.write("\(e.message)\n".data(using: .utf8)!); exit(1)
    } catch {
        FileHandle.standardError.write("No answer: \(error)\n".data(using: .utf8)!); exit(1)
    }
    sema.signal()
}
_ = sema.wait(timeout: .now() + 3600)
