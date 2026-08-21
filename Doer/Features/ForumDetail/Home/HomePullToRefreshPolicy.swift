import CoreGraphics

/// Pure policy for Home short-pull refresh. Kept free of UIKit view ownership
/// so unit tests can exercise thresholds without a view controller.
enum HomePullToRefreshPolicy {
    static let triggerDistance: CGFloat = 56

    static func shouldTrigger(
        pullDistance: CGFloat,
        isRefreshing: Bool,
        isLoading: Bool,
        hasReloadTask: Bool
    ) -> Bool {
        // A hung reload (DoH/offline) must still be replaceable. Only the
        // visible spinner is treated as an in-flight pull.
        _ = isLoading
        _ = hasReloadTask
        return pullDistance >= triggerDistance && !isRefreshing
    }
}
