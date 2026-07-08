import Foundation
import UIKit

struct DiscourseCurrentUserResponse: Decodable {
    let currentUser: DiscourseCurrentUser?

    enum CodingKeys: String, CodingKey {
        case currentUser = "current_user"
    }
}

struct DiscourseCurrentUser: Codable {
    let id: Int
    let username: String
    let name: String?
    let avatarTemplate: String?

    enum CodingKeys: String, CodingKey {
        case id, username, name
        case avatarTemplate = "avatar_template"
    }
}

struct DiscourseUserProfileResponse: Decodable {
    let user: DiscourseUserProfile
}

struct DiscourseUserProfile: Codable {
    let id: Int
    let username: String
    let name: String?
    let avatarTemplate: String?
    let title: String?
    let trustLevel: Int?
    let badgeCount: Int?
    let profileViewCount: Int?
    let timeRead: Int?
    let createdAt: String?
    let bioExcerpt: String?
    let flairName: String?
    let flairUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, username, name, title
        case avatarTemplate = "avatar_template"
        case trustLevel = "trust_level"
        case badgeCount = "badge_count"
        case profileViewCount = "profile_view_count"
        case timeRead = "time_read"
        case createdAt = "created_at"
        case bioExcerpt = "bio_excerpt"
        case flairName = "flair_name"
        case flairUrl = "flair_url"
    }
}

struct DiscourseUserBadgesResponse: Decodable {
    let userBadges: [DiscourseUserBadge]

    enum CodingKeys: String, CodingKey {
        case badges
        case userBadges = "user_badges"
        case topics
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let badges = try container.decodeIfPresent([DiscourseBadge].self, forKey: .badges) ?? []
        let badgeMap = Dictionary(uniqueKeysWithValues: badges.map { ($0.id, $0) })

        let topics = try container.decodeIfPresent([BadgeTopic].self, forKey: .topics) ?? []
        let topicMap = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0.title) })

        let rawBadges = try container.decodeIfPresent([RawUserBadge].self, forKey: .userBadges) ?? []
        userBadges = rawBadges.map { raw in
            DiscourseUserBadge(
                id: raw.id,
                badgeId: raw.badgeId,
                grantedAt: raw.grantedAt,
                topicId: raw.topicId,
                topicTitle: raw.topicTitle ?? raw.topicId.flatMap { topicMap[$0] },
                count: raw.count,
                badge: raw.badge ?? badgeMap[raw.badgeId]
            )
        }
    }

    private struct BadgeTopic: Decodable {
        let id: Int
        let title: String
    }

    private struct RawUserBadge: Decodable {
        let id: Int
        let badgeId: Int
        let grantedAt: String?
        let topicId: Int?
        let topicTitle: String?
        let count: Int
        let badge: DiscourseBadge?

        enum CodingKeys: String, CodingKey {
            case id
            case badgeId = "badge_id"
            case grantedAt = "granted_at"
            case topicId = "topic_id"
            case topicTitle = "topic_title"
            case count
            case badge
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = (try? container.decode(Int.self, forKey: .id)) ?? 0
            badgeId = (try? container.decode(Int.self, forKey: .badgeId)) ?? 0
            grantedAt = try container.decodeIfPresent(String.self, forKey: .grantedAt)
            topicId = try container.decodeIfPresent(Int.self, forKey: .topicId)
            topicTitle = try container.decodeIfPresent(String.self, forKey: .topicTitle)
            count = (try? container.decode(Int.self, forKey: .count)) ?? 1
            badge = try container.decodeIfPresent(DiscourseBadge.self, forKey: .badge)
        }
    }
}

struct DiscourseBadge: Decodable {
    let id: Int
    let name: String
    let description: String?
    let badgeTypeId: Int
    let imageURL: String?
    let icon: String?
    let slug: String?

    enum CodingKeys: String, CodingKey {
        case id, name, description, icon, slug
        case badgeTypeId = "badge_type_id"
        case imageURL = "image_url"
    }

    var type: BadgeType {
        BadgeType(rawValue: badgeTypeId) ?? .bronze
    }

    enum BadgeType: Int {
        case gold = 1
        case silver = 2
        case bronze = 3

        var title: String {
            switch self {
            case .gold: return String(localized: "badges.gold")
            case .silver: return String(localized: "badges.silver")
            case .bronze: return String(localized: "badges.bronze")
            }
        }

        var color: UIColor {
            switch self {
            case .gold: return .systemYellow
            case .silver: return .systemGray
            case .bronze: return .systemOrange
            }
        }
    }
}

struct DiscourseUserBadge: Identifiable {
    let id: Int
    let badgeId: Int
    let grantedAt: String?
    let topicId: Int?
    let topicTitle: String?
    let count: Int
    let badge: DiscourseBadge?
}

struct DiscoursePendingInvitesResponse: Decodable {
    let invites: [DiscourseInviteLink]

    enum CodingKeys: String, CodingKey {
        case invites
        case pendingInvites = "pending_invites"
        case invited
        case pending
    }

    init(from decoder: Decoder) throws {
        if let array = try? [DiscourseInviteLink].init(from: decoder) {
            invites = array
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let decoded = try? container.decode([DiscourseInviteLink].self, forKey: .invites) {
            invites = decoded
        } else if let decoded = try? container.decode([DiscourseInviteLink].self, forKey: .pendingInvites) {
            invites = decoded
        } else if let decoded = try? container.decode([DiscourseInviteLink].self, forKey: .invited) {
            invites = decoded
        } else if let decoded = try? container.decode([DiscourseInviteLink].self, forKey: .pending) {
            invites = decoded
        } else {
            invites = []
        }
    }
}

struct DiscourseInviteLink: Decodable, Identifiable {
    let id: Int
    let inviteKey: String?
    let inviteLink: String?
    let description: String?
    let createdAt: String?
    let expiresAt: String?

    enum CodingKeys: String, CodingKey {
        case id
        case invite
        case inviteKey = "invite_key"
        case inviteLink = "invite_link"
        case inviteURL = "invite_url"
        case url
        case link
        case description
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let nested = try container.decodeIfPresent(NestedInvite.self, forKey: .invite)

        let decodedInviteKey = try? container.decode(String.self, forKey: .inviteKey)
        let decodedInviteLink = try? container.decode(String.self, forKey: .inviteLink)
        let decodedInviteURL = try? container.decode(String.self, forKey: .inviteURL)
        let decodedURL = try? container.decode(String.self, forKey: .url)
        let decodedLink = try? container.decode(String.self, forKey: .link)
        let decodedDescription = try? container.decode(String.self, forKey: .description)
        let decodedCreatedAt = try? container.decode(String.self, forKey: .createdAt)
        let decodedExpiresAt = try? container.decode(String.self, forKey: .expiresAt)
        let decodedId = try? container.decode(Int.self, forKey: .id)

        inviteKey = decodedInviteKey ?? nested?.inviteKey
        inviteLink = decodedInviteLink ?? decodedInviteURL ?? decodedURL ?? decodedLink ?? nested?.inviteLink
        description = decodedDescription ?? nested?.description
        createdAt = decodedCreatedAt ?? nested?.createdAt
        expiresAt = decodedExpiresAt ?? nested?.expiresAt
        id = decodedId ?? nested?.id ?? Self.stableId(inviteKey ?? inviteLink ?? description ?? "")
    }

    var effectiveURLString: String? {
        if let inviteLink, !inviteLink.isEmpty {
            return inviteLink
        }
        if let inviteKey, !inviteKey.isEmpty {
            return "https://linux.do/invites/\(inviteKey)"
        }
        return nil
    }

    private struct NestedInvite: Decodable {
        let id: Int?
        let inviteKey: String?
        let inviteLink: String?
        let description: String?
        let createdAt: String?
        let expiresAt: String?

        enum CodingKeys: String, CodingKey {
            case id
            case inviteKey = "invite_key"
            case inviteLink = "invite_link"
            case description
            case createdAt = "created_at"
            case expiresAt = "expires_at"
        }
    }

    private static func stableId(_ value: String) -> Int {
        let hash = value.unicodeScalars.reduce(UInt64(5381)) { (($0 << 5) &+ $0) &+ UInt64($1.value) }
        return Int(hash % UInt64(Int.max))
    }
}
