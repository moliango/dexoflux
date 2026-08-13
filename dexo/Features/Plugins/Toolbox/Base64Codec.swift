import Foundation

/// UTF-8 text Base64 encode / decode helpers used by the Toolbox mini-program.
enum Base64Codec {
    enum Mode: String, CaseIterable {
        case standard
        /// RFC 4648 URL-safe alphabet (`-` / `_`), padding optional on decode.
        case urlSafe
    }

    enum DecodeError: LocalizedError, Equatable {
        case emptyInput
        case invalidBase64
        case invalidUTF8

        var errorDescription: String? {
            switch self {
            case .emptyInput:
                return String(localized: "toolbox.base64.error.empty", defaultValue: "请输入内容")
            case .invalidBase64:
                return String(
                    localized: "toolbox.base64.error.invalid",
                    defaultValue: "不是有效的 Base64 字符串"
                )
            case .invalidUTF8:
                return String(
                    localized: "toolbox.base64.error.utf8",
                    defaultValue: "解码结果不是有效的 UTF-8 文本"
                )
            }
        }
    }

    static func encode(_ text: String, mode: Mode = .standard) -> String {
        let data = Data(text.utf8)
        var encoded = data.base64EncodedString()
        if mode == .urlSafe {
            encoded = encoded
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
        }
        return encoded
    }

    static func decode(_ text: String, mode: Mode = .standard) -> Result<String, DecodeError> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.emptyInput) }

        var normalized = trimmed
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: " ", with: "")

        if mode == .urlSafe {
            normalized = normalized
                .replacingOccurrences(of: "-", with: "+")
                .replacingOccurrences(of: "_", with: "/")
        }

        // Restore missing padding so Data(base64Encoded:) accepts the string.
        let remainder = normalized.count % 4
        if remainder > 0 {
            normalized += String(repeating: "=", count: 4 - remainder)
        }

        guard let data = Data(base64Encoded: normalized, options: .ignoreUnknownCharacters) else {
            return .failure(.invalidBase64)
        }
        guard let string = String(data: data, encoding: .utf8) else {
            return .failure(.invalidUTF8)
        }
        return .success(string)
    }
}
