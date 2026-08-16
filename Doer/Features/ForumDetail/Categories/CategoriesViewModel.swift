import Foundation

final class CategoriesViewModel: DoerObservableObject {
    var categories: [DiscourseCategory] = []
    var isLoading = false
    var errorMessage: String?
    var requiresLogin = false

    private let api: DiscourseAPI

    init(api: DiscourseAPI) {
        self.api = api
    }

    func loadCategories() async {
        isLoading = true
        errorMessage = nil
        requiresLogin = false
        notifyChanged()
        do {
            let siteCategories = (try? await api.fetchSiteCategories()) ?? []
            if !siteCategories.isEmpty {
                categories = DiscourseCategory.hierarchy(fromFlat: siteCategories.filter { $0.id != 1 })
            } else {
                let result = try await api.fetchCategories()
                categories = DiscourseCategory.normalizedTree(fromNested: result.categoryList.categories)
                    .filter { $0.parentCategoryId == nil }
            }
        } catch {
            if AuthSessionInvalidationPolicy.shouldInvalidateWebSession(error: error, baseURL: api.baseURL) {
                requiresLogin = true
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
        notifyChanged()
    }
}
