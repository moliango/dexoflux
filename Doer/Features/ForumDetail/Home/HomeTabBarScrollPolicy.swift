import CoreGraphics

/// Pure rules for Home tab-bar auto-hide while scrolling.
enum HomeTabBarScrollPolicy {
    static let topRevealY: CGFloat = 48
    /// Finger moving up (content toward bottom) → hide tab bar.
    static let hideVelocityY: CGFloat = -40
    /// Finger moving down (content toward top) → show tab bar.
    static let showVelocityY: CGFloat = 40
    /// contentOffset delta: scrolling content toward bottom → hide.
    static let hideDeltaY: CGFloat = 3
    /// contentOffset delta: scrolling content toward top → show (drag only).
    static let showDeltaY: CGFloat = -3

    static func shouldForceShow(contentY: CGFloat) -> Bool {
        contentY <= topRevealY
    }

    /// - Returns: `true` hide, `false` show, `nil` leave unchanged.
    /// - Parameter nearBottomPagination: when true (load-more / list bottom),
    ///   never recommend showing the bar — only hide or leave alone.
    /// - Parameter suppressShow: post contentSize-jump / freeze settle window —
    ///   allow hide only; never recommend show (except force-show at top).
    /// - Parameter activelyDragging: finger still on screen. Show requires this
    ///   so deceleration bounce after load-more cannot reveal the tab bar.
    static func preferredHidden(
        contentY: CGFloat,
        userDriven: Bool,
        velocityY: CGFloat,
        nearBottomPagination: Bool = false,
        suppressShow: Bool = false,
        activelyDragging: Bool = true
    ) -> Bool? {
        if shouldForceShow(contentY: contentY) {
            return false
        }
        guard userDriven else { return nil }
        if velocityY < hideVelocityY { return true }
        // 上滑翻页 / contentSize 回弹窗口：禁止把 tab bar 弹出来。
        if nearBottomPagination || suppressShow { return nil }
        // 只有手指仍在拖时才允许「下滑显示」，惯性回弹不算。
        if activelyDragging, velocityY > showVelocityY { return false }
        return nil
    }

    /// Live scroll decision for revealing the tab bar (not hide).
    /// Show only on intentional finger drag toward top — never from decel bounce.
    static func shouldRevealFromScroll(
        contentY: CGFloat,
        isDragging: Bool,
        deltaY: CGFloat,
        contentGrew: Bool,
        suppressShow: Bool,
        nearBottomPagination: Bool
    ) -> Bool {
        if shouldForceShow(contentY: contentY) { return true }
        guard isDragging, !contentGrew, !suppressShow, !nearBottomPagination else {
            return false
        }
        return deltaY < showDeltaY
    }

    /// Live scroll decision for hiding the tab bar.
    static func shouldHideFromScroll(
        contentY: CGFloat,
        userDriven: Bool,
        deltaY: CGFloat
    ) -> Bool {
        guard userDriven, contentY > 40 else { return false }
        return deltaY > hideDeltaY
    }
}
