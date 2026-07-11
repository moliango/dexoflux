import Foundation

@MainActor
protocol UserProfileContentServicing: AnyObject {
    func fetchUserSummaryResponse(username: String) async throws -> DiscourseUserSummaryResponse
    func fetchUserActions(username: String, filter: String, offset: Int) async throws -> [DiscourseUserAction]
    func fetchUserReactions(username: String, beforeReactionUserId: Int?) async throws -> [DiscourseUserReaction]
}

extension DiscourseAPI: UserProfileContentServicing {}

enum UserProfileSection: Int, CaseIterable {
    case summary
    case activity
    case topics
    case replies
    case likesReceived
    case reactions

    var actionFilter: String? {
        switch self {
        case .activity: return "4,5"
        case .topics: return "4"
        case .replies: return "5"
        case .likesReceived: return "1"
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
        case .reactions: return String(localized: "user.profile.reactions")
        }
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

    init(username: String, service: UserProfileContentServicing) {
        self.username = username
        self.service = service
        super.init()
    }

    func applySummary(_ summary: DiscourseUserSummary?) {
        self.summary = summary
        guard section == .summary else { return }
        rows = makeSummaryRows(summary)
        errorMessage = nil
        canLoadMore = false
        notifyChanged()
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
        isLoadingMore = true
        loadMoreErrorMessage = nil
        notifyChanged()
        do {
            switch section {
            case .reactions:
                let page = try await service.fetchUserReactions(
                    username: username,
                    beforeReactionUserId: reactionCursor
                )
                appendReactions(page)
            case .activity, .topics, .replies, .likesReceived:
                guard let filter = section.actionFilter else { break }
                let page = try await service.fetchUserActions(
                    username: username,
                    filter: filter,
                    offset: actionOffset
                )
                appendActions(page)
            case .summary:
                break
            }
        } catch {
            loadMoreErrorMessage = error.localizedDescription
        }
        isLoadingMore = false
        notifyChanged()
    }

    private func reloadCurrentSection() async {
        actionOffset = 0
        reactionCursor = nil
        errorMessage = nil
        loadMoreErrorMessage = nil
        canLoadMore = false

        if section == .summary {
            rows = makeSummaryRows(summary)
            isLoading = true
            notifyChanged()
            do {
                let response = try await service.fetchUserSummaryResponse(username: username)
                summary = response.userSummary
                rows = makeSummaryRows(response.userSummary)
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
            notifyChanged()
            return
        }

        rows = []
        isLoading = true
        notifyChanged()
        do {
            switch section {
            case .reactions:
                let page = try await service.fetchUserReactions(username: username, beforeReactionUserId: nil)
                appendReactions(page)
            case .activity, .topics, .replies, .likesReceived:
                guard let filter = section.actionFilter else { break }
                let page = try await service.fetchUserActions(username: username, filter: filter, offset: 0)
                appendActions(page)
            case .summary:
                break
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
        notifyChanged()
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
