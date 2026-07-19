import Foundation

struct NewAPICurlRequest: Equatable, Sendable {
    let url: URL
    let method: String
    let headers: [String: String]
    let body: String?
}

enum NewAPICurlParseError: Error, Equatable, Sendable {
    case missingURL
    case invalidURL(String)
    case malformed(String)
}

enum NewAPICurlParser {
    nonisolated static func parse(_ input: String) throws -> NewAPICurlRequest {
        let tokens = try tokenize(input)
        guard !tokens.isEmpty else {
            throw NewAPICurlParseError.malformed("empty input")
        }

        var index = isCurlExecutable(tokens[0]) ? 1 : 0
        var urlString: String?
        var explicitMethod: String?
        var headers: [String: String] = [:]
        var body: String?
        var hasData = false

        while index < tokens.count {
            let token = tokens[index]
            let (option, attachedValue) = splitOption(token)

            switch option {
            case "-X", "--request":
                let value = try requiredValue(attachedValue, option: option, tokens: tokens, index: &index)
                explicitMethod = value.uppercased()

            case "-H", "--header":
                let value = try requiredValue(attachedValue, option: option, tokens: tokens, index: &index)
                if let header = splitHeader(value) {
                    setHeader(header.value, for: header.name, in: &headers)
                }

            case "-b", "--cookie":
                let value = try requiredValue(attachedValue, option: option, tokens: tokens, index: &index)
                guard headerValue(named: "Cookie", in: headers) == nil else { break }
                if let header = splitHeader(value), header.name.caseInsensitiveCompare("Cookie") == .orderedSame {
                    setHeader(header.value, for: "Cookie", in: &headers)
                } else {
                    setHeader(value, for: "Cookie", in: &headers)
                }

            case "--url":
                urlString = try requiredValue(attachedValue, option: option, tokens: tokens, index: &index)

            case "-A", "--user-agent":
                let value = try requiredValue(attachedValue, option: option, tokens: tokens, index: &index)
                setHeader(value, for: "User-Agent", in: &headers)

            case "-e", "--referer":
                let value = try requiredValue(attachedValue, option: option, tokens: tokens, index: &index)
                setHeader(value, for: "Referer", in: &headers)

            case "-d", "--data", "--data-raw", "--data-binary", "--data-urlencode":
                body = try requiredValue(attachedValue, option: option, tokens: tokens, index: &index)
                hasData = true

            case "--connect-timeout", "--max-time", "--output", "-o", "--proxy", "-x", "--retry", "--user", "-u":
                _ = try requiredValue(attachedValue, option: option, tokens: tokens, index: &index)

            case "--compressed", "--location", "-L", "--silent", "-s", "--show-error", "-S", "--insecure", "-k":
                break

            case let value where value.hasPrefix("-"):
                // Unknown options are ignored, but their following token is not consumed.
                // This prevents a flag such as --location from swallowing the request URL.
                break

            default:
                if urlString == nil {
                    urlString = token
                }
            }

            index += 1
        }

        guard let urlString else {
            throw NewAPICurlParseError.missingURL
        }
        guard
            let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host != nil
        else {
            throw NewAPICurlParseError.invalidURL(urlString)
        }

        return NewAPICurlRequest(
            url: url,
            method: explicitMethod ?? (hasData ? "POST" : "GET"),
            headers: headers,
            body: body
        )
    }

    private nonisolated static func tokenize(_ input: String) throws -> [String] {
        let characters = Array(input)
        var tokens: [String] = []
        var current = ""
        var tokenStarted = false
        var quote: Character?
        var index = 0

        while index < characters.count {
            let character = characters[index]

            if character == "\\", quote != "'" {
                guard index + 1 < characters.count else {
                    current.append(character)
                    tokenStarted = true
                    index += 1
                    continue
                }

                let next = characters[index + 1]
                if next == "\n" {
                    index += 2
                    continue
                }
                if next == "\r", index + 2 < characters.count, characters[index + 2] == "\n" {
                    index += 3
                    continue
                }

                current.append(next)
                tokenStarted = true
                index += 2
                continue
            }

            if character == "'" || character == "\"" {
                if quote == nil {
                    quote = character
                    tokenStarted = true
                    index += 1
                    continue
                }
                if quote == character {
                    quote = nil
                    index += 1
                    continue
                }
            }

            if character.isWhitespace, quote == nil {
                if tokenStarted {
                    tokens.append(current)
                    current = ""
                    tokenStarted = false
                }
            } else {
                current.append(character)
                tokenStarted = true
            }
            index += 1
        }

        if let quote {
            let kind = quote == "'" ? "single" : "double"
            throw NewAPICurlParseError.malformed("unterminated \(kind) quote")
        }
        if tokenStarted {
            tokens.append(current)
        }
        return tokens
    }

    private nonisolated static func requiredValue(
        _ attachedValue: String?,
        option: String,
        tokens: [String],
        index: inout Int
    ) throws -> String {
        if let attachedValue {
            return attachedValue
        }
        guard index + 1 < tokens.count else {
            throw NewAPICurlParseError.malformed("\(option) needs a value")
        }
        index += 1
        return tokens[index]
    }

    private nonisolated static func splitOption(_ token: String) -> (String, String?) {
        guard token.hasPrefix("--"), let separator = token.firstIndex(of: "=") else {
            return (token, nil)
        }
        return (String(token[..<separator]), String(token[token.index(after: separator)...]))
    }

    private nonisolated static func splitHeader(_ value: String) -> (name: String, value: String)? {
        guard let separator = value.firstIndex(of: ":") else { return nil }
        let name = value[..<separator].trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return nil }
        let headerValue = value[value.index(after: separator)...].trimmingCharacters(in: .whitespaces)
        return (name, headerValue)
    }

    private nonisolated static func headerValue(named name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
    }

    private nonisolated static func setHeader(_ value: String, for name: String, in headers: inout [String: String]) {
        if let existing = headers.keys.first(where: { $0.caseInsensitiveCompare(name) == .orderedSame }) {
            headers.removeValue(forKey: existing)
        }
        headers[name] = value
    }

    private nonisolated static func isCurlExecutable(_ token: String) -> Bool {
        token.split(separator: "/").last?.lowercased() == "curl"
    }
}
