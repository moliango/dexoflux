import CryptoKit
import Foundation

struct DecryptSuggestion {
    let algorithmId: String?
    let kind: SniffedCipherKind?
}

enum CryptoToolbox {
    static let defaultAlgorithmId = "aes-256-cbc"

    private static let registry: [String: any CryptoAlgorithm] = {
        var map: [String: any CryptoAlgorithm] = [:]
        for algo in allAlgorithms {
            map[algo.id] = algo
        }
        return map
    }()

    static let allAlgorithms: [any CryptoAlgorithm] = {
        var list: [any CryptoAlgorithm] = [
            Base64CryptoAlgorithm(),
            Base32CryptoAlgorithm(),
            HexCryptoAlgorithm(),
            URLEncodeCryptoAlgorithm(),
            Rot13CryptoAlgorithm(),
        ]
        list.append(contentsOf: makeSymmetricAlgorithms().map { $0 as any CryptoAlgorithm })
        let rest: [any CryptoAlgorithm] = [
            HashCryptoAlgorithm(id: "md5") { Data(Insecure.MD5.hash(data: $0)) },
            HashCryptoAlgorithm(id: "sha1") { Data(Insecure.SHA1.hash(data: $0)) },
            HashCryptoAlgorithm(id: "sha256") { Data(SHA256.hash(data: $0)) },
            HashCryptoAlgorithm(id: "sha512") { Data(SHA512.hash(data: $0)) },
            SM3HashAlgorithm(),
            RSAOAEPAlgorithm(),
            CaesarAlgorithm(),
            VigenereAlgorithm(),
            RailFenceAlgorithm(),
            MorseAlgorithm(),
        ]
        list.append(contentsOf: rest)
        return list
    }()

    static func byId(_ id: String) -> (any CryptoAlgorithm)? { registry[id] }

    static func algorithms(in category: CryptoAlgorithmCategory) -> [any CryptoAlgorithm] {
        var algos = allAlgorithms.filter { $0.category == category }
        if category == .symmetric {
            algos.sort { lhs, rhs in
                func rank(_ id: String) -> Int {
                    if id.hasSuffix("-cbc") { return 0 }
                    if id.contains("gcm") { return 1 }
                    return 2
                }
                let l = rank(lhs.id)
                let r = rank(rhs.id)
                return l == r ? lhs.id < rhs.id : l < r
            }
        }
        return algos
    }

    static func encrypt(
        plaintext: String,
        algorithmId: String,
        params: CryptoParams,
        format: CryptoOutputFormat = .enc1
    ) throws -> String {
        guard let algo = registry[algorithmId] else { throw CryptoException("未知算法: \(algorithmId)") }
        switch algo.category {
        case .encoding, .hash, .classic:
            return try algo.encrypt(plaintext, params: params)
        case .asymmetric:
            return CryptoCipherFormat.enc1Pack(algorithmId: algo.id, payloadBase64: try algo.encrypt(plaintext, params: params))
        case .symmetric:
            guard let sym = algo as? SymmetricCryptoAlgorithm else {
                throw CryptoException("未知算法: \(algorithmId)")
            }
            if format == .openssl {
                guard sym.openSslCompatible else {
                    throw CryptoException("\(sym.displayName) 不支持 OpenSSL 兼容输出（仅 CBC 系列与 RC4）")
                }
                return try openSslEncrypt(sym, plaintext: plaintext, params: params)
            }
            return CryptoCipherFormat.enc1Pack(algorithmId: sym.id, payloadBase64: try sym.encrypt(plaintext, params: params))
        }
    }

    static func decrypt(ciphertext: String, algorithmId: String, params: CryptoParams) throws -> String {
        guard let algo = registry[algorithmId] else { throw CryptoException("未知算法: \(algorithmId)") }
        switch algo.category {
        case .encoding, .hash, .classic:
            return try algo.decrypt(ciphertext, params: params)
        case .asymmetric:
            let payload = CryptoCipherFormat.enc1TryParse(ciphertext)?.payloadBase64 ?? ciphertext
            return try algo.decrypt(payload, params: params)
        case .symmetric:
            guard let sym = algo as? SymmetricCryptoAlgorithm else {
                throw CryptoException("未知算法: \(algorithmId)")
            }
            return try symmetricDecrypt(sym, ciphertext: ciphertext, params: params)
        }
    }

    static func suggestDecrypt(_ ciphertext: String) -> DecryptSuggestion {
        guard let sniffed = CryptoSniffer.sniffCipher(ciphertext) else {
            return DecryptSuggestion(algorithmId: nil, kind: nil)
        }
        switch sniffed.kind {
        case .enc1:
            let known = sniffed.algorithmId.flatMap { registry[$0] } != nil
            return DecryptSuggestion(
                algorithmId: known ? sniffed.algorithmId : defaultAlgorithmId,
                kind: sniffed.kind
            )
        case .opensslSalted:
            return DecryptSuggestion(algorithmId: "aes-256-cbc", kind: .opensslSalted)
        case .plainBase64:
            if let bytes = tryDecodeBase64(ciphertext), !looksLikeUTF8Text(bytes) {
                return DecryptSuggestion(algorithmId: defaultAlgorithmId, kind: .plainBase64)
            }
            return DecryptSuggestion(algorithmId: "base64", kind: .plainBase64)
        case .plainHex:
            if let bytes = try? CryptoEncoding.hexDecode(ciphertext), !looksLikeUTF8Text(bytes) {
                return DecryptSuggestion(algorithmId: defaultAlgorithmId, kind: .plainHex)
            }
            return DecryptSuggestion(algorithmId: "hex", kind: .plainHex)
        case .plainBase32:
            return DecryptSuggestion(algorithmId: "base32", kind: .plainBase32)
        case .urlEncoded:
            return DecryptSuggestion(algorithmId: "url", kind: .urlEncoded)
        case .morse:
            return DecryptSuggestion(algorithmId: "morse", kind: .morse)
        }
    }

    private static func openSslEncrypt(_ sym: SymmetricCryptoAlgorithm, plaintext: String, params: CryptoParams) throws -> String {
        let pw = params.password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pw.isEmpty else { throw CryptoException("请输入加密密码") }
        let salt = CryptoSymmetric.randomBytes(8)
        let derived = CryptoCipherFormat.evpBytesToKey(
            password: pw,
            salt: salt,
            keyLength: sym.keyLength,
            ivLength: sym.ivLength,
            useSHA256: true
        )
        let ct = try sym.processBytes(Data(plaintext.utf8), key: derived.key, iv: derived.iv, encrypt: true)
        return CryptoCipherFormat.openSslPack(salt: salt, ciphertext: ct)
    }

    private static func symmetricDecrypt(_ sym: SymmetricCryptoAlgorithm, ciphertext: String, params: CryptoParams) throws -> String {
        if let enc1 = CryptoCipherFormat.enc1TryParse(ciphertext) {
            if let inner = registry[enc1.algorithmId] as? SymmetricCryptoAlgorithm, inner.id == sym.id {
                return try inner.decrypt(enc1.payloadBase64, params: params)
            }
            return try sym.decrypt(enc1.payloadBase64, params: params)
        }
        if let ossl = CryptoCipherFormat.openSslTryParse(ciphertext) {
            guard sym.openSslCompatible else {
                throw CryptoException("OpenSSL Salted 密文需要 CBC 系列或 RC4 算法（当前: \(sym.displayName)）")
            }
            let pw = params.password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !pw.isEmpty else { throw CryptoException("请输入加密密码") }
            var lastError: Error?
            for useSHA256 in [true, false] {
                do {
                    let derived = CryptoCipherFormat.evpBytesToKey(
                        password: pw,
                        salt: ossl.salt,
                        keyLength: sym.keyLength,
                        ivLength: sym.ivLength,
                        useSHA256: useSHA256
                    )
                    let pt = try sym.processBytes(ossl.ciphertext, key: derived.key, iv: derived.iv, encrypt: false)
                    return CryptoEncoding.utf8OrLatin1(pt)
                } catch {
                    lastError = error
                }
            }
            throw lastError ?? CryptoException("解密失败（密码错误或密文损坏）")
        }
        return try sym.decrypt(ciphertext, params: params)
    }

    private static func tryDecodeBase64(_ text: String) -> Data? {
        Data(base64Encoded: CryptoEncoding.normalizeBase64(text.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)))
    }

    private static func looksLikeUTF8Text(_ bytes: Data) -> Bool {
        guard let decoded = String(data: bytes, encoding: .utf8) else { return false }
        for unit in decoded.unicodeScalars {
            let v = unit.value
            if (v < 0x20 && v != 0x09 && v != 0x0a && v != 0x0d) || v == 0xfffd {
                return false
            }
        }
        return true
    }
}
