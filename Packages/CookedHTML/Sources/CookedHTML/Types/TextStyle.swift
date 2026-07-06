import Foundation

/// Style attributes for inline text, combinable via OptionSet.
public struct TextStyle: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let bold          = TextStyle(rawValue: 1 << 0)
    public static let italic        = TextStyle(rawValue: 1 << 1)
    public static let strikethrough = TextStyle(rawValue: 1 << 2)
}
