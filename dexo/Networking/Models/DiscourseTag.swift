import Foundation

/// 站点标签分组（/tags.json extras.tag_groups；name == nil 表示未分组兜底）。
struct DiscourseSiteTagGroup: Equatable {
    let name: String?
    let tags: [DiscourseTag]
}

struct DiscourseTagList: Decodable {
    let tags: [DiscourseTag]
    let tagGroups: [DiscourseSiteTagGroup]

    enum CodingKeys: String, CodingKey {
        case tags
        case extras
    }

    enum ExtrasKeys: String, CodingKey {
        case tagGroups = "tag_groups"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let topTags = (try? container.decodeIfPresent([DiscourseTag].self, forKey: .tags)) ?? []

        var groups: [DiscourseSiteTagGroup] = []
        var seen = Set<String>()

        func takeUnique(_ list: [DiscourseTag]) -> [DiscourseTag] {
            var result: [DiscourseTag] = []
            for tag in list where !tag.name.isEmpty && seen.insert(tag.name).inserted {
                result.append(tag)
            }
            return result.sorted { $0.count > $1.count }
        }

        if let extras = try? container.nestedContainer(keyedBy: ExtrasKeys.self, forKey: .extras),
           let rawGroups = try? extras.decodeIfPresent([RawTagGroup].self, forKey: .tagGroups) {
            for group in rawGroups {
                let tags = takeUnique(group.tags)
                if !tags.isEmpty {
                    groups.append(DiscourseSiteTagGroup(name: group.name, tags: tags))
                }
            }
        }

        let ungrouped = takeUnique(topTags)
        if !ungrouped.isEmpty {
            groups.append(DiscourseSiteTagGroup(name: nil, tags: ungrouped))
        }

        // 兼容：某些调用只需要扁平 tags（保持顺序：各组按出现顺序 + 组内按 count）
        self.tagGroups = groups
        self.tags = groups.flatMap(\.tags)
    }

    private struct RawTagGroup: Decodable {
        let name: String?
        let tags: [DiscourseTag]
    }
}

struct DiscourseTag: Decodable, Identifiable, Hashable {
    let name: String
    let text: String
    let count: Int

    var id: String { name }

    init(text: String, count: Int) {
        self.name = text
        self.text = text
        self.count = count
    }

    init(name: String, text: String, count: Int) {
        self.name = name
        self.text = text
        self.count = count
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, text, count
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedName =
            (try? container.decodeIfPresent(String.self, forKey: .name))
            ?? (try? container.decodeIfPresent(String.self, forKey: .id))
            ?? (try? container.decodeIfPresent(String.self, forKey: .text))
            ?? ""
        let decodedText =
            (try? container.decodeIfPresent(String.self, forKey: .text))
            ?? decodedName
        let decodedCount = (try? container.decodeIfPresent(Int.self, forKey: .count)) ?? 0
        self.name = decodedName
        self.text = decodedText
        self.count = decodedCount
    }
}
