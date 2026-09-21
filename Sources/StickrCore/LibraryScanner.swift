import Foundation
import CryptoKit
import SQLite3

public struct ScanResult: Sendable {
    public var added: Int
    public var known: Int
    public var gone: Int
    public var sentBumped: Int
}

public struct LibraryScanner: Sendable {
    public let container: URL       // WhatsApp group container
    public let stickrDir: URL       // Stickr's own data folder

    public static func whatsappContainer() -> URL? {
        let candidates = [
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Group Containers/group.net.whatsapp.WhatsApp.shared"),
        ]
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    public init(container: URL? = nil, stickrDir: URL? = nil) throws {
        guard let container = container ?? Self.whatsappContainer() else {
            throw Store.StoreError("Stickr cannot see your stickers. macOS is blocking access to the WhatsApp data. Open System Settings, Privacy & Security, Files and Folders, and allow access for Stickr, then click Allow again.")
        }
        self.container = container
        self.stickrDir = stickrDir ?? URL(fileURLWithPath: NSString(string: "~/Library/Application Support/Stickr").expandingTildeInPath)
    }

    /// Copies the databases with their -wal and -shm files and reads the copies. Never opens the originals for writing.
    func copyDatabases() throws -> URL {
        let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("stickr-db-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        for name in ["Sticker.sqlite", "ChatStorage.sqlite"] {
            for ext in ["", "-wal", "-shm"] {
                let src = container.appendingPathComponent(name + ext)
                guard FileManager.default.fileExists(atPath: src.path) else {
                    if ext.isEmpty { throw Store.StoreError("Stickr cannot read \(name) in the WhatsApp data. Give Stickr access and run the scan again.") }
                    continue
                }
                try FileManager.default.copyItem(at: src, to: tmp.appendingPathComponent(name + ext))
            }
        }
        return tmp
    }

    func readOnly(_ path: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        guard sqlite3_open_v2(path.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let db else {
            throw Store.StoreError("The copied WhatsApp database could not be opened. Run the scan again.")
        }
        return db
    }

    public func scan(store: Store) throws -> ScanResult {
        let files = container.appendingPathComponent("stickers")
        let media = container.appendingPathComponent("Media")
        let tmp = try copyDatabases()
        defer { try? FileManager.default.removeItem(at: tmp) }

        var found: [String: (bytes: Data, source: String, animated: Bool, w: Int, h: Int, size: Int)] = [:]
        var sentCounts: [String: Int] = [:]

        let stickerDB = try readOnly(tmp.appendingPathComponent("Sticker.sqlite"))
        defer { sqlite3_close(stickerDB) }
        var q: OpaquePointer?
        guard sqlite3_prepare_v2(stickerDB, "SELECT ZRELATIVEIMAGEPATH, ZWIDTH, ZHEIGHT, ZFILELENGTH FROM ZWACDSTICKER WHERE ZSTICKERPACK IS NULL", -1, &q, nil) == SQLITE_OK else {
            throw Store.StoreError("Stickr cannot read the WhatsApp sticker library. Run the scan again.")
        }
        defer { sqlite3_finalize(q) }
        while sqlite3_step(q) == SQLITE_ROW {
            let rel = sqlite3_column_text(q, 0).map { String(cString: $0) } ?? ""
            guard !rel.isEmpty else { continue }
            let path = files.appendingPathComponent(rel)
            let w = Int(sqlite3_column_int64(q, 1)), h = Int(sqlite3_column_int64(q, 2))
            if let data = try? Data(contentsOf: path) {
                found[hash(data)] = (data, "favorite", isAnimatedWebP(data), w, h, data.count)
            }
        }

        let chatDB = try readOnly(tmp.appendingPathComponent("ChatStorage.sqlite"))
        defer { sqlite3_close(chatDB) }
        var cq: OpaquePointer?
        guard sqlite3_prepare_v2(chatDB, """
          SELECT mi.ZMEDIALOCALPATH, msg.ZISFROMME FROM ZWAMESSAGE msg
          JOIN ZWAMEDIAITEM mi ON mi.ZMESSAGE = msg.Z_PK
          WHERE msg.ZMESSAGETYPE = 15 AND mi.ZMEDIALOCALPATH IS NOT NULL
        """, -1, &cq, nil) == SQLITE_OK else {
            throw Store.StoreError("Stickr cannot read the WhatsApp chat database. Run the scan again.")
        }
        defer { sqlite3_finalize(cq) }
        while sqlite3_step(cq) == SQLITE_ROW {
            let rel = sqlite3_column_text(cq, 0).map { String(cString: $0) } ?? ""
            let fromMe = sqlite3_column_int64(cq, 1) == 1
            guard !rel.isEmpty else { continue }
            let path = media.appendingPathComponent(rel)
            guard let data = try? Data(contentsOf: path) else { continue }
            let h = hash(data)
            if found[h] == nil { found[h] = (data, fromMe ? "sent" : "received", isAnimatedWebP(data), 0, 0, data.count) }
            if fromMe { sentCounts[h, default: 0] += 1 }
        }

        let dir = stickrDir.appendingPathComponent("stickers")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let now = ISO8601DateFormatter().string(from: Date())
        var added = 0, known = 0
        for (id, f) in found {
            if let old = try store.sticker(id: id) {
                known += 1
                var s = old
                if !s.edited && s.source == "received" && f.source == "favorite" { s.source = "favorite" }
                try store.save(s)
            } else {
                added += 1
                let dest = dir.appendingPathComponent("\(id).webp")
                try f.bytes.write(to: dest, options: .atomic)
                let img = webpSize(f.bytes) ?? (f.w, f.h)
                try store.save(Sticker(
                    id: id, path: dest.path, animated: f.animated, width: img.0, height: img.1,
                    byteSize: f.bytes.count, source: f.source, sentCount: 0, firstSeen: now,
                    caption: "", textInImage: "", mood: "", tags: [], emojis: [], vector: nil,
                    state: "waiting", edited: false, model: "", provider: ""))
            }
        }
        let existing = Set(try store.allStickers().map(\.id))
        var gone = 0
        for id in existing where found[id] == nil {
            try store.deleteSticker(id: id)
            gone += 1
        }
        for (id, count) in sentCounts {
            try store.run("UPDATE stickers SET sent_count = ? WHERE id = ?", bind: [.int(Int64(count)), .text(id)])
        }
        return ScanResult(added: added, known: known, gone: gone, sentBumped: sentCounts.count)
    }

    func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    /// Reads the WebP header for the pixel size. Returns nil for exotic files.
    func webpSize(_ d: Data) -> (Int, Int)? {
        guard d.count >= 30, d.starts(with: [0x52, 0x49, 0x46, 0x46]) else { return nil }
        // VP8X
        if d.range(of: Data("VP8X".utf8), in: 12..<16) != nil, d.count >= 30 {
            func le(_ at: Int) -> Int { Int(d[at]) | Int(d[at+1]) << 8 | Int(d[at+2]) << 16 | Int(d[at+3]) << 24 }
            return ((le(24) & 0xFFFFFF) + 1, (le(27) & 0xFFFFFF) + 1)
        }
        // VP8 lossy
        if d.range(of: Data("VP8 ".utf8), in: 12..<16) != nil, d.count >= 30 {
            func le16(_ at: Int) -> Int { Int(d[at]) | Int(d[at+1]) << 8 }
            let w = le16(26) & 0x3FFF, h = le16(28) & 0x3FFF
            return (w, h)
        }
        // VP8L
        if d.range(of: Data("VP8L".utf8), in: 12..<16) != nil, d.count >= 25 {
            var b = UInt32(0)
            for k in 0..<4 { b |= UInt32(d[21 + k]) << (8 * k) }
            return (Int((b & 0x3FFF) + 1), Int(((b >> 14) & 0x3FFF) + 1))
        }
        return nil
    }
}
