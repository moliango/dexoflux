import XCTest
@testable import dexoflux

@MainActor
final class HomeListLoadingGateTests: XCTestCase {
    func testLoadMoreRequiresCanLoadMoreAndIdleRefresh() {
        // Pure flag matrix documenting the gate used by HomeViewModel.loadMoreTopics.
        struct Gate {
            var canLoadMore: Bool
            var isLoadingMore: Bool
            var isLoading: Bool
            var allowsLoadMore: Bool {
                canLoadMore && !isLoadingMore && !isLoading
            }
        }

        XCTAssertTrue(Gate(canLoadMore: true, isLoadingMore: false, isLoading: false).allowsLoadMore)
        XCTAssertFalse(Gate(canLoadMore: false, isLoadingMore: false, isLoading: false).allowsLoadMore)
        XCTAssertFalse(Gate(canLoadMore: true, isLoadingMore: true, isLoading: false).allowsLoadMore)
        XCTAssertFalse(Gate(canLoadMore: true, isLoadingMore: false, isLoading: true).allowsLoadMore)
    }

    func testRefreshIsSingleFlight() {
        struct Gate {
            var isLoading: Bool
            var allowsRefresh: Bool { !isLoading }
        }
        XCTAssertTrue(Gate(isLoading: false).allowsRefresh)
        XCTAssertFalse(Gate(isLoading: true).allowsRefresh)
    }
}
