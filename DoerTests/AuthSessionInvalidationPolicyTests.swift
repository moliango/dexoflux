import XCTest
@testable import Doer

final class AuthSessionInvalidationPolicyTests: XCTestCase {
    private let probeHost = "doer-session-invalidate.test"
    private var probeURL: URL { URL(string: "https://\(probeHost)")! }
    private var baseURL: String { "https://\(probeHost)" }

    override func tearDown() {
        WebCookieStore.shared.clearCookies(for: baseURL)
        super.tearDown()
    }

    func testForbiddenDoesNotInvalidateWhileTicketRemains() throws {
        try installTicket()
        let error = DiscourseAPIError(messages: ["nope"], errorType: "forbidden")
        XCTAssertFalse(
            AuthSessionInvalidationPolicy.shouldInvalidateWebSession(error: error, baseURL: baseURL)
        )
        XCTAssertTrue(WebCookieStore.shared.hasCookie(named: "_t", for: probeURL))
    }

    func testCloudflareDoesNotInvalidate() throws {
        try installTicket()
        let error = DiscourseAPIError(messages: ["cf"], errorType: "cloudflare_challenge")
        XCTAssertFalse(
            AuthSessionInvalidationPolicy.shouldInvalidateWebSession(error: error, baseURL: baseURL)
        )
    }

    func testNotLoggedInInvalidatesEvenWhenJarStillHasT() throws {
        try installTicket()
        let error = DiscourseAPIError(messages: ["login"], errorType: "not_logged_in")
        XCTAssertTrue(
            AuthSessionInvalidationPolicy.shouldInvalidateWebSession(error: error, baseURL: baseURL)
        )
        XCTAssertTrue(WebCookieStore.shared.hasCookie(named: "_t", for: probeURL))
    }

    func testNotLoggedInInvalidatesWhenTicketIsGone() {
        let error = DiscourseAPIError(messages: ["login"], errorType: "not_logged_in")
        XCTAssertTrue(
            AuthSessionInvalidationPolicy.shouldInvalidateWebSession(error: error, baseURL: baseURL)
        )
    }

    func testCurrentUserForbiddenJSONIsNotLoggedIn() throws {
        let data = try XCTUnwrap(#"{"errors":["You need to be logged in"],"error_type":"forbidden"}"#.data(using: .utf8))
        let error = try XCTUnwrap(DiscourseAPI.currentUserFailure(statusCode: 403, data: data))
        XCTAssertTrue(error.isNotLoggedIn)
        XCTAssertTrue(
            AuthSessionInvalidationPolicy.shouldInvalidateWebSession(error: error, baseURL: baseURL)
        )
    }

    func testCurrentUserNotLoggedInJSONIsNotLoggedIn() throws {
        let data = try XCTUnwrap(#"{"errors":["login required"],"error_type":"not_logged_in"}"#.data(using: .utf8))
        let error = try XCTUnwrap(DiscourseAPI.currentUserFailure(statusCode: 403, data: data))
        XCTAssertTrue(error.isNotLoggedIn)
    }

    func testCurrentUser401IsNotLoggedIn() throws {
        let error = try XCTUnwrap(DiscourseAPI.currentUserFailure(statusCode: 401, data: nil))
        XCTAssertTrue(error.isNotLoggedIn)
    }

    func testCurrentUserGeneric403IsNotSessionExpiry() throws {
        let error = try XCTUnwrap(DiscourseAPI.currentUserFailure(statusCode: 403, data: nil))
        XCTAssertEqual(error.errorType, "http_403")
        XCTAssertFalse(error.isNotLoggedIn)
        XCTAssertFalse(
            AuthSessionInvalidationPolicy.shouldInvalidateWebSession(error: error, baseURL: baseURL)
        )
    }

    func testForbiddenResponseKeepsDiscourseErrorType() throws {
        let data = try XCTUnwrap(#"{"errors":["invalid access"],"error_type":"invalid_access"}"#.data(using: .utf8))
        let error = DiscourseAPI.errorFromForbiddenStatus(data: data)
        XCTAssertEqual(error.errorType, "invalid_access")
        XCTAssertFalse(error.isNotLoggedIn)
        XCTAssertFalse(error.isForbidden)
    }

    func testGeneric403IsHttpStatusNotSessionExpired() {
        let error = DiscourseAPI.errorFromForbiddenStatus(data: nil)
        XCTAssertEqual(error.errorType, "http_403")
        XCTAssertFalse(error.isForbidden)
        XCTAssertFalse(error.isNotLoggedIn)
    }

    private func installTicket() throws {
        let cookie = try XCTUnwrap(HTTPCookie(properties: [
            .name: "_t",
            .value: "still-valid",
            .domain: probeHost,
            .path: "/",
            .secure: "TRUE",
            .expires: Date().addingTimeInterval(3600),
        ]))
        WebCookieStore.shared.setCookies([cookie])
    }
}
