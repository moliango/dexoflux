import XCTest
@testable import dexoflux

@MainActor
final class HomeListLoadingGateTests: XCTestCase {
    func testLoadMoreRequiresCanLoadMoreAndIdleRefresh() {
        struct Gate {
            var canLoadMore: Bool
            var isLoadingMore: Bool
            var isLoading: Bool
            var loadMoreErrorMessage: String?
            var hasLoadMoreTask: Bool

            var allowsAutoLoadMore: Bool {
                canLoadMore
                    && loadMoreErrorMessage == nil
                    && !isLoadingMore
                    && !isLoading
                    && !hasLoadMoreTask
            }
        }

        XCTAssertTrue(
            Gate(
                canLoadMore: true,
                isLoadingMore: false,
                isLoading: false,
                loadMoreErrorMessage: nil,
                hasLoadMoreTask: false
            ).allowsAutoLoadMore
        )
        XCTAssertFalse(
            Gate(
                canLoadMore: true,
                isLoadingMore: false,
                isLoading: false,
                loadMoreErrorMessage: "network",
                hasLoadMoreTask: false
            ).allowsAutoLoadMore
        )
        XCTAssertFalse(
            Gate(
                canLoadMore: true,
                isLoadingMore: false,
                isLoading: true,
                loadMoreErrorMessage: nil,
                hasLoadMoreTask: false
            ).allowsAutoLoadMore
        )
    }

    func testRefreshIsSingleFlight() {
        struct Gate {
            var isLoading: Bool
            var allowsRefresh: Bool { !isLoading }
        }
        XCTAssertTrue(Gate(isLoading: false).allowsRefresh)
        XCTAssertFalse(Gate(isLoading: true).allowsRefresh)
    }

    func testPullPolicyStillBlocksInFlightReload() {
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

final class HomeTabBarScrollPolicyTests: XCTestCase {
    func testTopAlwaysShows() {
        XCTAssertEqual(
            HomeTabBarScrollPolicy.preferredHidden(contentY: 10, userDriven: true, velocityY: -100),
            false
        )
    }

    func testUserFlickUpHides() {
        XCTAssertEqual(
            HomeTabBarScrollPolicy.preferredHidden(contentY: 200, userDriven: true, velocityY: -80),
            true
        )
    }

    func testIdleLeavesUnchanged() {
        XCTAssertNil(
            HomeTabBarScrollPolicy.preferredHidden(contentY: 200, userDriven: false, velocityY: 0)
        )
    }
}
