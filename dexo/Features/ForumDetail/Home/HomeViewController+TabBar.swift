import Combine
import Network
import UIKit

// MARK: - TabBar
extension HomeViewController {
    func updateTabBarVisibilityForCurrentScroll(animated: Bool) {
        // Passive layout / appear / inset changes must NEVER hide the tab bar.
        // Only user-driven scroll (see scrollViewDidScroll) may collapse it.
        // Hiding here caused intermittent "tab bar missing on first launch" when
        // contentOffset/insets jumped above 40pt after first data bind.
        guard !shouldFreezeTabBarScrollControl else { return }
        let y = tableView.contentOffset.y + tableView.contentInset.top
        if !AppSettings.shared.bottomBarAutoHideEnabled || y <= 48 || isHomeTabBarHidden {
            // Always restore when near top or when already stuck hidden without user scroll.
            if !AppSettings.shared.bottomBarAutoHideEnabled || y <= 48 {
                setHomeTabBarHidden(false, animated: animated)
            }
        }
    }

    /// 进入顶部刷新：只冻结滚动显隐，不主动 pin 显隐 tab bar（主动改会和 geometry/inset 抖动）。
    func beginTabBarScrollFreezeForRefresh() {
        tabBarScrollFreezeID += 1
        isTabBarScrollFrozenForRefresh = true
        lastHomeScrollY = tableView.contentOffset.y + tableView.contentInset.top
    }

    /// 顶部刷新 settle 后解冻，恢复上滑隐藏/下滑显示。
    func endTabBarScrollFreezeForRefresh() {
        tabBarScrollFreezeID += 1
        let freezeID = tabBarScrollFreezeID
        // 稍晚解冻，吃掉 endRefreshing 回弹。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.tabBarScrollFreezeID == freezeID else { return }
            self.isTabBarScrollFrozenForRefresh = false
            self.lastHomeScrollY = self.tableView.contentOffset.y + self.tableView.contentInset.top
            self.resyncTabBarVisibilityAfterFreeze()
        }
    }

    func beginTabBarScrollFreezeForLoadMore() {
        tabBarLoadMoreFreezeID += 1
        let freezeID = tabBarLoadMoreFreezeID
        isTabBarScrollFrozenForLoadMore = true
        lastHomeScrollY = tableView.contentOffset.y + tableView.contentInset.top
        lastTopicListContentHeight = tableView.contentSize.height
        // 上滑翻页时 tab bar 本应保持隐藏；冻结窗口内禁止被 contentSize 抖动拉出来。
        if AppSettings.shared.bottomBarAutoHideEnabled,
           tableView.contentOffset.y + tableView.contentInset.top > 40 {
            setHomeTabBarHidden(true, animated: true)
        }
        // Always arm an unfreeze timer. willDisplay used to freeze without a matching
        // end call when loadMore no-ops, permanently locking tab-bar auto-hide.
        scheduleLoadMoreTabBarUnfreeze(freezeID: freezeID, attempt: 0)
    }

    func endTabBarScrollFreezeForLoadMore() {
        tabBarLoadMoreFreezeID += 1
        let freezeID = tabBarLoadMoreFreezeID
        // contentSize 插入后继续禁止 show，覆盖 diffable apply + 惯性回弹。
        tabBarShowSuppressedUntil = max(tabBarShowSuppressedUntil, CACurrentMediaTime() + 0.55)
        // contentSize / footer 切换后多等一会儿，再解冻并同步显隐。
        scheduleLoadMoreTabBarUnfreeze(freezeID: freezeID, attempt: 0)
    }

    func scheduleLoadMoreTabBarUnfreeze(freezeID: Int, attempt: Int) {
        let delay: TimeInterval = attempt == 0 ? 0.28 : 0.18
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, self.tabBarLoadMoreFreezeID == freezeID else { return }
            self.lastHomeScrollY = self.tableView.contentOffset.y + self.tableView.contentInset.top
            self.lastTopicListContentHeight = self.tableView.contentSize.height
            // Keep freezing only while load-more is actually running.
            if self.viewModel.isLoadingMore, attempt < 12 {
                self.scheduleLoadMoreTabBarUnfreeze(freezeID: freezeID, attempt: attempt + 1)
                return
            }
            // Extra settle beats after loading ends (contentSize jump + decel bounce).
            if attempt < 2 {
                self.scheduleLoadMoreTabBarUnfreeze(freezeID: freezeID, attempt: attempt + 1)
                return
            }
            // Still decelerating after insert: hold freeze one more beat so bounce
            // cannot treat residual velocity as "show tab bar".
            if self.tableView.isDecelerating || self.tableView.isDragging, attempt < 6 {
                self.scheduleLoadMoreTabBarUnfreeze(freezeID: freezeID, attempt: attempt + 1)
                return
            }
            self.isTabBarScrollFrozenForLoadMore = false
            self.lastHomeScrollY = self.tableView.contentOffset.y + self.tableView.contentInset.top
            self.lastTopicListContentHeight = self.tableView.contentSize.height
            // Keep show suppressed briefly after unfreeze for late layout passes.
            self.tabBarShowSuppressedUntil = max(
                self.tabBarShowSuppressedUntil,
                CACurrentMediaTime() + 0.35
            )
            self.resyncTabBarVisibilityAfterFreeze()
        }
    }

    /// After refresh/load-more freeze, re-apply show/hide from the current offset
    /// so the bar is not stuck visible (or stuck hidden) until the next gesture.
    func resyncTabBarVisibilityAfterFreeze() {
        guard AppSettings.shared.bottomBarAutoHideEnabled else {
            setHomeTabBarHidden(false, animated: true)
            return
        }
        let y = tableView.contentOffset.y + tableView.contentInset.top
        lastHomeScrollY = y
        lastTopicListContentHeight = tableView.contentSize.height

        // 顶部必须露出；其余情况解冻后若已是隐藏，绝不因 velocity/回弹自动弹出来。
        // 真正的「下滑显示」只走 scrollViewDidScroll 的主动拖动手势。
        if y <= HomeTabBarScrollPolicy.topRevealY {
            setHomeTabBarHidden(false, animated: true)
            return
        }
        if isHomeTabBarHidden {
            return
        }

        let activelyDragging = tableView.isDragging
        let userDriven = activelyDragging || tableView.isDecelerating
        let velocityY = tableView.panGestureRecognizer.velocity(in: tableView).y
        let suppressShow = CACurrentMediaTime() < tabBarShowSuppressedUntil
        let nearBottom = isNearTopicListBottomForPagination
            && (viewModel.canLoadMore || viewModel.isLoadingMore)
        if let hidden = HomeTabBarScrollPolicy.preferredHidden(
            contentY: y,
            userDriven: userDriven,
            velocityY: velocityY,
            nearBottomPagination: nearBottom,
            suppressShow: suppressShow,
            activelyDragging: activelyDragging
        ) {
            // 解冻 resync 只允许继续隐藏，不允许把已显示改回… 等等，若当前是显示状态
            // 且 velocity 是 hide，可以藏。若 policy 说 show，忽略（上面已 early-return hidden）。
            if hidden {
                setHomeTabBarHidden(true, animated: true)
            }
            return
        }
        // Idle mid-list while flag says shown: heal broken "flag shown, bar gone".
        setHomeTabBarHidden(false, animated: false)
    }

    /// 跟踪 loadMore 状态，在加载中与刚结束时冻结 tab bar 滚动显隐。
    func syncTabBarFreezeWithLoadMoreState() {
        let loadingMore = viewModel.isLoadingMore
        if loadingMore {
            if !wasLoadingMoreTopics {
                beginTabBarScrollFreezeForLoadMore()
            }
            lastHomeScrollY = tableView.contentOffset.y + tableView.contentInset.top
        } else if wasLoadingMoreTopics {
            endTabBarScrollFreezeForLoadMore()
        }
        wasLoadingMoreTopics = loadingMore
    }

    func setHomeTabBarHidden(_ hidden: Bool, animated: Bool) {
        guard AppSettings.shared.bottomBarAutoHideEnabled || !hidden else { return }
        let tabBarController = tabBarController as? ForumTabBarController
        let bar = tabBarController?.tabBar
        // Broken "should be visible" states after CF / interrupted hide animations.
        let tabBarVisiblyBroken = !hidden && (
            bar?.isHidden == true
            || bar?.transform != .identity
            || (bar != nil && bar!.alpha < 0.99)
        )
        guard isHomeTabBarHidden != hidden || tabBarVisiblyBroken else { return }
        isHomeTabBarHidden = hidden
        // When recovering a broken bar, force a non-animated hard apply.
        tabBarController?.setTabBarHiddenByScroll(hidden, animated: animated && !tabBarVisiblyBroken)
        if !hidden {
            tabBarController?.forceRevealTabBarForRootContent()
        }
        updateBottomChrome(animated: animated)
    }

    /// Scroll-end safety net: if flag says visible but bar is gone/covered, unstick it.
    func healTabBarVisibilityAfterScrollSettles() {
        guard !shouldFreezeTabBarScrollControl else { return }
        let y = tableView.contentOffset.y + tableView.contentInset.top
        if !AppSettings.shared.bottomBarAutoHideEnabled || y <= 48 {
            setHomeTabBarHidden(false, animated: true)
            return
        }
        guard !isHomeTabBarHidden else { return }
        let bar = (tabBarController as? ForumTabBarController)?.tabBar
        let broken = bar?.isHidden == true || bar?.transform != .identity || (bar?.alpha ?? 1) < 0.99
        if broken {
            setHomeTabBarHidden(false, animated: false)
        }
    }
}
