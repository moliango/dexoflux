import XCTest
@testable import Doer

final class DailyForumUXTests: XCTestCase {
    func testConnectivityRecoverySkipsReloadWhenListIsHealthy() {
        XCTAssertFalse(HomeConnectivityRecoveryPolicy.shouldReloadTopicList(topicsEmpty: false, hasError: false))
        XCTAssertTrue(HomeConnectivityRecoveryPolicy.shouldReloadTopicList(topicsEmpty: true, hasError: false))
        XCTAssertTrue(HomeConnectivityRecoveryPolicy.shouldReloadTopicList(topicsEmpty: false, hasError: true))
    }

    func testQuoteMarkdownUsesDiscourseBBCode() {
        let markdown = DiscourseQuoteMarkdown.make(
            username: "alice",
            postNumber: 7,
            topicId: 42,
            excerpt: "  hello world  "
        )
        XCTAssertEqual(
            markdown,
            "[quote=\"alice, post:7, topic:42\"]\nhello world\n[/quote]\n\n"
        )
        XCTAssertEqual(
            DiscourseQuoteMarkdown.make(username: "alice", postNumber: 1, topicId: 1, excerpt: "   "),
            ""
        )
        XCTAssertEqual(
            DiscourseQuoteMarkdown.make(
                username: "al\"ice",
                postNumber: 1,
                topicId: 2,
                excerpt: "hi"
            ),
            "[quote=\"al'ice, post:1, topic:2\"]\nhi\n[/quote]\n\n"
        )
    }

    func testTrustBarNumsStripGroupingSeparators() {
        XCTAssertEqual(
            TrustLevelWidgetRefresher.parseBarCurrentAndTarget("5,000 / 20,000")?.current,
            5000
        )
        XCTAssertEqual(
            TrustLevelWidgetRefresher.parseBarCurrentAndTarget("5,000 / 20,000")?.target,
            20000
        )
        XCTAssertEqual(
            TrustLevelWidgetRefresher.parseBarCurrentAndTarget("5000 / 20000")?.current,
            5000
        )
        XCTAssertNil(TrustLevelWidgetRefresher.parseBarCurrentAndTarget("已达标"))
    }

    func testAPNsTokenEncodesAsLowercaseHex() {
        XCTAssertEqual(APNsPushRegistration.hexString(from: Data([0x0A, 0xFF, 0x00])), "0aff00")
    }

    func testTrustSnapshotRoundTripAndHeadlinePrefersPostsRead() {
        let defaults = UserDefaults(suiteName: "test.trust.widget.\(UUID().uuidString)")!
        let snapshot = TrustLevelWidgetSnapshot(
            title: "信任级别 3",
            badgeText: "未达标",
            subtitle: "@tester",
            items: [
                TrustLevelWidgetItem(label: "访问天数", current: 92, target: 100, isMet: false, isReverse: false),
                TrustLevelWidgetItem(label: "已读帖子", current: 5000, target: 20000, isMet: false, isReverse: false),
            ],
            updatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            trustLevel: 2
        )
        TrustLevelWidgetSnapshotStore.save(snapshot, defaults: defaults)
        let loaded = TrustLevelWidgetSnapshotStore.load(defaults: defaults)
        XCTAssertEqual(loaded?.title, snapshot.title)
        XCTAssertEqual(loaded?.badgeText, snapshot.badgeText)
        XCTAssertEqual(loaded?.items, snapshot.items)
        XCTAssertEqual(loaded?.trustLevel, 2)
        XCTAssertEqual(loaded?.headlineItem?.label, "已读帖子")
        XCTAssertEqual(loaded?.headlineItem?.remaining, 15000)
    }

    func testTrustDeepLinkRoutesToTrustPage() {
        XCTAssertEqual(
            DoerDeepLinkRouter.destination(from: URL(string: "doer://trust")!),
            .trustLevel
        )
        XCTAssertEqual(
            DoerDeepLinkRouter.destination(from: URL(string: "doer://trust-level")!),
            .trustLevel
        )
    }
}
