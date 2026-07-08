import Foundation

enum HomeListMode: CaseIterable, Hashable {
    case latest
    case newTopics
    case unread
    case hot
    case top

    var apiFilterName: String {
        switch self {
        case .latest:
            return "latest"
        case .newTopics:
            return "new"
        case .unread:
            return "unread"
        case .hot:
            return "hot"
        case .top:
            return "top"
        }
    }

    var categoryFilterName: String? {
        switch self {
        case .newTopics, .unread, .top:
            return apiFilterName
        case .latest, .hot:
            return nil
        }
    }
}

private enum TopicAccessState {
    case allowed
    case loginRequired
    case unavailable(Error)
}

@MainActor
final class HomeViewModel: DexoObservableObject {
    var listMode: HomeListMode = .latest
    var topics: [DiscourseTopicList.Topic] = []
    var incomingTopicIds: [Int] = []
    var isLoadingIncomingTopics = false
    var shouldRetryIncomingTopicsAfterCloudflare = false
    var isLoading = false
    var isLoadingMore = false
    var canLoadMore = false
    var errorMessage: String?
    var requiresLogin = false
    var isBlockedByCloudflare = false

    var categories: [DiscourseCategory] = []
    var selectedCategoryId: Int?

    private let api: DiscourseAPI
    private var currentPage = 0
    private var usersById: [Int: DiscourseTopicList.User] = [:]
    private var categoryIndex = DiscourseCategoryIndex()
    private var loggedTopicCategoryIds = Set<Int>()
    private var categoryMetadataTask: Task<Void, Never>?

    init(api: DiscourseAPI) {
        self.api = api
    }

    private var canBrowseTopics: Bool {
        AuthManager.shared.isAuthenticated(for: api.baseURL)
    }

    func avatarTemplate(for topic: DiscourseTopicList.Topic) -> String? {
        guard let firstPoster = topic.posters?.first else { return nil }
        return usersById[firstPoster.userId]?.avatarTemplate
    }

    func username(for topic: DiscourseTopicList.Topic) -> String? {
        guard let firstPoster = topic.posters?.first else { return nil }
        return usersById[firstPoster.userId]?.username
    }

    func category(for topic: DiscourseTopicList.Topic) -> DiscourseCategory? {
        guard let catId = topic.categoryId else { return nil }
        return categoryIndex[catId]
    }

    func category(id: Int) -> DiscourseCategory? {
        categoryIndex[id]
    }

    func pinnedCategories(for ids: [Int]) -> [DiscourseCategory] {
        ids.compactMap { categoryIndex[$0] }
    }

    func allSelectableCategories() -> [DiscourseCategory] {
        Self.flatten(categories)
    }

    func categoryDisplayName(for category: DiscourseCategory?) -> String? {
        guard let category else { return nil }
        let resolved = categoryIndex[category.id] ?? category
        return resolved.displayName(parent: parentCategory(for: resolved))
    }

    func selectedCategory() -> DiscourseCategory? {
        guard let id = selectedCategoryId else { return nil }
        return categoryIndex[id]
    }

    func loadTopics(retryingExplicitCancellation: Bool = false) async {
        isLoading = true
        errorMessage = nil
        requiresLogin = false
        isBlockedByCloudflare = false
        currentPage = 0
        notifyChanged()
        defer {
            isLoading = false
            notifyChanged()
        }

        switch await validateTopicAccess() {
        case .allowed:
            break
        case .loginRequired:
            clearProtectedContentForLoginRequired(invalidateSession: true)
            return
        case .unavailable(let error):
            if await handleExplicitCancellationIfNeeded(error, retryingExplicitCancellation: retryingExplicitCancellation) {
                return
            }
            isBlockedByCloudflare = isCloudflareChallenge(error)
            errorMessage = error.localizedDescription
            return
        }

        do {
            startLoadingCategoriesIfNeeded()
            let result = try await fetchTopics(page: 0)
            try Task.checkCancellation()
            topics = result.topicList.topics
            incomingTopicIds = []
            shouldRetryIncomingTopicsAfterCloudflare = false
            isBlockedByCloudflare = false
            canLoadMore = result.topicList.moreTopicsUrl != nil
            indexUsers(result.users)
            indexCategories(result.categories, source: .topicList)
            logTopicCategoryDiagnostics(context: "loadTopics", topics: topics)
        } catch is CancellationError {
            errorMessage = nil
        } catch {
            if await handleExplicitCancellationIfNeeded(error, retryingExplicitCancellation: retryingExplicitCancellation) {
                return
            }
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                clearProtectedContentForLoginRequired(invalidateSession: true)
                return
            }
            isBlockedByCloudflare = isCloudflareChallenge(error)
            errorMessage = error.localizedDescription
        }
    }

    func loadMoreTopics() async {
        guard canLoadMore, !isLoadingMore else { return }
        switch await validateTopicAccess() {
        case .allowed:
            break
        case .loginRequired:
            clearProtectedContentForLoginRequired(invalidateSession: true)
            return
        case .unavailable:
            return
        }
        isLoadingMore = true
        notifyChanged()
        defer {
            isLoadingMore = false
            notifyChanged()
        }

        let nextPage = currentPage + 1
        do {
            let result = try await fetchTopics(page: nextPage)
            try Task.checkCancellation()
            currentPage = nextPage
            let existingIds = Set(topics.map(\.id))
            let newTopics = result.topicList.topics.filter { !existingIds.contains($0.id) }
            topics.append(contentsOf: newTopics)
            canLoadMore = result.topicList.moreTopicsUrl != nil
            indexUsers(result.users)
            indexCategories(result.categories, source: .topicList)
            logTopicCategoryDiagnostics(context: "loadMore", topics: newTopics)
        } catch is CancellationError {
            // A newer refresh replaced this request.
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                clearProtectedContentForLoginRequired(invalidateSession: true)
                return
            }
            // Silently fail on load-more; user can scroll again to retry
        }
    }

    func detectIncomingTopics() async {
        guard canBrowseTopics else {
            clearProtectedContentForLoginRequired(invalidateSession: true)
            return
        }
        guard listMode == .latest, !topics.isEmpty, !isLoading else { return }
        do {
            let result = try await fetchTopics(page: 0)
            let incomingIds = incomingTopicIds(from: result.topicList.topics)
            if incomingIds != incomingTopicIds {
                incomingTopicIds = incomingIds
                indexUsers(result.users)
                indexCategories(result.categories, source: .topicList)
                notifyChanged()
            }
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                clearProtectedContentForLoginRequired(invalidateSession: true)
                return
            }
            // Incoming detection is a background affordance; keep the visible list stable on failure.
        }
    }

    func loadIncomingTopics() async {
        let ids = incomingTopicIds
        guard !ids.isEmpty, !isLoadingIncomingTopics else { return }
        shouldRetryIncomingTopicsAfterCloudflare = false
        isLoadingIncomingTopics = true
        notifyChanged()
        defer {
            isLoadingIncomingTopics = false
            notifyChanged()
        }

        switch await validateTopicAccess() {
        case .allowed:
            break
        case .loginRequired:
            clearProtectedContentForLoginRequired(invalidateSession: true)
            return
        case .unavailable(let error):
            if isCloudflareChallenge(error) {
                shouldRetryIncomingTopicsAfterCloudflare = true
                errorMessage = nil
            } else {
                errorMessage = error.localizedDescription
            }
            notifyChanged()
            return
        }

        do {
            let result = try await api.fetchTopicsByIds(ids)
            try Task.checkCancellation()
            let incomingTopics = result.topicList.topics
            if !incomingTopics.isEmpty {
                let incomingIds = Set(incomingTopics.map(\.id))
                let remaining = topics.filter { !incomingIds.contains($0.id) }
                topics = incomingTopics + remaining
                indexUsers(result.users)
                indexCategories(result.categories, source: .topicList)
            }
            incomingTopicIds.removeAll()
            shouldRetryIncomingTopicsAfterCloudflare = false
        } catch is CancellationError {
            // A newer refresh replaced this request.
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                clearProtectedContentForLoginRequired(invalidateSession: true)
                return
            }
            if isCloudflareChallenge(error) {
                shouldRetryIncomingTopicsAfterCloudflare = true
                errorMessage = nil
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    func resetCategoryMetadata(clearSelection: Bool) {
        categoryMetadataTask?.cancel()
        categoryMetadataTask = nil
        categories = []
        categoryIndex = DiscourseCategoryIndex()
        loggedTopicCategoryIds.removeAll()
        if clearSelection {
            selectedCategoryId = nil
        }
        notifyChanged()
    }

    func finishLoadingAfterTimeout(message: String) {
        guard isLoading || isLoadingMore || isLoadingIncomingTopics else { return }
        isLoading = false
        isLoadingMore = false
        isLoadingIncomingTopics = false
        shouldRetryIncomingTopicsAfterCloudflare = false
        requiresLogin = false
        isBlockedByCloudflare = false
        if topics.isEmpty {
            errorMessage = message
        }
        notifyChanged()
    }

    private func validateTopicAccess() async -> TopicAccessState {
        guard canBrowseTopics else {
            return .loginRequired
        }

        do {
            _ = try await api.fetchCurrentUser()
            return .allowed
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                return .loginRequired
            }
            return .unavailable(error)
        }
    }

    private func clearProtectedContentForLoginRequired(
        message: String = String(localized: "login.required.message"),
        invalidateSession: Bool = false
    ) {
        categoryMetadataTask?.cancel()
        categoryMetadataTask = nil
        topics = []
        incomingTopicIds = []
        shouldRetryIncomingTopicsAfterCloudflare = false
        isLoading = false
        isLoadingMore = false
        isLoadingIncomingTopics = false
        canLoadMore = false
        currentPage = 0
        usersById.removeAll()
        categories = []
        selectedCategoryId = nil
        categoryIndex = DiscourseCategoryIndex()
        loggedTopicCategoryIds.removeAll()
        requiresLogin = true
        isBlockedByCloudflare = false
        errorMessage = message
        if invalidateSession {
            AuthManager.shared.invalidateWebSession(for: api.baseURL)
        }
        notifyChanged()
    }

    private func isCloudflareChallenge(_ error: Error) -> Bool {
        (error as? DiscourseAPIError)?.isCloudflareChallenge == true
    }

    private func handleExplicitCancellationIfNeeded(
        _ error: Error,
        retryingExplicitCancellation: Bool
    ) async -> Bool {
        guard DiscourseAPI.isExplicitlyCancelledRequest(error) else { return false }
        errorMessage = nil
        isBlockedByCloudflare = false
        guard !retryingExplicitCancellation, !Task.isCancelled else { return true }
        do {
            try await Task.sleep(nanoseconds: 250_000_000)
        } catch {
            return true
        }
        guard !Task.isCancelled else { return true }
        await loadTopics(retryingExplicitCancellation: true)
        return true
    }

    private func fetchTopics(page: Int) async throws -> DiscourseTopicList {
        if let cat = selectedCategory() {
            if let filter = listMode.categoryFilterName {
                return try await api.fetchCategoryTopics(slug: cat.slug, id: cat.id, filter: filter, page: page)
            }
            return try await api.fetchCategoryTopics(slug: cat.slug, id: cat.id, page: page)
        }

        switch listMode {
        case .latest:
            return try await api.fetchLatestTopics(page: page)
        case .newTopics:
            return try await api.fetchNewTopics(page: page)
        case .unread:
            return try await api.fetchUnreadTopics(page: page)
        case .hot:
            return try await api.fetchHotTopics(page: page)
        case .top:
            return try await api.fetchTopTopics(page: page)
        }
    }

    private func incomingTopicIds(from latestTopics: [DiscourseTopicList.Topic]) -> [Int] {
        guard let firstCurrentTopicId = topics.first?.id else { return [] }
        var currentTopicsById: [Int: DiscourseTopicList.Topic] = [:]
        for topic in topics {
            currentTopicsById[topic.id] = topic
        }
        var ids: [Int] = []
        var seenIds = Set<Int>()
        var hasReachedFirstCurrentTopic = false

        for topic in latestTopics {
            if topic.id == firstCurrentTopicId {
                hasReachedFirstCurrentTopic = true
            }

            let isBeforeFirstCurrentTopic = !hasReachedFirstCurrentTopic && topic.id != firstCurrentTopicId
            let isUpdatedExistingTopic = currentTopicsById[topic.id].map { hasTopicUpdate(latest: topic, current: $0) } ?? false

            if (isBeforeFirstCurrentTopic || isUpdatedExistingTopic), seenIds.insert(topic.id).inserted {
                ids.append(topic.id)
            }
        }
        return ids
    }

    private func hasTopicUpdate(latest: DiscourseTopicList.Topic, current: DiscourseTopicList.Topic) -> Bool {
        latest.postsCount != current.postsCount
            || latest.replyCount != current.replyCount
            || latest.lastPostedAt != current.lastPostedAt
    }

    private func indexUsers(_ users: [DiscourseTopicList.User]?) {
        guard let users else { return }
        for user in users {
            usersById[user.id] = user
        }
    }

    private func loadCategoriesIfNeeded() async {
        guard canBrowseTopics else { return }
        guard categoryIndex.isEmpty else { return }
        do {
            let siteCategories = (try? await api.fetchSiteCategories()) ?? []
            if !siteCategories.isEmpty {
                let visibleCategories = siteCategories.filter { $0.id != 1 }
                categories = DiscourseCategory.hierarchy(fromFlat: visibleCategories)
                indexCategories(visibleCategories, source: .site)
                logCategoryMetadata(source: "site", categories: visibleCategories)
            } else {
                let list = try await api.fetchCategories()
                categories = DiscourseCategory.normalizedTree(fromNested: list.categoryList.categories)
                indexCategories(categories, source: .categoryList)
                logCategoryMetadata(source: "categories", categories: categories)
            }
            notifyChanged()
        } catch {
            // Non-critical — cells just won't show category names
            DohDebugLog.record("metadata load failed: \(error.localizedDescription)", subsystem: "Category")
        }
    }

    private func startLoadingCategoriesIfNeeded() {
        guard canBrowseTopics else { return }
        guard categoryIndex.isEmpty, categoryMetadataTask == nil else { return }
        categoryMetadataTask = Task { [weak self] in
            guard let self else { return }
            await self.loadCategoriesIfNeeded()
            guard !Task.isCancelled else { return }
            self.categoryMetadataTask = nil
        }
    }

    private func indexCategories(_ categories: [DiscourseCategory], source: DiscourseCategoryIndexSource) {
        categoryIndex.merge(categories, source: source)
    }

    private func indexCategories(_ categories: [DiscourseCategory]?, source: DiscourseCategoryIndexSource) {
        categoryIndex.merge(categories, source: source)
    }

    private func parentCategory(for category: DiscourseCategory) -> DiscourseCategory? {
        guard let parentId = category.parentCategoryId else { return nil }
        return categoryIndex[parentId]
    }

    private func logCategoryMetadata(source: String, categories: [DiscourseCategory]) {
        let indexed = DiscourseCategory.indexedById(from: categories)
        let levelCategories = indexed.values
            .filter { $0.serverLevelName != nil }
            .sorted { $0.id < $1.id }
            .prefix(30)
            .map { category in
                "id=\(category.id) name=\(category.name) parent=\(category.parentCategoryId.map(String.init) ?? "nil")"
            }
            .joined(separator: " | ")
        let namedCategories = indexed.values
            .filter { category in
                category.name.localizedCaseInsensitiveContains("lv")
                    || category.name.contains("搞七")
                    || category.name.contains("开发")
                    || category.name.contains("调优")
            }
            .sorted { $0.id < $1.id }
            .prefix(30)
            .map { category in
                "id=\(category.id) name=\(category.name) parent=\(category.parentCategoryId.map(String.init) ?? "nil")"
            }
            .joined(separator: " | ")

        DohDebugLog.record(
            "metadata source=\(source) count=\(indexed.count) levels=\(levelCategories.isEmpty ? "none" : levelCategories) matches=\(namedCategories.isEmpty ? "none" : namedCategories)",
            subsystem: "Category"
        )
    }

    private func logTopicCategoryDiagnostics(context: String, topics: [DiscourseTopicList.Topic]) {
        for topic in topics.prefix(20) where loggedTopicCategoryIds.insert(topic.id).inserted {
            let category = category(for: topic)
            let parent = category.flatMap { parentCategory(for: $0) }
            let displayName = categoryDisplayName(for: category) ?? "nil"
            let categoryId = topic.categoryId.map(String.init) ?? "nil"
            let source = topic.categoryId
                .flatMap { categoryIndex.source(for: $0) }
                .map(Self.categorySourceName) ?? "none"
            let categoryText = category.map { "id=\($0.id) name=\($0.name) parent=\($0.parentCategoryId.map(String.init) ?? "nil")" } ?? "nil"
            let parentText = parent.map { "id=\($0.id) name=\($0.name)" } ?? "nil"
            let tagsText = (topic.tags ?? []).isEmpty ? "none" : (topic.tags ?? []).joined(separator: ",")

            DohDebugLog.record(
                "\(context) topic=\(topic.id) categoryId=\(categoryId) source=\(source) category={\(categoryText)} parent={\(parentText)} display=\(displayName) tags=\(tagsText) title=\(topic.title)",
                subsystem: "Category"
            )
        }
    }

    private static func categorySourceName(_ source: DiscourseCategoryIndexSource) -> String {
        switch source {
        case .topicList:
            return "topicList"
        case .categoryList:
            return "categoryList"
        case .site:
            return "site"
        }
    }

    private static func flatten(_ categories: [DiscourseCategory]) -> [DiscourseCategory] {
        var result: [DiscourseCategory] = []

        func append(_ category: DiscourseCategory) {
            result.append(category)
            category.subcategoryList?.forEach(append)
        }

        categories.forEach(append)
        return result
    }
}
