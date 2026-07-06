import Foundation

struct DohConnectRequest {
    let host: String
    let port: UInt16

    enum ParseError: Error {
        case invalidEncoding
        case missingRequestLine
        case unsupportedMethod
        case invalidTarget
        case invalidPort
    }

    static func parse(_ data: Data) throws -> DohConnectRequest {
        guard let header = String(data: data, encoding: .utf8) else {
            throw ParseError.invalidEncoding
        }
        guard let requestLine = header.components(separatedBy: "\r\n").first,
              !requestLine.isEmpty
        else {
            throw ParseError.missingRequestLine
        }

        let parts = requestLine.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2, parts[0].uppercased() == "CONNECT" else {
            throw ParseError.unsupportedMethod
        }

        return try parseTarget(parts[1])
    }

    static func parseTarget(_ target: String) throws -> DohConnectRequest {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ParseError.invalidTarget }

        let host: String
        let portText: String
        if trimmed.hasPrefix("[") {
            guard let closing = trimmed.firstIndex(of: "]") else {
                throw ParseError.invalidTarget
            }
            host = String(trimmed[trimmed.index(after: trimmed.startIndex) ..< closing])
            let remainder = trimmed[trimmed.index(after: closing)...]
            guard remainder.hasPrefix(":") else { throw ParseError.invalidTarget }
            portText = String(remainder.dropFirst())
        } else {
            guard let separator = trimmed.lastIndex(of: ":") else {
                throw ParseError.invalidTarget
            }
            host = String(trimmed[..<separator])
            portText = String(trimmed[trimmed.index(after: separator)...])
        }

        guard !host.isEmpty,
              let parsedPort = UInt16(portText),
              parsedPort > 0
        else {
            throw ParseError.invalidPort
        }

        return DohConnectRequest(host: host.lowercased(), port: parsedPort)
    }
}
