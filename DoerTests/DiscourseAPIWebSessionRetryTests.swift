import XCTest
@testable import Doer

final class DiscourseAPIWebSessionRetryTests: XCTestCase {
    func testEmpty200DoesNotForceWebSessionRefresh() {
        XCTAssertNil(
            DiscourseAPI.webSessionRefreshRetryReason(
                route: .latestTopics(page: 0),
                statusCode: 200,
                error: nil,
                data: Data()
            )
        )
    }

    func testEmpty204DoesNotForceWebSessionRefresh() {
        XCTAssertNil(
            DiscourseAPI.webSessionRefreshRetryReason(
                route: .siteInfo,
                statusCode: 204,
                error: nil,
                data: Data()
            )
        )
    }

    func test401ForcesWebSessionRefresh() {
        XCTAssertEqual(
            DiscourseAPI.webSessionRefreshRetryReason(
                route: .latestTopics(page: 0),
                statusCode: 401,
                error: nil,
                data: Data()
            ),
            "api_auth_status_401"
        )
    }

    func test403ForcesWebSessionRefresh() {
        XCTAssertEqual(
            DiscourseAPI.webSessionRefreshRetryReason(
                route: .latestTopics(page: 0),
                statusCode: 403,
                error: nil,
                data: nil
            ),
            "api_auth_status_403"
        )
    }

    func testCurrentUserEmptyBodyIsAuthShapedFailure() {
        XCTAssertEqual(
            DiscourseAPI.webSessionRefreshRetryReason(
                route: .currentUser,
                statusCode: 200,
                error: nil,
                data: Data()
            ),
            "api_empty_auth_response"
        )
    }
}
