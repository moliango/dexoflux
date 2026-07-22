import XCTest
@testable import dexoflux

final class BackgroundTopicUpdateStoreTests: XCTestCase {
    func testFirstBackgroundSnapshotEstablishesBaselineWithoutPendingTopics() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let pending = store.processBackgroundSnapshot(
            [fingerprint(id: 3), fingerprint(id: 2), fingerprint(id: 1)],
            baseURL: "https://linux.do/"
        )

        XCTAssertEqual(pending, [])
        XCTAssertEqual(store.pendingTopicIDs(for: "https://linux.do"), [])
    }

    func testNewTopicBeforeForegroundReferenceBecomesPending() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.replaceForegroundBaseline(
            [fingerprint(id: 3), fingerprint(id: 2), fingerprint(id: 1)],
            baseURL: "https://linux.do"
        )

        let pending = store.processBackgroundSnapshot(
            [fingerprint(id: 4), fingerprint(id: 3), fingerprint(id: 2)],
            baseURL: "https://linux.do"
        )

        XCTAssertEqual(pending, [4])
    }

    func testExistingTopicWithChangedReplyStateBecomesPending() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.replaceForegroundBaseline(
            [fingerprint(id: 3, postsCount: 2, replyCount: 1)],
            baseURL: "https://linux.do"
        )

        let pending = store.processBackgroundSnapshot(
            [fingerprint(id: 3, postsCount: 3, replyCount: 2)],
            baseURL: "https://linux.do"
        )

        XCTAssertEqual(pending, [3])
    }

    func testRepeatedBackgroundSnapshotDoesNotDuplicatePendingTopics() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.replaceForegroundBaseline([fingerprint(id: 3)], baseURL: "https://linux.do")
        let latest = [fingerprint(id: 4), fingerprint(id: 3, postsCount: 2)]

        XCTAssertEqual(store.processBackgroundSnapshot(latest, baseURL: "https://linux.do"), [4, 3])
        XCTAssertEqual(store.processBackgroundSnapshot(latest, baseURL: "https://linux.do"), [4, 3])
    }

    func testPendingTopicsAreLimitedToThirtyInServerOrder() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.replaceForegroundBaseline([fingerprint(id: 1)], baseURL: "https://linux.do")
        let latest = (2...40).reversed().map { fingerprint(id: $0) } + [fingerprint(id: 1)]

        let pending = store.processBackgroundSnapshot(latest, baseURL: "https://linux.do")

        XCTAssertEqual(pending.count, 30)
        XCTAssertEqual(pending, Array((11...40).reversed()))
    }

    func testStateIsIsolatedByNormalizedBaseURL() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.replaceForegroundBaseline([fingerprint(id: 3)], baseURL: "https://linux.do/")
        store.replaceForegroundBaseline([fingerprint(id: 8)], baseURL: "https://example.com")

        _ = store.processBackgroundSnapshot(
            [fingerprint(id: 4), fingerprint(id: 3)],
            baseURL: "https://linux.do"
        )

        XCTAssertEqual(store.pendingTopicIDs(for: "https://linux.do/"), [4])
        XCTAssertEqual(store.pendingTopicIDs(for: "https://example.com/"), [])
    }

    func testPinnedTopicIsNotUsedAsForegroundReference() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.replaceForegroundBaseline(
            [fingerprint(id: 99, pinned: true), fingerprint(id: 10), fingerprint(id: 9)],
            baseURL: "https://linux.do"
        )

        let pending = store.processBackgroundSnapshot(
            [fingerprint(id: 99, pinned: true), fingerprint(id: 11), fingerprint(id: 10)],
            baseURL: "https://linux.do"
        )

        XCTAssertEqual(pending, [11])
    }

    func testEstablishingForegroundBaselineDoesNotDiscardExistingPendingTopics() throws {
        let (store, defaults, suiteName) = try makeStore()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        store.replaceForegroundBaseline([fingerprint(id: 3)], baseURL: "https://linux.do")
        _ = store.processBackgroundSnapshot(
            [fingerprint(id: 4), fingerprint(id: 3)],
            baseURL: "https://linux.do"
        )

        store.establishForegroundBaselineIfNeeded(
            [fingerprint(id: 4), fingerprint(id: 3)],
            baseURL: "https://linux.do"
        )

        XCTAssertEqual(store.pendingTopicIDs(for: "https://linux.do"), [4])
    }

    private func makeStore() throws -> (BackgroundTopicUpdateStore, UserDefaults, String) {
        let suiteName = "BackgroundTopicUpdateStoreTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        return (BackgroundTopicUpdateStore(defaults: defaults), defaults, suiteName)
    }

    private func fingerprint(
        id: Int,
        postsCount: Int = 1,
        replyCount: Int = 0,
        lastPostedAt: String? = "2026-07-20T00:00:00.000Z",
        pinned: Bool = false
    ) -> BackgroundTopicFingerprint {
        BackgroundTopicFingerprint(
            id: id,
            postsCount: postsCount,
            replyCount: replyCount,
            lastPostedAt: lastPostedAt,
            pinned: pinned
        )
    }
}
