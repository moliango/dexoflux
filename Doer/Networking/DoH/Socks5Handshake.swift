import Foundation

enum Socks5Handshake {
    static let version: UInt8 = 0x05
    static let methodNoAuth: UInt8 = 0x00
    static let commandConnect: UInt8 = 0x01
    static let addressIPv4: UInt8 = 0x01
    static let addressDomain: UInt8 = 0x03
    static let addressIPv6: UInt8 = 0x04

    static let authOK = Data([version, methodNoAuth])
    static let connectOK = Data([
        version, 0x00, 0x00, addressIPv4,
        0, 0, 0, 0,
        0, 0,
    ])
    static let connectFailed = Data([
        version, 0x05, 0x00, addressIPv4,
        0, 0, 0, 0,
        0, 0,
    ])

    enum ParseError: Error {
        case incomplete
        case invalidVersion
        case unsupportedMethod
        case unsupportedCommand
        case unsupportedAddress
        case invalidDomain
    }

    static func consumeGreeting(_ buffer: Data) throws -> Data? {
        guard buffer.count >= 2 else { return nil }
        guard buffer[0] == version else { throw ParseError.invalidVersion }
        let methodCount = Int(buffer[1])
        guard buffer.count >= 2 + methodCount else { return nil }
        let methods = buffer.subdata(in: 2 ..< (2 + methodCount))
        guard methods.contains(methodNoAuth) else { throw ParseError.unsupportedMethod }
        return buffer.subdata(in: (2 + methodCount) ..< buffer.endIndex)
    }

    static func consumeConnect(_ buffer: Data) throws -> (host: String, port: UInt16, remainder: Data)? {
        guard buffer.count >= 7 else { return nil }
        guard buffer[0] == version else { throw ParseError.invalidVersion }
        guard buffer[1] == commandConnect else { throw ParseError.unsupportedCommand }
        let atyp = buffer[3]
        var offset = 4
        let host: String
        switch atyp {
        case addressIPv4:
            guard buffer.count >= offset + 4 + 2 else { return nil }
            host = (0 ..< 4).map { String(buffer[offset + $0]) }.joined(separator: ".")
            offset += 4
        case addressDomain:
            guard buffer.count >= offset + 1 else { return nil }
            let length = Int(buffer[offset])
            offset += 1
            guard buffer.count >= offset + length + 2 else { return nil }
            let domainData = buffer.subdata(in: offset ..< (offset + length))
            guard let domain = String(data: domainData, encoding: .utf8), !domain.isEmpty else {
                throw ParseError.invalidDomain
            }
            host = domain
            offset += length
        case addressIPv6:
            guard buffer.count >= offset + 16 + 2 else { return nil }
            var groups: [String] = []
            var index = offset
            while index < offset + 16 {
                let value = (UInt16(buffer[index]) << 8) | UInt16(buffer[index + 1])
                groups.append(String(format: "%x", value))
                index += 2
            }
            host = groups.joined(separator: ":")
            offset += 16
        default:
            throw ParseError.unsupportedAddress
        }
        let port = (UInt16(buffer[offset]) << 8) | UInt16(buffer[offset + 1])
        offset += 2
        return (host.lowercased(), port, buffer.subdata(in: offset ..< buffer.endIndex))
    }
}
