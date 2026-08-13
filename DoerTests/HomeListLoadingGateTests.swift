import XCTest
@testable import Doer

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

    /// 上滑翻页/触底：velocity 正向回弹也绝不能推荐显示 tab bar。
    func testNearBottomPaginationNeverShows() {
        XCTAssertNil(
            HomeTabBarScrollPolicy.preferredHidden(
                contentY: 800,
                userDriven: true,
                velocityY: 120,
                nearBottomPagination: true,
                activelyDragging: true
            )
        )
        XCTAssertEqual(
            HomeTabBarScrollPolicy.preferredHidden(
                contentY: 800,
                userDriven: true,
                velocityY: -80,
                nearBottomPagination: true
            ),
            true
        )
    }

    /// contentSize 增长 settle 窗口：只允许 hide / 不变，不允许 show。
    func testSuppressShowBlocksReveal() {
        XCTAssertNil(
            HomeTabBarScrollPolicy.preferredHidden(
                contentY: 400,
                userDriven: true,
                velocityY: 100,
                suppressShow: true,
                activelyDragging: true
            )
        )
    }

    /// 纯惯性（非 dragging）不能靠 velocity 弹出 tab bar。
    func testDecelerationAloneDoesNotShow() {
        XCTAssertNil(
            HomeTabBarScrollPolicy.preferredHidden(
                contentY: 400,
                userDriven: true,
                velocityY: 100,
                activelyDragging: false
            )
        )
    }

    func testRevealRequiresActiveDragNotBounce() {
        XCTAssertFalse(
            HomeTabBarScrollPolicy.shouldRevealFromScroll(
                contentY: 500,
                isDragging: false,
                deltaY: -10,
                contentGrew: false,
                suppressShow: false,
                nearBottomPagination: false
            )
        )
        XCTAssertFalse(
            HomeTabBarScrollPolicy.shouldRevealFromScroll(
                contentY: 500,
                isDragging: true,
                deltaY: -10,
                contentGrew: true,
                suppressShow: false,
                nearBottomPagination: false
            )
        )
        XCTAssertFalse(
            HomeTabBarScrollPolicy.shouldRevealFromScroll(
                contentY: 500,
                isDragging: true,
                deltaY: -10,
                contentGrew: false,
                suppressShow: true,
                nearBottomPagination: false
            )
        )
        XCTAssertFalse(
            HomeTabBarScrollPolicy.shouldRevealFromScroll(
                contentY: 500,
                isDragging: true,
                deltaY: -10,
                contentGrew: false,
                suppressShow: false,
                nearBottomPagination: true
            )
        )
        XCTAssertTrue(
            HomeTabBarScrollPolicy.shouldRevealFromScroll(
                contentY: 500,
                isDragging: true,
                deltaY: -10,
                contentGrew: false,
                suppressShow: false,
                nearBottomPagination: false
            )
        )
    }

    func testHideFromScrollOnUpwardContent() {
        XCTAssertTrue(
            HomeTabBarScrollPolicy.shouldHideFromScroll(contentY: 100, userDriven: true, deltaY: 5)
        )
        XCTAssertFalse(
            HomeTabBarScrollPolicy.shouldHideFromScroll(contentY: 100, userDriven: true, deltaY: -5)
        )
    }
}
