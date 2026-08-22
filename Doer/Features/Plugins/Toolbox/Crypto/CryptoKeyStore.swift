import Foundation

enum CryptoKeyStore {
    static let maxEntries = 5
    private static let service = "com.naine.doer.crypto"
    private static let account = "remembered_passwords"

    static func readPasswords() -> [String] {
        guard let raw = KeychainHelper.string(service: service, account: account),
              let data = raw.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: data)
        else { return [] }
        return Array(decoded.prefix(maxEntries))
    }

    static func rememberPassword(_ password: String) {
        let trimmed = password.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        var next = [trimmed] + readPasswords().filter { $0 != trimmed }
        if next.count > maxEntries { next = Array(next.prefix(maxEntries)) }
        guard let data = try? JSONEncoder().encode(next),
              let raw = String(data: data, encoding: .utf8)
        else { return }
        try? KeychainHelper.setString(raw, service: service, account: account)
    }

    static func clear() {
        KeychainHelper.deleteString(service: service, account: account)
    }
}
