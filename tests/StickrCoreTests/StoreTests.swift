import XCTest
@testable import StickrCore

final class StoreTests: XCTestCase {
    func testStickerRoundTrip() throws {
        let store = try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("s-\(UUID().uuidString).sqlite"))
        let s = Sticker(id: "abc", path: "/tmp/x.webp", animated: true, width: 512, height: 512,
            byteSize: 1000, source: "favorite", sentCount: 3, firstSeen: "now",
            caption: "a cat", textInImage: "hi", mood: "calm", tags: ["cat"], emojis: ["🐱"],
            vector: [0.1, 0.2, 0.3], state: "read", edited: true, model: "m", provider: "p")
        try store.save(s)
        let back = try store.sticker(id: "abc")!
        XCTAssertEqual(back.caption, "a cat")
        XCTAssertEqual(back.emojis, ["🐱"])
        XCTAssertEqual(back.vector!.count, 3)
        XCTAssertTrue(back.edited)
        XCTAssertEqual(back.state, "read")
    }

    func testPackAndInstallRoundTrip() throws {
        let store = try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("s-\(UUID().uuidString).sqlite"))
        var pack = Store.Pack(name: "Cats", rule: "every sticker with a cat", pins: ["a"], removed: ["b"], members: ["a", "c"])
        try store.savePack(pack)
        let back = try store.pack(name: "Cats")!
        XCTAssertEqual(back.pins, ["a"])
        XCTAssertEqual(back.removed, ["b"])
        pack.members = ["a", "d"]
        try store.savePack(pack)
        try store.recordInstall(pack: "Cats", members: pack.members, waPackID: "stickr-cats")
        let install = try store.lastInstall(pack: "Cats")!
        XCTAssertEqual(install.members, pack.members)
        XCTAssertEqual(install.waPackID, "stickr-cats")
    }

    func testCostAddsUp() throws {
        let store = try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("s-\(UUID().uuidString).sqlite"))
        try store.addCost(0.0001)
        try store.addCost(0.0002)
        let (_, spent) = try store.monthCost()
        XCTAssertEqual(spent, 0.0003, accuracy: 1e-9)
    }
}
