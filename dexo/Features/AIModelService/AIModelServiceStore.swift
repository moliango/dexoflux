import Foundation
import Security

/// AI 模型服务持久化：供应商列表存 JSON（与 FluxDo 的结构兼容），
/// API Key 存 Keychain，默认模型引用存 UserDefaults。
actor AIModelServiceStore {
    static let shared = AIModelServiceStore()

    private struct StorageFile: Codable {
        var version = 1
        var providers: [AIProvider] = []
    }

    private static let keychainService = "com.naine.dexoflux.ai-model-service"
    private static let defaultModelKey = "ai.model_service.default_model"

    private let directoryURL: URL

    init(directoryURL: URL? = nil) {
        self.directoryURL = directoryURL ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DexoFlux/AIModelService", isDirectory: true)
    }

    // MARK: - Providers

    func providers() -> [AIProvider] {
        let providers = load().providers
        return providers.sorted { lhs, rhs in
            if lhs.pinned != rhs.pinned { return lhs.pinned }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    func provider(id: String) -> AIProvider? {
        load().providers.first { $0.id == id }
    }

    func save(_ provider: AIProvider, apiKey: String?) throws {
        var file = load()
        if let index = file.providers.firstIndex(where: { $0.id == provider.id }) {
            file.providers[index] = provider
        } else {
            file.providers.append(provider)
        }
        try persist(file)
        if let apiKey {
            try Self.setKeychainValue(apiKey, account: provider.id)
        }
    }

    func delete(providerID: String) throws {
        var file = load()
        file.providers.removeAll { $0.id == providerID }
        try persist(file)
        try Self.removeKeychainValue(account: providerID)
        if Self.defaultModelRef()?.providerID == providerID {
            Self.setDefaultModelRef(nil)
        }
    }

    func apiKey(for providerID: String) -> String? {
        Self.keychainValue(account: providerID)
    }

    // MARK: - Default model

    nonisolated static func defaultModelRef() -> AIDefaultModelRef? {
        AIDefaultModelRef(storageValue: UserDefaults.standard.string(forKey: defaultModelKey))
    }

    nonisolated static func setDefaultModelRef(_ ref: AIDefaultModelRef?) {
        if let ref {
            UserDefaults.standard.set(ref.storageValue, forKey: defaultModelKey)
        } else {
            UserDefaults.standard.removeObject(forKey: defaultModelKey)
        }
    }

    // MARK: - JSON persistence

    private func load() -> StorageFile {
        let url = directoryURL.appendingPathComponent("providers.json")
        guard let data = try? Data(contentsOf: url) else { return StorageFile() }
        return (try? JSONDecoder().decode(StorageFile.self, from: data)) ?? StorageFile()
    }

    private func persist(_ file: StorageFile) throws {
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let url = directoryURL.appendingPathComponent("providers.json")
        try encoder.encode(file).write(to: url, options: .atomic)
    }

    // MARK: - Keychain

    private nonisolated static func keychainValue(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private nonisolated static func setKeychainValue(_ value: String, account: String) throws {
        try removeKeychainValue(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private nonisolated static func removeKeychainValue(account: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }
}
