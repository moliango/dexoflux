import ObjectiveC
import UIKit

/// Safe self-sizing invalidation for DiffableDataSource-backed tables.
///
/// Raw `beginUpdates()` / `endUpdates()` while a snapshot apply, `reloadItems`,
/// or `scrollToRow` is in flight desyncs UITableView's internal
/// `_visibleRows` vs `_visibleCells` and traps with:
/// `UITableView internal inconsistency: _visibleRows and _visibleCells must be of same length`.
///
/// Scroll-busy gate: while the user is dragging/decelerating, height passes are
/// only marked pending and flush after scrolling settles — avoids mid-scroll
/// `beginUpdates` jank on long image posts.
extension UITableView {
    private static var mutationDepthKey: UInt8 = 0
    private static var pendingHeightPassKey: UInt8 = 0
    private static var heightPassScheduledKey: UInt8 = 0
    private static var scrollBusyKey: UInt8 = 0
    private static var scrollSettleWorkItemKey: UInt8 = 0
    private static var scrollSettledHandlerKey: UInt8 = 0

    /// True while any Diffable `apply` / structural mutation is in flight.
    var dexo_isMutatingData: Bool {
        get { dexo_mutationDepth > 0 }
        set {
            if newValue {
                dexo_beginDataMutation()
            } else {
                dexo_endDataMutation()
            }
        }
    }

    /// True while the user is actively scrolling (drag or decelerate), or during
    /// the short settle window after lift. Height flushes wait until this clears.
    var dexo_isScrollBusy: Bool {
        get { (objc_getAssociatedObject(self, &Self.scrollBusyKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &Self.scrollBusyKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    /// Invoked once after scroll busy clears (post-settle). Used to finish progressive
    /// post bodies and resume GIF/media without fighting the fling.
    var dexo_onScrollSettled: (() -> Void)? {
        get { objc_getAssociatedObject(self, &Self.scrollSettledHandlerKey) as? (() -> Void) }
        set { objc_setAssociatedObject(self, &Self.scrollSettledHandlerKey, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC) }
    }

    private var dexo_mutationDepth: Int {
        get { (objc_getAssociatedObject(self, &Self.mutationDepthKey) as? Int) ?? 0 }
        set { objc_setAssociatedObject(self, &Self.mutationDepthKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var dexo_hasPendingHeightPass: Bool {
        get { (objc_getAssociatedObject(self, &Self.pendingHeightPassKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &Self.pendingHeightPassKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var dexo_heightPassScheduled: Bool {
        get { (objc_getAssociatedObject(self, &Self.heightPassScheduledKey) as? Bool) ?? false }
        set { objc_setAssociatedObject(self, &Self.heightPassScheduledKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    private var dexo_scrollSettleWorkItem: DispatchWorkItem? {
        get { objc_getAssociatedObject(self, &Self.scrollSettleWorkItemKey) as? DispatchWorkItem }
        set { objc_setAssociatedObject(self, &Self.scrollSettleWorkItemKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }

    func dexo_beginDataMutation() {
        dexo_mutationDepth += 1
    }

    func dexo_endDataMutation() {
        dexo_mutationDepth = max(0, dexo_mutationDepth - 1)
        if dexo_mutationDepth == 0 {
            dexo_flushPendingSelfSizingUpdateIfNeeded()
        }
    }

    /// Mark table as scroll-busy so self-sizing passes queue instead of flushing.
    /// Call with `false` when drag ends without decelerate, or when decelerate ends.
    func dexo_setScrollBusy(_ busy: Bool) {
        dexo_scrollSettleWorkItem?.cancel()
        dexo_scrollSettleWorkItem = nil

        if busy {
            dexo_isScrollBusy = true
            return
        }

        // Short settle window: coalesce late image-load height requests after fling ends.
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.dexo_isScrollBusy = false
            self.dexo_scrollSettleWorkItem = nil
            self.dexo_flushPendingSelfSizingUpdateIfNeeded()
            self.dexo_onScrollSettled?()
        }
        dexo_scrollSettleWorkItem = work
        // Keep busy true until settle fires so mid-settle invalidates still queue.
        dexo_isScrollBusy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1, execute: work)
    }

    /// Coalesced, mutation- and scroll-gated replacement for `beginUpdates()` / `endUpdates()`
    /// used only to re-measure automatic-dimension rows after media/layout changes.
    func dexo_invalidateSelfSizingRows() {
        dexo_hasPendingHeightPass = true
        #if DEBUG
        TopicDetailPerfCounters.heightInvalidateRequests += 1
        #endif
        guard !dexo_isScrollBusy else { return }
        dexo_scheduleSelfSizingPass()
    }

    private func dexo_scheduleSelfSizingPass() {
        guard !dexo_heightPassScheduled else { return }
        dexo_heightPassScheduled = true
        // Next turn — never nest inside an existing layout / Diffable apply callback.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.dexo_heightPassScheduled = false
            self.dexo_flushPendingSelfSizingUpdateIfNeeded()
        }
    }

    private func dexo_flushPendingSelfSizingUpdateIfNeeded() {
        guard dexo_hasPendingHeightPass else { return }
        guard window != nil else { return }
        guard !dexo_isScrollBusy else { return }
        guard !dexo_isMutatingData else {
            // Still applying a snapshot — try again after the flag clears.
            dexo_scheduleSelfSizingPass()
            return
        }
        // Table must already have sections; empty tables crash on beginUpdates mid-teardown.
        guard numberOfSections > 0, numberOfRows(inSection: 0) > 0 else {
            dexo_hasPendingHeightPass = false
            return
        }

        dexo_hasPendingHeightPass = false
        UIView.performWithoutAnimation {
            self.beginUpdates()
            self.endUpdates()
        }
    }
}
