import XCTest
@testable import StickrCore

final class SearchTests: XCTestCase {
    func sticker(_ id: String, vector: [Float], sent: Int = 0) -> Sticker {
        Sticker(id: id, path: "/tmp/\(id).webp", animated: false, width: 512, height: 512,
            byteSize: 100, source: "favorite", sentCount: sent, firstSeen: "now",
            caption: "sticker \(id)", textInImage: "", mood: "", tags: [], emojis: [],
            vector: vector, state: "read", edited: false, model: "", provider: "")
    }

    func testZScoreCutKeepsOnlyStandouts() {
        // One sticker is clearly on topic, the rest are noise.
        let onTopic = sticker("on", vector: [1, 0, 0])
        let far = (0..<20).map { sticker("far\($0)", vector: [Float(0), Float(1), Float(0)]) }
        let engine = SearchEngine(stickers: [onTopic] + far)
        let hits = engine.zCut(query: [1, 0, 0], z: 2.0, cap: 15)
        XCTAssertEqual(hits.first?.id, "on")
        XCTAssertEqual(hits.count, 1)
    }

    func testCutIsEmptyWhenEverythingIsEquallyClose() {
        let all = (0..<10).map { sticker("s\($0)", vector: [1, 0, 0]) }
        let engine = SearchEngine(stickers: all)
        XCTAssertEqual(engine.zCut(query: [1, 0, 0], z: 2.0, cap: 15).count, 0)
    }

    func testCosineSameAndOrthogonal() {
        XCTAssertEqual(SearchEngine.cosine([1, 2, 3], [1, 2, 3]), 1.0, accuracy: 0.0001)
        XCTAssertEqual(SearchEngine.cosine([1, 0], [0, 1]), 0.0, accuracy: 0.0001)
    }
}

final class PackEngineTests: XCTestCase {
    func sticker(_ id: String, sent: Int = 0, animated: Bool = false) -> Sticker {
        Sticker(id: id, path: "/tmp/\(id).webp", animated: animated, width: 512, height: 512,
            byteSize: 100, source: "favorite", sentCount: sent, firstSeen: "now",
            caption: id, textInImage: "", mood: "", tags: [], emojis: ["🙂"],
            vector: [Float(1), Float(0), Float(0)], state: "read", edited: false, model: "", provider: "")
    }

    func testMembersOrderAndLimit() {
        let all = (0..<40).map { sticker("s\($0)", sent: 40 - $0) }
        let pack = Store.Pack(name: "P", rule: "r", pins: ["s10", "s5"], removed: ["s20"], members: [])
        let members = PackEngine.members(pack: pack, stickers: all, ruleResults: all)
        XCTAssertEqual(members.count, PackEngine.maxMembers)
        XCTAssertEqual(Array(members.prefix(2).map(\.id)), ["s10", "s5"], "pinned stickers come first in pinned order")
        XCTAssertFalse(members.contains { $0.id == "s20" }, "a removed sticker stays out")
    }

    func testMixedPackSplitsByAnimation() {
        let members = [sticker("a"), sticker("b"), sticker("c", animated: true)]
        let (still, animated) = PackEngine.splitByAnimation(members)
        XCTAssertEqual(still.count, 2)
        XCTAssertEqual(animated.count, 1)
    }

    func testLimitProblems() {
        var s = sticker("big")
        s.byteSize = 200_000
        XCTAssertNotNil(PackExport.limitProblems(s))
        s.animated = true; s.byteSize = 400_000
        XCTAssertNil(PackExport.limitProblems(s), "animated at 400 KB and 512 x 512 is fine")
        s.width = 300
        XCTAssertNotNil(PackExport.limitProblems(s))
    }
}
