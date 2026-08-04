import Combine
import Network
import UIKit

extension HomeViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard gestureRecognizer === createMenuDismissTapGesture, isCreateMenuVisible else { return true }
        let location = touch.location(in: view)
        return !createMenuContainer.frame.contains(location)
            && !floatingActionButton.frame.contains(location)
    }
}

extension HomeViewController: UITableViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        if isCreateMenuVisible, scrollView.isDragging || scrollView.isDecelerating {
            setCreateMenuVisible(false, animated: true)
        }
        hideHomeScrollIndicators()
        updateIncomingTopicsPlacement(animated: false)
        let y = scrollView.contentOffset.y + scrollView.contentInset.top
        let previousY = lastHomeScrollY ?? y
        var deltaY = y - previousY
        lastHomeScrollY = y

        // load-more 插入行会让 contentSize 突然变大，UITableView 常伴随 offset 回弹，
        // 产生假的 deltaY < 0，被误判成「下滑」从而弹出 tab bar。
        let contentHeight = scrollView.contentSize.height
        let contentGrew = contentHeight > lastTopicListContentHeight + 1
        if contentGrew {
            lastTopicListContentHeight = contentHeight
            // 重置基线，吞掉这一帧的假 delta；并短暂禁止 show（后续几帧回弹也不出 tab bar）。
            lastHomeScrollY = y
            deltaY = max(0, deltaY)
            tabBarShowSuppressedUntil = CACurrentMediaTime() + 0.55
        } else {
            lastTopicListContentHeight = contentHeight
        }

        let velocityY = scrollView.panGestureRecognizer.velocity(in: scrollView).y
        if velocityY > 80, y > 24 {
            setFABMode(.refresh, animated: true)
        } else if velocityY < -80 || y <= 2 {
            setFABMode(.create, animated: true)
        }

        // Only hide/show from real user interaction, never from programmatic offset jumps
        // (first load, banner insert, contentSize changes, inset adjustments).
        let userDriven = scrollView.isDragging
            || scrollView.isDecelerating
            || scrollView.panGestureRecognizer.state == .began
            || scrollView.panGestureRecognizer.state == .changed
        // 显示 tab bar 必须手指仍在拖；纯惯性/回弹的负 delta 不算「下滑」。
        let activelyDragging = scrollView.isDragging
            || scrollView.panGestureRecognizer.state == .began
            || scrollView.panGestureRecognizer.state == .changed
        let suppressShow = CACurrentMediaTime() < tabBarShowSuppressedUntil
        let nearBottomPagination = isNearTopicListBottomForPagination
            && (viewModel.canLoadMore || viewModel.isLoadingMore || isTabBarScrollFrozenForLoadMore)

        // Drive search morph while scrolling. Hysteresis avoids flicker at the
        // threshold; generation-guarded animators avoid the "icon vanished" race.
        if userDriven, !isTopRefreshGeometryLocked {
            if isSearchRowCollapsed {
                // Expand only when clearly near top.
                if y < 8 {
                    setSearchRowCollapsed(false, animated: true)
                }
            } else if y > 24 {
                setSearchRowCollapsed(true, animated: true)
            }
        }

        // 刷新 / 加载下一页 / 触底窗口：只允许「上滑隐藏」，禁止「下滑显示」。
        // 分页 contentSize 抖动的假 deltaY 绝不能把 tab bar 弹出来。
        if shouldFreezeTabBarScrollControl {
            if !AppSettings.shared.bottomBarAutoHideEnabled {
                setHomeTabBarHidden(false, animated: true)
            } else if y <= 8 {
                setHomeTabBarHidden(false, animated: true)
            } else if HomeTabBarScrollPolicy.shouldHideFromScroll(
                contentY: y, userDriven: userDriven, deltaY: deltaY
            ) {
                setHomeTabBarHidden(true, animated: true)
            }
            // 注意：此处故意没有 deltaY < 0 → show 的分支。
            return
        }
        if !AppSettings.shared.bottomBarAutoHideEnabled {
            setHomeTabBarHidden(false, animated: true)
            return
        }
        // Near top always show.
        if y <= 8 {
            setHomeTabBarHidden(false, animated: true)
            return
        }
        // 显示：仅主动手指下滑；上滑翻页 / contentSize 回弹 / 触底分页窗口一律不出。
        if HomeTabBarScrollPolicy.shouldRevealFromScroll(
            contentY: y,
            isDragging: activelyDragging,
            deltaY: deltaY,
            contentGrew: contentGrew,
            suppressShow: suppressShow,
            nearBottomPagination: nearBottomPagination
        ) {
            setHomeTabBarHidden(false, animated: true)
            return
        }
        if HomeTabBarScrollPolicy.shouldHideFromScroll(
            contentY: y, userDriven: userDriven, deltaY: deltaY
        ) {
            setHomeTabBarHidden(true, animated: true)
        }
    }

    func scrollViewDidEndDragging(_ scrollView: UIScrollView, willDecelerate decelerate: Bool) {
        guard scrollView === tableView else { return }
        if triggerShortPullRefreshIfNeeded(scrollView) { return }
        guard !decelerate else { return }
        settleSearchRowCollapse(animated: true)
        healTabBarVisibilityAfterScrollSettles()
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        settleSearchRowCollapse(animated: true)
        healTabBarVisibilityAfterScrollSettles()
    }

    func scrollViewDidEndScrollingAnimation(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        settleSearchRowCollapse(animated: true)
    }

    func settleSearchRowCollapse(animated: Bool) {
        guard !isTopRefreshGeometryLocked else {
            normalizeTopRefreshGeometry(animated: false)
            return
        }
        let y = tableView.contentOffset.y + tableView.contentInset.top
        // Settle with the same hysteresis band as live scroll.
        let shouldCollapse: Bool
        if isSearchRowCollapsed {
            shouldCollapse = y >= 8
        } else {
            shouldCollapse = y > 24
        }
        setSearchRowCollapsed(shouldCollapse, animated: animated)
        // Even if state unchanged, heal icon visibility after interrupted morphs.
        if searchChromeNeedsHeal() {
            applySearchRowChromeFinalState()
        }
        lastHomeScrollY = tableView.contentOffset.y + tableView.contentInset.top
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let topicId = dataSource.itemIdentifier(for: indexPath),
              Self.xiaohongshuRowIndex(from: topicId) == nil
        else { return }
        openTopic(topicId)
    }

    func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        // Follow-scroll avatar warm-up (not only the first page of the list).
        prefetchAvatarsAroundVisibleRows(around: indexPath)

        let totalRows = tableView.numberOfRows(inSection: 0)
        if indexPath.row >= totalRows - 5,
           viewModel.canLoadMore,
           viewModel.loadMoreErrorMessage == nil,
           !viewModel.isLoadingMore,
           !viewModel.isLoading,
           topicLoadMoreTask == nil {
            beginTabBarScrollFreezeForLoadMore()
            topicLoadMoreTask = Task { [weak self] in
                guard let self else { return }
                await self.viewModel.loadMoreTopics()
                await MainActor.run {
                    self.topicLoadMoreTask = nil
                    // Keep freeze until snapshot settles; updateUI ends freeze via syncTabBarFreezeWithLoadMoreState.
                    self.updateUI()
                }
            }
        }
    }

    @objc func loadMoreRetryTapped() {
        guard topicLoadMoreTask == nil, !viewModel.isLoadingMore, !viewModel.isLoading else { return }
        viewModel.loadMoreErrorMessage = nil
        beginTabBarScrollFreezeForLoadMore()
        topicLoadMoreTask = Task { [weak self] in
            guard let self else { return }
            await self.viewModel.loadMoreTopics()
            await MainActor.run {
                self.topicLoadMoreTask = nil
                self.updateUI()
            }
        }
    }
}
