import Foundation

struct StickerMarketIndex: Codable, Equatable {
    let totalPages: Int
    let pageSize: Int
    let totalGroups: Int

    enum CodingKeys: String, CodingKey {
        case totalPages, pageSize, totalGroups
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        totalPages = (try? container.decode(Int.self, forKey: .totalPages)) ?? 0
        pageSize = (try? container.decode(Int.self, forKey: .pageSize)) ?? 0
        totalGroups = (try? container.decode(Int.self, forKey: .totalGroups)) ?? 0
    }

    init(totalPages: Int, pageSize: Int, totalGroups: Int) {
        self.totalPages = totalPages
        self.pageSize = pageSize
        self.totalGroups = totalGroups
    }
}

struct StickerGroup: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let icon: String
    let order: Int
    let emojiCount: Int
    let isArchived: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, icon, order, emojiCount, isArchived
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        icon = (try? container.decode(String.self, forKey: .icon)) ?? ""
        order = (try? container.decode(Int.self, forKey: .order)) ?? 0
        emojiCount = (try? container.decode(Int.self, forKey: .emojiCount)) ?? 0
        isArchived = (try? container.decode(Bool.self, forKey: .isArchived)) ?? false
    }

    init(id: String, name: String, icon: String, order: Int, emojiCount: Int, isArchived: Bool) {
        self.id = id
        self.name = name
        self.icon = icon
        self.order = order
        self.emojiCount = emojiCount
        self.isArchived = isArchived
    }
}

struct StickerItem: Codable, Equatable, Identifiable {
    let id: String
    let name: String
    let url: String
    let width: Int
    let height: Int
    let groupId: String

    enum CodingKeys: String, CodingKey {
        case id, name, url, width, height, groupId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        url = (try? container.decode(String.self, forKey: .url)) ?? ""
        width = (try? container.decode(Int.self, forKey: .width)) ?? 0
        height = (try? container.decode(Int.self, forKey: .height)) ?? 0
        groupId = (try? container.decode(String.self, forKey: .groupId)) ?? ""
    }

    init(id: String, name: String, url: String, width: Int, height: Int, groupId: String) {
        self.id = id
        self.name = name
        self.url = url
        self.width = width
        self.height = height
        self.groupId = groupId
    }

    /// FluxDO-compatible Discourse markdown image insertion.
    var markdown: String {
        "![\(name)|\(width)x\(height),30%](\(url))"
    }
}

struct StickerGroupDetail: Codable, Equatable {
    let id: String
    let name: String
    let icon: String
    let emojis: [StickerItem]

    enum CodingKeys: String, CodingKey {
        case id, name, icon, emojis
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = (try? container.decode(String.self, forKey: .id)) ?? ""
        name = (try? container.decode(String.self, forKey: .name)) ?? ""
        icon = (try? container.decode(String.self, forKey: .icon)) ?? ""
        emojis = (try? container.decode([StickerItem].self, forKey: .emojis)) ?? []
    }

    init(id: String, name: String, icon: String, emojis: [StickerItem]) {
        self.id = id
        self.name = name
        self.icon = icon
        self.emojis = emojis
    }
}

private struct StickerGroupsPage: Codable {
    let groups: [StickerGroup]
}
