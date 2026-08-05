import ObjectiveC
import UIKit

/// Safe self-sizing invalidation for DiffableDataSource-backed tables.
///
/// Raw `beginUpdates()` / `endUpdates()` while a snapshot apply, `reloadItems`,
/// or `scrollToRow` is in flight desyncs UITableView's internal
/// `_visibleRows` vs `_visibleCells` and traps with:
/// `UITableView internal inconsistency: _visibleRows and _visibleCells must be of same length`.
extension UITableView {
    private static var mutationDepthKey: UInt8 = 0
    private static var pendingHeightPassKey: UInt8 = 0
    private static var heightPassScheduledKey: UInt8 = 0

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

    func dexo_beginDataMutation() {
        dexo_mutationDepth += 1
    }

    func dexo_endDataMutation() {
        dexo_mutationDepth = max(0, dexo_mutationDepth - 1)
        if dexo_mutationDepth == 0 {
            dexo_flushPendingSelfSizingUpdateIfNeeded()
        }
    }

    /// Coalesced, mutation-gated replacement for `beginUpdates()` / `endUpdates()`
    /// used only to re-measure automatic-dimension rows after media/layout changes.
    func dexo_invalidateSelfSizingRows() {
        dexo_hasPendingHeightPass = true
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
