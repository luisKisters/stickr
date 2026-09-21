import XCTest
@testable import StickrCore

final class LibraryTests: XCTestCase {
    func testDuplicateFilesCollapseToOneSticker() throws {
        let container = try makeFakeContainer()
        let store = try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("stickr-test-\(UUID().uuidString).sqlite"))
        let scanner = try LibraryScanner(container: container, stickrDir: FileManager.default.temporaryDirectory.appendingPathComponent("stickr-data-\(UUID().uuidString)"))
        let result = try scanner.scan(store: store)
        XCTAssertEqual(result.added, 2, "one favorite and one sent sticker")
        XCTAssertEqual(try store.allStickers().count, 2, "the duplicate file collapses to one row")
        XCTAssertEqual(result.sentBumped, 1)
        let sent = try store.allStickers().first { $0.source == "sent" }
        XCTAssertEqual(sent?.sentCount, 1)
        // A second run right after reports zero new.
        let second = try scanner.scan(store: store)
        XCTAssertEqual(second.added, 0)
        XCTAssertEqual(second.known, 2)
    }

    func testMissingContainerGivesPlainMessage() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-container-\(UUID().uuidString)")
        XCTAssertThrowsError(try LibraryScanner(container: missing)) { error in
            let message = (error as? Store.StoreError)?.message ?? ""
            XCTAssertTrue(message.contains("Stickr cannot see your stickers"), message)
            XCTAssertFalse(message.contains("0x"), message)
        }
    }

    func testHalfWrittenDatabaseCopyDoesNotCrashScan() throws {
        let container = try makeFakeContainer()
        // A locked or half-written database copy must not crash the scan: a truncated Sticker.sqlite yields a plain error.
        let bad = container.appendingPathComponent("Sticker.sqlite")
        let original = try Data(contentsOf: bad)
        try original.prefix(original.count / 2).write(to: bad)
        let store = try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("stickr-test-\(UUID().uuidString).sqlite"))
        let scanner = try LibraryScanner(container: container, stickrDir: FileManager.default.temporaryDirectory.appendingPathComponent("stickr-data-\(UUID().uuidString)"))
        XCTAssertThrowsError(try scanner.scan(store: store)) { error in
            let message = (error as? Store.StoreError)?.message ?? ""
            XCTAssertTrue(message.contains("WhatsApp sticker library"), message)
        }
    }

    func testScanNeverWritesToWhatsAppFiles() throws {
        let container = try makeFakeContainer()
        let db = container.appendingPathComponent("Sticker.sqlite")
        let before = try FileManager.default.attributesOfItem(atPath: db.path)[.modificationDate] as! Date
        sleep(1)
        let store = try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("stickr-test-\(UUID().uuidString).sqlite"))
        let scanner = try LibraryScanner(container: container, stickrDir: FileManager.default.temporaryDirectory.appendingPathComponent("stickr-data-\(UUID().uuidString)"))
        _ = try scanner.scan(store: store)
        let after = try FileManager.default.attributesOfItem(atPath: db.path)[.modificationDate] as! Date
        XCTAssertEqual(before, after)
    }
}
