import Combine
import Network
import UIKit

// MARK: - RefreshGeometry
extension HomeViewController {
    func beginTopRefreshGeometryLock(animated: Bool) {
        topRefreshGeometryLockID += 1
        isTopRefreshGeometryLocked = true
        beginTabBarScrollFreezeForRefresh()
        normalizeTopRefreshGeometry(animated: animated)
    }

    func finishTopRefreshGeometryLockIfNeeded() {
        guard isTopRefreshGeometryLocked else { return }
        let lockID = topRefreshGeometryLockID
        normalizeTopRefreshGeometry(animated: false)

        Task { @MainActor in
            self.normalizeTopRefreshGeometryIfStillLocked(lockID: lockID, release: false)
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(Self.topRefreshGeometryReleaseDelay * 1_000_000_000))
            self.normalizeTopRefreshGeometryIfStillLocked(lockID: lockID, release: true)
        }
    }

    func normalizeTopRefreshGeometryIfStillLocked(lockID: Int, release: Bool) {
        guard isTopRefreshGeometryLocked, topRefreshGeometryLockID == lockID else { return }
        normalizeTopRefreshGeometry(animated: false)
        if release {
            isTopRefreshGeometryLocked = false
            endTabBarScrollFreezeForRefresh()
        }
    }

    func normalizeTopRefreshGeometry(animated: Bool) {
        setSearchRowCollapsed(false, animated: false)
        view.layoutIfNeeded()
        updateTableInsets()
        let topOffset = CGPoint(x: 0, y: -tableView.contentInset.top)
        if abs(tableView.contentOffset.y - topOffset.y) > 0.5 {
            tableView.setContentOffset(topOffset, animated: animated)
        }
        lastHomeScrollY = 0
    }

    func updateBottomChrome(animated: Bool) {
        let updates = {
            self.floatingActionButtonBottomConstraint?.constant = -self.currentBottomChromeHeight - 20
            self.updateTableInsets()
            self.view.layoutIfNeeded()
        }

        if animated {
            DoerMotion.animate(duration: DoerMotion.quick, animations: updates)
        } else {
            updates()
        }
    }

    func reassertBottomChromeAfterApplicationActivation() {
        guard isViewLoaded, view.window != nil else { return }
        (tabBarController as? ForumTabBarController)?.reassertTabBarLayoutAfterApplicationActivation()
        updateBottomChrome(animated: false)
        lastHomeScrollY = tableView.contentOffset.y + tableView.contentInset.top

        Task { @MainActor in
            self.reassertBottomChromeIfVisible()
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 250_000_000)
            self.reassertBottomChromeIfVisible()
        }
    }

    func reassertBottomChromeIfVisible() {
        guard isViewLoaded, view.window != nil else { return }
        (tabBarController as? ForumTabBarController)?.syncTabBarVisibilityForCurrentContent()
        updateBottomChrome(animated: false)
        lastHomeScrollY = tableView.contentOffset.y + tableView.contentInset.top
    }
}
