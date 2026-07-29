import Foundation

/// Resolves relative URLs against a base URL.
enum URLResolver {
    /// Resolve a potentially relative URL string against a base URL.
    /// Returns the original string if resolution is not possible.
    static func resolve(_ urlString: String, baseURL: String?) -> String {
        // Empty src must stay empty — never collapse to the forum origin as a fake image URL.
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        guard let baseURL, !baseURL.isEmpty else { return trimmed }

        // Already absolute
        if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") || trimmed.hasPrefix("data:") {
            return trimmed
        }

        // Protocol-relative
        if trimmed.hasPrefix("//") {
            return "https:" + trimmed
        }

        guard let base = URL(string: baseURL) else { return trimmed }

        if trimmed.hasPrefix("/") {
            // Absolute path — resolve against scheme + host
            var components = URLComponents()
            components.scheme = base.scheme
            components.host = base.host
            components.port = base.port
            components.path = trimmed
            return components.url?.absoluteString ?? trimmed
        }

        // Relative path
        return base.appendingPathComponent(trimmed).absoluteString
    }
}
