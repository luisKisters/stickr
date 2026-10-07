import AppKit
import ServiceManagement
import WebKit

@MainActor
final class AppBridge: NSObject, WKScriptMessageHandlerWithReply {
    let store: Store
    weak var window: StickrWindowController?
    private var activeIndexer: Indexer?

    init(store: Store) { self.store = store }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
        guard let body = message.body as? [String: Any], let method = body["method"] as? String else {
            return (nil, "Stickr received an invalid request.")
        }
        let params = body["params"] as? [String: Any] ?? [:]
        do { return (try await call(method, params), nil) }
        catch { return (nil, plain(error)) }
    }

    private func call(_ method: String, _ p: [String: Any]) async throws -> Any {
        switch method {
        case "bootstrap":
            let stickers = try store.allStickers()
            return try json(Bootstrap(
                stickers: stickers,
                packs: try store.allPacks(),
                cost: try store.monthCost().usd,
                keyPresent: StickrKeychain.read() != nil,
                onboardingComplete: try store.setting("onboarding_complete") == "true",
                updates: try AppRefresh.statuses(store: store),
                settings: try settings()))
        case "refreshAll":
            return try json(try await AppRefresh.run(store: store, forcePackCheck: true))
        case "scan":
            let result = try LibraryScanner().scan(store: store)
            window?.bringForward(aboveSettings: true)
            return try json(result)
        case "saveSettings":
            if let key = p["key"] as? String, !key.isEmpty { try StickrKeychain.save(key) }
            for name in ["base_url", "caption_model", "embed_model", "routing", "schedule"] {
                if let value = p[name] as? String { try store.setSetting(name, value) }
            }
            if p["schedule"] != nil { NotificationCenter.default.post(name: .stickrScheduleChanged, object: nil) }
            if let hotkey = p["hotkey"] as? String {
                try HotKeyController.delegate?.applySearchHotKey(hotkey)
                try store.setSetting("hotkey", hotkey)
            }
            if let complete = p["onboarding_complete"] as? Bool { try store.setSetting("onboarding_complete", complete ? "true" : "false") }
            if let login = p["login"] as? Bool {
                if login { try? SMAppService.mainApp.register() } else { try? await SMAppService.mainApp.unregister() }
                try store.setSetting("start_at_login", login ? "true" : "false")
            }
            return "{\"ok\":true}"
        case "testConnection":
            let client = try modelClient(overrideKey: p["key"] as? String)
            guard let sample = try store.allStickers().first else { throw Store.StoreError("Allow access and scan your stickers first.") }
            let result = try await client.testConnection(bytes: Data(contentsOf: URL(fileURLWithPath: sample.path)))
            return try json(result)
        case "read":
            guard activeIndexer == nil else { throw Store.StoreError("Stickr is already reading your stickers.") }
            let indexer = Indexer(store: store, client: try modelClient())
            activeIndexer = indexer
            defer { activeIndexer = nil }
            let stats = try await indexer.readAll(retryFailed: p["retryFailed"] as? Bool ?? false) { [weak self] sticker, state in
                Task { @MainActor in self?.window?.reportProgress(stickerID: sticker.id, state: state) }
            }
            return try json(stats)
        case "pauseRead":
            activeIndexer?.setPaused(true)
            return "{\"ok\":true}"
        case "readOne":
            guard let id = p["id"] as? String, var sticker = try store.sticker(id: id) else { throw Store.StoreError("This sticker no longer exists.") }
            let client = try modelClient()
            let result = try await client.caption(bytes: Data(contentsOf: URL(fileURLWithPath: sticker.path)))
            sticker.caption = result.caption; sticker.textInImage = result.textInImage; sticker.mood = result.mood
            sticker.tags = result.tags; sticker.emojis = result.emojis; sticker.provider = result.provider
            sticker.model = client.captionModelName; sticker.state = "read"; sticker.edited = false
            sticker.vector = try await client.embed(texts: [sticker.docText]).first
            try store.save(sticker); try store.addCost(result.cost)
            return try json(sticker)
        case "resetReads":
            try store.resetAutomaticReads()
            return "{\"ok\":true}"
        case "saveSticker":
            guard let id = p["id"] as? String, var sticker = try store.sticker(id: id) else { throw Store.StoreError("This sticker no longer exists.") }
            if let v = p["caption"] as? String { sticker.caption = v }
            if let v = p["textInImage"] as? String { sticker.textInImage = v }
            if let v = p["mood"] as? String { sticker.mood = v }
            if let v = p["tags"] as? [String] { sticker.tags = Array(v.prefix(8)) }
            if let v = p["emojis"] as? [String] { sticker.emojis = Array(v.prefix(3)) }
            sticker.edited = true; try store.save(sticker)
            return try json(sticker)
        case "savePack":
            guard let name = p["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty else { throw Store.StoreError("Give this pack a name.") }
            let old = try store.pack(name: name)
            let pack = Store.Pack(name: name, rule: p["rule"] as? String ?? old?.rule ?? "",
                                  pins: p["pins"] as? [String] ?? old?.pins ?? [],
                                  removed: p["removed"] as? [String] ?? old?.removed ?? [],
                                  members: old?.members ?? [])
            try store.savePack(pack); return try json(pack)
        case "buildPack":
            guard let name = p["name"] as? String, var pack = try store.pack(name: name) else { throw Store.StoreError("This pack no longer exists.") }
            let all = try store.allStickers()
            let vector = try await modelClient().embed(texts: [pack.rule]).first ?? []
            let matches = SearchEngine(stickers: all.filter { $0.vector != nil }, searchZ: PackEngine.zSearch, packZ: PackEngine.zPack)
                .zCut(query: vector, z: PackEngine.zPack, cap: PackEngine.maxMembers)
            pack.members = PackEngine.members(pack: pack, stickers: all, ruleResults: matches).map(\.id)
            try store.savePack(pack); return try json(pack)
        case "search":
            let query = p["query"] as? String ?? ""
            guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return "[]" }
            let all = try store.allStickers()
            do {
                let vector = try await modelClient().embed(texts: [query]).first ?? []
                let result = SearchEngine(stickers: all.filter { $0.vector != nil }).zCut(query: vector, z: PackEngine.zSearch, cap: 15)
                return try json(SearchReply(items: result, fallback: false))
            } catch {
                return try json(SearchReply(items: wordFallback(all, query), fallback: true))
            }
        case "installPack":
            guard let name = p["name"] as? String, let pack = try store.pack(name: name) else { throw Store.StoreError("This pack no longer exists.") }
            let byID = Dictionary(uniqueKeysWithValues: try store.allStickers().map { ($0.id, $0) })
            let members = pack.members.compactMap { byID[$0] }
            let omitted = members.compactMap { sticker -> String? in PackExport.limitProblems(sticker).map { "\(sticker.caption): \($0)" } }
            let valid = members.filter { PackExport.limitProblems($0) == nil }
            let split = PackEngine.splitByAnimation(valid)
            let animated = p["animated"] as? Bool ?? false
            let title = animated ? "\(name) animated" : name
            let group = animated ? split.animated : split.still
            guard group.count >= 3 else { throw Store.StoreError("This variant needs at least three compatible stickers.") }
            let data = try PackExport.packJSON(name: title, members: group, animated: animated)
            _ = try await WhatsAppInstall.install(packJSON: data)
            try store.recordInstall(pack: title, members: group.map(\.id), waPackID: PackExport.slug(title))
            let pending = try AppRefresh.statuses(store: store).filter { !$0.current }
            try store.setSetting("pending_updates", String(data: try JSONEncoder().encode(pending), encoding: .utf8) ?? "[]")
            return try json(InstallReply(installed: [title], omitted: omitted))
        case "copyPicture":
            guard let id = p["id"] as? String, let sticker = try store.sticker(id: id), let image = NSImage(contentsOfFile: sticker.path) else { throw Store.StoreError("This sticker cannot be copied.") }
            NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([image])
            return "{\"ok\":true}"
        case "openPrivacy":
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
            window?.bringForward(aboveSettings: true)
            return "{\"ok\":true}"
        case "closeWindow":
            window?.closeWindow()
            return "{\"ok\":true}"
        default:
            throw Store.StoreError("Stickr does not know this action.")
        }
    }

    private func settings() throws -> SettingsReply {
        SettingsReply(baseURL: try store.setting("base_url") ?? "https://openrouter.ai/api/v1",
                      captionModel: try store.setting("caption_model") ?? "z-ai/glm-5.3-flash",
                      embedModel: try store.setting("embed_model") ?? "baai/bge-m3",
                      routing: try store.setting("routing") ?? "baseten-first",
                      schedule: try store.setting("schedule") ?? "Every 6 hours",
                      hotkey: try store.setting("hotkey") ?? "option+command+s",
                      login: try store.setting("start_at_login") != "false")
    }

    private func modelClient(overrideKey: String? = nil) throws -> ModelClient {
        guard let key = overrideKey.flatMap({ $0.isEmpty ? nil : $0 }) ?? StickrKeychain.read() else { throw Store.StoreError("Enter your OpenRouter key first.") }
        let s = try settings()
        return ModelClient(baseURL: URL(string: s.baseURL) ?? URL(string: "https://openrouter.ai/api/v1")!, key: key,
                           captionModel: s.captionModel, embedModel: s.embedModel, routing: s.routing)
    }

    private func wordFallback(_ all: [Sticker], _ query: String) -> [Sticker] {
        let words = query.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count > 1 }
        return Array(all.filter { sticker in
            let text = sticker.docText.lowercased(); return words.contains { text.contains($0) }
        }.prefix(15))
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        String(data: try JSONEncoder().encode(value), encoding: .utf8) ?? "null"
    }

    private func plain(_ error: Error) -> String {
        if let e = error as? ModelClient.ConnectionProblem {
            switch e { case .badKey: return "OpenRouter does not accept this key."; case .noCredit: return "This key has no credit left."; case .unknownProvider: return "This provider does not serve this model."; case .other(let text): return "No answer: \(text)" }
        }
        if let e = error as? ModelClient.HTTPError {
            if e.status == 401 { return "OpenRouter does not accept this key." }
            if e.status == 402 { return "This key has no credit left." }
            return e.message
        }
        return error.localizedDescription
    }
}

private struct Bootstrap: Encodable { let stickers: [Sticker]; let packs: [Store.Pack]; let cost: Double; let keyPresent: Bool; let onboardingComplete: Bool; let updates: [PackUpdate]; let settings: SettingsReply }
private struct SettingsReply: Encodable { let baseURL, captionModel, embedModel, routing, schedule, hotkey: String; let login: Bool }
private struct SearchReply: Encodable { let items: [Sticker]; let fallback: Bool }
private struct InstallReply: Encodable { let installed, omitted: [String] }
