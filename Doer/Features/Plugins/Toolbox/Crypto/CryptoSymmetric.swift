import CommonCrypto
import Foundation
import Security

struct SymmetricCryptoAlgorithm: CryptoAlgorithm {
    let id: String
    let category = CryptoAlgorithmCategory.symmetric
    let keyLength: Int
    let ivLength: Int
    let openSslCompatible: Bool
    let process: (Data, Data, Data, Bool) throws -> Data

    static let saltLength = 16
    static let pbkdf2Iterations = 100_000

    var displayName: String { id.uppercased() }

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String {
        let password = try requirePassword(params)
        let salt = randomBytes(Self.saltLength)
        let iv = ivLength > 0 ? randomBytes(ivLength) : Data()
        let key = try pbkdf2(password: password, salt: salt, length: keyLength)
        let ct = try process(Data(plaintext.utf8), key, iv, true)
        return (salt + iv + ct).base64EncodedString()
    }

    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String {
        let password = try requirePassword(params)
        guard let payload = Data(base64Encoded: CryptoEncoding.normalizeBase64(ciphertext)) else {
            throw CryptoException("密文不是有效的 Base64")
        }
        guard payload.count >= Self.saltLength + ivLength else {
            throw CryptoException("密文长度不完整")
        }
        let salt = payload.prefix(Self.saltLength)
        let iv = payload.subdata(in: Self.saltLength..<(Self.saltLength + ivLength))
        let ct = payload.suffix(from: Self.saltLength + ivLength)
        let key = try pbkdf2(password: password, salt: Data(salt), length: keyLength)
        let plain = try process(Data(ct), key, iv, false)
        return CryptoEncoding.utf8OrLatin1(plain)
    }

    func processBytes(_ data: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        try process(data, key, iv, encrypt)
    }

    private func requirePassword(_ params: CryptoParams) throws -> String {
        let pw = params.password?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pw.isEmpty else { throw CryptoException("请输入加密密码") }
        return pw
    }
}

enum CryptoSymmetric {
    static func randomBytes(_ count: Int) -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { SecRandomCopyBytes(kSecRandomDefault, count, $0.baseAddress!) }
        if status != errSecSuccess {
            for i in 0..<count { data[i] = UInt8.random(in: 0...255) }
        }
        return data
    }

    static func pbkdf2(password: String, salt: Data, length: Int, iterations: Int = SymmetricCryptoAlgorithm.pbkdf2Iterations) throws -> Data {
        var derived = Data(count: length)
        let status = derived.withUnsafeMutableBytes { derivedBytes in
            salt.withUnsafeBytes { saltBytes in
                password.withCString { passPtr in
                    CCKeyDerivationPBKDF(
                        CCPBKDFAlgorithm(kCCPBKDF2),
                        passPtr,
                        password.utf8.count,
                        saltBytes.bindMemory(to: UInt8.self).baseAddress,
                        salt.count,
                        CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
                        UInt32(iterations),
                        derivedBytes.bindMemory(to: UInt8.self).baseAddress,
                        length
                    )
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoException("密钥派生失败") }
        return derived
    }

    static func crypt(
        algorithm: CCAlgorithm,
        options: CCOptions,
        data: Data,
        key: Data,
        iv: Data,
        encrypt: Bool
    ) throws -> Data {
        let bufferSize = data.count + kCCBlockSizeAES128
        var out = Data(count: bufferSize)
        var moved = 0
        let status = out.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { dataBytes in
                key.withUnsafeBytes { keyBytes in
                    iv.withUnsafeBytes { ivBytes in
                        CCCrypt(
                            CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                            algorithm,
                            options,
                            keyBytes.baseAddress,
                            key.count,
                            iv.isEmpty ? nil : ivBytes.baseAddress,
                            dataBytes.baseAddress,
                            data.count,
                            outBytes.baseAddress,
                            bufferSize,
                            &moved
                        )
                    }
                }
            }
        }
        guard status == kCCSuccess else { throw CryptoException(encrypt ? "加密失败" : "解密失败（密码错误或密文损坏）") }
        out.count = moved
        return out
    }

    static func cryptCTR(data: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        var cryptor: CCCryptorRef?
        let create = key.withUnsafeBytes { keyBytes in
            iv.withUnsafeBytes { ivBytes in
                CCCryptorCreateWithMode(
                    CCOperation(encrypt ? kCCEncrypt : kCCDecrypt),
                    CCMode(kCCModeCTR),
                    CCAlgorithm(kCCAlgorithmAES),
                    CCPadding(ccNoPadding),
                    ivBytes.baseAddress,
                    keyBytes.baseAddress,
                    key.count,
                    nil,
                    0,
                    0,
                    CCModeOptions(kCCModeOptionCTR_BE),
                    &cryptor
                )
            }
        }
        guard create == kCCSuccess, let cryptor else { throw CryptoException("CTR 初始化失败") }
        defer { CCCryptorRelease(cryptor) }
        var out = Data(count: data.count)
        var moved = 0
        let status = out.withUnsafeMutableBytes { outBytes in
            data.withUnsafeBytes { dataBytes in
                CCCryptorUpdate(
                    cryptor,
                    dataBytes.baseAddress,
                    data.count,
                    outBytes.baseAddress,
                    data.count,
                    &moved
                )
            }
        }
        guard status == kCCSuccess else { throw CryptoException(encrypt ? "加密失败" : "解密失败（密码错误或密文损坏）") }
        out.count = moved
        return out
    }

    static func aesGCM(data: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        try CryptoAESGCM.process(data: data, key: key, iv: iv, encrypt: encrypt)
    }

    static func rc4(data: Data, key: Data) -> Data {
        var s = Array(UInt8(0)...UInt8(255))
        var j = 0
        let keyBytes = [UInt8](key)
        for i in 0..<256 {
            j = (j + Int(s[i]) + Int(keyBytes[i % keyBytes.count])) % 256
            s.swapAt(i, j)
        }
        var i = 0
        j = 0
        var out = Data(count: data.count)
        for (idx, byte) in data.enumerated() {
            i = (i + 1) % 256
            j = (j + Int(s[i])) % 256
            s.swapAt(i, j)
            let k = s[(Int(s[i]) + Int(s[j])) % 256]
            out[idx] = byte ^ k
        }
        return out
    }

    static func chacha20(data: Data, key: Data, nonce: Data, encrypt: Bool) throws -> Data {
        guard key.count == 32, nonce.count == 12 else { throw CryptoException("ChaCha20 需要 32 字节密钥与 12 字节 nonce") }
        let keyWords = words(from: key)
        let nonceWords = words(from: nonce)
        var out = Data(count: data.count)
        var counter: UInt32 = 1
        var offset = 0
        let input = [UInt8](data)
        while offset < input.count {
            var state: [UInt32] = [
                0x61707865, 0x3320646e, 0x79622d32, 0x6b206574,
                keyWords[0], keyWords[1], keyWords[2], keyWords[3],
                keyWords[4], keyWords[5], keyWords[6], keyWords[7],
                counter, nonceWords[0], nonceWords[1], nonceWords[2],
            ]
            var working = state
            for _ in 0..<10 {
                quarter(&working, 0, 4, 8, 12)
                quarter(&working, 1, 5, 9, 13)
                quarter(&working, 2, 6, 10, 14)
                quarter(&working, 3, 7, 11, 15)
                quarter(&working, 0, 5, 10, 15)
                quarter(&working, 1, 6, 11, 12)
                quarter(&working, 2, 7, 8, 13)
                quarter(&working, 3, 4, 9, 14)
            }
            for i in 0..<16 { working[i] &+= state[i] }
            var block = Data()
            for w in working {
                var le = w.littleEndian
                block.append(Data(bytes: &le, count: 4))
            }
            let n = min(64, input.count - offset)
            for i in 0..<n {
                out[offset + i] = input[offset + i] ^ block[i]
            }
            offset += n
            counter += 1
        }
        return out
    }

    private static func words(from data: Data) -> [UInt32] {
        data.withUnsafeBytes { raw in
            stride(from: 0, to: data.count, by: 4).map { i in
                raw.load(fromByteOffset: i, as: UInt32.self).littleEndian
            }
        }
    }

    private static func rotl(_ x: UInt32, _ n: UInt32) -> UInt32 { (x << n) | (x >> (32 - n)) }

    private static func quarter(_ s: inout [UInt32], _ a: Int, _ b: Int, _ c: Int, _ d: Int) {
        s[a] &+= s[b]; s[d] ^= s[a]; s[d] = rotl(s[d], 16)
        s[c] &+= s[d]; s[b] ^= s[c]; s[b] = rotl(s[b], 12)
        s[a] &+= s[b]; s[d] ^= s[a]; s[d] = rotl(s[d], 8)
        s[c] &+= s[d]; s[b] ^= s[c]; s[b] = rotl(s[b], 7)
    }
}

private func randomBytes(_ count: Int) -> Data { CryptoSymmetric.randomBytes(count) }
private func pbkdf2(password: String, salt: Data, length: Int) throws -> Data {
    try CryptoSymmetric.pbkdf2(password: password, salt: salt, length: length)
}

func makeSymmetricAlgorithms() -> [SymmetricCryptoAlgorithm] {
    func aesCBC(data: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        try CryptoSymmetric.crypt(
            algorithm: CCAlgorithm(kCCAlgorithmAES),
            options: CCOptions(kCCOptionPKCS7Padding),
            data: data,
            key: key,
            iv: iv,
            encrypt: encrypt
        )
    }
    func aesECB(data: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        try CryptoSymmetric.crypt(
            algorithm: CCAlgorithm(kCCAlgorithmAES),
            options: CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode),
            data: data,
            key: key,
            iv: Data(),
            encrypt: encrypt
        )
    }
    func tripleDES(data: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        try CryptoSymmetric.crypt(
            algorithm: CCAlgorithm(kCCAlgorithm3DES),
            options: CCOptions(kCCOptionPKCS7Padding),
            data: data,
            key: key,
            iv: iv,
            encrypt: encrypt
        )
    }

    return [
        SymmetricCryptoAlgorithm(id: "aes-128-cbc", keyLength: 16, ivLength: 16, openSslCompatible: true, process: aesCBC),
        SymmetricCryptoAlgorithm(id: "aes-192-cbc", keyLength: 24, ivLength: 16, openSslCompatible: true, process: aesCBC),
        SymmetricCryptoAlgorithm(id: "aes-256-cbc", keyLength: 32, ivLength: 16, openSslCompatible: true, process: aesCBC),
        SymmetricCryptoAlgorithm(id: "aes-128-ecb", keyLength: 16, ivLength: 0, openSslCompatible: false, process: aesECB),
        SymmetricCryptoAlgorithm(id: "aes-192-ecb", keyLength: 24, ivLength: 0, openSslCompatible: false, process: aesECB),
        SymmetricCryptoAlgorithm(id: "aes-256-ecb", keyLength: 32, ivLength: 0, openSslCompatible: false, process: aesECB),
        SymmetricCryptoAlgorithm(id: "aes-128-gcm", keyLength: 16, ivLength: 12, openSslCompatible: false, process: CryptoSymmetric.aesGCM),
        SymmetricCryptoAlgorithm(id: "aes-192-gcm", keyLength: 24, ivLength: 12, openSslCompatible: false, process: CryptoSymmetric.aesGCM),
        SymmetricCryptoAlgorithm(id: "aes-256-gcm", keyLength: 32, ivLength: 12, openSslCompatible: false, process: CryptoSymmetric.aesGCM),
        SymmetricCryptoAlgorithm(id: "aes-128-ctr", keyLength: 16, ivLength: 16, openSslCompatible: false, process: CryptoSymmetric.cryptCTR),
        SymmetricCryptoAlgorithm(id: "aes-192-ctr", keyLength: 24, ivLength: 16, openSslCompatible: false, process: CryptoSymmetric.cryptCTR),
        SymmetricCryptoAlgorithm(id: "aes-256-ctr", keyLength: 32, ivLength: 16, openSslCompatible: false, process: CryptoSymmetric.cryptCTR),
        SymmetricCryptoAlgorithm(id: "3des-cbc", keyLength: 24, ivLength: 8, openSslCompatible: true, process: tripleDES),
        SymmetricCryptoAlgorithm(id: "blowfish-cbc", keyLength: 16, ivLength: 8, openSslCompatible: true, process: CryptoBlowfish.process),
        SymmetricCryptoAlgorithm(id: "rc4", keyLength: 16, ivLength: 0, openSslCompatible: true) { data, key, _, _ in
            CryptoSymmetric.rc4(data: data, key: key)
        },
        SymmetricCryptoAlgorithm(id: "chacha20", keyLength: 32, ivLength: 12, openSslCompatible: false, process: CryptoSymmetric.chacha20),
    ]
}
