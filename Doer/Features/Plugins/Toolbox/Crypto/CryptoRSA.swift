import Foundation
import Security

struct RSAOAEPAlgorithm: CryptoAlgorithm {
    let id = "rsa-oaep-sha256"
    let category = CryptoAlgorithmCategory.asymmetric
    var displayName: String { "RSA-OAEP-SHA256" }

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String {
        let pem = params.rsaPem?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pem.isEmpty else { throw CryptoException("请粘贴 RSA 公钥 PEM") }
        let key = try RSAKeyParser.publicKey(fromPEM: pem)
        let data = Data(plaintext.utf8)
        let block = max(SecKeyGetBlockSize(key) - 66, 1)
        var out = Data()
        var offset = 0
        while offset < data.count {
            let end = min(offset + block, data.count)
            let chunk = data.subdata(in: offset..<end)
            var error: Unmanaged<CFError>?
            guard let encrypted = SecKeyCreateEncryptedData(key, .rsaEncryptionOAEPSHA256, chunk as CFData, &error) as Data? else {
                throw CryptoException((error?.takeRetainedValue() as Error?)?.localizedDescription ?? "RSA 加密失败")
            }
            out.append(encrypted)
            offset = end
        }
        return out.base64EncodedString()
    }

    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String {
        let pem = params.rsaPem?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pem.isEmpty else { throw CryptoException("请粘贴 RSA 私钥 PEM") }
        let key = try RSAKeyParser.privateKey(fromPEM: pem)
        guard let payload = Data(base64Encoded: CryptoEncoding.normalizeBase64(ciphertext)) else {
            throw CryptoException("密文不是有效的 Base64")
        }
        let block = SecKeyGetBlockSize(key)
        guard block > 0, payload.count.isMultiple(of: block) else {
            throw CryptoException("RSA 密文长度不完整")
        }
        var out = Data()
        var offset = 0
        while offset < payload.count {
            let chunk = payload.subdata(in: offset..<(offset + block))
            var error: Unmanaged<CFError>?
            guard let decrypted = SecKeyCreateDecryptedData(key, .rsaEncryptionOAEPSHA256, chunk as CFData, &error) as Data? else {
                throw CryptoException((error?.takeRetainedValue() as Error?)?.localizedDescription ?? "RSA 解密失败")
            }
            out.append(decrypted)
            offset += block
        }
        return CryptoEncoding.utf8OrLatin1(out)
    }
}

enum RSAKeyParser {
    static func publicKey(fromPEM pem: String) throws -> SecKey {
        let (label, der) = try parsePEM(pem)
        switch label {
        case "PUBLIC KEY", "RSA PUBLIC KEY":
            return try makeKey(der, class: kSecAttrKeyClassPublic)
        default:
            throw CryptoException("加密需要公钥 PEM（PUBLIC KEY / RSA PUBLIC KEY）")
        }
    }

    static func privateKey(fromPEM pem: String) throws -> SecKey {
        let (label, der) = try parsePEM(pem)
        switch label {
        case "PRIVATE KEY", "RSA PRIVATE KEY":
            return try makeKey(der, class: kSecAttrKeyClassPrivate)
        case "ENCRYPTED PRIVATE KEY":
            throw CryptoException("暂不支持加密私钥，请先用 openssl 去除口令")
        default:
            throw CryptoException("解密需要私钥 PEM（PRIVATE KEY / RSA PRIVATE KEY）")
        }
    }

    private static func parsePEM(_ pem: String) throws -> (String, Data) {
        guard let match = pem.range(of: "-----BEGIN ([A-Z ]+)-----", options: .regularExpression) else {
            throw CryptoException("未找到 PEM 密钥（缺少 -----BEGIN 行）")
        }
        let header = String(pem[match])
        let label = header
            .replacingOccurrences(of: "-----BEGIN ", with: "")
            .replacingOccurrences(of: "-----", with: "")
            .trimmingCharacters(in: .whitespaces)
        let body = pem
            .replacingOccurrences(of: "-----[A-Z ]+-----", with: "", options: .regularExpression)
            .replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        guard let der = Data(base64Encoded: CryptoEncoding.normalizeBase64(body)) else {
            throw CryptoException("PEM 内容不是有效的 Base64")
        }
        return (label, der)
    }

    private static func makeKey(_ der: Data, class keyClass: CFString) throws -> SecKey {
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass as String: keyClass,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateWithData(der as CFData, attrs as CFDictionary, &error) else {
            throw CryptoException((error?.takeRetainedValue() as Error?)?.localizedDescription ?? "无法解析 RSA PEM")
        }
        return key
    }
}
