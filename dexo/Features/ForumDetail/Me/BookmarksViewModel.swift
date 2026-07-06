import Foundation

final class BookmarksViewModel: DexoObservableObject {
    var bookmarks: [DiscourseBookmark] = []
    var isLoading = false
    var errorMessage: String?
    var requiresLogin = false

    private let api: DiscourseAPI
    private var username: String?

    init(api: DiscourseAPI, username: String?) {
        self.api = api
        self.username = username
    }

    func updateUsername(_ username: String?) {
        self.username = username
    }

    func loadBookmarks() async {
        guard let username, !username.isEmpty else {
            bookmarks = []
            isLoading = false
            requiresLogin = true
            errorMessage = String(localized: "login.required.message")
            notifyChanged()
            return
        }

        isLoading = true
        errorMessage = nil
        requiresLogin = false
        notifyChanged()
        do {
            let list = try await api.fetchBookmarks(username: username)
            bookmarks = list.bookmarks
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                requiresLogin = true
            }
            errorMessage = error.localizedDescription
        }
        isLoading = false
        notifyChanged()
    }

    func reload() async {
        bookmarks = []
        errorMessage = nil
        requiresLogin = false
        notifyChanged()
        await loadBookmarks()
    }
}
