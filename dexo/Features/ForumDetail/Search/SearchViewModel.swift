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
    var searchResults: [DiscourseSearchResult.SearchPost] = []
    var isSearching = false
    var canLoadMore = false
    var hasSearched = false
    var errorMessage: String?

    var categories: [DiscourseCategory] = []
    var selectedCategoryId: Int?
    var selectedTag: String?
    var selectedSortOrder: SearchSortOrder = .latest

    private let api: DiscourseAPI
    private var currentPage = 0
    private var currentTerm = ""
    private(set) var categoriesById: [Int: DiscourseCategory] = [:]

    init(api: DiscourseAPI) {
        self.api = api
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

    func search(term: String) async {
        let query = buildQuery(term: term)
        guard !query.isEmpty else {
            searchResults = []
            hasSearched = false
            notifyChanged()
            return
        }

        isSearching = true
        currentTerm = term
        currentPage = 0
        hasSearched = true
        errorMessage = nil
        notifyChanged()

        do {
            let result = try await api.search(term: query, page: 0)
            searchResults = result.posts ?? []
            canLoadMore = result.groupedSearchResult?.morePosts ?? false
        } catch {
            searchResults = []
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
            let result = try await api.search(term: query, page: nextPage)
            let newPosts = result.posts ?? []
            let existingIds = Set(searchResults.map(\.id))
            let filtered = newPosts.filter { !existingIds.contains($0.id) }
            searchResults.append(contentsOf: filtered)
            currentPage = nextPage
            canLoadMore = result.groupedSearchResult?.morePosts ?? false
        } catch {
            canLoadMore = false
        }
        isSearching = false
        notifyChanged()
    }

    private func buildQuery(term: String) -> String {
        var parts: [String] = []
        if !term.isEmpty {
            parts.append(term)
        }
        if let catId = selectedCategoryId, let slug = categoriesById[catId]?.slug {
            parts.append("category:\(slug)")
        }
        if let tag = selectedTag {
            parts.append("tag:\(tag)")
        }
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

    private func parentCategory(for category: DiscourseCategory) -> DiscourseCategory? {
        guard let parentId = category.parentCategoryId else { return nil }
        return categoriesById[parentId]
    }
}
