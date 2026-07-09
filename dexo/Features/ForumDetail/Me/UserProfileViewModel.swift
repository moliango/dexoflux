import Foundation

final class UserProfileViewModel: DexoObservableObject {
    var userProfile: DiscourseUserProfile?
    var summary: DiscourseUserSummary?
    var summaryTopics: [DiscourseUserSummaryTopic] = []
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
            async let summaryTask = api.fetchUserSummaryResponse(username: username)
            let (profile, summaryResponse) = try await (profileTask, summaryTask)
            userProfile = profile
            summary = summaryResponse.userSummary
            summaryTopics = summaryResponse.topics
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        notifyChanged()
    }
}
