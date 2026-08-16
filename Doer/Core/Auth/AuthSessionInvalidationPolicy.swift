import Foundation

/// When a Discourse request fails, UI layers used to treat every 403 / `forbidden`
/// as logout and call `AuthManager.invalidateWebSession`, which deletes `_t` and
/// `cf_clearance`. Transient Cloudflare, permission, and CSRF 403s then looked
/// like being kicked off the server.
enum AuthSessionInvalidationPolicy {
    /// Clear the local web session only when Discourse reported not-logged-in
    /// **and** the jar no longer has `_t`. A still-valid ticket must survive.
    static func shouldInvalidateWebSession(error: Error, baseURL: String) -> Bool {
        guard let apiError = error as? DiscourseAPIError, apiError.isNotLoggedIn else {
            return false
        }
        let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: normalized) else { return false }
        let hasTicket = WebCookieStore.shared.hasCookie(named: "_t", for: url)
        if hasTicket {
            DohDebugLog.record(
                "skipped session invalidation; _t still present type=\(apiError.errorType ?? "nil")",
                subsystem: "Auth"
            )
        }
        return !hasTicket
    }
}
