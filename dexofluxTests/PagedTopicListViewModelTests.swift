import XCTest
@testable import dexoflux

@MainActor
final class PagedTopicListViewModelTests: XCTestCase {
    func testRefreshLoadsFirstPageAndDeduplicatesTopics() async throws {
        let loader = FakePagedTopicLoader()
        loader.pages[0] = try topicList(ids: [17, 17, 18], hasMore: true)
        let viewModel = PagedTopicListViewModel(loader: loader.load)

        await viewModel.refresh()

        XCTAssertEqual(viewModel.topics.map(\.id), [17, 18])
        XCTAssertEqual(loader.requestedPages, [0])
        XCTAssertTrue(viewModel.canLoadMore)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadMoreAppendsOnlyNewTopics() async throws {
        let loader = FakePagedTopicLoader()
        loader.pages[0] = try topicList(ids: [17, 18], hasMore: true)
        loader.pages[1] = try topicList(ids: [18, 19], hasMore: false)
        let viewModel = PagedTopicListViewModel(loader: loader.load)
        await viewModel.refresh()

        await viewModel.loadMore()

        XCTAssertEqual(viewModel.topics.map(\.id), [17, 18, 19])
        XCTAssertEqual(loader.requestedPages, [0, 1])
        XCTAssertFalse(viewModel.canLoadMore)
    }

    func testLoadMoreFailurePreservesExistingTopicsAndAllowsRetry() async throws {
        let loader = FakePagedTopicLoader()
        loader.pages[0] = try topicList(ids: [17], hasMore: true)
        let viewModel = PagedTopicListViewModel(loader: loader.load)
        await viewModel.refresh()
        loader.errorPages.insert(1)

        await viewModel.loadMore()

        XCTAssertEqual(viewModel.topics.map(\.id), [17])
        XCTAssertNotNil(viewModel.loadMoreErrorMessage)
        XCTAssertTrue(viewModel.canLoadMore)

        loader.errorPages.remove(1)
        loader.pages[1] = try topicList(ids: [18], hasMore: false)
        await viewModel.loadMore()

        XCTAssertEqual(viewModel.topics.map(\.id), [17, 18])
        XCTAssertNil(viewModel.loadMoreErrorMessage)
    }

    private func topicList(ids: [Int], hasMore: Bool) throws -> DiscourseTopicList {
        let topics = ids.map { id in
            """
            {
              "id": \(id),
              "fancy_title": "Topic \(id)",
              "title": "Topic \(id)",
              "posts_count": 2,
              "reply_count": 1,
              "views": 10,
              "category_id": 1,
              "created_at": "2026-07-10T00:00:00.000Z",
              "last_posted_at": "2026-07-10T01:00:00.000Z",
              "posters": [{"user_id": 1}],
              "tags": ["swift"]
            }
            """
        }.joined(separator: ",")
        let moreTopicsURL = hasMore ? #""more_topics_url":"/latest.json?page=1","# : ""
        let json = """
        {
          "users": [{"id":1,"username":"sam","avatar_template":"/avatar/{size}.png"}],
          "categories": [{"id":1,"name":"开发调优","slug":"dev","color":"0088CC"}],
          "topic_list": {\(moreTopicsURL)"topics":[\(topics)]}
        }
        """
        return try JSONDecoder().decode(DiscourseTopicList.self, from: Data(json.utf8))
    }
}

@MainActor
private final class FakePagedTopicLoader {
    var pages: [Int: DiscourseTopicList] = [:]
    var errorPages: Set<Int> = []
    var requestedPages: [Int] = []

    func load(page: Int) async throws -> DiscourseTopicList {
        requestedPages.append(page)
        if errorPages.contains(page) {
            throw PagedTopicListTestError.failed
        }
        if let page = pages[page] {
            return page
        }
        return try JSONDecoder().decode(
            DiscourseTopicList.self,
            from: Data(#"{"topic_list":{"topics":[]}}"#.utf8)
        )
    }
}

private enum PagedTopicListTestError: Error {
    case failed
}
