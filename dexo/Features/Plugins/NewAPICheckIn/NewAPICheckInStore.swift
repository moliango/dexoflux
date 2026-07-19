import Foundation
import Security

protocol NewAPICheckInCredentialVault: Sendable {
    nonisolated func data(for key: String) throws -> Data?
    nonisolated func setData(_ data: Data, for key: String) throws
    nonisolated func removeData(for key: String) throws
}

enum NewAPICheckInStoreError: Error {
    case credentialEncodingFailed
    case keychain(OSStatus)
}

final class NewAPICheckInKeychainVault: NewAPICheckInCredentialVault, @unchecked Sendable {
    private let service = "com.naine.dexoflux.plugin.newapi-checkin"

    nonisolated init() {}

    nonisolated func data(for key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.naine.dexoflux.plugin.newapi-checkin",
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw NewAPICheckInStoreError.keychain(status) }
        return result as? Data
    }

    nonisolated func setData(_ data: Data, for key: String) throws {
        try removeData(for: key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.naine.dexoflux.plugin.newapi-checkin",
            kSecAttrAccount as String: key,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw NewAPICheckInStoreError.keychain(status) }
    }

    nonisolated func removeData(for key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.naine.dexoflux.plugin.newapi-checkin",
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NewAPICheckInStoreError.keychain(status)
        }
    }
}

actor NewAPICheckInStore {
    private struct StorageFile: Codable {
        var version = 1
        var accounts: [AccountState] = []
    }

    private struct AccountState: Codable {
        let scopeKey: String
        var platforms: [NewAPICheckInPlatform]
        var attempts: [NewAPICheckInAttempt]
    }

    private let scopeKey: String
    private let directoryURL: URL
    private let credentialVault: NewAPICheckInCredentialVault
    private let maximumAttemptCount: Int

    init(
        scope: PluginScope,
        directoryURL: URL? = nil,
        credentialVault: NewAPICheckInCredentialVault = NewAPICheckInKeychainVault(),
        maximumAttemptCount: Int = 500
    ) {
        scopeKey = scope.storageKey
        self.directoryURL = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DexoFlux/Plugins/NewAPICheckIn", isDirectory: true)
        self.credentialVault = credentialVault
        self.maximumAttemptCount = max(1, maximumAttemptCount)
    }

    static func storageURL(in directoryURL: URL) -> URL {
        directoryURL.appendingPathComponent("newapi-checkin.json")
    }

    func platforms() -> [NewAPICheckInPlatform] {
        accountState(in: load()).platforms.sorted { $0.createdAt < $1.createdAt }
    }

    func attempts(platformID: UUID? = nil) -> [NewAPICheckInAttempt] {
        accountState(in: load()).attempts
            .filter { platformID == nil || $0.platformID == platformID }
            .sorted { $0.attemptedAt > $1.attemptedAt }
    }

    func clearAttempts(platformID: UUID? = nil) throws {
        var file = load()
        var state = accountState(in: file)
        if let platformID {
            state.attempts.removeAll { $0.platformID == platformID }
        } else {
            state.attempts.removeAll()
        }
        replace(state, in: &file)
        try persist(file)
    }

    func save(_ platform: NewAPICheckInPlatform, credential: NewAPICheckInCredential? = nil) throws {
        var file = load()
        var state = accountState(in: file)
        var platform = platform
        platform.updatedAt = Date()
        if let index = state.platforms.firstIndex(where: { $0.id == platform.id }) {
            state.platforms[index] = platform
        } else {
            state.platforms.append(platform)
        }
        replace(state, in: &file)
        try persist(file)
        if let credential {
            let data = try encodeCredential(credential)
            try credentialVault.setData(data, for: credentialKey(platformID: platform.id))
        }
    }

    func delete(platformID: UUID) throws {
        var file = load()
        var state = accountState(in: file)
        state.platforms.removeAll { $0.id == platformID }
        state.attempts.removeAll { $0.platformID == platformID }
        replace(state, in: &file)
        try persist(file)
        try credentialVault.removeData(for: credentialKey(platformID: platformID))
    }

    func credential(for platformID: UUID) throws -> NewAPICheckInCredential? {
        guard let data = try credentialVault.data(for: credentialKey(platformID: platformID)) else { return nil }
        return try decodeCredential(data)
    }

    func record(_ result: NewAPICheckInResult, for platformID: UUID) throws {
        var file = load()
        var state = accountState(in: file)
        let now = Date()
        state.attempts.insert(NewAPICheckInAttempt(platformID: platformID, attemptedAt: now, result: result), at: 0)
        state.attempts = Array(state.attempts.prefix(maximumAttemptCount))
        if let index = state.platforms.firstIndex(where: { $0.id == platformID }) {
            state.platforms[index].lastStatus = result.status
            state.platforms[index].lastAttemptAt = now
            state.platforms[index].lastMessage = result.message
            if let quotaValue = result.quotaValue {
                state.platforms[index].lastQuotaValue = quotaValue
                state.platforms[index].lastQuotaUnit = result.quotaUnit
            }
            state.platforms[index].updatedAt = now
        }
        replace(state, in: &file)
        try persist(file)
    }

    private func credentialKey(platformID: UUID) -> String {
        "\(scopeKey)|\(platformID.uuidString)"
    }

    private func encodeCredential(_ credential: NewAPICheckInCredential) throws -> Data {
        var object: [String: Any] = ["additionalHeaders": credential.additionalHeaders]
        object["accessToken"] = credential.accessToken
        object["userID"] = credential.userID
        object["cookieHeader"] = credential.cookieHeader
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }

    private func decodeCredential(_ data: Data) throws -> NewAPICheckInCredential {
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return NewAPICheckInCredential(
            accessToken: object?["accessToken"] as? String,
            userID: object?["userID"] as? String,
            cookieHeader: object?["cookieHeader"] as? String,
            additionalHeaders: object?["additionalHeaders"] as? [String: String] ?? [:]
        )
    }

    private func accountState(in file: StorageFile) -> AccountState {
        file.accounts.first(where: { $0.scopeKey == scopeKey })
            ?? AccountState(scopeKey: scopeKey, platforms: [], attempts: [])
    }

    private func replace(_ state: AccountState, in file: inout StorageFile) {
        if let index = file.accounts.firstIndex(where: { $0.scopeKey == scopeKey }) {
            file.accounts[index] = state
        } else {
            file.accounts.append(state)
        }
    }

    private func load() -> StorageFile {
        let url = Self.storageURL(in: directoryURL)
        guard let data = try? Data(contentsOf: url) else { return StorageFile() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(StorageFile.self, from: data)) ?? StorageFile()
    }

    private func persist(_ file: StorageFile) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(file).write(to: Self.storageURL(in: directoryURL), options: .atomic)
    }
}
