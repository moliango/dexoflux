import Foundation

struct DiscourseTopicDetail: Decodable {
    let id: Int
    let title: String
    let fancyTitle: String?
    let postsCount: Int
    let replyCount: Int
    let views: Int
    let categoryId: Int?
    let createdAt: String
    let tags: [Tag]
    var postStream: PostStream
    let validReactions: [String]
    let bookmarked: Bool
    let bookmarkId: Int?

    enum CodingKeys: String, CodingKey {
        case id, title, tags, bookmarked, views
        case fancyTitle = "fancy_title"
        case postsCount = "posts_count"
        case replyCount = "reply_count"
        case categoryId = "category_id"
        case createdAt = "created_at"
        case postStream = "post_stream"
        case validReactions = "valid_reactions"
        case bookmarkId = "bookmark_id"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        fancyTitle = try? container.decodeIfPresent(String.self, forKey: .fancyTitle)
        postsCount = try container.decode(Int.self, forKey: .postsCount)
        replyCount = try container.decode(Int.self, forKey: .replyCount)
        views = container.decodeLossyInt(forKey: .views) ?? 0
        categoryId = try? container.decodeIfPresent(Int.self, forKey: .categoryId)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        tags = (try? container.decodeIfPresent([Tag].self, forKey: .tags)) ?? []
        postStream = try container.decode(PostStream.self, forKey: .postStream)
        validReactions = (try? container.decodeIfPresent([String].self, forKey: .validReactions)) ?? []
        bookmarked = (try? container.decodeIfPresent(Bool.self, forKey: .bookmarked)) ?? false
        bookmarkId = try? container.decodeIfPresent(Int.self, forKey: .bookmarkId)
    }

    struct PostStream: Decodable {
        var posts: [Post]
        let stream: [Int]?
    }

    struct Tag: Decodable {
        let id: Int
        let name: String
        let slug: String
    }

    struct ReplyToUser: Decodable {
        let username: String
        let avatarTemplate: String?

        enum CodingKeys: String, CodingKey {
            case username
            case avatarTemplate = "avatar_template"
        }
    }

    struct Reaction: Decodable {
        let id: String
        let type: String
        let count: Int

        enum CodingKeys: String, CodingKey {
            case id
            case name
            case type
            case count
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = ((try? container.decodeIfPresent(String.self, forKey: .id))
                ?? (try? container.decodeIfPresent(String.self, forKey: .name))
                ?? "")
            type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? "emoji"
            count = container.decodeLossyInt(forKey: .count) ?? 0
        }
    }

    struct LinkCount: Decodable, Hashable {
        let url: String
        let title: String?
        let clicks: Int
        let internalLink: Bool
        let reflection: Bool

        enum CodingKeys: String, CodingKey {
            case url, title, clicks, reflection
            case internalLink = "internal"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            url = (try? container.decodeIfPresent(String.self, forKey: .url)) ?? ""
            title = (try? container.decodeIfPresent(String.self, forKey: .title))
                .flatMap { $0.isEmpty ? nil : $0 }
            clicks = container.decodeLossyInt(forKey: .clicks) ?? 0
            internalLink = (try? container.decodeIfPresent(Bool.self, forKey: .internalLink)) ?? false
            reflection = (try? container.decodeIfPresent(Bool.self, forKey: .reflection)) ?? false
        }
    }

    struct BoostUser: Decodable, Hashable {
        let id: Int
        let username: String
        let name: String?
        let avatarTemplate: String?

        enum CodingKeys: String, CodingKey {
            case id, username, name
            case avatarTemplate = "avatar_template"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.decodeLossyInt(forKey: .id) ?? 0
            username = (try? container.decodeIfPresent(String.self, forKey: .username)) ?? ""
            name = (try? container.decodeIfPresent(String.self, forKey: .name))
                .flatMap { $0.isEmpty ? nil : $0 }
            avatarTemplate = (try? container.decodeIfPresent(String.self, forKey: .avatarTemplate))
                .flatMap { $0.isEmpty ? nil : $0 }
        }

        init(id: Int, username: String, name: String?, avatarTemplate: String?) {
            self.id = id
            self.username = username
            self.name = name
            self.avatarTemplate = avatarTemplate
        }
    }

    struct Boost: Decodable, Identifiable, Hashable {
        let id: Int
        let cooked: String
        let user: BoostUser
        let canDelete: Bool
        let canFlag: Bool

        enum CodingKeys: String, CodingKey {
            case id, cooked, user
            case canDelete = "can_delete"
            case canFlag = "can_flag"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = container.decodeLossyInt(forKey: .id) ?? 0
            cooked = (try? container.decodeIfPresent(String.self, forKey: .cooked)) ?? ""
            user = (try? container.decodeIfPresent(BoostUser.self, forKey: .user))
                ?? BoostUser(id: 0, username: "", name: nil, avatarTemplate: nil)
            canDelete = (try? container.decodeIfPresent(Bool.self, forKey: .canDelete)) ?? false
            canFlag = (try? container.decodeIfPresent(Bool.self, forKey: .canFlag)) ?? false
        }

        init(id: Int, cooked: String, user: BoostUser, canDelete: Bool, canFlag: Bool) {
            self.id = id
            self.cooked = cooked
            self.user = user
            self.canDelete = canDelete
            self.canFlag = canFlag
        }
    }

    struct Post: Decodable, Identifiable {
        let id: Int
        let name: String?
        let username: String
        let avatarTemplate: String?
        let createdAt: String
        let cooked: String
        let postNumber: Int
        let replyCount: Int
        let replyToPostNumber: Int?
        let replyToUser: ReplyToUser?
        let actionCode: String?
        let userTitle: String?
        let flairUrl: String?
        let flairBgColor: String?
        var bookmarked: Bool
        var bookmarkId: Int?
        var reactions: [Reaction]
        var reactionUsersCount: Int
        var currentUserReaction: Reaction?
        var currentUserUsedMainReaction: Bool
        let linkCounts: [LinkCount]
        let polls: [DiscoursePollVoteResponse.Poll]
        let pollsVotes: [String: [String]]
        var boosts: [Boost]
        var canBoost: Bool

        enum CodingKeys: String, CodingKey {
            case id, name, username, cooked
            case avatarTemplate = "avatar_template"
            case createdAt = "created_at"
            case postNumber = "post_number"
            case replyCount = "reply_count"
            case replyToPostNumber = "reply_to_post_number"
            case replyToUser = "reply_to_user"
            case actionCode = "action_code"
            case userTitle = "user_title"
            case flairUrl = "flair_url"
            case flairBgColor = "flair_bg_color"
            case bookmarked
            case bookmarkId = "bookmark_id"
            case reactions
            case reactionUsersCount = "reaction_users_count"
            case currentUserReaction = "current_user_reaction"
            case currentUserUsedMainReaction = "current_user_used_main_reaction"
            case linkCounts = "link_counts"
            case polls
            case pollsVotes = "polls_votes"
            case boosts
            case canBoost = "can_boost"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(Int.self, forKey: .id)
            username = try container.decode(String.self, forKey: .username)
            name = (try? container.decodeIfPresent(String.self, forKey: .name))
                .flatMap { $0.isEmpty ? nil : $0 } ?? username
            avatarTemplate = try container.decodeIfPresent(String.self, forKey: .avatarTemplate)
            createdAt = try container.decode(String.self, forKey: .createdAt)
            cooked = try container.decode(String.self, forKey: .cooked)
            postNumber = try container.decode(Int.self, forKey: .postNumber)
            replyCount = try container.decode(Int.self, forKey: .replyCount)
            replyToPostNumber = try? container.decodeIfPresent(Int.self, forKey: .replyToPostNumber)
            replyToUser = try? container.decodeIfPresent(ReplyToUser.self, forKey: .replyToUser)
            actionCode = try? container.decodeIfPresent(String.self, forKey: .actionCode)
            userTitle = try? container.decodeIfPresent(String.self, forKey: .userTitle)
            flairUrl = try? container.decodeIfPresent(String.self, forKey: .flairUrl)
            flairBgColor = try? container.decodeIfPresent(String.self, forKey: .flairBgColor)
            bookmarked = (try? container.decodeIfPresent(Bool.self, forKey: .bookmarked)) ?? false
            bookmarkId = try? container.decodeIfPresent(Int.self, forKey: .bookmarkId)
            reactions = (try? container.decodeIfPresent([Reaction].self, forKey: .reactions)) ?? []
            reactionUsersCount = (try? container.decodeIfPresent(Int.self, forKey: .reactionUsersCount)) ?? 0
            currentUserReaction = try? container.decodeIfPresent(Reaction.self, forKey: .currentUserReaction)
            currentUserUsedMainReaction = (try? container.decodeIfPresent(Bool.self, forKey: .currentUserUsedMainReaction)) ?? false
            linkCounts = (try? container.decodeIfPresent([LinkCount].self, forKey: .linkCounts)) ?? []
            polls = (try? container.decodeIfPresent([DiscoursePollVoteResponse.Poll].self, forKey: .polls)) ?? []
            pollsVotes = (try? container.decodeIfPresent(LossyPollVotesValue.self, forKey: .pollsVotes)?.value) ?? [:]
            boosts = (try? container.decodeIfPresent([Boost].self, forKey: .boosts)) ?? []
            canBoost = (try? container.decodeIfPresent(Bool.self, forKey: .canBoost)) ?? false
        }
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return Int(value)
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}

struct DiscourseTopicPostsResponse: Decodable {
    let postStream: PostStreamPosts

    enum CodingKeys: String, CodingKey {
        case postStream = "post_stream"
    }

    struct PostStreamPosts: Decodable {
        let posts: [DiscourseTopicDetail.Post]
    }
}

struct DiscoursePollVoteResponse: Decodable {
    struct Poll: Decodable {
        let name: String?
        let status: String?
        let type: String?
        let votersCount: Int?
        let minSelections: Int?
        let maxSelections: Int?
        let resultsMode: String?
        let isPublic: Bool?
        let options: [Option]

        var hasResultPayload: Bool {
            votersCount != nil || !options.isEmpty
        }

        init(
            name: String?,
            status: String?,
            type: String?,
            votersCount: Int?,
            minSelections: Int?,
            maxSelections: Int?,
            resultsMode: String?,
            isPublic: Bool?,
            options: [Option]
        ) {
            self.name = name
            self.status = status
            self.type = type
            self.votersCount = votersCount
            self.minSelections = minSelections
            self.maxSelections = maxSelections
            self.resultsMode = resultsMode
            self.isPublic = isPublic
            self.options = options
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
            name = container.decodeLossyString(forKeys: ["name", "poll_name", "pollName"])
            status = container.decodeLossyString(forKeys: ["status", "poll_status", "pollStatus"])
            type = container.decodeLossyString(forKeys: ["type", "poll_type", "pollType"])
            votersCount = container.decodeLossyInt(forKeys: [
                "voters",
                "voters_count",
                "votersCount",
                "voter_count",
                "voterCount",
                "total",
                "total_votes",
                "totalVotes",
                "total_voters",
                "totalVoters",
                "votes"
            ])
            minSelections = container.decodeLossyInt(forKeys: ["min", "poll_min", "minSelections", "min_selections"])
            maxSelections = container.decodeLossyInt(forKeys: ["max", "poll_max", "maxSelections", "max_selections"])
            resultsMode = container.decodeLossyString(forKeys: ["results", "poll_results", "resultsMode", "results_mode"])
            isPublic = container.decodeLossyBool(forKeys: ["public", "isPublic", "is_public", "poll_public"])
            options = Self.decodeOptions(from: container)
        }

        func named(_ fallbackName: String) -> Poll {
            Poll(
                name: name ?? fallbackName,
                status: status,
                type: type,
                votersCount: votersCount,
                minSelections: minSelections,
                maxSelections: maxSelections,
                resultsMode: resultsMode,
                isPublic: isPublic,
                options: options
            )
        }

        private static func decodeOptions(from container: KeyedDecodingContainer<FlexibleCodingKey>) -> [Option] {
            for keyName in [
                "options",
                "choices",
                "poll_options",
                "pollOptions",
                "option_votes",
                "optionVotes",
                "vote_counts",
                "voteCounts",
                "votes"
            ] {
                let key = FlexibleCodingKey(stringValue: keyName)
                if let options = try? container.decode([Option].self, forKey: key) {
                    return options.filter(\.hasResultPayload)
                }
                if let options = try? container.decode([String: Option].self, forKey: key) {
                    return options.map { optionId, option in
                        option.identified(by: optionId)
                    }
                    .filter(\.hasResultPayload)
                    .sorted { ($0.id ?? "") < ($1.id ?? "") }
                }
                if let votes = try? container.decode([String: LossyIntValue].self, forKey: key) {
                    return votes.map { optionId, value in
                        Option(
                            id: optionId,
                            text: nil,
                            voteCount: value.value,
                            percentageText: nil,
                            isSelected: nil
                        )
                    }
                    .filter(\.hasResultPayload)
                    .sorted { ($0.id ?? "") < ($1.id ?? "") }
                }
            }
            return []
        }
    }

    struct Option: Decodable {
        let id: String?
        let text: String?
        let voteCount: Int?
        let percentageText: String?
        let isSelected: Bool?

        var hasResultPayload: Bool {
            id != nil || voteCount != nil || percentageText != nil || isSelected != nil
        }

        init(
            id: String?,
            text: String?,
            voteCount: Int?,
            percentageText: String?,
            isSelected: Bool?
        ) {
            self.id = id
            self.text = text
            self.voteCount = voteCount
            self.percentageText = percentageText
            self.isSelected = isSelected
        }

        init(from decoder: Decoder) throws {
            if let intValue = try? LossyIntValue(from: decoder), let value = intValue.value {
                id = nil
                text = nil
                voteCount = value
                percentageText = nil
                isSelected = nil
                return
            }

            let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
            id = container.decodeLossyString(forKeys: ["id", "option_id", "optionId", "poll_option_id", "pollOptionId"])
            text = container.decodeLossyString(forKeys: ["html", "text", "title", "label", "name"])
            voteCount = container.decodeLossyInt(forKeys: ["votes", "vote_count", "voteCount", "count", "voters"])
            isSelected = container.decodeLossyBool(forKeys: ["selected", "isSelected", "is_selected", "chosen", "voted"])

            if let text = container.decodeLossyString(forKeys: ["percentage", "percent", "percentText", "percentageText", "percentage_text", "percent_text"]) {
                percentageText = Self.normalizedPercentageText(text)
            } else if let value = container.decodeLossyDouble(forKeys: ["percentage", "percent", "percentText", "percentageText", "percentage_text", "percent_text"]) {
                percentageText = Self.percentageText(from: value)
            } else {
                percentageText = nil
            }
        }

        func identified(by fallbackId: String) -> Option {
            Option(
                id: id ?? fallbackId,
                text: text,
                voteCount: voteCount,
                percentageText: percentageText,
                isSelected: isSelected
            )
        }

        private static func normalizedPercentageText(_ text: String) -> String {
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.contains("%") {
                return trimmed
            }
            guard let value = Double(trimmed) else {
                return trimmed
            }
            return percentageText(from: value)
        }

        private static func percentageText(from value: Double) -> String {
            let percent = value > 0 && value < 1 ? value * 100 : value
            let rounded = (percent * 10).rounded() / 10
            if rounded.rounded() == rounded {
                return "\(Int(rounded))%"
            }
            return "\(rounded)%"
        }
    }

    let polls: [Poll]
    private static let pollEnvelopeKeys = ["poll", "polls", "result", "results", "data", "poll_result", "pollResult"]

    init(polls: [Poll] = []) {
        self.polls = polls
    }

    init(from decoder: Decoder) throws {
        var decodedPolls: [Poll] = []

        if let container = try? decoder.container(keyedBy: FlexibleCodingKey.self) {
            for key in Self.pollEnvelopeKeys {
                decodedPolls.append(contentsOf: Self.decodePolls(from: container, forKey: key))
            }
        }

        if let rootPoll = try? Poll(from: decoder), rootPoll.hasResultPayload {
            decodedPolls.append(rootPoll)
        }

        var seenNames: Set<String> = []
        polls = decodedPolls.filter { poll in
            guard poll.hasResultPayload else { return false }
            guard let name = poll.name, !name.isEmpty else { return true }
            return seenNames.insert(name).inserted
        }
    }

    func poll(named name: String?) -> Poll? {
        let normalizedName = name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let normalizedName, !normalizedName.isEmpty,
           let match = polls.first(where: { $0.name?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedName }) {
            return match
        }
        return polls.count == 1 ? polls[0] : nil
    }

    private static func decodePolls(from container: KeyedDecodingContainer<FlexibleCodingKey>, forKey keyName: String) -> [Poll] {
        let key = FlexibleCodingKey(stringValue: keyName)
        if let poll = try? container.decode(Poll.self, forKey: key), poll.hasResultPayload {
            return [poll]
        }
        if let polls = try? container.decode([Poll].self, forKey: key) {
            return polls.filter(\.hasResultPayload)
        }
        if let polls = try? container.decode([String: Poll].self, forKey: key) {
            return polls.map { name, poll in
                poll.named(name)
            }
            .filter(\.hasResultPayload)
        }
        if let nestedContainer = try? container.nestedContainer(keyedBy: FlexibleCodingKey.self, forKey: key) {
            var polls: [Poll] = []
            for nestedKey in pollEnvelopeKeys where nestedKey != keyName {
                polls.append(contentsOf: decodePolls(from: nestedContainer, forKey: nestedKey))
            }
            return polls
        }
        return []
    }
}

private struct FlexibleCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init(intValue: Int) {
        stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

private struct LossyIntValue: Decodable {
    let value: Int?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = Int(doubleValue)
        } else if let stringValue = try? container.decode(String.self) {
            value = Int(stringValue.trimmingCharacters(in: .whitespacesAndNewlines))
        } else {
            value = nil
        }
    }
}

private struct LossyStringValue: Decodable {
    let value: String?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let stringValue = try? container.decode(String.self) {
            let trimmed = stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            value = trimmed.isEmpty ? nil : trimmed
        } else if let intValue = try? container.decode(Int.self) {
            value = "\(intValue)"
        } else if let doubleValue = try? container.decode(Double.self) {
            value = "\(doubleValue)"
        } else {
            value = nil
        }
    }
}

private struct LossyPollVotesValue: Decodable {
    let value: [String: [String]]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleCodingKey.self)
        var votes: [String: [String]] = [:]
        for key in container.allKeys {
            if let values = try? container.decode([LossyStringValue].self, forKey: key) {
                let optionIds = values.compactMap(\.value)
                if !optionIds.isEmpty {
                    votes[key.stringValue] = optionIds
                }
            } else if let value = try? container.decode(LossyStringValue.self, forKey: key),
                      let optionId = value.value {
                votes[key.stringValue] = [optionId]
            }
        }
        value = votes
    }
}

private extension KeyedDecodingContainer where Key == FlexibleCodingKey {
    func decodeLossyString(forKeys keys: [String]) -> String? {
        for key in keys {
            let codingKey = FlexibleCodingKey(stringValue: key)
            if let value = try? decodeIfPresent(String.self, forKey: codingKey) {
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return "\(value)"
            }
            if let value = try? decodeIfPresent(Double.self, forKey: codingKey) {
                return "\(value)"
            }
        }
        return nil
    }

    func decodeLossyInt(forKeys keys: [String]) -> Int? {
        for key in keys {
            let codingKey = FlexibleCodingKey(stringValue: key)
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return value
            }
            if let value = try? decodeIfPresent(Double.self, forKey: codingKey) {
                return Int(value)
            }
            if let value = try? decodeIfPresent(String.self, forKey: codingKey),
               let intValue = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return intValue
            }
        }
        return nil
    }

    func decodeLossyDouble(forKeys keys: [String]) -> Double? {
        for key in keys {
            let codingKey = FlexibleCodingKey(stringValue: key)
            if let value = try? decodeIfPresent(Double.self, forKey: codingKey) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return Double(value)
            }
            if let value = try? decodeIfPresent(String.self, forKey: codingKey),
               let doubleValue = Double(value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "%", with: "")) {
                return doubleValue
            }
        }
        return nil
    }

    func decodeLossyBool(forKeys keys: [String]) -> Bool? {
        for key in keys {
            let codingKey = FlexibleCodingKey(stringValue: key)
            if let value = try? decodeIfPresent(Bool.self, forKey: codingKey) {
                return value
            }
            if let value = try? decodeIfPresent(Int.self, forKey: codingKey) {
                return value != 0
            }
            if let value = try? decodeIfPresent(String.self, forKey: codingKey) {
                let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if ["true", "1", "yes", "y"].contains(normalized) {
                    return true
                }
                if ["false", "0", "no", "n"].contains(normalized) {
                    return false
                }
            }
        }
        return nil
    }
}
