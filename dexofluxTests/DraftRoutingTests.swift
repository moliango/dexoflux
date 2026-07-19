import XCTest
@testable import dexoflux

@MainActor
final class DraftRoutingTests: XCTestCase {
    func testNewTopicDraftRoutesToTopicComposer() async throws {
        let draft = try decodeDraft(key: "new_topic", data: #"{"title":"Hello","reply":"Body"}"#)

        XCTAssertEqual(draft.destination, .newTopic)
    }

    func testTopicPostDraftRoutesToReplyTarget() async throws {
        let draft = try decodeDraft(key: "topic_42_post_3", data: #"{"reply":"Reply"}"#)

        XCTAssertEqual(draft.destination, .topicReply(topicId: 42, postNumber: 3))
    }

    func testPrivateMessageDraftRoutesToFirstRecipient() async throws {
        let draft = try decodeDraft(
            key: "new_private_message",
            data: #"{"title":"Hi","reply":"Body","target_recipients":"sam,alex"}"#
        )

        XCTAssertEqual(draft.destination, .privateMessage(recipient: "sam"))
    }

    func testUnknownDraftIsUnsupported() async throws {
        let draft = try decodeDraft(key: "mystery", data: #"{"reply":"Body"}"#)

        XCTAssertEqual(draft.destination, .unsupported)
    }

    func testNewTopicSubmissionTrimsContentAndDeduplicatesTags() {
        let submission = NewTopicSubmission.make(
            title: "  A useful title  ",
            raw: "\nBody content\n",
            categoryId: 42,
            tags: ["swift", " ios ", "swift", ""]
        )

        XCTAssertEqual(
            submission,
            NewTopicSubmission(
                title: "A useful title",
                raw: "Body content",
                categoryId: 42,
                tags: ["swift", "ios"]
            )
        )
    }

    func testNewTopicSubmissionRejectsBlankTitleOrBody() {
        XCTAssertNil(NewTopicSubmission.make(title: " ", raw: "Body", categoryId: nil, tags: []))
        XCTAssertNil(NewTopicSubmission.make(title: "Title", raw: "\n", categoryId: nil, tags: []))
    }

    private func decodeDraft(key: String, data: String) throws -> DiscourseDraft {
        let escapedData = data
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let json = #"{"draft_key":"\#(key)","draft_sequence":1,"data":"\#(escapedData)"}"#
        return try JSONDecoder().decode(DiscourseDraft.self, from: Data(json.utf8))
    }
}
