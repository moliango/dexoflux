import Foundation

enum IncomingTopicPageTraversal {
    static func shouldContinue(
        reachedCurrentFirstTopic: Bool,
        moreTopicsURL: String?,
        pageAddedNewTopicIds: Bool
    ) -> Bool {
        !reachedCurrentFirstTopic && moreTopicsURL != nil && pageAddedNewTopicIds
    }
}

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
    private let backgroundTopicUpdateStore: BackgroundTopicUpdateStore
    private var currentPage = 0
    private var usersById: [Int: DiscourseTopicList.User] = [:]
    private var categoryIndex = DiscourseCategoryIndex()
    private var loggedTopicCategoryIds = Set<Int>()
    private var categoryMetadataTask: Task<Void, Never>?
    private var hasLoadedFullCategoryMetadata = false

    init(
        api: DiscourseAPI,
        backgroundTopicUpdateStore: BackgroundTopicUpdateStore = .shared
    ) {
        self.api = api
        self.backgroundTopicUpdateStore = backgroundTopicUpdateStore
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

    func categoryBadgePresentation(for topic: DiscourseTopicList.Topic) -> TopicCategoryBadgePresentation? {
        guard let categoryId = topic.categoryId else { return nil }
        guard let category = categoryIndex[categoryId]
            ?? LinuxDoCategoryCatalog.category(id: categoryId, baseURL: api.baseURL)
        else { return nil }
        let parent = category.parentCategoryId.flatMap {
            categoryIndex[$0] ?? LinuxDoCategoryCatalog.category(id: $0, baseURL: api.baseURL)
        }
        return TopicCategoryBadgePresentation.resolve(
            category: category,
            parent: parent,
            displayName: category.displayName(parent: parent),
            baseURL: api.baseURL
        )
    }

    func selectedCategory() -> DiscourseCategory? {
        guard let id = selectedCategoryId else { return nil }
        return categoryIndex[id]
    }

    @discardableResult
    func updateTopicReadProgress(topicId: Int, highestSeen: Int) -> Bool {
        guard highestSeen > 0,
              let index = topics.firstIndex(where: { $0.id == topicId })
        else { return false }

        let current = topics[index]
        guard highestSeen > (current.lastReadPostNumber ?? 0) || current.unseen else {
            return false
        }
        topics[index] = current.updatingReadProgress(highestSeen: highestSeen)
        notifyChanged()
        return true
    }

    /// 冷启动/列表为空时，先用后台刷新缓存填满列表，避免只剩“查看 N 个新话题”横幅。
    func hydrateFromBackgroundCacheIfNeeded() {
        guard isGlobalLatestList, topics.isEmpty else { return }
        guard let cached = BackgroundTopicListCache.load(baseURL: api.baseURL) else { return }
        topics = cached.topicList.topics
        canLoadMore = cached.topicList.moreTopicsUrl != nil
        indexUsers(cached.users)
        indexCategories(cached.categories, source: .topicList)
        incomingTopicIds = backgroundTopicUpdateStore.pendingTopicIDs(for: api.baseURL)
        notifyChanged()
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
            // 网络返回前先露出后台缓存，避免首页空白只剩 incoming banner。
            if topics.isEmpty {
                hydrateFromBackgroundCacheIfNeeded()
            }
            let result = try await fetchTopics(page: 0)
            try Task.checkCancellation()
            topics = result.topicList.topics
            if isGlobalLatestList {
                backgroundTopicUpdateStore.establishForegroundBaselineIfNeeded(
                    topics,
                    baseURL: api.baseURL
                )
                incomingTopicIds = backgroundTopicUpdateStore.pendingTopicIDs(for: api.baseURL)
            } else {
                incomingTopicIds = []
            }
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
            // 仍在 isLoadingMore=true 时通知 UI：方便冻结 tab bar，避免 contentSize 突增时显隐打架。
            if !newTopics.isEmpty {
                notifyChanged()
            }
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
        guard isGlobalLatestList, !topics.isEmpty, !isLoading else { return }
        do {
            guard let firstCurrentTopicId = topics.first?.id else { return }
            var page = 0
            var latestTopics: [DiscourseTopicList.Topic] = []
            var seenTopicIds = Set<Int>()
            var latestUsers: [DiscourseTopicList.User] = []
            var latestCategories: [DiscourseCategory] = []

            while true {
                let result = try await fetchTopics(page: page)
                try Task.checkCancellation()
                let pageTopics = result.topicList.topics
                let previousCount = seenTopicIds.count
                for topic in pageTopics where seenTopicIds.insert(topic.id).inserted {
                    latestTopics.append(topic)
                }
                latestUsers.append(contentsOf: result.users ?? [])
                latestCategories.append(contentsOf: result.categories ?? [])

                let shouldContinue = IncomingTopicPageTraversal.shouldContinue(
                    reachedCurrentFirstTopic: pageTopics.contains(where: { $0.id == firstCurrentTopicId }),
                    moreTopicsURL: result.topicList.moreTopicsUrl,
                    pageAddedNewTopicIds: seenTopicIds.count > previousCount
                )
                guard shouldContinue else { break }
                page += 1
            }

            let incomingIds = backgroundTopicUpdateStore.processBackgroundSnapshot(
                latestTopics,
                baseURL: api.baseURL
            )
            if incomingIds != incomingTopicIds {
                incomingTopicIds = incomingIds
                indexUsers(latestUsers)
                indexCategories(latestCategories, source: .topicList)
                notifyChanged()
            }
        } catch is CancellationError {
            // A foreground refresh or a newer detection replaced this poll.
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
            var incomingTopics: [DiscourseTopicList.Topic] = []
            var incomingUsers: [DiscourseTopicList.User] = []
            var incomingCategories: [DiscourseCategory] = []
            for start in stride(from: 0, to: ids.count, by: 100) {
                let end = min(start + 100, ids.count)
                let result = try await api.fetchTopicsByIds(Array(ids[start..<end]))
                try Task.checkCancellation()
                incomingTopics.append(contentsOf: result.topicList.topics)
                incomingUsers.append(contentsOf: result.users ?? [])
                incomingCategories.append(contentsOf: result.categories ?? [])
            }
            if !incomingTopics.isEmpty {
                let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
                incomingTopics.sort { (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max) }
                let incomingIds = Set(incomingTopics.map(\.id))
                let remaining = topics.filter { !incomingIds.contains($0.id) }
                topics = incomingTopics + remaining
                indexUsers(incomingUsers)
                indexCategories(incomingCategories, source: .topicList)
            }
            incomingTopicIds.removeAll()
            if isGlobalLatestList {
                backgroundTopicUpdateStore.replaceForegroundBaseline(
                    topics,
                    baseURL: api.baseURL
                )
            }
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
        hasLoadedFullCategoryMetadata = false
        loggedTopicCategoryIds.removeAll()
        if clearSelection {
            selectedCategoryId = nil
        }
        notifyChanged()
    }

    func restoreBackgroundTopicUpdates() {
        guard isGlobalLatestList else { return }
        let persistedTopicIDs = backgroundTopicUpdateStore.pendingTopicIDs(for: api.baseURL)
        guard persistedTopicIDs != incomingTopicIds else { return }
        incomingTopicIds = persistedTopicIDs
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
        hasLoadedFullCategoryMetadata = false
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
            if page == 0, selectedCategoryId == nil {
                let fetch = try await api.fetchLatestTopicsWithRawData(page: page)
                BackgroundTopicListCache.save(fetch.rawData, baseURL: api.baseURL)
                return fetch.list
            }
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

    private var isGlobalLatestList: Bool {
        listMode == .latest && selectedCategoryId == nil
    }

    private func indexUsers(_ users: [DiscourseTopicList.User]?) {
        guard let users else { return }
        for user in users {
            usersById[user.id] = user
        }
    }

    private func loadCategoriesIfNeeded() async {
        guard canBrowseTopics else { return }
        guard !hasLoadedFullCategoryMetadata else { return }
        let cachedCategories = DiscourseTaxonomySessionStore.categories(for: api.baseURL)
        if !cachedCategories.isEmpty {
            let visibleCategories = cachedCategories.filter { $0.id != 1 }
            categories = DiscourseCategory.hierarchy(fromFlat: visibleCategories)
            indexCategories(visibleCategories, source: .site)
            hasLoadedFullCategoryMetadata = true
            notifyChanged()
            return
        }
        guard DiscourseTaxonomySessionStore.beginRefresh(for: api.baseURL) else {
            let sharedCategories = await DiscourseTaxonomySessionStore.waitForRefresh(for: api.baseURL)
            guard !Task.isCancelled, !sharedCategories.isEmpty else { return }
            let visibleCategories = sharedCategories.filter { $0.id != 1 }
            categories = DiscourseCategory.hierarchy(fromFlat: visibleCategories)
            indexCategories(visibleCategories, source: .site)
            hasLoadedFullCategoryMetadata = true
            notifyChanged()
            return
        }
        defer { DiscourseTaxonomySessionStore.endRefresh(for: api.baseURL) }
        do {
            let siteCategories = (try? await api.fetchSiteCategories()) ?? []
            try Task.checkCancellation()
            if !siteCategories.isEmpty {
                let visibleCategories = siteCategories.filter { $0.id != 1 }
                categories = DiscourseCategory.hierarchy(fromFlat: visibleCategories)
                indexCategories(visibleCategories, source: .site)
                DiscourseTaxonomySessionStore.replace(categories: siteCategories, for: api.baseURL)
                logCategoryMetadata(source: "site", categories: visibleCategories)
            } else {
                let list = try await api.fetchCategories()
                try Task.checkCancellation()
                categories = DiscourseCategory.normalizedTree(fromNested: list.categoryList.categories)
                indexCategories(categories, source: .categoryList)
                DiscourseTaxonomySessionStore.replace(categories: categories, for: api.baseURL)
                logCategoryMetadata(source: "categories", categories: categories)
            }
            hasLoadedFullCategoryMetadata = true
            notifyChanged()
        } catch {
            // Non-critical — cells just won't show category names
            DohDebugLog.record("metadata load failed: \(error.localizedDescription)", subsystem: "Category")
        }
    }

    private func startLoadingCategoriesIfNeeded() {
        guard canBrowseTopics else { return }
        guard !hasLoadedFullCategoryMetadata, categoryMetadataTask == nil else { return }
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
