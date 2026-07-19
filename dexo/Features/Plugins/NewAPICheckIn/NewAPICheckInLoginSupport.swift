import Foundation

enum NewAPICheckInLoginSupport {
    nonisolated static func normalizedLoginURL(_ rawValue: String) -> URL? {
        var value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }
        if !value.contains("://") {
            value = "https://\(value)"
        }
        guard let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    nonisolated static func hasValidLoginEvidence(
        apiLoggedIn: Bool,
        hints: NewAPICheckInLoginHints,
        hasTargetCookies: Bool
    ) -> Bool {
        apiLoggedIn || (hasTargetCookies && hints.userID?.isEmpty == false)
    }

    static let localStorageScript = #"""
    (function() {
        try {
            var keys = ['user', 'userInfo', 'currentUser', 'auth', 'state'];
            for (var i = 0; i < keys.length; i++) {
                var raw = localStorage.getItem(keys[i]);
                if (!raw) continue;
                try {
                    var value = JSON.parse(raw);
                    var candidate = value;
                    if (!candidate.id && candidate.user) candidate = candidate.user;
                    if (!candidate.id && candidate.state && candidate.state.user) candidate = candidate.state.user;
                    if (!candidate.id && candidate.state) candidate = candidate.state;
                    var id = candidate.id || candidate.user_id || candidate.userId;
                    if (id !== undefined && id !== null && id !== '') {
                        var token = candidate.access_token || candidate.accessToken ||
                            localStorage.getItem('access_token') || localStorage.getItem('accessToken') || null;
                        return JSON.stringify({ id: String(id), accessToken: token });
                    }
                } catch (e) {}
            }
            return null;
        } catch (e) { return null; }
    })()
    """#

    nonisolated static func parseLocalStorageResult(_ value: Any?) -> NewAPICheckInLoginHints {
        guard let string = value as? String,
              let data = string.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return NewAPICheckInLoginHints(userID: nil, accessToken: nil)
        }
        let userID = object["id"] as? String
        let token = object["accessToken"] as? String
        return NewAPICheckInLoginHints(
            userID: userID?.isEmpty == false ? userID : nil,
            accessToken: token?.isEmpty == false ? token : nil
        )
    }

    nonisolated static func relevantCookies(
        _ cookies: [HTTPCookie],
        baseURL: URL,
        currentURL: URL?
    ) -> [HTTPCookie] {
        var hosts = [baseURL.host].compactMap { $0?.lowercased() }
        if let currentURL, samePlatformFamily(baseURL, currentURL), let currentHost = currentURL.host?.lowercased() {
            hosts.append(currentHost)
        }
        let now = Date()
        return cookies.filter { cookie in
            if let expiresDate = cookie.expiresDate, expiresDate <= now { return false }
            return hosts.contains { cookieMatchesHost(cookie, host: $0) }
        }
    }

    nonisolated static func cookieHeader(
        from cookies: [HTTPCookie],
        baseURL: URL,
        currentURL: URL?
    ) -> String? {
        let relevant = relevantCookies(cookies, baseURL: baseURL, currentURL: currentURL)
        let header = HTTPCookie.requestHeaderFields(with: relevant)["Cookie"]
        return header?.isEmpty == false ? header : nil
    }

    nonisolated static func samePlatformFamily(_ lhs: URL, _ rhs: URL) -> Bool {
        guard let left = lhs.host?.lowercased(), let right = rhs.host?.lowercased() else { return false }
        return left == right || left.hasSuffix(".\(right)") || right.hasSuffix(".\(left)")
    }

    nonisolated private static func cookieMatchesHost(_ cookie: HTTPCookie, host: String) -> Bool {
        let domain = cookie.domain
            .lowercased()
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return host == domain || host.hasSuffix(".\(domain)")
    }
}
