import XCTest
@testable import Doer

@MainActor
final class SuggestedTopicRowModelTests: XCTestCase {
    func testRelatedTopicDecodesOwnCategoryAndTags() throws {
        let topic = try decodeSuggestedTopic([
            "id": 42,
            "title": "related title",
            "category_id": 11,
            "tags": ["纯水", "随手拍"],
            "reply_count": 9,
            "last_posted_at": "2026-08-14T04:00:00.000Z",
        ])

        XCTAssertEqual(topic.categoryId, 11)
        XCTAssertEqual(topic.tags, ["纯水", "随手拍"])
        XCTAssertEqual(topic.replyCount, 9)
    }

    func testNestedTopicSuppliesCategoryIdWhenTopLevelOmitsIt() throws {
        let topic = try decodeSuggestedTopic([
            "id": 7,
            "title": "nested related",
            "topic": [
                "category_id": 4,
                "category_name": "开发调优",
                "tags": ["VPS"],
            ],
        ])

        XCTAssertEqual(topic.categoryId, 4)
        XCTAssertEqual(topic.categoryName, "开发调优")
        XCTAssertEqual(topic.tags, ["VPS"])
    }

    func testListItemLooksUpCategoryAndKeepsTopicTags() throws {
        let topic = try decodeSuggestedTopic([
            "id": 42,
            "title": "related title",
            "category_id": 11,
            "tags": ["纯水"],
            "reply_count": 9,
            "last_posted_at": "2026-08-14T04:00:00.000Z",
        ])
        let context = SuggestedTopicListItem.context(
            from: topic,
            baseURL: "https://linux.do",
            showCategory: true,
            showTags: true
        )

        XCTAssertEqual(context.categoryName, "搞七捻三")
        XCTAssertEqual(context.categoryPresentation?.colorHex.lowercased(), "3ab54a")
        XCTAssertEqual(context.tags, ["纯水"])
        XCTAssertEqual(context.topic.id, 42)
        XCTAssertEqual(context.topic.replyCount, 9)
        XCTAssertEqual(context.topic.categoryId, 11)
    }

    func testListItemFallsBackToPayloadCategoryNameWithoutCatalog() throws {
        let topic = try decodeSuggestedTopic([
            "id": 8,
            "title": "other forum",
            "category_id": 99,
            "category_name": "本地分类",
            "tags": ["alpha"],
        ])
        let context = SuggestedTopicListItem.context(
            from: topic,
            baseURL: "https://example.com",
            showCategory: true,
            showTags: true
        )

        XCTAssertEqual(context.categoryName, "本地分类")
        XCTAssertNil(context.categoryPresentation)
        XCTAssertEqual(context.tags, ["alpha"])
    }

    private func decodeSuggestedTopic(_ json: [String: Any]) throws -> DiscourseTopicDetail.SuggestedTopic {
        let data = try JSONSerialization.data(withJSONObject: json)
        return try JSONDecoder().decode(DiscourseTopicDetail.SuggestedTopic.self, from: data)
    }
}
