import Foundation

final class UserProfileViewModel: DexoObservableObject {
    var userProfile: DiscourseUserProfile?
    var summary: DiscourseUserSummary?
    var isLoading = false
    var errorMessage: String?

    private let api: DiscourseAPI
    let username: String

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.username = username
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        notifyChanged()
        do {
            async let profileTask = api.fetchUserProfile(username: username)
            async let summaryTask = api.fetchUserSummary(username: username)
            let (profile, userSummary) = try await (profileTask, summaryTask)
            userProfile = profile
            summary = userSummary
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        notifyChanged()
    }
}
