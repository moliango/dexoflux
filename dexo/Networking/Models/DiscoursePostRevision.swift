
import Foundation

struct DiscoursePostRevision: Decodable {
    let currentVersion: Int?
    let versionCount: Int?
    let previousHidden: Bool?
    let currentHidden: Bool?
    let firstRevision: Int?
    let previousRevision: Int?
    let currentRevision: Int?
    let nextRevision: Int?
    let lastRevision: Int?
    let bodyChanges: BodyChanges?
    let username: String?
    let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case username
        case currentVersion = "current_version"
        case versionCount = "version_count"
        case previousHidden = "previous_hidden"
        case currentHidden = "current_hidden"
        case firstRevision = "first_revision"
        case previousRevision = "previous_revision"
        case currentRevision = "current_revision"
        case nextRevision = "next_revision"
        case lastRevision = "last_revision"
        case bodyChanges = "body_changes"
        case createdAt = "created_at"
    }

    struct BodyChanges: Decodable {
        let inline: String?
        let sideBySide: String?
        let sideBySideMarkdown: String?

        enum CodingKeys: String, CodingKey {
            case inline
            case sideBySide = "side_by_side"
            case sideBySideMarkdown = "side_by_side_markdown"
        }
    }

    var displayHTML: String {
        bodyChanges?.sideBySide
            ?? bodyChanges?.inline
            ?? bodyChanges?.sideBySideMarkdown
            ?? "<p>No diff</p>"
    }
}
