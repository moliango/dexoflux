import XCTest
@testable import Doer

final class StickerMarketStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: StickerMarketStore!

    override func setUp() {
        super.setUp()
        suiteName = "StickerMarketStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        defaults.removePersistentDomain(forName: suiteName)
        store = StickerMarketStore(defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        store = nil
        defaults = nil
        super.tearDown()
    }

    func testStickerMarkdownFormat() {
        let item = StickerItem(
            id: "1",
            name: "ok",
            url: "https://example.com/a.png",
            width: 100,
            height: 80,
            groupId: "g1"
        )
        XCTAssertEqual(item.markdown, "![ok|100x80,30%](https://example.com/a.png)")
    }

    func testSubscribeAndRecent() {
        let id = "g1"
        XCTAssertFalse(store.isSubscribed(id))
        store.subscribe(id)
        XCTAssertTrue(store.isSubscribed(id))
        store.unsubscribe(id)
        XCTAssertFalse(store.isSubscribed(id))

        let item = StickerItem(
            id: "s1",
            name: "wave",
            url: "https://example.com/w.png",
            width: 64,
            height: 64,
            groupId: id
        )
        store.addRecent(item)
        XCTAssertEqual(store.recentStickers().first?.id, item.id)
    }

    func testBaseURLReset() {
        XCTAssertEqual(store.baseURL, StickerMarketStore.defaultBaseURL)
        store.setBaseURL("https://example.invalid/market")
        XCTAssertEqual(store.baseURL, "https://example.invalid/market")
        store.resetBaseURL()
        XCTAssertEqual(store.baseURL, StickerMarketStore.defaultBaseURL)
    }
}
