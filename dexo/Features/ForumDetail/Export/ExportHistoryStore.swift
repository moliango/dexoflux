import Foundation

struct TopicExportRecord: Codable, Hashable, Identifiable {
    let id: UUID
    let topicId: Int
    let title: String
    let format: TopicExportFormat
    let filePath: String?
    let postCount: Int
    let timestamp: Date
    let errorMessage: String?

    init(
        id: UUID = UUID(),
        topicId: Int,
        title: String,
        format: TopicExportFormat,
        filePath: String?,
        postCount: Int,
        timestamp: Date = Date(),
        errorMessage: String?
    ) {
        self.id = id
        self.topicId = topicId
        self.title = title
        self.format = format
        self.filePath = filePath
        self.postCount = postCount
        self.timestamp = timestamp
        self.errorMessage = errorMessage
    }

    var fileURL: URL? {
        filePath.map(URL.init(fileURLWithPath:))
    }

    var fileExists: Bool {
        fileURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
    }
}

final class ExportHistoryStore {
    private struct StorageFile: Codable {
        var accounts: [AccountData] = []
    }

    private struct AccountData: Codable {
        let scopeKey: String
        var records: [TopicExportRecord]
    }

    private(set) var records: [TopicExportRecord] = []

    private let scopeKey: String
    private let directoryURL: URL

    init(baseURL: String, username: String?, directoryURL: URL? = nil) {
        self.scopeKey = AccountScopeKey.make(baseURL: baseURL, username: username)
        self.directoryURL = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        reload()
    }

    static func storageURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent("dexo_export_history.json")
    }

    func reload() {
        let account = loadStorage().accounts.first { $0.scopeKey == scopeKey }
        records = account?.records.sorted { $0.timestamp > $1.timestamp } ?? []
    }

    func add(_ record: TopicExportRecord) throws {
        try mutate { account in
            account.records.removeAll { $0.id == record.id }
            account.records.insert(record, at: 0)
            account.records.sort { $0.timestamp > $1.timestamp }
        }
    }

    func remove(_ record: TopicExportRecord, deleteFile: Bool = true) throws {
        if deleteFile, let fileURL = record.fileURL,
           FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        try mutate { account in
            account.records.removeAll { $0.id == record.id }
        }
    }

    func clear(deleteFiles: Bool = true) throws {
        if deleteFiles {
            for record in records {
                guard let fileURL = record.fileURL,
                      FileManager.default.fileExists(atPath: fileURL.path) else { continue }
                try? FileManager.default.removeItem(at: fileURL)
            }
        }
        try mutate { $0.records.removeAll() }
    }

    private func mutate(_ update: (inout AccountData) -> Void) throws {
        var storage = loadStorage()
        var account = storage.accounts.first(where: { $0.scopeKey == scopeKey })
            ?? AccountData(scopeKey: scopeKey, records: [])
        update(&account)
        if let index = storage.accounts.firstIndex(where: { $0.scopeKey == scopeKey }) {
            storage.accounts[index] = account
        } else {
            storage.accounts.append(account)
        }

        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(storage)
        try data.write(to: Self.storageURL(in: directoryURL), options: .atomic)
        records = account.records.sorted { $0.timestamp > $1.timestamp }
    }

    private func loadStorage() -> StorageFile {
        let url = Self.storageURL(in: directoryURL)
        guard let data = try? Data(contentsOf: url),
              let storage = try? JSONDecoder().decode(StorageFile.self, from: data) else {
            return StorageFile()
        }
        return storage
    }
}
