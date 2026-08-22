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

    func testPublicChannelDecodesCategoryLogoObject() throws {
        let json = """
        {
          "id": 7,
          "title": "公告",
          "chatable_type": "Category",
          "chatable": {
            "name": "公告",
            "color": "E45735",
            "uploaded_logo": { "url": "/uploads/default/original/1X/logo.png" }
          }
        }
        """.data(using: .utf8)!
        let channel = try JSONDecoder().decode(DiscourseChatChannel.self, from: json)
        XCTAssertEqual(
            channel.avatarURL(baseURL: "https://example.com")?.absoluteString,
            "https://example.com/uploads/default/original/1X/logo.png"
        )
        XCTAssertEqual(channel.monogramLetter, "#")
        XCTAssertTrue(channel.isPublicChannel)
        XCTAssertEqual(channel.accentHexColor, "E45735")
    }

    func testPublicChannelWithoutLogoUsesHashMonogram() throws {
        let json = """
        {
          "id": 3,
          "title": "水区",
          "chatable_type": "Category",
          "chatable": { "name": "水区", "color": "F5D76E" }
        }
        """.data(using: .utf8)!
        let channel = try JSONDecoder().decode(DiscourseChatChannel.self, from: json)
        XCTAssertNil(channel.avatarURL(baseURL: "https://example.com"))
        XCTAssertEqual(channel.monogramLetter, "#")
        XCTAssertEqual(channel.accentHexColor, "F5D76E")
    }

    func testChannelEmojiAndIconAliasDecode() throws {
        let json = """
        {
          "id": 9,
          "title": "闲聊",
          "emoji": "💬",
          "icon": { "url": "/uploads/icon.png" },
          "chatable_type": "Category",
          "chatable": { "color": "0088CC" }
        }
        """.data(using: .utf8)!
        let channel = try JSONDecoder().decode(DiscourseChatChannel.self, from: json)
        XCTAssertEqual(channel.monogramLetter, "💬")
        XCTAssertEqual(
            channel.avatarURL(baseURL: "https://example.com")?.absoluteString,
            "https://example.com/uploads/icon.png"
        )
    }

    func testShortcodeEmojiUsesTwemojiAvatarForPublicChannel() throws {
        EmojiStore.clearCache()
        let json = """
        {
          "id": 10,
          "title": "常规频道",
          "emoji": ":speech_balloon:",
          "chatable_type": "Category"
        }
        """.data(using: .utf8)!
        let channel = try JSONDecoder().decode(DiscourseChatChannel.self, from: json)
        XCTAssertEqual(channel.namedEmojiCode, "speech_balloon")
        XCTAssertEqual(channel.monogramLetter, "#")
        XCTAssertEqual(
            channel.avatarURL(baseURL: "https://example.com")?.absoluteString,
            "https://example.com/images/emoji/twitter/speech_balloon.png?v=12"
        )
    }

    func testBareEmojiNameUsesTwemojiAvatar() throws {
        EmojiStore.clearCache()
        let json = """
        {
          "id": 12,
          "title": "常规频道",
          "emoji": "speech_balloon",
          "chatable_type": "Category"
        }
        """.data(using: .utf8)!
        let channel = try JSONDecoder().decode(DiscourseChatChannel.self, from: json)
        XCTAssertEqual(channel.namedEmojiCode, "speech_balloon")
        XCTAssertEqual(
            channel.avatarURL(baseURL: "https://linux.do")?.absoluteString,
            "https://linux.do/images/emoji/twitter/speech_balloon.png?v=12"
        )
    }

    func testPublicChannelDecodesUploadedLogoString() throws {
        let json = """
        {
          "id": 8,
          "title": "General",
          "chatable": {
            "uploaded_logo": "/uploads/logo.png"
          }
        }
        """.data(using: .utf8)!
        let channel = try JSONDecoder().decode(DiscourseChatChannel.self, from: json)
        XCTAssertEqual(
            channel.avatarURL(baseURL: "https://forum.example")?.absoluteString,
            "https://forum.example/uploads/logo.png"
        )
        XCTAssertEqual(channel.monogramLetter, "G")
    }

    func testChatableIntegerDoesNotDropTheChannel() throws {
        let json = """
        { "id": 11, "title": "Lounge", "chatable_type": "Category", "chatable": 4 }
        """.data(using: .utf8)!
        let channel = try JSONDecoder().decode(DiscourseChatChannel.self, from: json)
        XCTAssertEqual(channel.id, 11)
        XCTAssertNil(channel.chatable)
        XCTAssertEqual(channel.monogramLetter, "#")
    }

    func testFormatSendTimeTodayYesterdayAndOlder() {
        let calendar = Calendar.current
        let now = Date()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let today = DiscourseChatMessage.formatSendTime(formatter.string(from: now), now: now)
        XCTAssertFalse(today.isEmpty)
        XCTAssertFalse(today.contains("\n"))

        let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now)!
        let yesterday = DiscourseChatMessage.formatSendTime(formatter.string(from: yesterdayDate), now: now)
        XCTAssertTrue(yesterday.contains("\n"))
        XCTAssertTrue(yesterday.contains(":"))

        let olderDate = calendar.date(byAdding: .day, value: -5, to: now)!
        let older = DiscourseChatMessage.formatSendTime(formatter.string(from: olderDate), now: now)
        XCTAssertTrue(older.contains("/"))
        XCTAssertTrue(older.contains("\n"))

        let sixDigit = DiscourseChatMessage.formatSendTime("2024-01-02T03:04:05.123456Z", now: now)
        XCTAssertFalse(sixDigit.isEmpty)
    }
}
