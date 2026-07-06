import Foundation

final class UserPostsViewModel: DexoObservableObject {
    enum Filter {
        case topics
        case posts
    }

    var searchResults: [DiscourseSearchResult.SearchPost] = []
    var isLoading = false
    var canLoadMore = false
    var errorMessage: String?

    private let api: DiscourseAPI
    private let username: String
    private let filter: Filter
    private var currentPage = 0

    init(api: DiscourseAPI, username: String, filter: Filter) {
        self.api = api
        self.username = username
        self.filter = filter
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        currentPage = 0
        notifyChanged()

        let query = buildQuery()
        do {
            let result = try await api.search(term: query, page: 0)
            searchResults = result.posts ?? []
            canLoadMore = result.groupedSearchResult?.morePosts ?? false
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        notifyChanged()
    }

    func loadMore() async {
        guard canLoadMore, !isLoading else { return }
        isLoading = true
        notifyChanged()
        let nextPage = currentPage + 1
        let query = buildQuery()

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
        isLoading = false
        notifyChanged()
    }

    private func buildQuery() -> String {
        switch filter {
        case .topics:
            return "@\(username) in:first order:latest"
        case .posts:
            return "@\(username) order:latest"
        }
    }
}
