import Foundation

/// Configuration options for the HTML parser.
public struct ParseOptions: Sendable {
    /// Base URL for resolving relative URLs in the HTML content.
    public let baseURL: String?

    public init(baseURL: String? = nil) {
        self.baseURL = baseURL
    }
}
