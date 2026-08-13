import XCTest
@testable import Doer

/// Covers jar → WK priming selection: injection keeps apex auth cookies for SSO,
/// while request headers stay host-only for `_t` / `_forum_session`.
@MainActor
final class WebCookieStoreSessionTests: XCTestCase {
    private let probeHost = "doer-cookie-prime.test"
    private var probeURL: URL { URL(string: "https://\(probeHost)/")! }
    private var subdomainURL: URL { URL(string: "https://sub.\(probeHost)/home")! }

    override func tearDown() {
        WebCookieStore.shared.clearCookies(for: probeURL.absoluteString)
        WebCookieStore.shared.clearCookies(for: subdomainURL.absoluteString)
        super.tearDown()
    }

    func testSiteCookiesForInjectionKeepsApexAuthWhenPrimingSubdomain() throws {
        let auth = try XCTUnwrap(HTTPCookie(properties: [
            .name: "_t",
            .value: "session-token",
            .domain: probeHost,
            .path: "/",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(3600),
        ]))
        let clearance = try XCTUnwrap(HTTPCookie(properties: [
            .name: "cf_clearance",
            .value: "cf-token",
            .domain: ".\(probeHost)",
            .path: "/",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(3600),
        ]))
        WebCookieStore.shared.setCookies([auth, clearance])

        let forRequest = WebCookieStore.shared.siteCookies(forHost: "sub.\(probeHost)")
        XCTAssertFalse(forRequest.contains(where: { $0.name == "_t" }),
                       "Request cookies must not attach apex _t to a subdomain host")
        XCTAssertTrue(forRequest.contains(where: { $0.name == "cf_clearance" }))

        let forInjection = WebCookieStore.shared.siteCookiesForInjection(forHost: "sub.\(probeHost)")
        XCTAssertTrue(forInjection.contains(where: { $0.name == "_t" && $0.domain.contains(probeHost) }),
                      "Injection must keep apex _t so SSO redirects to the forum stay logged in")
        XCTAssertTrue(forInjection.contains(where: { $0.name == "cf_clearance" }))
    }

    func testSiteCookiesForInjectionIncludesAuthForApexHost() throws {
        let auth = try XCTUnwrap(HTTPCookie(properties: [
            .name: "_t",
            .value: "session-token",
            .domain: probeHost,
            .path: "/",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(3600),
        ]))
        WebCookieStore.shared.setCookies([auth])

        let injected = WebCookieStore.shared.siteCookiesForInjection(forHost: probeHost)
        XCTAssertTrue(injected.contains(where: { $0.name == "_t" }))

        let header = WebCookieStore.shared.cookieHeader(for: probeURL)
        XCTAssertTrue(header.contains("_t=session-token"))
    }

    func testWebKitReadyCookiePinsExpiresOnSessionCookies() throws {
        let session = try XCTUnwrap(HTTPCookie(properties: [
            .name: "_forum_session",
            .value: "anon-or-session",
            .domain: probeHost,
            .path: "/",
            .secure: "TRUE",
        ]))
        XCTAssertNil(session.expiresDate)

        let prepared = WebCookieStore.webKitReadyCookie(from: session)
        XCTAssertNotNil(prepared.expiresDate, "Session cookies need Expires so WK keeps them across the first load")
        XCTAssertEqual(prepared.name, "_forum_session")
        XCTAssertEqual(prepared.value, "anon-or-session")
    }
}
