import Foundation

final class MeViewModel: DexoObservableObject {
    var currentUser: DiscourseCurrentUser?
    var userProfile: DiscourseUserProfile?
    var summary: DiscourseUserSummary?
    var isLoading = false
    var requiresLogin = false
    var errorMessage: String?

    private let api: DiscourseAPI

    init(api: DiscourseAPI) {
        self.api = api
    }

    func loadProfile() async {
        isLoading = true
        errorMessage = nil
        notifyChanged()
        do {
            let username = AuthManager.shared.username(for: api.baseURL) ?? ""
            async let profileTask = api.fetchUserProfile(username: username)
            currentUser = await DiscourseCurrentUser(id: profileTask.id, username: profileTask.username, name: profileTask.name, avatarTemplate: profileTask.avatarTemplate)
            async let summaryTask = api.fetchUserSummary(username: username)
            let (profile, userSummary) = try await (profileTask, summaryTask)
            userProfile = profile
            summary = userSummary
        } catch {
            if let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn || apiError.isForbidden {
                requiresLogin = true
            } else {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false
        notifyChanged()
    }

    func reload() async {
        requiresLogin = false
        errorMessage = nil
        currentUser = nil
        userProfile = nil
        summary = nil
        notifyChanged()
        await loadProfile()
    }
}
