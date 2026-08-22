import CommonCrypto
import Foundation

/// AES-GCM (128-bit tag) for 128/192/256-bit keys. Output is `ciphertext || tag`.
enum CryptoAESGCM {
    static func process(data: Data, key: Data, iv: Data, encrypt: Bool) throws -> Data {
        guard [16, 24, 32].contains(key.count) else {
            throw CryptoException("AES-GCM 需要 128/192/256 位密钥")
        }
        guard iv.count == 12 else {
            throw CryptoException("AES-GCM 需要 12 字节 nonce")
        }
        let h = try encryptBlock(key: key, block: Data(count: 16))
        var j0 = iv
        j0.append(contentsOf: [0, 0, 0, 1])

        if encrypt {
            let ciphertext = try ctr(key: key, counter: inc32(j0), data: data)
            let tag = try authTag(key: key, h: h, j0: j0, ciphertext: ciphertext)
            return ciphertext + tag
        }
        guard data.count >= 16 else { throw CryptoException("密文长度不完整") }
        let ciphertext = Data(data.prefix(data.count - 16))
        let tag = Data(data.suffix(16))
        let expected = try authTag(key: key, h: h, j0: j0, ciphertext: ciphertext)
        guard constantTimeEqual(tag, expected) else {
            throw CryptoException("解密失败：密码错误或密文已损坏")
        }
        return try ctr(key: key, counter: inc32(j0), data: ciphertext)
    }

    private static func authTag(key: Data, h: Data, j0: Data, ciphertext: Data) throws -> Data {
        let s = ghash(h: h, ciphertext: ciphertext)
        return xor16(try encryptBlock(key: key, block: j0), s)
    }

    private static func encryptBlock(key: Data, block: Data) throws -> Data {
        try CryptoSymmetric.crypt(
            algorithm: CCAlgorithm(kCCAlgorithmAES),
            options: CCOptions(kCCOptionECBMode),
            data: block,
            key: key,
            iv: Data(),
            encrypt: true
        )
    }

    private static func ctr(key: Data, counter: Data, data: Data) throws -> Data {
        guard !data.isEmpty else { return Data() }
        var counter = counter
        var out = Data(count: data.count)
        var offset = 0
        let bytes = [UInt8](data)
        while offset < bytes.count {
            let stream = try encryptBlock(key: key, block: counter)
            let n = min(16, bytes.count - offset)
            for i in 0..<n {
                out[offset + i] = bytes[offset + i] ^ stream[i]
            }
            offset += n
            counter = inc32(counter)
        }
        return out
    }

    private static func inc32(_ block: Data) -> Data {
        var out = block
        var carry: UInt16 = 1
        for i in stride(from: 15, through: 12, by: -1) {
            let sum = UInt16(out[i]) + carry
            out[i] = UInt8(sum & 0xff)
            carry = sum >> 8
        }
        return out
    }

    private static func ghash(h: Data, ciphertext: Data) -> Data {
        var y = [UInt8](repeating: 0, count: 16)
        let hBytes = [UInt8](h)
        let cBytes = [UInt8](ciphertext)
        var offset = 0
        while offset < cBytes.count {
            var block = [UInt8](repeating: 0, count: 16)
            let n = min(16, cBytes.count - offset)
            for i in 0..<n { block[i] = cBytes[offset + i] }
            xorInPlace(&y, block)
            y = gfmul(y, hBytes)
            offset += 16
        }
        var lenBlock = [UInt8](repeating: 0, count: 16)
        let bitLen = UInt64(cBytes.count) * 8
        var be = bitLen.bigEndian
        withUnsafeBytes(of: &be) { raw in
            for i in 0..<8 { lenBlock[8 + i] = raw[i] }
        }
        xorInPlace(&y, lenBlock)
        y = gfmul(y, hBytes)
        return Data(y)
    }

    private static func gfmul(_ x: [UInt8], _ y: [UInt8]) -> [UInt8] {
        var z = [UInt8](repeating: 0, count: 16)
        var v = y
        for bit in 0..<128 {
            if x[bit / 8] & (0x80 >> (bit % 8)) != 0 {
                xorInPlace(&z, v)
            }
            let lsb = v[15] & 1
            var carry: UInt8 = 0
            for i in 0..<16 {
                let next = v[i] & 1
                v[i] = (v[i] >> 1) | (carry << 7)
                carry = next
            }
            if lsb != 0 { v[0] ^= 0xe1 }
        }
        return z
    }

    private static func xorInPlace(_ a: inout [UInt8], _ b: [UInt8]) {
        for i in 0..<16 { a[i] ^= b[i] }
    }

    private static func xor16(_ a: Data, _ b: Data) -> Data {
        var out = Data(count: 16)
        for i in 0..<16 { out[i] = a[i] ^ b[i] }
        return out
    }

    private static func constantTimeEqual(_ a: Data, _ b: Data) -> Bool {
        guard a.count == b.count else { return false }
        var acc: UInt8 = 0
        for i in 0..<a.count { acc |= a[i] ^ b[i] }
        return acc == 0
    }
}
