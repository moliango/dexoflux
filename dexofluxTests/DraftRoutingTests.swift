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

    private func decodeDraft(key: String, data: String) throws -> DiscourseDraft {
        let escapedData = data
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let json = #"{"draft_key":"\#(key)","draft_sequence":1,"data":"\#(escapedData)"}"#
        return try JSONDecoder().decode(DiscourseDraft.self, from: Data(json.utf8))
    }
}
