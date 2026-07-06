import Foundation
import Security

enum KeychainHelper {

    // MARK: - Legacy Auth Cleanup

    static func deleteLegacyCredential(for baseURL: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.eilgnaw.dexo.userApiKey",
            kSecAttrAccount as String: baseURL,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func rsaTag(for baseURL: String) -> String {
        "com.eilgnaw.dexo.rsaKey.\(baseURL)"
    }

    static func deleteLegacyRSAKeyPair(for baseURL: String) {
        let tag = rsaTag(for: baseURL)
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: Data(tag.utf8),
        ]
        SecItemDelete(query as CFDictionary)
    }
}
