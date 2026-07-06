import Foundation
import GRDB

struct ForumInstance: Sendable, Codable, Identifiable, Equatable, Hashable,
    FetchableRecord, MutablePersistableRecord
{
    nonisolated static let databaseTableName = "forumInstance"

    var id: Int64?
    var title: String
    var baseURL: String
    var iconURL: String?
    var username: String?
    var addedAt: Date
    var sortOrder: Int

    static let linuxDoTitle = "Linux.do"
    static let linuxDoBaseURL = "https://linux.do"

    static func new(title: String, baseURL: String, iconURL: String? = nil) -> ForumInstance {
        ForumInstance(
            id: nil,
            title: title,
            baseURL: baseURL,
            iconURL: iconURL,
            username: nil,
            addedAt: Date(),
            sortOrder: 0
        )
    }

    static func linuxDoDefault() -> ForumInstance {
        new(title: linuxDoTitle, baseURL: linuxDoBaseURL)
    }

    static func normalizedBaseURL(_ rawValue: String) -> String {
        rawValue
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()
    }

    var isLinuxDoDefault: Bool {
        Self.normalizedBaseURL(baseURL) == Self.linuxDoBaseURL
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
