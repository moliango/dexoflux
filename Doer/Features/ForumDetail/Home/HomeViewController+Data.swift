import Combine
import Network
import UIKit

// MARK: - Data
extension HomeViewController {
    func applyTopicSnapshot(animatingDifferences: Bool? = nil) {
        let itemIdentifiers = topicSnapshotItemIdentifiers()
        var snapshot = NSDiffableDataSourceSnapshot<Int, Int>()
        snapshot.appendSections([0])
        snapshot.appendItems(itemIdentifiers, toSection: 0)

        prefetchAvatarImages(for: viewModel.topics)
        let currentSnapshot = dataSource.snapshot()
        let currentIds = currentSnapshot.itemIdentifiers
        let needsInitialSnapshot = currentSnapshot.sectionIdentifiers.isEmpty
        let visibleExistingIds = Set(
            tableView.indexPathsForVisibleRows?.compactMap { dataSource.itemIdentifier(for: $0) } ?? []
        )
        let idsNeedingReconfigure = itemIdentifiers.filter { visibleExistingIds.contains($0) }
        // load more / contentSize 突变窗口禁止 diffable 动画，否则 offset 会抖并带动 tab bar。
        // Also disable while user is near bottom with pending pagination (pre-freeze window).
        let shouldAnimateSnapshot: Bool
        if let animatingDifferences {
            shouldAnimateSnapshot = animatingDifferences
        } else if shouldFreezeTabBarScrollControl
            || viewModel.isLoadingMore
            || isTabBarScrollFrozenForLoadMore
            || topicLoadMoreTask != nil {
            shouldAnimateSnapshot = false
        } else {
            shouldAnimateSnapshot = view.window != nil
                && !tableView.isDragging
                && !tableView.isDecelerating
        }

        let layoutKind = homeListLayoutKind
        let layoutChanged = lastAppliedHomeListLayoutKind != layoutKind
        lastAppliedHomeListLayoutKind = layoutKind

        if !needsInitialSnapshot, currentIds == itemIdentifiers, !layoutChanged {
            if !idsNeedingReconfigure.isEmpty {
                var updatedSnapshot = currentSnapshot
                updatedSnapshot.reconfigureItems(idsNeedingReconfigure)
                dataSource.apply(updatedSnapshot, animatingDifferences: false)
            }
        } else {
            if layoutChanged, !itemIdentifiers.isEmpty, currentIds == itemIdentifiers {
                // Same topic ids but different cell class (TopicCell ↔ chat session list).
                snapshot.reloadItems(itemIdentifiers)
            } else if !idsNeedingReconfigure.isEmpty {
                snapshot.reconfigureItems(idsNeedingReconfigure)
            }
            dataSource.apply(snapshot, animatingDifferences: layoutChanged ? false : shouldAnimateSnapshot)
        }
    }

    func topicSnapshotItemIdentifiers() -> [Int] {
        let orderedTopics = HomeTopicListOrdering.withPinnedFirst(
            viewModel.topics,
            pinnedIds: viewModel.pinnedTopicIds
        )

        if usesXiaohongshuCardLayout {
            let pinnedIds = orderedTopics.compactMap { topic -> Int? in
                HomeTopicListOrdering.isPinned(topic, pinnedIds: viewModel.pinnedTopicIds) ? topic.id : nil
            }
            let unpinnedCount = orderedTopics.filter {
                !HomeTopicListOrdering.isPinned($0, pinnedIds: viewModel.pinnedTopicIds)
            }.count
            let rowCount = Int(ceil(Double(unpinnedCount) / 2.0))
            return pinnedIds + (0..<rowCount).map(Self.xiaohongshuRowIdentifier(for:))
        }

        var seen = Set<Int>()
        return orderedTopics.compactMap { topic -> Int? in
            guard seen.insert(topic.id).inserted else { return nil }
            return topic.id
        }
    }

    func reloadTopics(resetCategoryMetadata: Bool = false, detectIncoming: Bool = true) {
        topicReloadTask?.cancel()
        topicLoadMoreTask?.cancel()
        topicLoadMoreTask = nil
        reloadTimeoutTask?.cancel()
        incomingTopicsRetryTask?.cancel()
        incomingTopicsRetryTask = nil
        reloadSequence += 1
        let sequence = reloadSequence
        if viewModel.topics.isEmpty {
            isInitialTopicLoadPending = true
            updateUI()
        }

        if resetCategoryMetadata {
            viewModel.resetCategoryMetadata(clearSelection: true)
        }

        reloadTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: Self.reloadTimeoutNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.handleReloadTimeout(sequence: sequence)
            }
        }

        topicReloadTask = Task { [weak self] in
            guard let self else { return }
            await self.viewModel.loadTopics()
            guard !Task.isCancelled else { return }
            if detectIncoming {
                await self.viewModel.detectIncomingTopics()
            }
            await MainActor.run {
                self.finishReload(sequence: sequence)
            }
        }
    }

    func handleReloadTimeout(sequence: Int) {
        guard sequence == reloadSequence else { return }
        topicReloadTask?.cancel()
        topicReloadTask = nil
        reloadTimeoutTask = nil
        isInitialTopicLoadPending = false
        postInitialContentReadyIfNeeded()
        viewModel.finishLoadingAfterTimeout(message: String(localized: "error.network_timeout"))
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
        // 只收 geometry lock；tab bar 等 lock 释放后再 restore，避开 endRefreshing 回弹窗口。
        finishTopRefreshGeometryLockIfNeeded()
    }

    func finishReload(sequence: Int) {
        guard sequence == reloadSequence else { return }
        reloadTimeoutTask?.cancel()
        reloadTimeoutTask = nil
        topicReloadTask = nil
        isInitialTopicLoadPending = false
        postInitialContentReadyIfNeeded()
        if refreshControl.isRefreshing {
            refreshControl.endRefreshing()
        }
        // 先 updateUI 再收 lock；restore 只在 lock 真正 release 时做一次。
        updateUI()
        finishTopRefreshGeometryLockIfNeeded()
    }

    func postInitialContentReadyIfNeeded() {
        guard !didPostInitialContentReady else { return }
        didPostInitialContentReady = true
        // First paint/bind can thrash contentOffset; re-assert tab bar after first content.
        setHomeTabBarHidden(false, animated: false)
        (tabBarController as? ForumTabBarController)?.syncTabBarVisibilityForCurrentContent()
        NotificationCenter.default.post(
            name: Self.initialContentReadyNotification,
            object: self,
            userInfo: [DiscourseAPI.cloudflareBaseURLUserInfoKey: api.baseURL]
        )
    }

    func selectListMode(_ mode: HomeListMode) {
        guard viewModel.listMode != mode else { return }
        viewModel.listMode = mode
        updateFilterButton()
        reloadTopics()
    }

    @objc func searchTapped() {
        let searchVC = SearchViewController(api: api)
        navigationController?.pushViewController(searchVC, animated: true)
    }

    @objc func notificationsTapped() {
        let notificationsVC = NotificationsViewController(
            api: api,
            authGate: authGate,
            notificationCoordinator: notificationCoordinator
        )
        notificationsVC.onTopicSelected = { [weak self] topicId, postNumber, postId in
            guard let self else { return }
            let detailVC = TopicDetailFactory.make(
                api: self.api,
                topicId: topicId,
                initialFloor: postNumber,
                initialPostId: postId
            )
            self.navigationController?.pushViewController(detailVC, animated: true)
        }
        let nav = UINavigationController(rootViewController: notificationsVC)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(nav, animated: true)
    }

    func updateNotificationBadge() {
        let unreadCount = notificationCoordinator.unreadCount
        notificationBadgeView.isHidden = unreadCount == 0
        notificationBadgeView.layer.borderColor = headerContainer.backgroundColor?.cgColor
        notificationButton.accessibilityValue = unreadCount > 0 ? String(unreadCount) : nil
    }

    @objc func categoryManagerTapped() {
        if AppSettings.shared.homeCategoryDrawerSwipeEnabled {
            refreshCategoryDrawerContent()
            view.bringSubviewToFront(categoryDrawer)
            categoryDrawer.open(animated: true)
            return
        }
        presentCategoryPinManager()
    }

    @objc func miniProgramButtonTapped() {
        guard AppSettings.shared.miniProgramsEnabled else { return }
        presentMiniProgramDrawer()
    }
}
