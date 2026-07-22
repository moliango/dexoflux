import Foundation

enum SearchSortOrder: String, CaseIterable {
    case relevance
    case latest
    case likes
    case views
    case latestTopic = "latest_topic"

    var displayName: String {
        switch self {
        case .relevance: String(localized: "search.sort.relevance")
        case .latest: String(localized: "search.sort.latest")
        case .likes: String(localized: "search.sort.most_likes")
        case .views: String(localized: "search.sort.most_views")
        case .latestTopic: String(localized: "search.sort.latest_topic")
        }
    }
}

final class SearchViewModel: DexoObservableObject {
    private static let sortOrderDefaultsKey = "search.sort_order"

    var searchResults: [DiscourseSearchResult.SearchPost] = []
    var userResults: [DiscourseSearchResult.SearchUser] = []
    /// AI 语义搜索命中的 topicId（用于结果行的 AI 徽标）。
    private(set) var aiTopicIds: Set<Int> = []
    var isSearching = false
    var canLoadMore = false
    var hasSearched = false
    var errorMessage: String?

    var recentSearches: [String] = []

    var categories: [DiscourseCategory] = []
    var selectedCategoryId: Int?
    var advancedFilter = SearchAdvancedFilter()

    // 排序跨会话持久化（FluxDo 将其存在 search settings 中）。
    var selectedSortOrder: SearchSortOrder {
        didSet {
            UserDefaults.standard.set(selectedSortOrder.rawValue, forKey: Self.sortOrderDefaultsKey)
        }
    }

    private let api: DiscourseAPI
    private var currentPage = 0
    private var currentTerm = ""
    private(set) var categoriesById: [Int: DiscourseCategory] = [:]

    // AI 语义搜索：站点不支持时（403/404 等）本会话内静默停用。
    private var aiSearchUnavailable = false
    private var standardPosts: [DiscourseSearchResult.SearchPost] = []
    private var aiPosts: [DiscourseSearchResult.SearchPost] = []
    private var aiSearchTask: Task<Void, Never>?
    private var searchGeneration = 0

    init(api: DiscourseAPI) {
        self.api = api
        selectedSortOrder = UserDefaults.standard.string(forKey: Self.sortOrderDefaultsKey)
            .flatMap(SearchSortOrder.init(rawValue:)) ?? .relevance
    }

    func selectedCategory() -> DiscourseCategory? {
        guard let id = selectedCategoryId else { return nil }
        return categoriesById[id]
    }

    func categoryDisplayName(for category: DiscourseCategory?) -> String? {
        guard let category else { return nil }
        let resolved = categoriesById[category.id] ?? category
        return resolved.displayName(parent: parentCategory(for: resolved))
    }

    func loadCategories() async {
        do {
            categoriesById.removeAll()
            let siteCategories = (try? await api.fetchSiteCategories()) ?? []
            if !siteCategories.isEmpty {
                let visibleCategories = siteCategories.filter { $0.id != 1 }
                categories = DiscourseCategory.hierarchy(fromFlat: visibleCategories)
                indexCategories(visibleCategories)
            } else {
                let catList = try await api.fetchCategories()
                categories = DiscourseCategory.normalizedTree(fromNested: catList.categoryList.categories)
                indexCategories(categories)
            }
            notifyChanged()
        } catch {}
    }

    // MARK: - Recent searches (server-side, FluxDo parity)

    func loadRecentSearches() async {
        recentSearches = (try? await api.fetchRecentSearches()) ?? []
        notifyChanged()
    }

    func clearRecentSearches() async {
        try? await api.clearRecentSearches()
        recentSearches = []
        notifyChanged()
    }

    // MARK: - Search

    func search(term: String) async {
        let query = buildQuery(term: term)
        guard !query.isEmpty else {
            searchResults = []
            userResults = []
            hasSearched = false
            notifyChanged()
            return
        }

        isSearching = true
        currentTerm = term
        currentPage = 0
        hasSearched = true
        errorMessage = nil
        searchGeneration += 1
        aiPosts = []
        aiTopicIds = []
        notifyChanged()

        triggerAISearchIfNeeded(term: term, generation: searchGeneration)

        do {
            let result = try await api.search(term: query, page: 1, typeFilter: "topic")
            standardPosts = uniqueTopics(from: result.posts ?? [])
            userResults = result.users ?? []
            currentPage = 1
            canLoadMore = result.groupedSearchResult?.morePosts
                ?? result.groupedSearchResult?.moreFullPageResults
                ?? false
            rebuildDisplayPosts()
        } catch {
            standardPosts = []
            searchResults = []
            userResults = []
            canLoadMore = false
            errorMessage = error.localizedDescription
        }
        isSearching = false
        notifyChanged()
    }

    func loadMoreResults() async {
        guard canLoadMore, !isSearching else { return }
        isSearching = true
        notifyChanged()
        let nextPage = currentPage + 1
        let query = buildQuery(term: currentTerm)

        do {
            let result = try await api.search(term: query, page: nextPage, typeFilter: "topic")
            let newPosts = uniqueTopics(from: result.posts ?? [])
            let existingTopicIds = Set(standardPosts.map(\.topicId))
            standardPosts.append(contentsOf: newPosts.filter { !existingTopicIds.contains($0.topicId) })
            currentPage = nextPage
            canLoadMore = result.groupedSearchResult?.morePosts
                ?? result.groupedSearchResult?.moreFullPageResults
                ?? false
            rebuildDisplayPosts()
        } catch {
            canLoadMore = false
        }
        isSearching = false
        notifyChanged()
    }

    // MARK: - AI semantic search (RRF merge, FluxDo/Discourse parity)

    private func triggerAISearchIfNeeded(term: String, generation: Int) {
        aiSearchTask?.cancel()
        guard !aiSearchUnavailable, selectedSortOrder == .relevance else { return }
        aiSearchTask = Task { [weak self] in
            guard let self else { return }
            do {
                let result = try await api.semanticSearch(term: term)
                guard !Task.isCancelled, generation == searchGeneration else { return }
                aiPosts = uniqueTopics(from: result.posts ?? [])
                rebuildDisplayPosts()
                notifyChanged()
            } catch {
                guard !Task.isCancelled else { return }
                // 站点未启用 discourse-ai：静默停用，避免每次搜索都白打一发。
                // 其他错误（超时、HTML 404 解码失败等）按 FluxDo 行为逐次静默忽略。
                if let apiError = error as? DiscourseAPIError,
                   apiError.isForbidden || apiError.errorType == "not_found" {
                    aiSearchUnavailable = true
                }
            }
        }
    }

    /// RRF（Reciprocal Rank Fusion，k=5，与 Discourse 前端一致）融合标准与 AI 结果。
    private func rebuildDisplayPosts() {
        aiTopicIds = Set(aiPosts.map(\.topicId)).subtracting(standardPosts.map(\.topicId))
        guard selectedSortOrder == .relevance, !aiPosts.isEmpty else {
            searchResults = standardPosts
            return
        }
        guard !standardPosts.isEmpty else {
            searchResults = aiPosts
            return
        }

        let k = 5.0
        var scores: [Int: Double] = [:]
        var postsByTopic: [Int: DiscourseSearchResult.SearchPost] = [:]

        for (index, post) in standardPosts.enumerated() {
            scores[post.topicId] = 1.0 / (Double(index) + k)
            postsByTopic[post.topicId] = post
        }
        for (index, post) in aiPosts.enumerated() {
            let score = 1.0 / (Double(index) + k)
            if let existing = scores[post.topicId] {
                scores[post.topicId] = existing + score
            } else {
                scores[post.topicId] = score
                postsByTopic[post.topicId] = post
            }
        }

        searchResults = scores
            .sorted { $0.value > $1.value }
            .compactMap { postsByTopic[$0.key] }
    }

    private func buildQuery(term: String) -> String {
        var parts: [String] = []
        if !term.isEmpty {
            parts.append(term)
        }
        if let catId = selectedCategoryId, let slug = categoriesById[catId]?.slug {
            parts.append("category:\(slug)")
        }
        parts.append(contentsOf: advancedFilter.queryParts())
        if selectedSortOrder != .relevance {
            parts.append("order:\(selectedSortOrder.rawValue)")
        }
        return parts.joined(separator: " ")
    }

    private func indexCategories(_ categories: [DiscourseCategory]) {
        let indexed = DiscourseCategory.indexedById(from: categories)
        for (id, category) in indexed {
            categoriesById[id] = category
        }
    }

    private func uniqueTopics(from posts: [DiscourseSearchResult.SearchPost]) -> [DiscourseSearchResult.SearchPost] {
        var seen = Set<Int>()
        return posts.filter { post in
            post.topicId > 0 && seen.insert(post.topicId).inserted
        }
    }

    private func parentCategory(for category: DiscourseCategory) -> DiscourseCategory? {
        guard let parentId = category.parentCategoryId else { return nil }
        return categoriesById[parentId]
    }
}
