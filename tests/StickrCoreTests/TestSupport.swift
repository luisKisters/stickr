import Foundation
import SQLite3
@testable import StickrCore

/// A 1 x 1 lossless WebP built from bytes, so no binary fixture is needed.
func tinyWebP() -> Data {
    var out = Data("RIFF".utf8)
    out += withUnsafeBytes(of: UInt32(21).littleEndian) { Data($0) }
    out += Data("WEBP".utf8)
    out += Data("VP8L".utf8)
    out += withUnsafeBytes(of: UInt32(5).littleEndian) { Data($0) }
    out += Data([0x2F, 0x00, 0x00, 0x00, 0x00])
    return out
}

/// Builds a fake WhatsApp container with empty-schema databases and invented rows.
func makeFakeContainer() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent("stickr-test-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: root.appendingPathComponent("stickers/no-sticker-pack"), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: root.appendingPathComponent("Media/chat/b/7"), withIntermediateDirectories: true)

    let stickerDB = root.appendingPathComponent("Sticker.sqlite")
    try createDB(at: stickerDB, schema: """
      CREATE TABLE ZWACDSTICKER (Z_PK INTEGER PRIMARY KEY, Z_ENT INTEGER, ZFILELENGTH INTEGER, ZHEIGHT INTEGER,
        ZWIDTH INTEGER, ZSTICKERPACK INTEGER, ZACCESSIBILITYTEXT VARCHAR, ZRELATIVEIMAGEPATH VARCHAR, ZEMOJIS VARCHAR, ZMEDIAKEY BLOB);
      """)
    let webp = tinyWebP()
    let p1 = "stickers/no-sticker-pack/aaa.webp"
    try webp.write(to: root.appendingPathComponent(p1))
    // A second row that points at the same bytes: duplicates collapse to one sticker.
    let p2 = "stickers/no-sticker-pack/bbb.webp"
    try webp.write(to: root.appendingPathComponent(p2))
    try execDB(at: stickerDB, sql: """
      INSERT INTO ZWACDSTICKER (Z_PK, Z_ENT, ZFILELENGTH, ZHEIGHT, ZWIDTH, ZSTICKERPACK, ZRELATIVEIMAGEPATH)
        VALUES (1, 4, \(webp.count), 1, 1, NULL, 'no-sticker-pack/aaa.webp');
      INSERT INTO ZWACDSTICKER (Z_PK, Z_ENT, ZFILELENGTH, ZHEIGHT, ZWIDTH, ZSTICKERPACK, ZRELATIVEIMAGEPATH)
        VALUES (2, 4, \(webp.count), 1, 1, NULL, 'no-sticker-pack/bbb.webp');
      """)

    let chatDB = root.appendingPathComponent("ChatStorage.sqlite")
    try createDB(at: chatDB, schema: """
      CREATE TABLE ZWAMESSAGE (Z_PK INTEGER PRIMARY KEY, ZMESSAGETYPE INTEGER, ZISFROMME INTEGER, ZCHATSESSION INTEGER);
      CREATE TABLE ZWAMEDIAITEM (Z_PK INTEGER PRIMARY KEY, ZMESSAGE INTEGER, ZMEDIALOCALPATH VARCHAR, ZMEDIAKEY BLOB);
      CREATE TABLE ZWACHATSESSION (Z_PK INTEGER PRIMARY KEY, ZCONTACTJID VARCHAR);
      INSERT INTO ZWACHATSESSION (Z_PK, ZCONTACTJID) VALUES (1, 'me@whatsapp');
      INSERT INTO ZWAMESSAGE (Z_PK, ZMESSAGETYPE, ZISFROMME, ZCHATSESSION) VALUES (1, 15, 1, 1);
      INSERT INTO ZWAMESSAGE (Z_PK, ZMESSAGETYPE, ZISFROMME, ZCHATSESSION) VALUES (2, 15, 0, 1);
      INSERT INTO ZWAMEDIAITEM (Z_PK, ZMESSAGE, ZMEDIALOCALPATH) VALUES (1, 1, 'chat/b/7/sent.webp');
      INSERT INTO ZWAMEDIAITEM (Z_PK, ZMESSAGE, ZMEDIALOCALPATH) VALUES (2, 2, 'chat/b/7/gone.webp');
      """)
    // Only the sent sticker has a file on disk. The received one is gone, like on the real Mac.
    var sentWebP = webp
    sentWebP[sentWebP.count - 1] = 0x01
    try sentWebP.write(to: root.appendingPathComponent("Media/chat/b/7/sent.webp"))
    return root
}

func createDB(at url: URL, schema: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let db else {
        throw Store.StoreError("cannot create \(url.path)")
    }
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK else {
        throw Store.StoreError("fixture schema failed: \(String(cString: sqlite3_errmsg(db)))")
    }
}

func execDB(at url: URL, sql: String) throws {
    var db: OpaquePointer?
    guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK, let db else {
        throw Store.StoreError("cannot open \(url.path)")
    }
    defer { sqlite3_close(db) }
    guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
        throw Store.StoreError("fixture insert failed: \(String(cString: sqlite3_errmsg(db)))")
    }
}

/// A fake model client for Indexer tests. Counts calls, can fail on demand.
final class FakeClient: ModelReading, @unchecked Sendable {
    let captionModelName = "fake/caption"
    var captionCalls = 0
    var embedCalls = 0
    var failBefore = 0          // the first N caption calls fail with 429
    var failWith401 = false
    let q = DispatchQueue(label: "fake.client")
    func caption(bytes: Data) async throws -> CaptionResult {
        let n = q.sync { captionCalls += 1; return captionCalls }
        if failWith401 { throw ModelClient.HTTPError(status: 401, message: "no") }
        if n <= failBefore { throw ModelClient.HTTPError(status: 429, message: "busy") }
        return CaptionResult(caption: "a test sticker", textInImage: "", mood: "calm",
                             tags: ["test"], emojis: ["🙂"], provider: "fake", seconds: 0.1, cost: 0.0001)
    }
    func embed(texts: [String]) async throws -> [[Float]] {
        q.sync { embedCalls += 1 }
        return texts.map { _ in [Float(1), Float(0), Float(0)] }
    }
    func testConnection(bytes: Data) async throws -> CaptionResult {
        try await caption(bytes: bytes)
    }
}
