import CryptoKit
import Foundation

enum CryptoEncoding {
    static func normalizeBase64(_ input: String) -> String {
        var text = input.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
        if text.contains("-") || text.contains("_") {
            text = text.replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        }
        switch text.count % 4 {
        case 2: text += "=="
        case 3: text += "="
        default: break
        }
        return text
    }

    static func utf8OrLatin1(_ data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }
        return String(data: data, encoding: .isoLatin1) ?? ""
    }

    static func hexEncode(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func hexDecode(_ text: String) throws -> Data {
        let clean = text.replacingOccurrences(of: "[\\s:,-]", with: "", options: .regularExpression)
        guard !clean.isEmpty else { return Data() }
        guard clean.count.isMultiple(of: 2), clean.range(of: "^[0-9A-Fa-f]+$", options: .regularExpression) != nil else {
            throw CryptoException("无效的 Hex 密文（需为偶数长度的十六进制字符）")
        }
        var data = Data()
        var index = clean.startIndex
        while index < clean.endIndex {
            let next = clean.index(index, offsetBy: 2)
            guard let byte = UInt8(clean[index..<next], radix: 16) else {
                throw CryptoException("无效的 Hex 密文（需为偶数长度的十六进制字符）")
            }
            data.append(byte)
            index = next
        }
        return data
    }
}

struct Base64CryptoAlgorithm: CryptoAlgorithm {
    let id = "base64"
    let category = CryptoAlgorithmCategory.encoding

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String {
        Data(plaintext.utf8).base64EncodedString()
    }

    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String {
        guard let data = Data(base64Encoded: CryptoEncoding.normalizeBase64(ciphertext)) else {
            throw CryptoException("无效的 Base64 密文")
        }
        return CryptoEncoding.utf8OrLatin1(data)
    }
}

struct Base32CryptoAlgorithm: CryptoAlgorithm {
    let id = "base32"
    let category = CryptoAlgorithmCategory.encoding
    private static let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ234567")

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String {
        let bytes = Array(plaintext.utf8)
        var buffer = 0
        var bits = 0
        var out = ""
        for b in bytes {
            buffer = (buffer << 8) | Int(b)
            bits += 8
            while bits >= 5 {
                bits -= 5
                out.append(Self.alphabet[(buffer >> bits) & 0x1f])
            }
            buffer &= (1 << bits) - 1
        }
        if bits > 0 {
            out.append(Self.alphabet[(buffer << (5 - bits)) & 0x1f])
        }
        while out.count % 8 != 0 { out.append("=") }
        return out
    }

    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String {
        let clean = ciphertext.uppercased().replacingOccurrences(of: "[\\s=]", with: "", options: .regularExpression)
        guard !clean.isEmpty else { return "" }
        var buffer = 0
        var bits = 0
        var out = Data()
        for ch in clean {
            guard let v = Self.alphabet.firstIndex(of: ch) else {
                throw CryptoException("无效的 Base32 字符: \(ch)")
            }
            buffer = (buffer << 5) | v
            bits += 5
            if bits >= 8 {
                bits -= 8
                out.append(UInt8((buffer >> bits) & 0xff))
            }
            buffer &= (1 << bits) - 1
        }
        guard let text = String(data: out, encoding: .utf8) else {
            throw CryptoException("Base32 解码失败：内容不是有效的 UTF-8 文本")
        }
        return text
    }
}

struct HexCryptoAlgorithm: CryptoAlgorithm {
    let id = "hex"
    let category = CryptoAlgorithmCategory.encoding

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String {
        CryptoEncoding.hexEncode(Data(plaintext.utf8))
    }

    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String {
        let data = try CryptoEncoding.hexDecode(ciphertext)
        guard let text = String(data: data, encoding: .utf8) else {
            throw CryptoException("Hex 解码失败：内容不是有效的 UTF-8 文本")
        }
        return text
    }
}

struct URLEncodeCryptoAlgorithm: CryptoAlgorithm {
    let id = "url"
    let category = CryptoAlgorithmCategory.encoding
    var displayName: String { "URL" }

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String {
        plaintext.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: ":/?#[]@!$&'()*+,;=")))
            ?? plaintext
    }

    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String {
        ciphertext.removingPercentEncoding ?? ciphertext
    }
}

struct Rot13CryptoAlgorithm: CryptoAlgorithm {
    let id = "rot13"
    let category = CryptoAlgorithmCategory.encoding

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String { Self.rot13(plaintext) }
    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String { Self.rot13(ciphertext) }

    private static func rot13(_ input: String) -> String {
        String(input.unicodeScalars.map { scalar in
            let v = scalar.value
            if (65...90).contains(v) { return Character(UnicodeScalar(65 + (v - 65 + 13) % 26)!) }
            if (97...122).contains(v) { return Character(UnicodeScalar(97 + (v - 97 + 13) % 26)!) }
            return Character(scalar)
        })
    }
}

struct HashCryptoAlgorithm: CryptoAlgorithm {
    let id: String
    let category = CryptoAlgorithmCategory.hash
    private let digest: (Data) -> Data

    init(id: String, digest: @escaping (Data) -> Data) {
        self.id = id
        self.digest = digest
    }

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String {
        CryptoEncoding.hexEncode(digest(Data(plaintext.utf8)))
    }

    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String {
        throw CryptoException("哈希是单向摘要，无法解密")
    }
}

enum SM3 {
    static func hash(_ message: Data) -> Data {
        var bytes = [UInt8](message)
        let bitLen = UInt64(bytes.count) * 8
        bytes.append(0x80)
        while (bytes.count % 64) != 56 { bytes.append(0) }
        bytes.append(contentsOf: withUnsafeBytes(of: bitLen.bigEndian, Array.init))

        var v: [UInt32] = [
            0x7380166f, 0x4914b2b9, 0x172442d7, 0xda8a0600,
            0xa96f30bc, 0x163138aa, 0xe38dee4d, 0xb0fb0e4e,
        ]
        let n = bytes.count / 64
        for i in 0..<n {
            let block = Array(bytes[i * 64..<(i + 1) * 64])
            compress(block, v: &v)
        }
        var out = Data()
        for w in v {
            var be = w.bigEndian
            out.append(Data(bytes: &be, count: 4))
        }
        return out
    }

    private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 {
        (x << n) | (x >> (32 - n))
    }

    private static func compress(_ block: [UInt8], v: inout [UInt32]) {
        var w = [UInt32](repeating: 0, count: 68)
        var w1 = [UInt32](repeating: 0, count: 64)
        for i in 0..<16 {
            w[i] = (UInt32(block[i * 4]) << 24)
                | (UInt32(block[i * 4 + 1]) << 16)
                | (UInt32(block[i * 4 + 2]) << 8)
                | UInt32(block[i * 4 + 3])
        }
        for j in 16..<68 {
            w[j] = p1(w[j - 16] ^ w[j - 9] ^ rotl(w[j - 3], 15)) ^ rotl(w[j - 13], 7) ^ w[j - 6]
        }
        for j in 0..<64 { w1[j] = w[j] ^ w[j + 4] }

        var a = v[0], b = v[1], c = v[2], d = v[3]
        var e = v[4], f = v[5], g = v[6], h = v[7]
        for j in 0..<64 {
            let tj: UInt32 = j < 16 ? 0x79cc4519 : 0x7a879d8a
            let ss1 = rotl(rotl(a, 12) &+ e &+ rotl(tj, UInt32(j)), 7)
            let ss2 = ss1 ^ rotl(a, 12)
            let tt1 = (j < 16 ? (a ^ b ^ c) : ff1(a, b, c)) &+ d &+ ss2 &+ w1[j]
            let tt2 = (j < 16 ? (e ^ f ^ g) : gg1(e, f, g)) &+ h &+ ss1 &+ w[j]
            d = c; c = rotl(b, 9); b = a; a = tt1
            h = g; g = rotl(f, 19); f = e; e = p0(tt2)
        }
        v[0] ^= a; v[1] ^= b; v[2] ^= c; v[3] ^= d
        v[4] ^= e; v[5] ^= f; v[6] ^= g; v[7] ^= h
    }

    private static func ff1(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & y) | (x & z) | (y & z) }
    private static func gg1(_ x: UInt32, _ y: UInt32, _ z: UInt32) -> UInt32 { (x & y) | (~x & z) }
    private static func p0(_ x: UInt32) -> UInt32 { x ^ rotl(x, 9) ^ rotl(x, 17) }
    private static func p1(_ x: UInt32) -> UInt32 { x ^ rotl(x, 15) ^ rotl(x, 23) }
}

struct SM3HashAlgorithm: CryptoAlgorithm {
    let id = "sm3"
    let category = CryptoAlgorithmCategory.hash

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String {
        CryptoEncoding.hexEncode(SM3.hash(Data(plaintext.utf8)))
    }

    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String {
        throw CryptoException("哈希是单向摘要，无法解密")
    }
}
