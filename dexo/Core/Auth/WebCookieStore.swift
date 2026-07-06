import Foundation
import WebKit

/// In-memory + persisted cookie store used for web-login sessions.
/// Cookies are keyed by "domain|name|path" for deduplication.
final class WebCookieStore {
    static let shared = WebCookieStore()

    private var jar: [String: HTTPCookie] = [:]
    private let lock = NSLock()
    private let filePath: URL
    private static let maxAgeKey = HTTPCookiePropertyKey("Max-Age")
    private static let httpOnlyKey = HTTPCookiePropertyKey("HttpOnly")
    private static let sameSiteKey = HTTPCookiePropertyKey("SameSite")
    private static let sameSitePolicyKey = HTTPCookiePropertyKey("SameSitePolicy")
    private static let createdKey = HTTPCookiePropertyKey("Created")
    private static let authCookieNames: Set<String> = ["_t", "_forum_session"]

    /// The User-Agent captured from the WKWebView that completed login.
    var userAgent: String? {
        didSet { saveUserAgent() }
    }

    private let userAgentPath: URL

    private init() {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        filePath = dir.appendingPathComponent("dexo_web_cookies.json")
        userAgentPath = dir.appendingPathComponent("dexo_web_ua.txt")
        load()
        userAgent = loadUserAgent()
    }

    // MARK: - Read / Write

    func setCookies(_ cookies: [HTTPCookie]) {
        let now = Date()
        var storedCookies: [HTTPCookie] = []
        var removedNames: [String] = []
        var policyChanges: [String] = []

        lock.lock()
        for cookie in cookies {
            let key = key(for: cookie)
            if Self.isDeletionCookie(cookie, now: now) {
                if Self.isAuthCookieName(cookie.name) {
                    let removed = removeAuthCookieVariantsLocked(
                        named: cookie.name,
                        siteHost: Self.normalizedDomain(cookie.domain)
                    )
                    if removed > 0 {
                        removedNames.append(cookie.name)
                    }
                } else if jar.removeValue(forKey: key) != nil {
                    removedNames.append(cookie.name)
                }
            } else {
                jar[key] = cookie
                storedCookies.append(cookie)
            }
        }
        policyChanges = enforceAuthCookiePolicyLocked(now: now)
        lock.unlock()

        if !storedCookies.isEmpty {
            DohDebugLog.record("stored cookies: \(Self.cookieSummary(storedCookies))", subsystem: "Auth")
        }
        if !removedNames.isEmpty {
            DohDebugLog.record("removed expired cookies: \(removedNames.sorted().joined(separator: ","))", subsystem: "Auth")
        }
        if !policyChanges.isEmpty {
            DohDebugLog.record("normalized auth cookies: \(policyChanges.joined(separator: ","))", subsystem: "Auth")
        }
        save()
    }

    func cookies(for url: URL) -> [HTTPCookie] {
        lock.lock()
        let expiredKeys = expiredCookieKeys()
        for key in expiredKeys {
            jar.removeValue(forKey: key)
        }
        guard let host = url.host?.lowercased() else {
            lock.unlock()
            if !expiredKeys.isEmpty {
                save()
            }
            return []
        }
        let path = url.path.isEmpty ? "/" : url.path
        let matchedCookies = jar.values.filter { cookie in
            Self.cookieMatches(cookie, host: host, path: path)
        }
        let cookies = Self.selectCookiesForRequest(matchedCookies, host: host)
        let duplicateNames = matchedCookies.count > cookies.count
            ? Self.duplicateCookieNames(in: matchedCookies, selected: cookies)
            : []
        lock.unlock()

        if !expiredKeys.isEmpty {
            DohDebugLog.record("cleaned expired cookies: \(expiredKeys.count)", subsystem: "Auth")
            save()
        }
        if !duplicateNames.isEmpty {
            DohDebugLog.record(
                "suppressed duplicate cookies for \(host): \(duplicateNames.joined(separator: ","))",
                subsystem: "Auth"
            )
        }
        return cookies
    }

    func cookieHeader(for url: URL) -> String {
        cookies(for: url).map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }

    func cookieHeader(for url: URL, names: Set<String>) -> String {
        cookies(for: url)
            .filter { names.contains($0.name) }
            .map { "\($0.name)=\($0.value)" }
            .joined(separator: "; ")
    }

    func cookieNames(for url: URL) -> [String] {
        cookies(for: url)
            .map(\.name)
            .sorted()
    }

    func hasCookie(named name: String, for url: URL) -> Bool {
        cookies(for: url).contains { cookie in
            cookie.name == name && !cookie.value.isEmpty
        }
    }

    func hasDiscourseWebSessionCookie(for url: URL) -> Bool {
        hasCookie(named: "_t", for: url)
    }

    func cookieValue(named name: String, for url: URL) -> String? {
        cookies(for: url).first { cookie in
            cookie.name == name && !cookie.value.isEmpty
        }?.value
    }

    func deleteCookie(named name: String, for url: URL) {
        guard let host = url.host?.lowercased() else { return }
        lock.lock()
        jar = jar.filter { _, cookie in
            guard cookie.name == name else { return true }
            if Self.isAuthCookieName(name) {
                return Self.normalizedDomain(cookie.domain) != host
            }
            return !Self.domainMatches(host: host, cookieDomain: cookie.domain)
        }
        lock.unlock()
        save()
    }

    func mergeResponseHeaders(_ headers: [AnyHashable: Any], for url: URL) {
        let newCookies = Self.cookies(fromResponseHeaders: headers, for: url)
        if !newCookies.isEmpty { setCookies(newCookies) }
    }

    @MainActor
    func syncFromWebView(_ dataStore: WKWebsiteDataStore, names: Set<String>? = nil, for url: URL? = nil) async {
        let webViewCookies = await withCheckedContinuation { cont in
            dataStore.httpCookieStore.getAllCookies { cont.resume(returning: $0) }
        }
        let cookies = webViewCookies.filter { cookie in
            if let names, !names.contains(cookie.name) {
                return false
            }
            guard let url, let host = url.host?.lowercased() else {
                return true
            }
            return Self.domainMatches(host: host, cookieDomain: cookie.domain)
        }
        setCookies(cookies)
    }

    @MainActor
    func syncToWebView(_ dataStore: WKWebsiteDataStore, for url: URL) async {
        guard let host = url.host?.lowercased() else { return }
        let cookieStore = dataStore.httpCookieStore
        let cookies = cookies(for: url)
        let authCookieNames = cookies
            .filter { Self.isAuthCookieName($0.name) }
            .map(\.name)

        if !authCookieNames.isEmpty {
            let existingCookies = await withCheckedContinuation { continuation in
                cookieStore.getAllCookies { continuation.resume(returning: $0) }
            }
            for cookie in existingCookies {
                guard authCookieNames.contains(cookie.name),
                      Self.normalizedDomain(cookie.domain) == host
                else { continue }
                await withCheckedContinuation { continuation in
                    cookieStore.delete(cookie) {
                        continuation.resume()
                    }
                }
            }
        }

        for cookie in cookies {
            await withCheckedContinuation { continuation in
                cookieStore.setCookie(cookie) {
                    continuation.resume()
                }
            }
        }
        if !cookies.isEmpty {
            DohDebugLog.record("primed WebView cookies: \(Self.cookieSummary(cookies))", subsystem: "Auth")
        }
    }

    func clearAll() {
        lock.lock()
        jar.removeAll()
        lock.unlock()
        userAgent = nil
        try? FileManager.default.removeItem(at: filePath)
    }

    func clearCookies(for baseURL: String) {
        guard let host = URL(string: baseURL)?.host?.lowercased() else { return }
        lock.lock()
        jar = jar.filter { _, cookie in
            if Self.isAuthCookieName(cookie.name) {
                return Self.normalizedDomain(cookie.domain) != host
            }
            return !Self.domainMatches(host: host, cookieDomain: cookie.domain)
        }
        lock.unlock()
        save()
    }

    // MARK: - Persistence

    private func key(for cookie: HTTPCookie) -> String {
        "\(cookie.domain)|\(cookie.name)|\(cookie.path)"
    }

    private static func isExpired(_ cookie: HTTPCookie, now: Date = Date()) -> Bool {
        cookie.expiresDate.map { $0 <= now } ?? false
    }

    private static func isDeletionCookie(_ cookie: HTTPCookie, now: Date = Date()) -> Bool {
        cookie.value.isEmpty || cookie.value == "del" || isExpired(cookie, now: now)
    }

    private static func isAuthCookieName(_ name: String) -> Bool {
        authCookieNames.contains(name)
    }

    private static func normalizedDomain(_ domain: String) -> String {
        domain.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
    }

    private static func domainMatches(host: String, cookieDomain: String) -> Bool {
        let domain = normalizedDomain(cookieDomain)
        guard !domain.isEmpty else { return false }
        return host == domain || host.hasSuffix(".\(domain)")
    }

    private static func cookieMatches(_ cookie: HTTPCookie, host: String, path: String) -> Bool {
        let cookiePath = cookie.path.isEmpty ? "/" : cookie.path
        guard path.hasPrefix(cookiePath) else { return false }
        if isAuthCookieName(cookie.name) {
            // FluxDo 同款思路：Discourse 登录 cookie 按主站 host-only 处理，不跨子域发送。
            return host == normalizedDomain(cookie.domain)
        }
        return domainMatches(host: host, cookieDomain: cookie.domain)
    }

    private static func isDiscourseWebSessionCookie(_ cookie: HTTPCookie) -> Bool {
        guard !cookie.value.isEmpty else { return false }
        if isAuthCookieName(cookie.name) { return true }
        return cookie.name.hasPrefix("_") && cookie.name.hasSuffix("_session")
    }

    private func expiredCookieKeys(now: Date = Date()) -> [String] {
        jar.compactMap { key, cookie in
            Self.isExpired(cookie, now: now) ? key : nil
        }
    }

    private func save() {
        lock.lock()
        let records = jar.values.compactMap(StoredCookie.init(cookie:))
        lock.unlock()

        do {
            let data = try JSONEncoder().encode(records)
            try data.write(to: filePath, options: .atomic)
        } catch {
            DohDebugLog.record("cookie save failed: \(error.localizedDescription)", subsystem: "Auth")
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: filePath) else { return }
        let now = Date()

        if let records = try? JSONDecoder().decode([StoredCookie].self, from: data) {
            let cookies = records.compactMap { $0.makeCookie() }.filter { !Self.isExpired($0, now: now) }
            for cookie in cookies { jar[key(for: cookie)] = cookie }
            _ = enforceAuthCookiePolicyLocked(now: now)
            if !cookies.isEmpty {
                DohDebugLog.record("loaded cookies: \(Self.cookieSummary(cookies))", subsystem: "Auth")
            }
            return
        }

        guard let cookies = loadLegacyCookies(from: data, now: now) else {
            DohDebugLog.record("cookie load failed: unsupported cookie file", subsystem: "Auth")
            return
        }
        for cookie in cookies { jar[key(for: cookie)] = cookie }
        _ = enforceAuthCookiePolicyLocked(now: now)
        if !cookies.isEmpty {
            DohDebugLog.record("migrated legacy cookies: \(Self.cookieSummary(cookies))", subsystem: "Auth")
            save()
        }
    }

    private func saveUserAgent() {
        if let ua = userAgent {
            try? ua.write(to: userAgentPath, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: userAgentPath)
        }
    }

    private func loadUserAgent() -> String? {
        try? String(contentsOf: userAgentPath, encoding: .utf8)
    }
}

private extension WebCookieStore {
    struct StoredCookie: Codable {
        let name: String
        let value: String
        let domain: String
        let path: String
        let expiresAt: TimeInterval?
        let secure: Bool
        let httpOnly: Bool
        let version: Int?
        let sameSitePolicy: String?

        init?(cookie: HTTPCookie) {
            guard !cookie.name.isEmpty, !cookie.domain.isEmpty else { return nil }
            name = cookie.name
            value = cookie.value
            domain = cookie.domain
            path = cookie.path.isEmpty ? "/" : cookie.path
            expiresAt = cookie.expiresDate?.timeIntervalSince1970
            secure = cookie.isSecure
            httpOnly = cookie.isHTTPOnly
            version = cookie.version > 0 ? cookie.version : nil
            let props = cookie.properties ?? [:]
            sameSitePolicy = props[WebCookieStore.sameSitePolicyKey] as? String
                ?? props[WebCookieStore.sameSiteKey] as? String
        }

        func makeCookie() -> HTTPCookie? {
            var props: [HTTPCookiePropertyKey: Any] = [
                .name: name,
                .value: value,
                .domain: domain,
                .path: path.isEmpty ? "/" : path,
            ]
            if let expiresAt {
                props[.expires] = Date(timeIntervalSince1970: expiresAt)
            }
            if secure {
                props[.secure] = "TRUE"
            }
            if httpOnly {
                props[WebCookieStore.httpOnlyKey] = "TRUE"
            }
            if let version {
                props[.version] = version
            }
            if let sameSitePolicy {
                props[WebCookieStore.sameSitePolicyKey] = sameSitePolicy
            }
            return HTTPCookie(properties: props)
        }
    }

    func loadLegacyCookies(from data: Data, now: Date) -> [HTTPCookie]? {
        guard let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return nil
        }

        return array.compactMap { dict in
            var props: [HTTPCookiePropertyKey: Any] = [:]
            var maxAge: TimeInterval?
            var createdAt: TimeInterval?

            for (rawKey, rawValue) in dict {
                let key = HTTPCookiePropertyKey(rawKey)
                switch key {
                case .expires:
                    if let timestamp = Self.timeInterval(from: rawValue) {
                        props[.expires] = Date(timeIntervalSinceReferenceDate: timestamp)
                    } else {
                        props[.expires] = rawValue
                    }
                case Self.maxAgeKey:
                    maxAge = Self.timeInterval(from: rawValue)
                case Self.createdKey:
                    createdAt = Self.timeInterval(from: rawValue)
                default:
                    props[key] = rawValue
                }
            }

            if props[.expires] == nil, let maxAge {
                let base = createdAt.map { Date(timeIntervalSinceReferenceDate: $0) } ?? now
                props[.expires] = base.addingTimeInterval(maxAge)
            }

            return HTTPCookie(properties: props)
        }.filter { !Self.isExpired($0, now: now) }
    }

    func removeAuthCookieVariantsLocked(named name: String, siteHost: String) -> Int {
        guard !siteHost.isEmpty else { return 0 }
        let keys = jar.compactMap { key, cookie -> String? in
            guard cookie.name == name,
                  Self.isAuthCookieName(cookie.name),
                  Self.normalizedDomain(cookie.domain) == siteHost
            else { return nil }
            return key
        }
        for key in keys {
            jar.removeValue(forKey: key)
        }
        return keys.count
    }

    func enforceAuthCookiePolicyLocked(now: Date) -> [String] {
        let candidates = jar.values.filter { cookie in
            Self.isAuthCookieName(cookie.name) && !Self.normalizedDomain(cookie.domain).isEmpty
        }
        let groups = Dictionary(grouping: candidates) { cookie in
            "\(cookie.name)|\(Self.normalizedDomain(cookie.domain))"
        }
        var changes: [String] = []

        for group in groups.values {
            guard let first = group.first else { continue }
            let siteHost = Self.normalizedDomain(first.domain)
            let active = group.filter { !Self.isDeletionCookie($0, now: now) }
            if active.isEmpty {
                for cookie in group {
                    jar.removeValue(forKey: key(for: cookie))
                }
                changes.append("\(first.name)@\(siteHost):deleted")
                continue
            }

            let winner = active.max { lhs, rhs in
                Self.compareCookies(lhs, rhs, host: siteHost) < 0
            } ?? first
            let normalized = Self.canonicalAuthCookie(from: winner, siteHost: siteHost)
            let normalizedKey = key(for: normalized)
            let alreadyCanonical = group.count == 1
                && key(for: first) == normalizedKey
                && first.value == normalized.value
                && first.path == normalized.path
                && !first.domain.hasPrefix(".")

            guard !alreadyCanonical else { continue }
            for cookie in group {
                jar.removeValue(forKey: key(for: cookie))
            }
            jar[normalizedKey] = normalized
            changes.append("\(winner.name)@\(siteHost)")
        }

        return changes.sorted()
    }

    static func canonicalAuthCookie(from source: HTTPCookie, siteHost: String) -> HTTPCookie {
        var props: [HTTPCookiePropertyKey: Any] = [
            .name: source.name,
            .value: source.value,
            .domain: siteHost,
            .path: "/",
        ]
        if let expiresDate = source.expiresDate {
            props[.expires] = expiresDate
        }
        if source.isSecure {
            props[.secure] = "TRUE"
        }
        props[httpOnlyKey] = "TRUE"
        if source.version > 0 {
            props[.version] = source.version
        }
        let sourceProps = source.properties ?? [:]
        if let sameSite = sourceProps[sameSitePolicyKey] ?? sourceProps[sameSiteKey] {
            props[sameSitePolicyKey] = sameSite
        }
        return HTTPCookie(properties: props) ?? source
    }

    static func selectCookiesForRequest(_ cookies: [HTTPCookie], host: String) -> [HTTPCookie] {
        let sorted = cookies.sorted { lhs, rhs in
            let lhsPathLength = lhs.path.count
            let rhsPathLength = rhs.path.count
            if lhsPathLength != rhsPathLength {
                return lhsPathLength > rhsPathLength
            }
            return compareCookies(lhs, rhs, host: host) > 0
        }

        var selected: [String: HTTPCookie] = [:]
        for cookie in sorted {
            if isAuthCookieName(cookie.name), normalizedDomain(cookie.domain) != host {
                continue
            }
            let requestKey = isAuthCookieName(cookie.name)
                ? cookie.name
                : "\(cookie.name)|\(cookie.path.isEmpty ? "/" : cookie.path)"
            guard let existing = selected[requestKey] else {
                selected[requestKey] = cookie
                continue
            }
            if compareCookies(cookie, existing, host: host) > 0 {
                selected[requestKey] = cookie
            }
        }

        return selected.values.sorted { lhs, rhs in
            let lhsPathLength = lhs.path.count
            let rhsPathLength = rhs.path.count
            if lhsPathLength != rhsPathLength {
                return lhsPathLength > rhsPathLength
            }
            return compareCookies(lhs, rhs, host: host) > 0
        }
    }

    static func duplicateCookieNames(in matched: [HTTPCookie], selected: [HTTPCookie]) -> [String] {
        let matchedCounts = Dictionary(grouping: matched, by: \.name).mapValues(\.count)
        let selectedCounts = Dictionary(grouping: selected, by: \.name).mapValues(\.count)
        return matchedCounts.compactMap { name, count in
            count > (selectedCounts[name] ?? 0) ? name : nil
        }.sorted()
    }

    static func authCookiePriority(_ cookie: HTTPCookie, siteHost: String) -> Int {
        var score = 0
        let domain = normalizedDomain(cookie.domain)
        if domain == siteHost { score += 100_000 }
        if !cookie.domain.hasPrefix(".") { score += 50_000 }
        if cookie.path == "/" { score += 25_000 }
        if cookie.isSecure { score += 5_000 }
        if cookie.isHTTPOnly { score += 5_000 }
        if cookie.expiresDate != nil { score += 1_000 }
        score += min(cookie.value.count, 999)
        return score
    }

    static func cookiePriority(_ cookie: HTTPCookie, host: String) -> Int {
        if isAuthCookieName(cookie.name) {
            return authCookiePriority(cookie, siteHost: host)
        }

        let domain = normalizedDomain(cookie.domain)
        var score = 0
        if domain == host {
            score += 10_000 + domain.count
        } else if host.hasSuffix(".\(domain)") {
            score += 1_000 + domain.count
        }
        if !cookie.domain.hasPrefix(".") { score += 250 }
        if cookie.isSecure { score += 100 }
        if cookie.isHTTPOnly { score += 100 }
        score += min(cookie.value.count, 99)
        return score
    }

    static func compareCookies(_ lhs: HTTPCookie, _ rhs: HTTPCookie, host: String) -> Int {
        let scoreDiff = cookiePriority(lhs, host: host) - cookiePriority(rhs, host: host)
        if scoreDiff != 0 { return scoreDiff }

        let versionDiff = lhs.version - rhs.version
        if versionDiff != 0 { return versionDiff }

        switch (lhs.expiresDate, rhs.expiresDate) {
        case let (lhsExpires?, rhsExpires?) where lhsExpires != rhsExpires:
            return lhsExpires > rhsExpires ? 1 : -1
        case (_?, nil):
            return 1
        case (nil, _?):
            return -1
        default:
            break
        }

        let createdDiff = createdTime(lhs).compare(createdTime(rhs))
        if createdDiff != .orderedSame {
            return createdDiff == .orderedDescending ? 1 : -1
        }

        return lhs.value.count - rhs.value.count
    }

    static func createdTime(_ cookie: HTTPCookie) -> Date {
        let value = cookie.properties?[createdKey]
        if let date = value as? Date {
            return date
        }
        if let interval = timeInterval(from: value as Any) {
            return Date(timeIntervalSinceReferenceDate: interval)
        }
        return .distantPast
    }

    static func cookies(fromResponseHeaders headers: [AnyHashable: Any], for url: URL) -> [HTTPCookie] {
        var result: [HTTPCookie] = []
        for (key, value) in headers {
            guard "\(key)".lowercased() == "set-cookie" else { continue }
            for header in setCookieHeaderStrings(from: value) {
                result.append(
                    contentsOf: HTTPCookie.cookies(
                        withResponseHeaderFields: ["Set-Cookie": header],
                        for: url
                    )
                )
            }
        }
        return result
    }

    static func setCookieHeaderStrings(from value: Any) -> [String] {
        if let strings = value as? [String] {
            return strings.flatMap(splitSetCookieHeader)
        }
        if let values = value as? [Any] {
            return values.flatMap { setCookieHeaderStrings(from: $0) }
        }
        if let string = value as? String {
            return splitSetCookieHeader(string)
        }
        return splitSetCookieHeader("\(value)")
    }

    static func splitSetCookieHeader(_ header: String) -> [String] {
        var parts: [String] = []
        var start = header.startIndex
        var index = header.startIndex

        while index < header.endIndex {
            guard let comma = header[index...].firstIndex(of: ",") else {
                break
            }
            let afterComma = header.index(after: comma)
            if isCookieSeparator(afterComma, in: header) {
                let part = header[start..<comma].trimmingCharacters(in: .whitespacesAndNewlines)
                if !part.isEmpty {
                    parts.append(part)
                }
                start = afterComma
            }
            index = afterComma
        }

        let tail = header[start..<header.endIndex].trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty {
            parts.append(tail)
        }
        return parts
    }

    static func isCookieSeparator(_ index: String.Index, in header: String) -> Bool {
        var cursor = index
        while cursor < header.endIndex, header[cursor].isWhitespace {
            cursor = header.index(after: cursor)
        }
        guard cursor < header.endIndex else { return false }

        let tokenEnd = header[cursor...].firstIndex { $0 == ";" || $0 == "," } ?? header.endIndex
        let token = header[cursor..<tokenEnd]
        guard let equals = token.firstIndex(of: "=") else { return false }
        let name = token[..<equals].trimmingCharacters(in: .whitespacesAndNewlines)
        return isValidCookieName(name)
    }

    static func isValidCookieName(_ name: String) -> Bool {
        guard !name.isEmpty else { return false }
        let separators = CharacterSet(charactersIn: "()<>@,;:\\\"/[]?={} \t")
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.value > 0x20 && scalar.value < 0x7f && !separators.contains(scalar)
        }
    }

    static func timeInterval(from value: Any) -> TimeInterval? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let value = value as? TimeInterval {
            return value
        }
        if let string = value as? String {
            return TimeInterval(string)
        }
        return nil
    }

    static func cookieSummary(_ cookies: [HTTPCookie]) -> String {
        cookies
            .sorted { $0.name < $1.name }
            .map { cookie in
                let expiry = cookie.expiresDate.map { "exp=\(Int($0.timeIntervalSince1970))" } ?? "session"
                return "\(cookie.name)(\(expiry))"
            }
            .joined(separator: ",")
    }
}
