import Foundation
import SQLite3

let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

public final class Store: @unchecked Sendable {
    public let url: URL
    private var db: OpaquePointer?
    private let queue = DispatchQueue(label: "stickr.store")

    public init(url: URL) throws {
        self.url = url
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try queue.sync {
            var handle: OpaquePointer?
            guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK else {
                throw StoreError("cannot open \(url.path)")
            }
            self.db = handle
            try exec("""
            PRAGMA journal_mode=WAL;
            CREATE TABLE IF NOT EXISTS stickers(
              id TEXT PRIMARY KEY, path TEXT NOT NULL, animated INTEGER NOT NULL,
              width INTEGER NOT NULL, height INTEGER NOT NULL, byte_size INTEGER NOT NULL,
              source TEXT NOT NULL, sent_count INTEGER NOT NULL DEFAULT 0, first_seen TEXT NOT NULL,
              caption TEXT DEFAULT '', text_in_image TEXT DEFAULT '', mood TEXT DEFAULT '',
              tags TEXT DEFAULT '[]', emojis TEXT DEFAULT '[]', vector BLOB,
              state TEXT NOT NULL DEFAULT 'waiting', edited INTEGER NOT NULL DEFAULT 0,
              model TEXT DEFAULT '', provider TEXT DEFAULT '');
            CREATE TABLE IF NOT EXISTS packs(
              name TEXT PRIMARY KEY, rule TEXT NOT NULL DEFAULT '',
              pins TEXT NOT NULL DEFAULT '[]', removed TEXT NOT NULL DEFAULT '[]',
              members TEXT NOT NULL DEFAULT '[]');
            CREATE TABLE IF NOT EXISTS pack_installs(
              pack TEXT NOT NULL, members TEXT NOT NULL, installed_at TEXT NOT NULL, wa_pack_id TEXT DEFAULT '');
            CREATE TABLE IF NOT EXISTS settings(key TEXT PRIMARY KEY, value TEXT NOT NULL);
            CREATE TABLE IF NOT EXISTS cost(month TEXT PRIMARY KEY, usd REAL NOT NULL DEFAULT 0);
            """)
        }
    }
    deinit { if let db { sqlite3_close(db) } }

    public struct StoreError: LocalizedError, Sendable {
        public let message: String
        public init(_ message: String) { self.message = message }
        public var errorDescription: String? { message }
    }

    public enum SQLiteValue { case text(String), int(Int64), real(Double), blob(Data) }

    public struct Row {
        let stmt: OpaquePointer
        let names: [Int32: String]
        func i(_ col: String) -> Int32? { names.first(where: { $0.value.caseInsensitiveCompare(col) == .orderedSame })?.key }
        public func text(_ col: String) -> String {
            guard let c = i(col), let p = sqlite3_column_text(stmt, c) else { return "" }
            return String(cString: p)
        }
        public func int(_ col: String) -> Int { i(col).map { Int(sqlite3_column_int64(stmt, $0)) } ?? 0 }
        public func double(_ col: String) -> Double { i(col).map { sqlite3_column_double(stmt, $0) } ?? 0 }
        public func blob(_ col: String) -> Data? {
            guard let c = i(col) else { return nil }
            let n = sqlite3_column_bytes(stmt, c)
            guard n > 0, let base = sqlite3_column_blob(stmt, c) else { return nil }
            return Data(bytes: base, count: Int(n))
        }
    }

    func exec(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw StoreError("sqlite: \(String(cString: sqlite3_errmsg(db)))")
        }
    }

    func query(_ sql: String, bind: [SQLiteValue] = [], row: @escaping (Row) throws -> Void) throws {
        try queue.sync { try queryLocked(sql, bind: bind, row: row) }
    }
    func run(_ sql: String, bind: [SQLiteValue] = []) throws {
        try queue.sync { _ = try queryLocked(sql, bind: bind) { _ in } }
    }
    private func queryLocked(_ sql: String, bind: [SQLiteValue], row: (Row) throws -> Void) throws -> Bool {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK, let stmt else {
            throw StoreError("sqlite prepare: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(stmt) }
        var names: [Int32: String] = [:]
        for c in 0..<sqlite3_column_count(stmt) {
            names[c] = String(cString: sqlite3_column_name(stmt, c))
        }
        for (n, v) in bind.enumerated() {
            switch v {
            case .text(let s): sqlite3_bind_text(stmt, Int32(n + 1), s, -1, transient)
            case .int(let x): sqlite3_bind_int64(stmt, Int32(n + 1), x)
            case .real(let r): sqlite3_bind_double(stmt, Int32(n + 1), r)
            case .blob(let b): b.withUnsafeBytes { ptr in sqlite3_bind_blob(stmt, Int32(n + 1), ptr.baseAddress, Int32(b.count), transient) }
            }
        }
        var found = false
        while sqlite3_step(stmt) == SQLITE_ROW { found = true; try row(Row(stmt: stmt, names: names)) }
        return found
    }

    // ---------- sticker CRUD ----------
    public func sticker(id: String) throws -> Sticker? {
        var found: Sticker?
        try query("SELECT * FROM stickers WHERE id = ?", bind: [.text(id)]) { found = try $0.sticker() }
        return found
    }
    public func allStickers() throws -> [Sticker] {
        var out: [Sticker] = []
        try query("SELECT * FROM stickers ORDER BY id") { out.append(try $0.sticker()) }
        return out
    }
    public func save(_ s: Sticker) throws {
        try run("""
        INSERT INTO stickers(id, path, animated, width, height, byte_size, source, sent_count, first_seen,
          caption, text_in_image, mood, tags, emojis, vector, state, edited, model, provider)
        VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)
        ON CONFLICT(id) DO UPDATE SET
          path=excluded.path, source=excluded.source,
          caption=excluded.caption, text_in_image=excluded.text_in_image, mood=excluded.mood,
          tags=excluded.tags, emojis=excluded.emojis, vector=excluded.vector,
          state=excluded.state, edited=excluded.edited, model=excluded.model, provider=excluded.provider
        """, bind: [
            .text(s.id), .text(s.path), .int(s.animated ? 1 : 0), .int(Int64(s.width)), .int(Int64(s.height)),
            .int(Int64(s.byteSize)), .text(s.source), .int(Int64(s.sentCount)), .text(s.firstSeen),
            .text(s.caption), .text(s.textInImage), .text(s.mood),
            .text(json(s.tags)), .text(json(s.emojis)),
            s.vector.map { .blob($0.withUnsafeBufferPointer { Data(buffer: $0) }) } ?? .text(""),
            .text(s.state), .int(s.edited ? 1 : 0), .text(s.model), .text(s.provider),
        ])
    }
    public func deleteSticker(id: String) throws {
        try run("DELETE FROM stickers WHERE id = ?", bind: [.text(id)])
    }
    public func stickers(state: String) throws -> [Sticker] {
        var out: [Sticker] = []
        try query("SELECT * FROM stickers WHERE state = ? ORDER BY id", bind: [.text(state)]) { out.append(try $0.sticker()) }
        return out
    }
    public func resetAutomaticReads() throws {
        try run("UPDATE stickers SET state = 'waiting', vector = NULL WHERE edited = 0")
    }

    // ---------- packs ----------
    public struct Pack: Codable, Sendable {
        public var name: String
        public var rule: String
        public var pins: [String]
        public var removed: [String]
        public var members: [String]
        public init(name: String, rule: String = "", pins: [String] = [], removed: [String] = [], members: [String] = []) {
            self.name = name; self.rule = rule; self.pins = pins; self.removed = removed; self.members = members
        }
    }
    public func pack(name: String) throws -> Pack? {
        var found: Pack?
        try query("SELECT * FROM packs WHERE name = ?", bind: [.text(name)]) {
            found = Pack(name: $0.text("name"), rule: $0.text("rule"), pins: unjson($0.text("pins")), removed: unjson($0.text("removed")), members: unjson($0.text("members")))
        }
        return found
    }
    public func allPacks() throws -> [Pack] {
        var out: [Pack] = []
        try query("SELECT * FROM packs ORDER BY name") {
            out.append(Pack(name: $0.text("name"), rule: $0.text("rule"), pins: unjson($0.text("pins")), removed: unjson($0.text("removed")), members: unjson($0.text("members"))))
        }
        return out
    }
    public func savePack(_ p: Pack) throws {
        try run("""
        INSERT INTO packs(name, rule, pins, removed, members) VALUES(?,?,?,?,?)
        ON CONFLICT(name) DO UPDATE SET rule=excluded.rule, pins=excluded.pins,
          removed=excluded.removed, members=excluded.members
        """, bind: [.text(p.name), .text(p.rule), .text(json(p.pins)), .text(json(p.removed)), .text(json(p.members))])
    }
    public func deletePack(name: String) throws {
        try run("DELETE FROM packs WHERE name = ?", bind: [.text(name)])
    }
    public func recordInstall(pack: String, members: [String], waPackID: String) throws {
        try run("INSERT INTO pack_installs(pack, members, installed_at, wa_pack_id) VALUES(?,?,?,?)",
                bind: [.text(pack), .text(json(members)), .text(ISO8601DateFormatter().string(from: Date())), .text(waPackID)])
    }
    public func lastInstall(pack: String) throws -> (members: [String], at: String, waPackID: String)? {
        var found: (members: [String], at: String, waPackID: String)?
        try query("SELECT * FROM pack_installs WHERE pack = ? ORDER BY installed_at DESC LIMIT 1", bind: [.text(pack)]) {
            found = (unjson($0.text("members")), $0.text("installed_at"), $0.text("wa_pack_id"))
        }
        return found
    }

    // ---------- settings and cost ----------
    public func setting(_ key: String) throws -> String? {
        var found: String?
        try query("SELECT value FROM settings WHERE key = ?", bind: [.text(key)]) { found = $0.text("value") }
        return found
    }
    public func setSetting(_ key: String, _ value: String) throws {
        try run("INSERT INTO settings(key, value) VALUES(?,?) ON CONFLICT(key) DO UPDATE SET value=excluded.value", bind: [.text(key), .text(value)])
    }
    func monthString() -> String {
        let c = Calendar.current.dateComponents([.year, .month], from: Date())
        return String(c.year!) + "-" + String(format: "%02d", c.month!)
    }
    public func addCost(_ usd: Double) throws {
        try run("INSERT INTO cost(month, usd) VALUES(?,?) ON CONFLICT(month) DO UPDATE SET usd = usd + excluded.usd",
                bind: [.text(monthString()), .real(usd)])
    }
    public func monthCost() throws -> (month: String, usd: Double) {
        var usd = 0.0
        try query("SELECT usd FROM cost WHERE month = ?", bind: [.text(monthString())]) { usd = $0.double("usd") }
        return (monthString(), usd)
    }
}

func json(_ list: [String]) -> String {
    (try? JSONEncoder().encode(list)).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
}
func unjson(_ s: String) -> [String] {
    (try? JSONDecoder().decode([String].self, from: Data(s.utf8))) ?? []
}

extension Store.Row {
    func sticker() throws -> Sticker {
        let vec: [Float]? = blob("vector").map { d in d.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) } }
        return Sticker(
            id: text("id"), path: text("path"), animated: int("animated") == 1,
            width: int("width"), height: int("height"), byteSize: int("byte_size"),
            source: text("source"), sentCount: int("sent_count"), firstSeen: text("first_seen"),
            caption: text("caption"), textInImage: text("text_in_image"), mood: text("mood"),
            tags: unjson(text("tags")), emojis: unjson(text("emojis")), vector: vec,
            state: text("state"), edited: int("edited") == 1, model: text("model"), provider: text("provider"))
    }
}
