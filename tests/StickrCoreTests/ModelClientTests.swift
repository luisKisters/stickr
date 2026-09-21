import XCTest
@testable import StickrCore

final class ModelClientTests: XCTestCase {
    override func setUp() {
        super.setUp()
        resetMock()
    }

    func client() -> ModelClient {
        ModelClient(key: "test-key", session: mockSession())
    }

    func testRetryOn429ThenSuccess() async throws {
        MockURLProtocol.responses = [
            (429, Data("{\"error\":{\"message\":\"slow down\"}}".utf8)),
            (500, Data("{}".utf8)),
            (200, chatResponseJSON(caption: "worked after retries")),
        ]
        let r = try await client().caption(bytes: tinyWebP())
        XCTAssertEqual(r.caption, "worked after retries")
        XCTAssertEqual(r.provider, "fake-provider")
        XCTAssertEqual(r.cost, 0.0001, accuracy: 1e-9)
    }

    func testNoRetryOn401() async {
        MockURLProtocol.responses = [(401, Data("{\"error\":{\"message\":\"bad key\"}}".utf8))]
        do {
            _ = try await client().caption(bytes: tinyWebP())
            XCTFail("should throw")
        } catch let e as ModelClient.HTTPError {
            XCTAssertEqual(e.status, 401)
        } catch { XCTFail("wrong error \(error)") }
        XCTAssertEqual(MockURLProtocol.seenRequests.count, 1, "no retry on 401")
    }

    func testGivesUpAfterFourTries() async {
        MockURLProtocol.responses = Array(repeating: (429, Data("{}".utf8)), count: 10)
        do {
            _ = try await client().caption(bytes: tinyWebP())
            XCTFail("should throw")
        } catch { }
        XCTAssertEqual(MockURLProtocol.seenRequests.count, 4)
    }

    func testEmbedding() async throws {
        MockURLProtocol.responses = [(200, embeddingsJSON(count: 2))]
        let vectors = try await client().embed(texts: ["one", "two"])
        XCTAssertEqual(vectors.count, 2)
        XCTAssertEqual(vectors[0].count, 3)
    }
}

final class IndexerTests: XCTestCase {
    func makeLibrary(_ n: Int) throws -> (Store, URL) {
        let store = try Store(url: FileManager.default.temporaryDirectory.appendingPathComponent("ix-\(UUID().uuidString).sqlite"))
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ixd-\(UUID().uuidString)")
        let webp = tinyWebP()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for i in 0..<n {
            let p = dir.appendingPathComponent("s\(i).webp")
            try webp.write(to: p)
            try store.save(Sticker(id: "id\(i)", path: p.path, animated: false, width: 1, height: 1,
                byteSize: webp.count, source: "favorite", sentCount: 0, firstSeen: "now",
                caption: "", textInImage: "", mood: "", tags: [], emojis: [], vector: nil,
                state: "waiting", edited: false, model: "", provider: ""))
        }
        return (store, dir)
    }

    func testReadFillsCaptionsAndVectors() async throws {
        let (store, _) = try makeLibrary(3)
        let fake = FakeClient()
        let stats = try await Indexer(store: store, client: fake).readAll() { _, _ in }
        XCTAssertEqual(stats.read, 3)
        XCTAssertEqual(stats.failed, 0)
        let all = try store.allStickers()
        XCTAssertTrue(all.allSatisfy { $0.state == "read" && $0.vector != nil })
        let (_, spent) = try store.monthCost()
        XCTAssertEqual(spent, 0.0003, accuracy: 1e-9, "each caption request adds its reported cost")
    }

    func testFailedStickerDoesNotStopTheRun() async throws {
        let (store, _) = try makeLibrary(3)
        let fake = FakeClient()
        fake.failBefore = 2
        let stats = try await Indexer(store: store, client: fake).readAll() { _, _ in }
        XCTAssertEqual(stats.read, 1)
        XCTAssertEqual(stats.failed, 2)
        XCTAssertEqual(try store.stickers(state: "failed").count, 2)
        // A later run with retryFailed picks the failed ones up again.
        fake.failBefore = 0
        let second = try await Indexer(store: store, client: fake).readAll(retryFailed: true) { _, _ in }
        XCTAssertEqual(second.read, 2)
        XCTAssertEqual(try store.stickers(state: "failed").count, 0)
    }

    func testEditedStickerIsNeverOverwritten() async throws {
        let (store, _) = try makeLibrary(2)
        var edited = try store.sticker(id: "id0")!
        edited.caption = "my own caption"; edited.edited = true; edited.state = "read"
        try store.save(edited)
        let fake = FakeClient()
        let stats = try await Indexer(store: store, client: fake).readAll() { _, _ in }
        XCTAssertEqual(stats.read, 1, "only the untouched sticker is read")
        XCTAssertEqual(try store.sticker(id: "id0")!.caption, "my own caption")
    }

    func testRunContinuesWhereItStopped() async throws {
        let (store, _) = try makeLibrary(4)
        let fake = FakeClient()
        let first = try await Indexer(store: store, client: fake).readAll(limit: 2) { _, _ in }
        XCTAssertEqual(first.read, 2)
        let fake2 = FakeClient()
        let second = try await Indexer(store: store, client: fake2).readAll() { _, _ in }
        XCTAssertEqual(second.read, 2, "the next run reads only what is left")
        XCTAssertEqual(try store.allStickers().filter { $0.vector != nil }.count, 4)
    }
}
