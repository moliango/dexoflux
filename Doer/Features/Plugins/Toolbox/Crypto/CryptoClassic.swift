import Foundation

enum CryptoClassic {
    static func normalizeMorseGlyphs(_ text: String) -> String {
        text
            .replacingOccurrences(of: "[\u{2010}\u{2011}\u{2012}\u{2013}\u{2014}\u{2015}\u{2212}]", with: "-", options: .regularExpression)
            .replacingOccurrences(of: "[\u{00b7}\u{2022}\u{25cf}\u{2024}\u{2027}]", with: ".", options: .regularExpression)
    }
}

struct CaesarAlgorithm: CryptoAlgorithm {
    let id = "caesar"
    let category = CryptoAlgorithmCategory.classic
    var displayName: String { String(localized: "crypto.algo.caesar", defaultValue: "凯撒") }

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String {
        Self.shift(plaintext, params.caesarShift % 26)
    }

    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String {
        Self.shift(ciphertext, (26 - (params.caesarShift % 26)) % 26)
    }

    private static func shift(_ input: String, _ shift: Int) -> String {
        String(input.unicodeScalars.map { scalar in
            let v = scalar.value
            if (65...90).contains(v) { return Character(UnicodeScalar(65 + (Int(v) - 65 + shift) % 26)!) }
            if (97...122).contains(v) { return Character(UnicodeScalar(97 + (Int(v) - 97 + shift) % 26)!) }
            return Character(scalar)
        })
    }
}

struct VigenereAlgorithm: CryptoAlgorithm {
    let id = "vigenere"
    let category = CryptoAlgorithmCategory.classic
    var displayName: String { String(localized: "crypto.algo.vigenere", defaultValue: "维吉尼亚") }
    var requiresPassword: Bool { false }

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String {
        try Self.process(plaintext, params: params, decrypt: false)
    }

    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String {
        try Self.process(ciphertext, params: params, decrypt: true)
    }

    private static func process(_ input: String, params: CryptoParams, decrypt: Bool) throws -> String {
        let keyRaw = (params.vigenereKey ?? "").replacingOccurrences(of: "[^A-Za-z]", with: "", options: .regularExpression)
        guard !keyRaw.isEmpty else { throw CryptoException("维吉尼亚密码需要字母密钥") }
        let key = Array(keyRaw.uppercased().utf8)
        var keyIndex = 0
        return String(input.unicodeScalars.map { scalar -> Character in
            let v = scalar.value
            let isUpper = (65...90).contains(v)
            let isLower = (97...122).contains(v)
            guard isUpper || isLower else { return Character(scalar) }
            let shift = Int(key[keyIndex % key.count] - 65)
            keyIndex += 1
            let base: UInt32 = isUpper ? 65 : 97
            let moved = (Int(v - base) + (decrypt ? 26 - shift : shift)) % 26
            return Character(UnicodeScalar(base + UInt32(moved))!)
        })
    }
}

struct RailFenceAlgorithm: CryptoAlgorithm {
    let id = "railfence"
    let category = CryptoAlgorithmCategory.classic
    var displayName: String { String(localized: "crypto.algo.railfence", defaultValue: "栅栏") }

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String {
        let rails = params.railCount
        guard rails >= 2 else { throw CryptoException("栅栏数至少为 2") }
        let chars = Array(plaintext)
        guard chars.count >= 2 else { return plaintext }
        var rows = Array(repeating: "", count: rails)
        var row = 0
        var down = true
        for ch in chars {
            rows[row].append(ch)
            if down {
                row += 1
                if row == rails - 1 { down = false }
            } else {
                row -= 1
                if row == 0 { down = true }
            }
        }
        return rows.joined()
    }

    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String {
        let rails = params.railCount
        guard rails >= 2 else { throw CryptoException("栅栏数至少为 2") }
        let chars = Array(ciphertext)
        let n = chars.count
        guard n >= 2 else { return ciphertext }
        var pattern = Array(repeating: 0, count: n)
        var row = 0
        var down = true
        for i in 0..<n {
            pattern[i] = row
            if down {
                row += 1
                if row == rails - 1 { down = false }
            } else {
                row -= 1
                if row == 0 { down = true }
            }
        }
        var counts = Array(repeating: 0, count: rails)
        for r in pattern { counts[r] += 1 }
        var offsets = Array(repeating: 0, count: rails)
        var acc = 0
        for r in 0..<rails {
            offsets[r] = acc
            acc += counts[r]
        }
        var cursor = offsets
        var out = Array(repeating: Character(" "), count: n)
        for i in 0..<n {
            let r = pattern[i]
            out[i] = chars[cursor[r]]
            cursor[r] += 1
        }
        return String(out)
    }
}

struct MorseAlgorithm: CryptoAlgorithm {
    let id = "morse"
    let category = CryptoAlgorithmCategory.classic
    var displayName: String { String(localized: "crypto.algo.morse", defaultValue: "摩斯电码") }

    private static let toMorse: [Character: String] = [
        "A": ".-", "B": "-...", "C": "-.-.", "D": "-..", "E": ".", "F": "..-.",
        "G": "--.", "H": "....", "I": "..", "J": ".---", "K": "-.-", "L": ".-..",
        "M": "--", "N": "-.", "O": "---", "P": ".--.", "Q": "--.-", "R": ".-.",
        "S": "...", "T": "-", "U": "..-", "V": "...-", "W": ".--", "X": "-..-",
        "Y": "-.--", "Z": "--..",
        "0": "-----", "1": ".----", "2": "..---", "3": "...--", "4": "....-",
        "5": ".....", "6": "-....", "7": "--...", "8": "---..", "9": "----.",
        ".": ".-.-.-", ",": "--..--", "?": "..--..", "!": "-.-.--", "'": ".----.",
        "\"": ".-..-.", "/": "-..-.", "(": "-.--.", ")": "-.--.-", "&": ".-...",
        ":": "---...", ";": "-.-.-.", "=": "-...-", "+": ".-.-.", "-": "-....-",
        "@": ".--.-.",
    ]

    private static let fromMorse: [String: Character] = {
        var map: [String: Character] = [:]
        for (k, v) in toMorse { map[v] = k }
        return map
    }()

    func encrypt(_ plaintext: String, params: CryptoParams) throws -> String {
        plaintext.uppercased().split(separator: " ", omittingEmptySubsequences: false).map { word in
            word.compactMap { Self.toMorse[$0] }.joined(separator: " ")
        }.joined(separator: " / ")
    }

    func decrypt(_ ciphertext: String, params: CryptoParams) throws -> String {
        let tokens = CryptoClassic.normalizeMorseGlyphs(ciphertext)
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
        var out = ""
        for token in tokens {
            if token == "/" {
                out.append(" ")
                continue
            }
            guard let ch = Self.fromMorse[token] else {
                throw CryptoException("无法识别的摩斯码: \(token)")
            }
            out.append(ch)
        }
        return out
    }
}
