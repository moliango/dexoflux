import CryptoKit
import Foundation

enum CryptoCipherFormat {
    static let enc1Prefix = "ENC1:"
    static let openSslMagic = "U2FsdGVkX1"

    struct Enc1Parsed {
        let algorithmId: String
        let payloadBase64: String
    }

    struct OpenSslParsed {
        let salt: Data
        let ciphertext: Data
    }

    struct DerivedKeyIV {
        let key: Data
        let iv: Data
    }

    static func enc1Pack(algorithmId: String, payloadBase64: String) -> String {
        "\(enc1Prefix)\(algorithmId):\(payloadBase64)"
    }

    static func enc1TryParse(_ text: String) -> Enc1Parsed? {
        var t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard t.hasPrefix(enc1Prefix) else { return nil }
        t.removeFirst(enc1Prefix.count)
        t = t.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        guard let colon = t.firstIndex(of: ":") else { return nil }
        let algo = String(t[..<colon])
        let payload = String(t[t.index(after: colon)...])
        guard !algo.isEmpty, !payload.isEmpty else { return nil }
        return Enc1Parsed(algorithmId: algo, payloadBase64: payload)
    }

    static func openSslTryParse(_ text: String) -> OpenSslParsed? {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        guard t.hasPrefix(openSslMagic) else { return nil }
        guard let bytes = Data(base64Encoded: CryptoEncoding.normalizeBase64(t)) else { return nil }
        guard bytes.count >= 17 else { return nil }
        let magic = String(data: bytes.prefix(8), encoding: .ascii)
        guard magic == "Salted__" else { return nil }
        return OpenSslParsed(salt: bytes.subdata(in: 8..<16), ciphertext: bytes.subdata(in: 16..<bytes.count))
    }

    static func openSslPack(salt: Data, ciphertext: Data) -> String {
        var bytes = Data("Salted__".utf8)
        bytes.append(salt)
        bytes.append(ciphertext)
        return bytes.base64EncodedString()
    }

    static func evpBytesToKey(
        password: String,
        salt: Data,
        keyLength: Int,
        ivLength: Int,
        useSHA256: Bool
    ) -> DerivedKeyIV {
        let pwd = Data(password.utf8)
        var material = Data()
        var prev = Data()
        while material.count < keyLength + ivLength {
            var input = Data()
            input.append(prev)
            input.append(pwd)
            input.append(salt)
            if useSHA256 {
                prev = Data(SHA256.hash(data: input))
            } else {
                prev = Data(Insecure.MD5.hash(data: input))
            }
            material.append(prev)
        }
        let key = material.prefix(keyLength)
        let iv: Data = ivLength == 0 ? Data() : material.subdata(in: keyLength..<(keyLength + ivLength))
        return DerivedKeyIV(key: Data(key), iv: iv)
    }
}

enum SniffedCipherKind {
    case enc1
    case opensslSalted
    case plainBase64
    case plainHex
    case urlEncoded
    case plainBase32
    case morse
}

struct SniffedCipher {
    let kind: SniffedCipherKind
    let algorithmId: String?
}

enum CryptoSniffer {
    static func sniffCipher(_ rawText: String) -> SniffedCipher? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if let enc1 = CryptoCipherFormat.enc1TryParse(text),
           Data(base64Encoded: CryptoEncoding.normalizeBase64(enc1.payloadBase64)) != nil {
            return SniffedCipher(kind: .enc1, algorithmId: enc1.algorithmId)
        }

        if CryptoCipherFormat.openSslTryParse(text) != nil {
            return SniffedCipher(kind: .opensslSalted, algorithmId: nil)
        }

        let hasWhitespace = text.rangeOfCharacter(from: .whitespacesAndNewlines) != nil
        if hasWhitespace {
            let lines = text.split(whereSeparator: { $0.isWhitespace }).map(String.init)
            if lines.count >= 2,
               lines.allSatisfy({ $0.count >= 16 && $0.range(of: "^[A-Za-z0-9+/]+={0,2}$", options: .regularExpression) != nil }) {
                return SniffedCipher(kind: .plainBase64, algorithmId: nil)
            }
            if looksLikeMorse(text) {
                return SniffedCipher(kind: .morse, algorithmId: nil)
            }
            return nil
        }

        if text.range(of: "(%[0-9A-Fa-f]{2}){2,}", options: .regularExpression) != nil {
            return SniffedCipher(kind: .urlEncoded, algorithmId: nil)
        }

        if text.range(of: "^([0-9A-Fa-f]{2}[:-]){7,}[0-9A-Fa-f]{2}$", options: .regularExpression) != nil {
            return SniffedCipher(kind: .plainHex, algorithmId: nil)
        }

        if text.count >= 16, text.count.isMultiple(of: 2),
           text.range(of: "^[0-9A-Fa-f]+$", options: .regularExpression) != nil {
            return SniffedCipher(kind: .plainHex, algorithmId: nil)
        }

        if text.count >= 16, text.count.isMultiple(of: 8),
           text.range(of: "^[A-Z2-7]+={0,6}$", options: .regularExpression) != nil,
           text.rangeOfCharacter(from: CharacterSet(charactersIn: "234567")) != nil {
            return SniffedCipher(kind: .plainBase32, algorithmId: nil)
        }

        if text.count >= 16,
           text.range(of: "^[A-Za-z0-9+/_-]+={0,2}$", options: .regularExpression) != nil,
           let bytes = Data(base64Encoded: CryptoEncoding.normalizeBase64(text)),
           !bytes.isEmpty {
            return SniffedCipher(kind: .plainBase64, algorithmId: nil)
        }

        if looksLikeMorse(text) {
            return SniffedCipher(kind: .morse, algorithmId: nil)
        }
        return nil
    }

    static func isDecryptableText(_ plainText: String, codeLanguage: String? = nil) -> Bool {
        if codeLanguage?.lowercased() == "enc" { return true }
        return sniffCipher(plainText) != nil
    }

    private static func looksLikeMorse(_ text: String) -> Bool {
        let normalized = CryptoClassic.normalizeMorseGlyphs(text)
        return normalized.range(of: "^[.\\-/\\s]+$", options: .regularExpression) != nil
            && normalized.contains(".")
            && normalized.contains("-")
    }
}
