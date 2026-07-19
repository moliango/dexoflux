import XCTest
@testable import dexoflux

final class HomePullToRefreshPolicyTests: XCTestCase {
    func testTriggersAtShorterReleaseDistance() {
        XCTAssertFalse(
            HomePullToRefreshPolicy.shouldTrigger(
                pullDistance: 55,
                isRefreshing: false,
                isLoading: false,
                hasReloadTask: false
            )
        )
        XCTAssertTrue(
            HomePullToRefreshPolicy.shouldTrigger(
                pullDistance: 56,
                isRefreshing: false,
                isLoading: false,
                hasReloadTask: false
            )
        )
    }

    func testDoesNotTriggerWhileRefreshIsAlreadyRunning() {
        XCTAssertFalse(
            HomePullToRefreshPolicy.shouldTrigger(
                pullDistance: 80,
                isRefreshing: true,
                isLoading: false,
                hasReloadTask: false
            )
        )
        XCTAssertFalse(
            HomePullToRefreshPolicy.shouldTrigger(
                pullDistance: 80,
                isRefreshing: false,
                isLoading: true,
                hasReloadTask: false
            )
        )
        XCTAssertFalse(
            HomePullToRefreshPolicy.shouldTrigger(
                pullDistance: 80,
                isRefreshing: false,
                isLoading: false,
                hasReloadTask: true
            )
        )
    }
}
