import Foundation

final class UserProfileViewModel: DexoObservableObject {
    var userProfile: DiscourseUserProfile?
    var userCard: DiscourseUserProfile?
    var summary: DiscourseUserSummary?
    var summaryTopics: [DiscourseUserSummaryTopic] = []
    var isLoading = false
    var errorMessage: String?

    private let api: DiscourseAPI
    let username: String
    let relationshipController: UserRelationshipController

    init(api: DiscourseAPI, username: String) {
        self.api = api
        self.username = username
        relationshipController = UserRelationshipController(username: username, service: api)
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        notifyChanged()
        let cardTask = Task { try await api.fetchUserCard(username: username) }
        let profileTask = Task { try await api.fetchUserProfile(username: username) }
        let summaryTask = Task { try await api.fetchUserSummaryResponse(username: username) }
        do {
            let profile = try await profileTask.value
            let card = (try? await cardTask.value) ?? profile
            let summaryResponse = try? await summaryTask.value
            userProfile = profile
            userCard = card
            relationshipController.apply(profile: card)
            summary = summaryResponse?.userSummary
            summaryTopics = summaryResponse?.topics ?? []
        } catch {
            cardTask.cancel()
            summaryTask.cancel()
            errorMessage = error.localizedDescription
        }
        isLoading = false
        notifyChanged()
    }
}
