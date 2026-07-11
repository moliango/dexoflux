import XCTest
@testable import dexoflux

@MainActor
final class AccountScopedStoreTests: XCTestCase {
    func testBrowserHistoryIsAccountScopedAndBaseURLIsNormalized() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let sam = BrowserHistoryStore(
            baseURL: "HTTPS://LINUX.DO/",
            username: "Sam",
            directoryURL: directory
        )
        try sam.recordVisit(url: URL(string: "https://linux.do/t/one/1")!, title: "One")

        let sameAccount = BrowserHistoryStore(
            baseURL: "https://linux.do",
            username: "sam",
            directoryURL: directory
        )
        let alex = BrowserHistoryStore(
            baseURL: "https://linux.do",
            username: "alex",
            directoryURL: directory
        )

        XCTAssertEqual(sameAccount.history.map(\.title), ["One"])
        XCTAssertTrue(alex.history.isEmpty)
    }

    func testRepeatVisitMovesToFrontAndHistoryIsBounded() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserHistoryStore(
            baseURL: "https://linux.do",
            username: "sam",
            directoryURL: directory,
            maxHistoryCount: 3
        )

        try store.recordVisit(url: URL(string: "https://linux.do/1")!, title: "One", visitedAt: Date(timeIntervalSince1970: 1))
        try store.recordVisit(url: URL(string: "https://linux.do/2")!, title: "Two", visitedAt: Date(timeIntervalSince1970: 2))
        try store.recordVisit(url: URL(string: "https://linux.do/3")!, title: "Three", visitedAt: Date(timeIntervalSince1970: 3))
        try store.recordVisit(url: URL(string: "https://linux.do/4")!, title: "Four", visitedAt: Date(timeIntervalSince1970: 4))
        try store.recordVisit(url: URL(string: "https://linux.do/2")!, title: "Two Updated", visitedAt: Date(timeIntervalSince1970: 5))

        XCTAssertEqual(store.history.map(\.urlString), [
            "https://linux.do/2",
            "https://linux.do/4",
            "https://linux.do/3",
        ])
        XCTAssertEqual(store.history.first?.title, "Two Updated")
    }

    func testBookmarksAreUniqueByNormalizedURL() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserHistoryStore(
            baseURL: "https://linux.do",
            username: "sam",
            directoryURL: directory
        )

        try store.addBookmark(url: URL(string: "https://LINUX.do/t/one/1#post_2")!, title: "One")
        try store.addBookmark(url: URL(string: "https://linux.do/t/one/1")!, title: "One Updated")

        XCTAssertEqual(store.bookmarks.count, 1)
        XCTAssertEqual(store.bookmarks.first?.title, "One Updated")
        XCTAssertEqual(store.bookmarks.first?.urlString, "https://linux.do/t/one/1")
    }

    func testBookmarkRenamePersistsWithoutChangingIdentity() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = BrowserHistoryStore(
            baseURL: "https://linux.do",
            username: "sam",
            directoryURL: directory
        )
        try store.addBookmark(url: URL(string: "https://linux.do/t/one/1")!, title: "Original")
        let bookmark = try XCTUnwrap(store.bookmarks.first)

        try store.renameBookmark(bookmark, title: "  Renamed  ")

        let reloaded = BrowserHistoryStore(
            baseURL: "https://linux.do",
            username: "sam",
            directoryURL: directory
        )
        XCTAssertEqual(reloaded.bookmarks.first?.title, "Renamed")
        XCTAssertEqual(reloaded.bookmarks.first?.urlString, bookmark.urlString)
        XCTAssertEqual(reloaded.bookmarks.first?.timestamp, bookmark.timestamp)
    }

    func testCorruptStorageLoadsEmptyAndNextWriteReplacesIt() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: BrowserHistoryStore.storageURL(in: directory), options: .atomic)

        let store = BrowserHistoryStore(
            baseURL: "https://linux.do",
            username: "sam",
            directoryURL: directory
        )
        XCTAssertTrue(store.history.isEmpty)

        try store.recordVisit(url: URL(string: "https://linux.do/latest")!, title: "Latest")

        let reloaded = BrowserHistoryStore(
            baseURL: "https://linux.do",
            username: "sam",
            directoryURL: directory
        )
        XCTAssertEqual(reloaded.history.map(\.title), ["Latest"])
    }

    func testExportHistoryIsAccountScoped() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let sam = ExportHistoryStore(
            baseURL: "https://linux.do",
            username: "sam",
            directoryURL: directory
        )
        let record = TopicExportRecord(
            topicId: 17,
            title: "Topic",
            format: .markdown,
            filePath: "/tmp/topic.md",
            postCount: 1,
            timestamp: Date(timeIntervalSince1970: 1),
            errorMessage: nil
        )
        try sam.add(record)

        let sameAccount = ExportHistoryStore(
            baseURL: "HTTPS://LINUX.DO/",
            username: "Sam",
            directoryURL: directory
        )
        let alex = ExportHistoryStore(
            baseURL: "https://linux.do",
            username: "alex",
            directoryURL: directory
        )

        XCTAssertEqual(sameAccount.records.map(\.topicId), [17])
        XCTAssertTrue(alex.records.isEmpty)
    }

    func testTopicExportGeneratesReadableMarkdownAndEscapedHTML() async throws {
        let directory = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let service = TopicExportService(
            baseURL: "https://linux.do",
            username: "sam",
            directoryURL: directory
        )
        let post = try decodePost(
            cooked: "<p>Hello &amp; <strong>world</strong></p>",
            username: "sam & alex"
        )

        let markdownURL = try service.export(
            topicId: 17,
            title: "A & <B>",
            posts: [post],
            format: .markdown,
            range: .loadedPosts
        )
        let markdown = try String(contentsOf: markdownURL, encoding: .utf8)
        XCTAssertTrue(markdown.contains("Hello & world"))
        XCTAssertFalse(markdown.contains("<strong>"))

        let htmlURL = try service.export(
            topicId: 17,
            title: "A & <B>",
            posts: [post],
            format: .html,
            range: .loadedPosts
        )
        let html = try String(contentsOf: htmlURL, encoding: .utf8)
        XCTAssertTrue(html.contains("<title>A &amp; &lt;B&gt;</title>"))
        XCTAssertTrue(html.contains("sam &amp; alex"))
        XCTAssertTrue(html.contains("<strong>world</strong>"))
    }

    private func decodePost(cooked: String, username: String) throws -> DiscourseTopicDetail.Post {
        let object: [String: Any] = [
            "id": 1,
            "username": username,
            "created_at": "2026-07-10T00:00:00.000Z",
            "cooked": cooked,
            "post_number": 1,
            "reply_count": 0,
        ]
        let data = try JSONSerialization.data(withJSONObject: object)
        return try JSONDecoder().decode(DiscourseTopicDetail.Post.self, from: data)
    }

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("dexoflux-store-tests-\(UUID().uuidString)", isDirectory: true)
    }
}
