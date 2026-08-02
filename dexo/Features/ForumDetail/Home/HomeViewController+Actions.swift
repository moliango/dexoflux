import Combine
import Network
import UIKit

// MARK: - Actions
extension HomeViewController {
    func presentMiniProgramDrawer() {
        let drawer: MiniProgramDrawerViewController
        if let existing = miniProgramDrawer {
            drawer = existing
        } else {
            let created = MiniProgramDrawerViewController(
                api: api,
                username: authGate?.currentUsername()
            )
            created.onSelectProgram = { [weak self] program in
                guard let self else { return }
                MiniProgramFactory.present(
                    program: program,
                    from: self,
                    api: self.api,
                    username: self.authGate?.currentUsername()
                )
            }
            created.onOpenMyPrograms = { [weak self] in
                guard let self else { return }
                let launcher = MiniProgramLauncherViewController(
                    api: self.api,
                    username: self.authGate?.currentUsername()
                )
                self.navigationController?.pushViewController(launcher, animated: true)
            }
            // Host on ForumTabBarController so the drawer can cover the full
            // screen including the custom tab bar region.
            let host: UIViewController = tabBarController ?? navigationController ?? self
            host.addChild(created)
            created.view.translatesAutoresizingMaskIntoConstraints = false
            host.view.addSubview(created.view)
            NSLayoutConstraint.activate([
                created.view.topAnchor.constraint(equalTo: host.view.topAnchor),
                created.view.leadingAnchor.constraint(equalTo: host.view.leadingAnchor),
                created.view.trailingAnchor.constraint(equalTo: host.view.trailingAnchor),
                created.view.bottomAnchor.constraint(equalTo: host.view.bottomAnchor),
            ])
            created.didMove(toParent: host)
            miniProgramDrawer = created
            drawer = created
        }

        // Always (re)bind dismiss so tab bar is restored even if the drawer was
        // created before this behavior existed.
        drawer.onDismissed = { [weak self] in
            guard let self else { return }
            if let forumTab = self.tabBarController as? ForumTabBarController {
                forumTab.setTabBarHiddenByScroll(false, animated: true)
            } else {
                self.tabBarController?.tabBar.isHidden = false
            }
        }

        // ForumTabBarController always re-brings tabBar to front on layout —
        // hide it while the drawer is open so the panel is truly full-screen.
        if let forumTab = tabBarController as? ForumTabBarController {
            forumTab.setTabBarHiddenByScroll(true, animated: false)
        } else {
            tabBarController?.tabBar.isHidden = true
        }

        // Ensure drawer sits above any remaining chrome.
        if let hostView = drawer.view.superview {
            hostView.bringSubviewToFront(drawer.view)
        }
        drawer.open(animated: true, username: authGate?.currentUsername())
    }

    @objc func categoryManagerLongPressed(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began else { return }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        presentCategoryPinManager()
    }

    func presentCategoryPinManager() {
        let manager = CategoryTabManagerViewController(
            categories: viewModel.allSelectableCategories(),
            pinnedCategoryIds: AppSettings.shared.homePinnedCategoryIds,
            displayNameProvider: { [weak self] category in
                self?.viewModel.categoryDisplayName(for: category) ?? category.name
            },
            parentNameProvider: { [weak self] category in
                guard let parentId = category.parentCategoryId,
                      let parent = self?.viewModel.category(id: parentId)
                else { return nil }
                return self?.viewModel.categoryDisplayName(for: parent) ?? parent.name
            },
            colorProvider: { [weak self] category in
                self?.viewModel.category(id: category.id).flatMap { Self.color(fromHex: $0.color) }
                    ?? Self.color(fromHex: category.color)
            }
        )
        manager.onPinnedCategoryIdsChanged = { [weak self] ids in
            AppSettings.shared.homePinnedCategoryIds = ids
            self?.rebuildCategoryTabs()
        }
        let nav = UINavigationController(rootViewController: manager)
        nav.modalPresentationStyle = .pageSheet
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = 20
        }
        present(nav, animated: true)
    }

    @objc func pullToRefresh() {
        guard topicReloadTask == nil, !viewModel.isLoading else {
            if refreshControl.isRefreshing, !isTopRefreshGeometryLocked {
                refreshControl.endRefreshing()
            }
            return
        }
        beginTopRefreshGeometryLock(animated: false)
        reloadTopics()
    }

    @discardableResult
    func triggerShortPullRefreshIfNeeded(_ scrollView: UIScrollView) -> Bool {
        let pullDistance = max(
            0,
            -(scrollView.contentOffset.y + scrollView.contentInset.top)
        )
        guard HomePullToRefreshPolicy.shouldTrigger(
            pullDistance: pullDistance,
            isRefreshing: refreshControl.isRefreshing,
            isLoading: viewModel.isLoading,
            hasReloadTask: topicReloadTask != nil
        ) else {
            return false
        }

        refreshControl.beginRefreshing()
        pullToRefresh()
        return true
    }

    @objc func incomingTopicsTapped() {
        beginTopRefreshGeometryLock(animated: true)
        incomingTopicsRetryTask?.cancel()
        incomingTopicsRetryTask = nil
        Task {
            await viewModel.loadIncomingTopics()
            finishTopRefreshGeometryLockIfNeeded()
        }
    }

    func retryIncomingTopicsAfterCloudflareIfNeeded() {
        guard viewModel.shouldRetryIncomingTopicsAfterCloudflare,
              !viewModel.incomingTopicIds.isEmpty
        else { return }
        logCloudflareState("scheduling incoming topics retry after verification ids=\(viewModel.incomingTopicIds)")
        incomingTopicsRetryTask?.cancel()
        incomingTopicsRetryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 450_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.viewModel.loadIncomingTopics()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.incomingTopicsRetryTask = nil
                self.updateIncomingTopicsHeader()
                self.logCloudflareState("incoming topics retry completed remainingIds=\(self.viewModel.incomingTopicIds)")
                if self.viewModel.incomingTopicIds.isEmpty {
                    let topOffset = CGPoint(x: 0, y: -self.tableView.contentInset.top)
                    self.tableView.setContentOffset(topOffset, animated: true)
                }
            }
        }
    }

    /// Resume pagination that failed mid-scroll when CF blocked the next page.
    func retryLoadMoreAfterCloudflareIfNeeded() {
        let shouldRetry = viewModel.shouldRetryLoadMoreAfterCloudflare
            || isCloudflareLoadMoreErrorMessage(viewModel.loadMoreErrorMessage)
        guard shouldRetry, viewModel.canLoadMore else {
            viewModel.shouldRetryLoadMoreAfterCloudflare = false
            return
        }

        // Drop sticky CF footer text immediately so the list is not stuck on the
        // "需要完成 Cloudflare 验证…" banner after a successful pass.
        if viewModel.loadMoreErrorMessage != nil {
            viewModel.loadMoreErrorMessage = nil
            updateUI()
        }

        if viewModel.isLoading || viewModel.isLoadingMore || topicLoadMoreTask != nil {
            // Another list request is in flight — keep the flag and try again shortly
            // so we don't require the user to scroll away and back.
            viewModel.shouldRetryLoadMoreAfterCloudflare = true
            logCloudflareState("load-more retry deferred; list request still in flight")
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 800_000_000)
                await MainActor.run {
                    self?.retryLoadMoreAfterCloudflareIfNeeded()
                }
            }
            return
        }

        logCloudflareState("scheduling load-more retry after verification topics=\(viewModel.topics.count)")
        viewModel.shouldRetryLoadMoreAfterCloudflare = false
        beginTabBarScrollFreezeForLoadMore()
        topicLoadMoreTask = Task { [weak self] in
            // Let grace + cookie/session reset settle before the next page request.
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard !Task.isCancelled, let self else { return }
            await self.viewModel.loadMoreTopics()
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self.topicLoadMoreTask = nil
                self.updateUI()
                self.logCloudflareState(
                    "load-more retry completed topics=\(self.viewModel.topics.count) error=\(self.viewModel.loadMoreErrorMessage != nil)"
                )
            }
        }
    }

    func isCloudflareLoadMoreErrorMessage(_ message: String?) -> Bool {
        guard let message, !message.isEmpty else { return false }
        let cfMessage = String(localized: "error.cloudflare_challenge")
        return message == cfMessage
            || message.localizedCaseInsensitiveContains("cloudflare")
            || message.contains("验证")
    }

    func shouldReloadTopicsAfterCloudflareVerification() -> Bool {
        // Full-list CF block (empty or error banner). Pagination is handled separately.
        if viewModel.isBlockedByCloudflare { return true }
        if viewModel.topics.isEmpty, viewModel.errorMessage != nil { return true }
        return false
    }

    func reloadTopicsAfterCloudflareVerificationIfNeeded(_ shouldReload: Bool) {
        guard shouldReload else { return }
        logCloudflareState("scheduling topics reload after verification")
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                guard self.isViewLoaded, self.view.window != nil else { return }
                self.logCloudflareState("reloading topics after verification")
                self.recoverTransportAndReload()
            }
        }
    }

    @objc func pollIncomingTopics() {
        Task {
            await viewModel.detectIncomingTopics()
        }
    }

    @objc func fabTapped() {
        switch fabMode {
        case .create:
            setCreateMenuVisible(!isCreateMenuVisible, animated: true)
        case .refresh:
            setCreateMenuVisible(false, animated: false)
            refreshFromFloatingActionButton()
        }
    }

    @objc func createMenuBackdropTapped() {
        setCreateMenuVisible(false, animated: true)
    }

    @objc func createTopicMenuTapped() {
        setCreateMenuVisible(false, animated: true)
        openNewTopicComposer()
    }

    @objc func draftsMenuTapped() {
        setCreateMenuVisible(false, animated: true)
        openDrafts()
    }

    func openNewTopicComposer() {
        let presentComposer = { [weak self] in
            guard let self else { return }
            let composer = NewTopicComposerViewController(
                api: self.api,
                categories: self.viewModel.categories,
                initialCategoryId: self.viewModel.selectedCategoryId
            )
            composer.onTopicCreated = { [weak self] topicId in
                guard let self else { return }
                self.reloadTopics()
                let detailVC = TopicDetailViewController(api: self.api, topicId: topicId)
                self.navigationController?.pushViewController(detailVC, animated: true)
            }
            let nav = UINavigationController(rootViewController: composer)
            self.present(nav, animated: true)
        }
        if let authGate {
            authGate.requireAuth(then: presentComposer)
        } else {
            presentComposer()
        }
    }

    func openDrafts() {
        let presentDrafts = { [weak self] in
            guard let self else { return }
            self.navigationController?.pushViewController(DraftsViewController(api: self.api), animated: true)
        }
        if let authGate {
            authGate.requireAuth(then: presentDrafts)
        } else {
            presentDrafts()
        }
    }

    func refreshFromFloatingActionButton() {
        setFABMode(.create, animated: true)
        beginTopRefreshGeometryLock(animated: true)
        reloadTopics()
    }

    func refreshFromEmptyState() {
        beginTopRefreshGeometryLock(animated: false)
        reloadTopics()
    }

    @objc func loginTapped() {
        authGate?.requireAuth { [weak self] in
            guard let self else { return }
            self.reloadTopics(resetCategoryMetadata: true)
        }
    }
}
