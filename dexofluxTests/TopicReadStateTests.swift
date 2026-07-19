import XCTest
@testable import dexoflux

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

    private func decodeTopic(extra: String = "") throws -> DiscourseTopicList.Topic {
        let json = """
        {
          "topic_list": {
            "topics": [{
              "id": 17,
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
