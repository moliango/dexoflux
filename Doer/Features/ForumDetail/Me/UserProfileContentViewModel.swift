import Foundation

@MainActor
protocol UserProfileContentServicing: AnyObject {
    func fetchUserSummaryResponse(username: String) async throws -> DiscourseUserSummaryResponse
    func fetchUserActions(username: String, filter: String, offset: Int) async throws -> [DiscourseUserAction]
    func fetchUserReactions(username: String, beforeReactionUserId: Int?) async throws -> [DiscourseUserReaction]
}

extension DiscourseAPI: UserProfileContentServicing {}

enum UserProfileSection: String, CaseIterable, Codable {
    case summary
    case activity
    case topics
    case replies
    case likesReceived
    case likesGiven
    case reactions

    var actionFilter: String? {
        switch self {
        case .activity: return "4,5"
        case .topics: return "4"
        case .replies: return "5"
        case .likesReceived: return "1"
        case .likesGiven: return "2"
        case .summary, .reactions: return nil
        }
    }

    var title: String {
        switch self {
        case .summary: return String(localized: "user.profile.summary")
        case .activity: return String(localized: "user.profile.activity")
        case .topics: return String(localized: "user.topics_title")
        case .replies: return String(localized: "user.profile.replies")
        case .likesReceived: return String(localized: "me.stats.likes")
        case .likesGiven: return String(localized: "me.stats.likes_given")
        case .reactions: return String(localized: "user.profile.reactions")
        }
    }
}

final class UserProfileTabPreferences {
    static let didChangeNotification = Notification.Name("UserProfileTabPreferences.didChange")

    private let storageKey = "user.profile.visible_sections"
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var visibleSections: [UserProfileSection] {
        guard let storedValues = defaults.stringArray(forKey: storageKey) else {
            return UserProfileSection.allCases
        }
        let sections = sanitized(storedValues.compactMap(UserProfileSection.init(rawValue:)))
        return sections.isEmpty ? UserProfileSection.allCases : sections
    }

    func setVisibleSections(_ sections: [UserProfileSection]) {
        let sections = sanitized(sections)
        guard !sections.isEmpty else { return }
        defaults.set(sections.map(\.rawValue), forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    func reset() {
        defaults.removeObject(forKey: storageKey)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    private func sanitized(_ sections: [UserProfileSection]) -> [UserProfileSection] {
        var seen = Set<UserProfileSection>()
        return sections.filter { seen.insert($0).inserted }
    }
}

enum UserProfileContentRow {
    case header(String, String)
    case summaryTopic(DiscourseUserSummaryTopic)
    case summaryReply(DiscourseUserSummaryReply)
    case summaryLink(DiscourseUserSummaryLink)
    case summaryUser(String, DiscourseUserSummaryUser)
    case summaryCategory(DiscourseUserSummaryCategory)
    case summaryBadge(DiscourseBadge)
    case action(DiscourseUserAction)
    case reaction(DiscourseUserReaction)
}

@MainActor
final class UserProfileContentViewModel: DexoObservableObject {
    private(set) var section: UserProfileSection = .summary
    private(set) var rows: [UserProfileContentRow] = []
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = false
    private(set) var errorMessage: String?
    private(set) var loadMoreErrorMessage: String?

    private let username: String
    private let service: UserProfileContentServicing
    private var summary: DiscourseUserSummary?
    private var actionOffset = 0
    private var reactionCursor: Int?
    private var requestGeneration = 0

    var contentGeneration: Int {
        requestGeneration
    }

    init(
        username: String,
        service: UserProfileContentServicing,
        initialSection: UserProfileSection = .summary
    ) {
        self.username = username
        self.service = service
        section = initialSection
        super.init()
    }

    @discardableResult
    func applySummary(_ summary: DiscourseUserSummary?, ifGeneration generation: Int) -> Bool {
        guard generation == requestGeneration, section == .summary else { return false }
        self.summary = summary
        rows = makeSummaryRows(summary)
        errorMessage = nil
        canLoadMore = false
        notifyChanged()
        return true
    }

    func select(_ section: UserProfileSection) async {
        self.section = section
        await reloadCurrentSection()
    }

    func refresh() async {
        await reloadCurrentSection()
    }

    func loadMoreIfNeeded(currentIndex: Int) async {
        guard currentIndex >= rows.count - 4 else { return }
        await loadMore()
    }

    func loadMore() async {
        guard canLoadMore, !isLoading, !isLoadingMore, section != .summary else { return }
        let generation = requestGeneration
        let requestedSection = section
        let requestedActionOffset = actionOffset
        let requestedReactionCursor = reactionCursor
        isLoadingMore = true
        loadMoreErrorMessage = nil
        notifyChanged()
        do {
            switch requestedSection {
            case .reactions:
                let page = try await service.fetchUserReactions(
                    username: username,
                    beforeReactionUserId: requestedReactionCursor
                )
                guard isCurrentRequest(generation, section: requestedSection) else { return }
                appendReactions(page)
            case .activity, .topics, .replies, .likesReceived, .likesGiven:
                guard let filter = requestedSection.actionFilter else { break }
                let page = try await service.fetchUserActions(
                    username: username,
                    filter: filter,
                    offset: requestedActionOffset
                )
                guard isCurrentRequest(generation, section: requestedSection) else { return }
                appendActions(page)
            case .summary:
                break
            }
        } catch {
            guard isCurrentRequest(generation, section: requestedSection) else { return }
            loadMoreErrorMessage = error.localizedDescription
        }
        guard isCurrentRequest(generation, section: requestedSection) else { return }
        isLoadingMore = false
        notifyChanged()
    }

    private func reloadCurrentSection() async {
        requestGeneration += 1
        let generation = requestGeneration
        let requestedSection = section
        actionOffset = 0
        reactionCursor = nil
        errorMessage = nil
        loadMoreErrorMessage = nil
        canLoadMore = false
        isLoadingMore = false

        if requestedSection == .summary {
            rows = makeSummaryRows(summary)
            isLoading = true
            notifyChanged()
            do {
                let response = try await service.fetchUserSummaryResponse(username: username)
                guard isCurrentRequest(generation, section: requestedSection) else { return }
                summary = response.userSummary
                rows = makeSummaryRows(response.userSummary)
            } catch {
                guard isCurrentRequest(generation, section: requestedSection) else { return }
                errorMessage = error.localizedDescription
            }
            guard isCurrentRequest(generation, section: requestedSection) else { return }
            isLoading = false
            notifyChanged()
            return
        }

        rows = []
        isLoading = true
        notifyChanged()
        do {
            switch requestedSection {
            case .reactions:
                let page = try await service.fetchUserReactions(username: username, beforeReactionUserId: nil)
                guard isCurrentRequest(generation, section: requestedSection) else { return }
                appendReactions(page)
            case .activity, .topics, .replies, .likesReceived, .likesGiven:
                guard let filter = requestedSection.actionFilter else { break }
                let page = try await service.fetchUserActions(username: username, filter: filter, offset: 0)
                guard isCurrentRequest(generation, section: requestedSection) else { return }
                appendActions(page)
            case .summary:
                break
            }
        } catch {
            guard isCurrentRequest(generation, section: requestedSection) else { return }
            errorMessage = error.localizedDescription
        }
        guard isCurrentRequest(generation, section: requestedSection) else { return }
        isLoading = false
        notifyChanged()
    }

    private func isCurrentRequest(_ generation: Int, section requestedSection: UserProfileSection) -> Bool {
        generation == requestGeneration && requestedSection == section
    }

    private func appendActions(_ page: [DiscourseUserAction]) {
        var seen = Set(rows.compactMap { row -> String? in
            guard case .action(let action) = row else { return nil }
            return action.id
        })
        let uniquePage = page.filter { seen.insert($0.id).inserted }
        rows.append(contentsOf: uniquePage.map(UserProfileContentRow.action))
        actionOffset += page.count
        canLoadMore = !page.isEmpty
    }

    private func appendReactions(_ page: [DiscourseUserReaction]) {
        var seen = Set(rows.compactMap { row -> Int? in
            guard case .reaction(let reaction) = row else { return nil }
            return reaction.id
        })
        let uniquePage = page.filter { seen.insert($0.id).inserted }
        rows.append(contentsOf: uniquePage.map(UserProfileContentRow.reaction))
        reactionCursor = page.last?.id
        canLoadMore = !page.isEmpty
    }

    private func makeSummaryRows(_ summary: DiscourseUserSummary?) -> [UserProfileContentRow] {
        guard let summary else { return [] }
        var result: [UserProfileContentRow] = []

        appendSection(
            title: String(localized: "user.profile.top_topics"),
            symbol: "list.bullet.rectangle",
            rows: summary.topics.map(UserProfileContentRow.summaryTopic),
            to: &result
        )
        appendSection(
            title: String(localized: "user.profile.top_replies", defaultValue: "Top replies"),
            symbol: "quote.bubble",
            rows: summary.replies.map(UserProfileContentRow.summaryReply),
            to: &result
        )
        appendSection(
            title: String(localized: "user.profile.top_links", defaultValue: "Top links"),
            symbol: "link",
            rows: summary.links.map(UserProfileContentRow.summaryLink),
            to: &result
        )
        appendSection(
            title: String(localized: "user.profile.interactions", defaultValue: "Frequent interactions"),
            symbol: "person.2",
            rows: summary.mostRepliedToUsers.map {
                UserProfileContentRow.summaryUser(
                    String(localized: "user.profile.replied_to", defaultValue: "Replied to"),
                    $0
                )
            },
            to: &result
        )
        appendSection(
            title: String(localized: "user.profile.most_liked_by", defaultValue: "Most liked by"),
            symbol: "heart.circle",
            rows: summary.mostLikedByUsers.map {
                UserProfileContentRow.summaryUser(
                    String(localized: "user.profile.liked_by", defaultValue: "Liked by"),
                    $0
                )
            },
            to: &result
        )
        appendSection(
            title: String(localized: "user.profile.most_liked", defaultValue: "Most liked"),
            symbol: "hand.thumbsup",
            rows: summary.mostLikedUsers.map {
                UserProfileContentRow.summaryUser(
                    String(localized: "user.profile.liked", defaultValue: "Liked"),
                    $0
                )
            },
            to: &result
        )
        appendSection(
            title: String(localized: "user.profile.top_categories", defaultValue: "Top categories"),
            symbol: "square.grid.2x2",
            rows: summary.topCategories.map(UserProfileContentRow.summaryCategory),
            to: &result
        )
        appendSection(
            title: String(localized: "me.badges"),
            symbol: "medal",
            rows: summary.badges.map(UserProfileContentRow.summaryBadge),
            to: &result
        )
        return result
    }

    private func appendSection(
        title: String,
        symbol: String,
        rows: [UserProfileContentRow],
        to result: inout [UserProfileContentRow]
    ) {
        guard !rows.isEmpty else { return }
        result.append(.header(title, symbol))
        result.append(contentsOf: rows)
    }
}
