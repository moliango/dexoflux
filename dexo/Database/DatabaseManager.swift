import Foundation
import GRDB

final class DatabaseManager: Sendable {
    static let shared = DatabaseManager()

    private let dbPool: DatabasePool

    private init() {
        do {
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            let dbURL = appSupport.appendingPathComponent("dexo.sqlite")
            dbPool = try DatabasePool(path: dbURL.path)
            try migrator.migrate(dbPool)
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.create(table: "forumInstance") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("baseURL", .text).notNull()
                t.column("iconURL", .text)
                t.column("addedAt", .datetime).notNull()
                t.column("sortOrder", .integer).notNull().defaults(to: 0)
            }
        }

        migrator.registerMigration("v2") { db in
            try db.alter(table: "forumInstance") { t in
                t.add(column: "username", .text)
            }
        }

        return migrator
    }

    // MARK: - Forum CRUD

    func defaultForum() -> ForumInstance {
        do {
            return try ensureDefaultForum()
        } catch {
            assertionFailure("Failed to prepare default forum: \(error)")
            return ForumInstance.linuxDoDefault()
        }
    }

    func ensureDefaultForum() throws -> ForumInstance {
        try dbPool.write { db in
            let forums = try ForumInstance.fetchAll(db)
            if var forum = forums.first(where: { $0.isLinuxDoDefault }) {
                if forum.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    forum.title = ForumInstance.linuxDoTitle
                    try forum.save(db)
                }
                return forum
            }

            var forum = ForumInstance.linuxDoDefault()
            try forum.save(db)
            return forum
        }
    }

    func fetchAllForums() throws -> [ForumInstance] {
        try dbPool.read { db in
            try ForumInstance.order(Column("sortOrder").asc, Column("addedAt").asc).fetchAll(db)
        }
    }

    @discardableResult
    func saveForum(_ forum: inout ForumInstance) throws -> ForumInstance {
        try dbPool.write { db in
            try forum.save(db)
            return forum
        }
    }

    func deleteForum(_ forum: ForumInstance) throws {
        try dbPool.write { db in
            _ = try forum.delete(db)
        }
    }
}
