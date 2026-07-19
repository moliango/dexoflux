import XCTest
@testable import dexoflux

@MainActor
final class UserProfileContentViewModelTests: XCTestCase {
    func testProfileTabPreferencesDefaultToAllSections() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = UserProfileTabPreferences(defaults: defaults)

        XCTAssertEqual(preferences.visibleSections, UserProfileSection.allCases)
    }

    func testProfileTabPreferencesPersistSanitizedOrder() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserProfileTabPreferences(defaults: defaults)

        preferences.setVisibleSections([.likesGiven, .summary, .likesGiven, .replies])

        XCTAssertEqual(
            UserProfileTabPreferences(defaults: defaults).visibleSections,
            [.likesGiven, .summary, .replies]
        )
    }

    func testProfileTabPreferencesIgnoreEmptyConfiguration() {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = UserProfileTabPreferences(defaults: defaults)
        preferences.setVisibleSections([.likesReceived, .likesGiven])

        preferences.setVisibleSections([])

        XCTAssertEqual(preferences.visibleSections, [.likesReceived, .likesGiven])
    }

    func testViewModelStartsOnConfiguredSection() {
        let service = FakeUserProfileContentService()
        let viewModel = UserProfileContentViewModel(
            username: "sam",
            service: service,
            initialSection: .likesGiven
        )

        XCTAssertEqual(viewModel.section, .likesGiven)
    }

    func testInitialSummaryIsIgnoredAfterContentGenerationChanges() async throws {
        let service = FakeUserProfileContentService()
        let viewModel = UserProfileContentViewModel(username: "sam", service: service)
        let initialGeneration = viewModel.contentGeneration
        let summary = try JSONDecoder().decode(
            DiscourseUserSummaryResponse.self,
            from: Data(#"{"user_summary":{"topic_count":7}}"#.utf8)
        ).userSummary

        await viewModel.select(.summary)
        let applied = viewModel.applySummary(summary, ifGeneration: initialGeneration)

        XCTAssertFalse(applied)
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testSectionsMapToFluxDoFilters() {
        XCTAssertEqual(UserProfileSection.activity.actionFilter, "4,5")
        XCTAssertEqual(UserProfileSection.topics.actionFilter, "4")
        XCTAssertEqual(UserProfileSection.replies.actionFilter, "5")
        XCTAssertEqual(UserProfileSection.likesReceived.actionFilter, "1")
        XCTAssertEqual(UserProfileSection.likesGiven.actionFilter, "2")
        XCTAssertNil(UserProfileSection.summary.actionFilter)
        XCTAssertNil(UserProfileSection.reactions.actionFilter)
    }

    func testSelectingLikesGivenLoadsLikedPosts() async throws {
        let service = FakeUserProfileContentService()
        service.actionPages = [[try action(idSuffix: "liked", actionType: 2)]]
        let viewModel = UserProfileContentViewModel(username: "sam", service: service)

        await viewModel.select(.likesGiven)

        XCTAssertEqual(service.actionCalls, [.init(filter: "2", offset: 0)])
        XCTAssertEqual(viewModel.rows.compactMap(\.action).count, 1)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testStaleTabResponseDoesNotReplaceCurrentSection() async throws {
        let service = ControlledUserProfileContentService()
        let viewModel = UserProfileContentViewModel(username: "sam", service: service)
        let topicAction = try action(idSuffix: "topic", actionType: 4)
        let likedAction = try action(idSuffix: "liked", actionType: 2)

        let topicsTask = Task { await viewModel.select(.topics) }
        await waitUntil { service.actionCallCount == 1 }
        let likesTask = Task { await viewModel.select(.likesGiven) }
        await waitUntil { service.actionCallCount == 2 }

        service.resumeActionCall(at: 1, with: [likedAction])
        await likesTask.value
        service.resumeActionCall(at: 0, with: [topicAction])
        await topicsTask.value

        XCTAssertEqual(viewModel.section, .likesGiven)
        XCTAssertEqual(viewModel.rows.compactMap(\.action).map(\.title), [likedAction.title])
    }

    func testStaleTabCompletionDoesNotEndCurrentLoading() async throws {
        let service = ControlledUserProfileContentService()
        let viewModel = UserProfileContentViewModel(username: "sam", service: service)
        let topicAction = try action(idSuffix: "topic", actionType: 4)
        let likedAction = try action(idSuffix: "liked", actionType: 2)

        let topicsTask = Task { await viewModel.select(.topics) }
        await waitUntil { service.actionCallCount == 1 }
        let likesTask = Task { await viewModel.select(.likesGiven) }
        await waitUntil { service.actionCallCount == 2 }

        service.resumeActionCall(at: 0, with: [topicAction])
        await topicsTask.value

        XCTAssertEqual(viewModel.section, .likesGiven)
        XCTAssertTrue(viewModel.isLoading)
        XCTAssertTrue(viewModel.rows.isEmpty)
        XCTAssertNil(viewModel.errorMessage)

        service.resumeActionCall(at: 1, with: [likedAction])
        await likesTask.value

        XCTAssertFalse(viewModel.isLoading)
        XCTAssertEqual(viewModel.rows.compactMap(\.action).map(\.title), [likedAction.title])
    }

    func testStalePaginationDoesNotAppendToNewSection() async throws {
        let service = ControlledUserProfileContentService()
        let viewModel = UserProfileContentViewModel(username: "sam", service: service)
        let firstAction = try action(idSuffix: "first", actionType: 4)
        let oldPageAction = try action(idSuffix: "old-page", actionType: 4)
        let likedAction = try action(idSuffix: "liked", actionType: 2)

        let initialTask = Task { await viewModel.select(.activity) }
        await waitUntil { service.actionCallCount == 1 }
        service.resumeActionCall(at: 0, with: [firstAction])
        await initialTask.value

        let paginationTask = Task { await viewModel.loadMore() }
        await waitUntil { service.actionCallCount == 2 }
        let likesTask = Task { await viewModel.select(.likesGiven) }
        await waitUntil { service.actionCallCount == 3 }
        service.resumeActionCall(at: 2, with: [likedAction])
        await likesTask.value

        service.resumeActionCall(at: 1, with: [oldPageAction])
        await paginationTask.value

        XCTAssertEqual(viewModel.section, .likesGiven)
        XCTAssertEqual(viewModel.rows.compactMap(\.action).map(\.title), [likedAction.title])
        XCTAssertNil(viewModel.loadMoreErrorMessage)
        XCTAssertFalse(viewModel.isLoadingMore)
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

    private func action(idSuffix: String, actionType: Int = 4) throws -> DiscourseUserAction {
        let data = Data(#"{"action_type":\#(actionType),"topic_id":17,"title":"Topic \#(idSuffix)","post_number":1,"acting_at":"\#(idSuffix)"}"#.utf8)
        return try JSONDecoder().decode(DiscourseUserAction.self, from: data)
    }

    private func makeDefaults() -> (UserDefaults, String) {
        let suiteName = "UserProfileContentViewModelTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func waitUntil(_ condition: @escaping @MainActor () -> Bool) async {
        for _ in 0 ..< 100 where !condition() {
            await Task.yield()
        }
        XCTAssertTrue(condition())
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

@MainActor
private final class ControlledUserProfileContentService: UserProfileContentServicing {
    private var actionContinuations: [CheckedContinuation<[DiscourseUserAction], Error>?] = []
    private(set) var actionCallCount = 0

    func fetchUserSummaryResponse(username: String) async throws -> DiscourseUserSummaryResponse {
        throw TestContentError.failed
    }

    func fetchUserActions(username: String, filter: String, offset: Int) async throws -> [DiscourseUserAction] {
        actionCallCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            actionContinuations.append(continuation)
        }
    }

    func fetchUserReactions(username: String, beforeReactionUserId: Int?) async throws -> [DiscourseUserReaction] {
        []
    }

    func resumeActionCall(at index: Int, with actions: [DiscourseUserAction]) {
        guard actionContinuations.indices.contains(index), let continuation = actionContinuations[index] else { return }
        actionContinuations[index] = nil
        continuation.resume(returning: actions)
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
