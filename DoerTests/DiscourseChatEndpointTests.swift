import XCTest
@testable import Doer

final class DiscourseChatEndpointTests: XCTestCase {
    func testSendUsesLegacyCreateRoute() {
        XCTAssertEqual(DiscourseChatEndpoint.sendMessage(channelId: 42), "/chat/42")
    }

    func testModernSendAndReadStayOnChatAPI() {
        XCTAssertEqual(
            DiscourseChatEndpoint.sendMessageModern(channelId: 42),
            "/chat/api/channels/42/messages"
        )
        XCTAssertEqual(
            DiscourseChatEndpoint.messages(channelId: 42, pageSize: 50),
            "/chat/api/channels/42/messages?page_size=50"
        )
        XCTAssertEqual(DiscourseChatEndpoint.channels(), "/chat/api/me/channels")
    }
}
