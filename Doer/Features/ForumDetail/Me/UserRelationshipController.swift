import Foundation

@MainActor
protocol UserRelationshipServicing: AnyObject {
    func followUser(username: String) async throws
    func unfollowUser(username: String) async throws
    func updateUserNotificationLevel(username: String, level: String, expiringAt: Date?) async throws
}

extension DiscourseAPI: UserRelationshipServicing {}

enum UserRelationshipMutation: Equatable {
    case toggleFollow
    case mute
    case ignore(until: Date)
    case restore
}

@MainActor
final class UserRelationshipController: DexoObservableObject {
    struct State: Equatable {
        var isFollowed = false
        var isMuted = false
        var isIgnored = false
        var canFollow = false
        var canSendPrivateMessage = false
        var canMute = false
        var canIgnore = false
        var isMutating = false
        var errorMessage: String?
    }

    private(set) var state = State()

    let username: String
    private let service: UserRelationshipServicing

    init(username: String, service: UserRelationshipServicing) {
        self.username = username
        self.service = service
        super.init()
    }

    func apply(profile: DiscourseUserProfile) {
        state.isFollowed = profile.isFollowed ?? false
        state.isMuted = profile.muted ?? false
        state.isIgnored = profile.ignored ?? false
        state.canFollow = profile.canFollow ?? false
        state.canSendPrivateMessage = profile.canSendPrivateMessageToUser
            ?? profile.canSendPrivateMessages
            ?? false
        state.canMute = profile.canMuteUser ?? false
        state.canIgnore = profile.canIgnoreUser ?? false
        state.errorMessage = nil
        notifyChanged()
    }

    func perform(_ mutation: UserRelationshipMutation) async {
        guard !state.isMutating, isAllowed(mutation) else { return }

        let previous = state
        state.isMutating = true
        state.errorMessage = nil
        applyOptimistic(mutation)
        notifyChanged()

        do {
            try await send(mutation, previous: previous)
            state.isMutating = false
        } catch {
            state = previous
            state.isMutating = false
            state.errorMessage = error.localizedDescription
        }
        notifyChanged()
    }

    func clearError() {
        guard state.errorMessage != nil else { return }
        state.errorMessage = nil
        notifyChanged()
    }

    private func isAllowed(_ mutation: UserRelationshipMutation) -> Bool {
        switch mutation {
        case .toggleFollow:
            return state.canFollow
        case .mute:
            return state.canMute
        case .ignore:
            return state.canIgnore
        case .restore:
            return state.isMuted || state.isIgnored
        }
    }

    private func applyOptimistic(_ mutation: UserRelationshipMutation) {
        switch mutation {
        case .toggleFollow:
            state.isFollowed.toggle()
        case .mute:
            state.isMuted = true
            state.isIgnored = false
        case .ignore:
            state.isMuted = false
            state.isIgnored = true
        case .restore:
            state.isMuted = false
            state.isIgnored = false
        }
    }

    private func send(_ mutation: UserRelationshipMutation, previous: State) async throws {
        switch mutation {
        case .toggleFollow:
            if previous.isFollowed {
                try await service.unfollowUser(username: username)
            } else {
                try await service.followUser(username: username)
            }
        case .mute:
            try await service.updateUserNotificationLevel(username: username, level: "mute", expiringAt: nil)
        case .ignore(let expiry):
            try await service.updateUserNotificationLevel(username: username, level: "ignore", expiringAt: expiry)
        case .restore:
            try await service.updateUserNotificationLevel(username: username, level: "normal", expiringAt: nil)
        }
    }
}
