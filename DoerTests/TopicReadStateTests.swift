import XCTest
@testable import Doer

final class TopicReadStateTests: XCTestCase {
    func testTopicListDecodesDiscourseReadState() throws {
        let topic = try decodeTopic(
            extra: #", "unseen": false, "unread_posts": 0, "last_read_post_number": 4, "highest_post_number": 4"#
        )

        XCTAssertFalse(topic.unseen)
        XCTAssertEqual(topic.unreadPosts, 0)
        XCTAssertEqual(topic.lastReadPostNumber, 4)
        XCTAssertEqual(topic.highestPostNumber, 4)
        XCTAssertFalse(topic.isUnreadForDisplay)
    }

    func testMissingReadStateStaysVisuallyUnread() throws {
        let topic = try decodeTopic()

        XCTAssertTrue(topic.isUnreadForDisplay)
    }

    func testNewReplyMakesPreviouslyReadTopicUnread() throws {
        let topic = try decodeTopic(
            extra: #", "unseen": false, "unread_posts": 1, "last_read_post_number": 4, "highest_post_number": 5"#
        )

        XCTAssertTrue(topic.isUnreadForDisplay)
    }

    func testIncomingTopicDetectionContinuesPastFirstServerPageWithoutFixedLimit() {
        XCTAssertTrue(IncomingTopicPageTraversal.shouldContinue(
            reachedCurrentFirstTopic: false,
            moreTopicsURL: "/latest?page=1",
            pageAddedNewTopicIds: true
        ))
        XCTAssertFalse(IncomingTopicPageTraversal.shouldContinue(
            reachedCurrentFirstTopic: true,
            moreTopicsURL: "/latest?page=2",
            pageAddedNewTopicIds: true
        ))
        XCTAssertFalse(IncomingTopicPageTraversal.shouldContinue(
            reachedCurrentFirstTopic: false,
            moreTopicsURL: nil,
            pageAddedNewTopicIds: true
        ))
    }

    func testIncomingMergeKeepsPinnedTopicsAboveNewRows() throws {
        let pinned = try decodeTopic(id: 1, extra: #", "pinned": true"#)
        let older = try decodeTopic(id: 2)
        let incoming = try decodeTopic(id: 3)

        let merged = HomeTopicListOrdering.mergeIncoming(
            incoming: [incoming],
            existing: [pinned, older],
            pinnedIds: [1]
        )

        XCTAssertEqual(merged.topics.map(\.id), [1, 3, 2])
        XCTAssertEqual(merged.pinnedIds, [1])
    }

    func testWithPinnedFirstUsesRememberedPinnedIdsWhenFlagMissing() throws {
        let rememberedPinned = try decodeTopic(id: 9)
        let fresh = try decodeTopic(id: 10)

        let ordered = HomeTopicListOrdering.withPinnedFirst(
            [fresh, rememberedPinned],
            pinnedIds: [9]
        )

        XCTAssertEqual(ordered.map(\.id), [9, 10])
    }

    @MainActor
    func testHomeTopicLookupUsesIdIndex() throws {
        let viewModel = HomeViewModel(api: DiscourseAPI(baseURL: "https://linux.do"))
        viewModel.topics = [
            try decodeTopic(id: 1),
            try decodeTopic(id: 2),
        ]

        XCTAssertEqual(viewModel.topic(id: 2)?.id, 2)
        XCTAssertNil(viewModel.topic(id: 99))

        viewModel.topics = []
        XCTAssertNil(viewModel.topic(id: 2))
    }

    @MainActor
    func testHomeReadProgressUpdateClearsUnreadOnlyThroughHighestSeen() throws {
        let viewModel = HomeViewModel(api: DiscourseAPI(baseURL: "https://linux.do"))
        viewModel.topics = [try decodeTopic(
            extra: #", "unseen": true, "unread_posts": 5, "last_read_post_number": 1, "highest_post_number": 6"#
        )]

        XCTAssertTrue(viewModel.updateTopicReadProgress(topicId: 17, highestSeen: 4))
        XCTAssertFalse(viewModel.topics[0].unseen)
        XCTAssertEqual(viewModel.topics[0].lastReadPostNumber, 4)
        XCTAssertEqual(viewModel.topics[0].unreadPosts, 2)
        XCTAssertTrue(viewModel.topics[0].isUnreadForDisplay)

        XCTAssertTrue(viewModel.updateTopicReadProgress(topicId: 17, highestSeen: 6))
        XCTAssertEqual(viewModel.topics[0].unreadPosts, 0)
        XCTAssertFalse(viewModel.topics[0].isUnreadForDisplay)
    }

    @MainActor
    func testHomeUIScopeCoalescesBeforeFlush() {
        let viewModel = HomeViewModel(api: DiscourseAPI(baseURL: "https://linux.do"))
        XCTAssertEqual(viewModel.consumePendingUIScope(), .all)

        viewModel.notifyChanged(.list)
        viewModel.notifyChanged(.incoming)
        let coalesced = viewModel.consumePendingUIScope()
        XCTAssertEqual(coalesced, [.list, .incoming])
        XCTAssertEqual(viewModel.consumePendingUIScope(), .all)
    }

    @MainActor
    func testHomeTopicListLayoutFactoryMatchesTheme() {
        XCTAssertEqual(HomeTopicListLayoutFactory.make(style: .systemDefault).kind, .standard)
        XCTAssertEqual(HomeTopicListLayoutFactory.make(style: .eyeCare).kind, .standard)
        XCTAssertEqual(HomeTopicListLayoutFactory.make(style: .xiaohongshu).kind, .xiaohongshu)
        XCTAssertEqual(HomeTopicListLayoutFactory.make(style: .weChat).kind, .weChat)
        XCTAssertEqual(HomeTopicListLayoutFactory.make(style: .telegram).kind, .telegram)
    }

    @MainActor
    func testChatTopicDetailSubclassesFreezeThemeHooks() {
        let api = DiscourseAPI(baseURL: "https://linux.do")
        let wechat = WeChatTopicDetailViewController(api: api, topicId: 1)
        let telegram = TelegramTopicDetailViewController(api: api, topicId: 1)
        XCTAssertTrue(wechat is ChatTopicDetailViewController)
        XCTAssertTrue(telegram is ChatTopicDetailViewController)
        XCTAssertEqual(wechat.chatThemeStyle(), .weChat)
        XCTAssertEqual(telegram.chatThemeStyle(), .telegram)
        XCTAssertEqual(wechat.incomingLinkColor(defaultColor: .red), .red)
        XCTAssertEqual(telegram.incomingLinkColor(defaultColor: .red), ChatTopicStyle.telegram.accentColor)
        XCTAssertEqual(wechat.estimatedChatRowHeight(), 140)
        XCTAssertEqual(telegram.estimatedChatRowHeight(), 168)
        XCTAssertEqual(wechat.jumpScrollPosition(), .middle)
        XCTAssertEqual(telegram.jumpScrollPosition(), .bottom)
        XCTAssertTrue(wechat.scrollsToBottomWhenOpeningLatest())
        XCTAssertTrue(telegram.scrollsToBottomWhenOpeningLatest())
        XCTAssertFalse(wechat.animatesCanvasColorChange())
        XCTAssertTrue(telegram.animatesCanvasColorChange())
        XCTAssertFalse(WeChatChatPostCell().prefersContextMenuForLongPress())
        XCTAssertTrue(TelegramChatPostCell().prefersContextMenuForLongPress())
        XCTAssertEqual(WeChatChatPostCell().bubbleLongPressDuration(), 0.5)
        XCTAssertEqual(TelegramChatPostCell().bubbleLongPressDuration(), 0.35)
        XCTAssertEqual(WeChatChatPostCell().dateChipCornerRadius(), 4)
        XCTAssertEqual(TelegramChatPostCell().dateChipCornerRadius(), 11)
    }

    func testUnopenedTopicOpensAtTopInsteadOfFirstPaintTail() {
        XCTAssertEqual(
            TopicDetailOpenAnchor.resolve(
                initialPostId: nil,
                initialFloor: nil,
                lastRead: 0,
                totalFloors: 80,
                pinLatestWhenFullyRead: true
            ),
            .top
        )
        XCTAssertEqual(
            TopicDetailOpenAnchor.resolve(
                initialPostId: nil,
                initialFloor: nil,
                lastRead: 12,
                totalFloors: 80,
                pinLatestWhenFullyRead: true
            ),
            .floor(13)
        )
        XCTAssertEqual(
            TopicDetailOpenAnchor.resolve(
                initialPostId: nil,
                initialFloor: nil,
                lastRead: 80,
                totalFloors: 80,
                pinLatestWhenFullyRead: true
            ),
            .floor(80)
        )
        XCTAssertEqual(
            TopicDetailOpenAnchor.resolve(
                initialPostId: nil,
                initialFloor: nil,
                lastRead: 80,
                totalFloors: 80,
                pinLatestWhenFullyRead: false
            ),
            .top
        )
    }

    func testChatDateSeparatorHidesOnSameCalendarDay() {
        let morning = "2026-01-15T02:00:00.000Z"
        let evening = "2026-01-15T18:00:00.000Z"
        let nextDay = "2026-01-16T02:00:00.000Z"
        XCTAssertNotNil(ChatDateSeparator.text(forCreatedAt: morning, previousCreatedAt: nil))
        XCTAssertNil(ChatDateSeparator.text(forCreatedAt: evening, previousCreatedAt: morning))
        XCTAssertNotNil(ChatDateSeparator.text(forCreatedAt: nextDay, previousCreatedAt: evening))
    }

    private func decodeTopic(id: Int = 17, extra: String = "") throws -> DiscourseTopicList.Topic {
        let json = """
        {
          "topic_list": {
            "topics": [{
              "id": \(id),
              "fancy_title": "Topic",
              "title": "Topic",
              "posts_count": 6,
              "reply_count": 5,
              "views": 20,
              "created_at": "2026-07-11T00:00:00.000Z"\(extra)
            }]
          }
        }
        """
        return try JSONDecoder().decode(DiscourseTopicList.self, from: Data(json.utf8)).topicList.topics[0]
    }
}
