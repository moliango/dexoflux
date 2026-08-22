import Foundation

enum CryptoAlgorithmCategory: String, CaseIterable {
    case encoding
    case symmetric
    case hash
    case asymmetric
    case classic

    var title: String {
        switch self {
        case .encoding:
            return String(localized: "crypto.category.encoding", defaultValue: "编码")
        case .symmetric:
            return String(localized: "crypto.category.symmetric", defaultValue: "对称加密")
        case .hash:
            return String(localized: "crypto.category.hash", defaultValue: "哈希")
        case .asymmetric:
            return String(localized: "crypto.category.asymmetric", defaultValue: "非对称")
        case .classic:
            return String(localized: "crypto.category.classic", defaultValue: "经典密码")
        }
    }
}

struct CryptoException: Error, LocalizedError, Equatable {
    let message: String
    var errorDescription: String? { message }

    init(_ message: String) {
        self.message = message
    }
}

struct CryptoParams {
    var password: String?
    var rsaPem: String?
    var caesarShift: Int
    var vigenereKey: String?
    var railCount: Int

    init(
        password: String? = nil,
        rsaPem: String? = nil,
        caesarShift: Int = 3,
        vigenereKey: String? = nil,
        railCount: Int = 2
    ) {
        self.password = password
        self.rsaPem = rsaPem
        self.caesarShift = caesarShift
        self.vigenereKey = vigenereKey
        self.railCount = railCount
    }
}

protocol CryptoAlgorithm {
    var id: String { get }
    var category: CryptoAlgorithmCategory { get }
    var displayName: String { get }
    var isReversible: Bool { get }
    var requiresPassword: Bool { get }
    var requiresPem: Bool { get }
    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String
    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String
}

extension CryptoAlgorithm {
    var displayName: String { id.uppercased() }
    var isReversible: Bool { category != .hash }
    var requiresPassword: Bool { category == .symmetric }
    var requiresPem: Bool { category == .asymmetric }
}

enum CryptoOutputFormat: String, CaseIterable {
    case enc1
    case openssl

    var title: String {
        switch self {
        case .enc1:
            return String(localized: "crypto.format.enc1", defaultValue: "ENC1（自描述）")
        case .openssl:
            return String(localized: "crypto.format.openssl", defaultValue: "OpenSSL Salted")
        }
    }
}
