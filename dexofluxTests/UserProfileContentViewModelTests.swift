import XCTest
@testable import dexoflux

@MainActor
final class UserProfileContentViewModelTests: XCTestCase {
    func testSectionsMapToFluxDoFilters() {
        XCTAssertEqual(UserProfileSection.activity.actionFilter, "4,5")
        XCTAssertEqual(UserProfileSection.topics.actionFilter, "4")
        XCTAssertEqual(UserProfileSection.replies.actionFilter, "5")
        XCTAssertEqual(UserProfileSection.likesReceived.actionFilter, "1")
        XCTAssertNil(UserProfileSection.summary.actionFilter)
        XCTAssertNil(UserProfileSection.reactions.actionFilter)
    }

    func testSelectingTopicsLoadsAndDeduplicatesActions() async throws {
        let service = FakeUserProfileContentService()
        service.actionPages = [[try action(idSuffix: "same"), try action(idSuffix: "same")]]
        let viewModel = UserProfileContentViewModel(username: "sam", service: service)

        await viewModel.select(.topics)

        XCTAssertEqual(service.actionCalls, [.init(filter: "4", offset: 0)])
        XCTAssertEqual(viewModel.rows.compactMap(\.action).count, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testLoadMoreFailurePreservesExistingRows() async throws {
        let service = FakeUserProfileContentService()
        service.actionPages = [[try action(idSuffix: "first")]]
        let viewModel = UserProfileContentViewModel(username: "sam", service: service)
        await viewModel.select(.activity)
        let initialRows = viewModel.rows.count
        service.error = TestContentError.failed

        await viewModel.loadMore()

        XCTAssertEqual(viewModel.rows.count, initialRows)
        XCTAssertNotNil(viewModel.loadMoreErrorMessage)
    }

    private func action(idSuffix: String) throws -> DiscourseUserAction {
        let data = Data(#"{"action_type":4,"topic_id":17,"title":"Topic \#(idSuffix)","post_number":1,"acting_at":"\#(idSuffix)"}"#.utf8)
        return try JSONDecoder().decode(DiscourseUserAction.self, from: data)
    }
}

@MainActor
private final class FakeUserProfileContentService: UserProfileContentServicing {
    struct ActionCall: Equatable {
        let filter: String
        let offset: Int
    }

    var actionPages: [[DiscourseUserAction]] = []
    var reactionPages: [[DiscourseUserReaction]] = []
    var actionCalls: [ActionCall] = []
    var error: Error?

    func fetchUserSummaryResponse(username: String) async throws -> DiscourseUserSummaryResponse {
        throw error ?? TestContentError.failed
    }

    func fetchUserActions(username: String, filter: String, offset: Int) async throws -> [DiscourseUserAction] {
        actionCalls.append(.init(filter: filter, offset: offset))
        if let error { throw error }
        return actionPages.isEmpty ? [] : actionPages.removeFirst()
    }

    func fetchUserReactions(username: String, beforeReactionUserId: Int?) async throws -> [DiscourseUserReaction] {
        if let error { throw error }
        return reactionPages.isEmpty ? [] : reactionPages.removeFirst()
    }
}

private extension UserProfileContentRow {
    var action: DiscourseUserAction? {
        guard case .action(let action) = self else { return nil }
        return action
    }
}

private enum TestContentError: Error {
    case failed
}
