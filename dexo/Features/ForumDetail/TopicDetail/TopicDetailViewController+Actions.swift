import UIKit
import SafariServices

extension TopicDetailViewController {
    // MARK: - Auth / error helpers (used by Coordinator + cells)

    func performAuthenticated(_ action: @escaping () -> Void) {
        if let authGate = findAuthGating() {
            authGate.requireAuth(then: action)
        } else {
            action()
        }
    }

    func findAuthGating() -> AuthGating? {
        nearestAuthGating()
    }

    func showPostActionError(_ error: Error) {
        let alert = UIAlertController(
            title: String(localized: "post.action.failed"),
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }

    // MARK: - Diffable / bottom bar helpers (stay on VC)

    func reloadPostCell(postId: Int) {
        var snapshot = dataSource.snapshot()
        guard snapshot.indexOfItem(postId) != nil else { return }
        // Gate self-sizing beginUpdates while Diffable reloads cells.
        tableView.dexo_beginDataMutation()
        snapshot.reloadItems([postId])
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            self?.tableView.dexo_endDataMutation()
        }
    }

    func reconfigureVisiblePostCells(reloadAllIfNoneVisible: Bool = false) {
        // Never reloadItems while a full snapshot replace is in flight.
        guard !isApplyingPostSnapshot else { return }
        var snapshot = dataSource.snapshot()
        guard !snapshot.itemIdentifiers.isEmpty else { return }

        let visibleIds = (tableView.indexPathsForVisibleRows ?? []).compactMap {
            dataSource.itemIdentifier(for: $0)
        }.filter { snapshot.indexOfItem($0) != nil }

        let ids: [Int]
        if !visibleIds.isEmpty {
            ids = visibleIds
        } else if reloadAllIfNoneVisible {
            ids = snapshot.itemIdentifiers
        } else {
            return
        }

        tableView.dexo_beginDataMutation()
        snapshot.reloadItems(ids)
        dataSource.apply(snapshot, animatingDifferences: false) { [weak self] in
            self?.tableView.dexo_endDataMutation()
        }
    }

    func updateBottomBarProgress() {
        let current = currentVisibleFloor()
        let total = viewModel.totalFloors
        if let lastBottomBarProgressState,
           lastBottomBarProgressState.current == current,
           lastBottomBarProgressState.total == total {
            bottomBar.refreshGestureRecognizers()
            return
        }
        lastBottomBarProgressState = (current: current, total: total)
        bottomBar.configure(
            currentFloor: current,
            totalFloors: total
        )
    }

    func currentVisibleFloor() -> Int {
        guard viewModel.totalFloors > 0 else { return 0 }
        let visibleIndexPath = tableView.indexPathsForVisibleRows?
            .sorted { $0.row < $1.row }
            .first
        guard let visibleIndexPath,
              let postId = dataSource.itemIdentifier(for: visibleIndexPath),
              let streamIndex = viewModel.allPostIds.firstIndex(of: postId)
        else {
            return max(1, min(viewModel.loadedRangeStart + 1, viewModel.totalFloors))
        }
        return streamIndex + 1
    }

    // MARK: - Nav chrome (stays on VC; actions go through Coordinator)

    func makeExportMenu() -> UIMenu {
        let formatMenus = TopicExportFormat.allCases.map { format in
            UIMenu(
                title: format.title,
                image: UIImage(systemName: format == .markdown ? "doc.plaintext" : "chevron.left.forwardslash.chevron.right"),
                children: TopicExportRange.allCases.map { range in
                    UIAction(title: range.title) { [weak self] _ in
                        self?.coordinator.exportTopic(format: format, range: range)
                    }
                }
            )
        }
        let notionMenus = NotionSyncScope.allCases.map { scope in
            UIAction(title: scope.title) { [weak self] _ in
                self?.coordinator.syncTopicToNotion(scope: scope)
            }
        }
        let notionMenu = UIMenu(
            title: String(localized: "notion.sync", defaultValue: "同步到 Notion"),
            image: UIImage(systemName: "tray.and.arrow.up"),
            children: notionMenus
        )
        return UIMenu(
            title: String(localized: "topic.export", defaultValue: "导出话题"),
            image: UIImage(systemName: "square.and.arrow.up"),
            children: formatMenus + [notionMenu]
        )
    }

    func configureTopicActions() {
        let searchButton = UIBarButtonItem(
            image: UIImage(systemName: "magnifyingglass"),
            style: .plain,
            target: self,
            action: #selector(searchTopicTapped)
        )
        searchButton.accessibilityLabel = String(localized: "topic.search", defaultValue: "搜索话题")

        let topic = viewModel.topic
        let bookmarkTitle = topic?.bookmarked == true
            ? String(localized: "topic.bookmark.remove", defaultValue: "取消书签")
            : String(localized: "topic.bookmark.add", defaultValue: "添加书签")
        let bookmark = UIAction(
            title: bookmarkTitle,
            image: UIImage(systemName: topic?.bookmarked == true ? "bookmark.slash" : "bookmark")
        ) { [weak self] _ in
            self?.coordinator.bookmarkTopic()
        }
        let share = UIAction(
            title: String(localized: "topic.share", defaultValue: "分享链接"),
            image: UIImage(systemName: "square.and.arrow.up")
        ) { [weak self] _ in
            self?.coordinator.shareTopicLink(sourceView: nil)
        }
        let username = AuthManager.shared.username(for: api.baseURL)
        let isReadLater = TopicReadLaterStore.shared.contains(
            topicId: topicId,
            baseURL: api.baseURL,
            username: username
        )
        let readLater = UIAction(
            title: isReadLater
                ? String(localized: "topic.read_later.remove", defaultValue: "移出稍后阅读")
                : String(localized: "topic.read_later.add", defaultValue: "稍后阅读"),
            image: UIImage(systemName: "square.stack.3d.up"),
            state: isReadLater ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            let title = self.viewModel.topic?.title
                ?? self.viewModel.topic?.fancyTitle
                ?? "#\(self.topicId)"
            TopicReadLaterStore.shared.toggle(
                topicId: self.topicId,
                baseURL: self.api.baseURL,
                username: AuthManager.shared.username(for: self.api.baseURL),
                title: title,
                lastReadPostNumber: self.lastReadPostNumber ?? self.viewModel.topic?.lastReadPostNumber
            )
            self.configureTopicActions()
        }
        let shareImage = UIAction(
            title: String(localized: "topic.share_image", defaultValue: "生成分享图片"),
            image: UIImage(systemName: "photo")
        ) { [weak self] _ in
            self?.coordinator.shareTopicImage()
        }
        let opFilter = UIAction(
            title: viewModel.isFilteringByOP
                ? String(localized: "topic.filter_all", defaultValue: "显示全部回复")
                : String(localized: "topic.filter_op", defaultValue: "只看楼主"),
            image: UIImage(systemName: "line.3.horizontal.decrease.circle"),
            state: viewModel.isFilteringByOP ? .on : .off
        ) { [weak self] _ in
            guard let self else { return }
            self.viewModel.setFilteringByOP(!self.viewModel.isFilteringByOP)
        }
        let notificationMenu = UIMenu(
            title: String(localized: "topic.notifications", defaultValue: "通知级别"),
            image: UIImage(systemName: "bell"),
            children: DiscourseTopicDetail.NotificationLevel.allCases.reversed().map { level in
                UIAction(
                    title: self.title(for: level),
                    state: topic?.notificationLevel == level ? .on : .off
                ) { [weak self] _ in
                    self?.coordinator.setNotificationLevel(level)
                }
            }
        )
        let openBrowser = UIAction(
            title: String(localized: "topic.open_browser", defaultValue: "在浏览器打开"),
            image: UIImage(systemName: "globe")
        ) { [weak self] _ in
            guard let self, let url = URL(string: "\(self.baseURL)/t/\(self.topicId)") else { return }
            let browser = InAppBrowserViewController(
                api: self.api,
                username: AuthManager.shared.username(for: self.api.baseURL),
                initialURL: url
            )
            self.navigationController?.pushViewController(browser, animated: true)
        }
        let readingSettings = UIAction(
            title: String(localized: "topic.reading_settings", defaultValue: "阅读设置"),
            image: UIImage(systemName: "book")
        ) { [weak self] _ in
            self?.navigationController?.pushViewController(ReadingSettingsViewController(), animated: true)
        }
        var actions: [UIMenuElement] = [bookmark, readLater, notificationMenu, share, shareImage, opFilter]
        if topic?.canEdit == true {
            actions.append(UIAction(
                title: String(localized: "topic.edit", defaultValue: "编辑话题"),
                image: UIImage(systemName: "pencil")
            ) { [weak self] _ in
                self?.coordinator.editTopic()
            })
        }
        if DexoPluginRuntime.shared.registry.isPluginEnabled(BuiltInPluginID.topicExport, for: pluginScope) {
            actions.append(makeExportMenu())
        }
        actions.append(contentsOf: [openBrowser, readingSettings])

        let moreButton = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            menu: UIMenu(children: actions)
        )
        moreButton.accessibilityLabel = String(localized: "topic.more", defaultValue: "更多操作")
        navigationItem.rightBarButtonItems = [moreButton, searchButton]
    }

    func title(for level: DiscourseTopicDetail.NotificationLevel) -> String {
        switch level {
        case .watching: return String(localized: "topic.notifications.watching", defaultValue: "关注")
        case .tracking: return String(localized: "topic.notifications.tracking", defaultValue: "跟踪")
        case .regular: return String(localized: "topic.notifications.regular", defaultValue: "常规")
        case .muted: return String(localized: "topic.notifications.muted", defaultValue: "静音")
        }
    }

    // MARK: - Action entry points → Coordinator

    func replyButtonTapped() {
        coordinator.replyButtonTapped()
    }

    func shareTopicLink(sourceView: UIView?) {
        coordinator.shareTopicLink(sourceView: sourceView)
    }

    func bookmarkTopic() {
        coordinator.bookmarkTopic()
    }

    func exportTopic(format: TopicExportFormat, range: TopicExportRange) {
        coordinator.exportTopic(format: format, range: range)
    }

    func notionSync() {
        coordinator.notionSync()
    }

    @objc func aiAssistantTapped() {
        coordinator.aiAssistantTapped()
    }

    @objc func searchTopicTapped() {
        coordinator.searchTopicTapped()
    }

    @objc func pluginStateDidChange() {
        // Coordinator also observes; keep for any direct NotificationCenter.addObserver(self) call sites.
        configureTopicActions()
    }

    func editTopic() {
        coordinator.editTopic()
    }

    func handleLink(_ url: URL) {
        coordinator.handleLink(url)
    }

    func openInternalDestination(_ destination: ForumInternalLinkDestination) {
        coordinator.openInternalDestination(destination)
    }

    func shareTopicImage(postId: Int? = nil) {
        coordinator.shareTopicImage(postId: postId)
    }

    func maybeAutoSyncNotionAfterBookmark() {
        coordinator.maybeAutoSyncNotionAfterBookmark()
    }

    func presentSafari(_ url: URL) {
        coordinator.presentSafari(url)
    }

    func openInternalViewController(_ viewController: UIViewController) {
        coordinator.openInternalViewController(viewController)
    }

    func setNotificationLevel(_ level: DiscourseTopicDetail.NotificationLevel) {
        coordinator.setNotificationLevel(level)
    }

    func syncTopicToNotion(scope: NotionSyncScope, duplicate: NotionDuplicateAction = .skip) {
        coordinator.syncTopicToNotion(scope: scope, duplicate: duplicate)
    }

    // MARK: - Live topic stream sync

    func startLiveTopicSync() {
        stopLiveTopicSync()
        let timer = Timer(timeInterval: TopicDetailPaginationPolicy.liveSyncInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.performLiveTopicSync(reason: "timer")
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        liveSyncTimer = timer

        if appForegroundObserver == nil {
            appForegroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor [weak self] in
                    await self?.performLiveTopicSync(reason: "foreground")
                }
            }
        }

        Task { await performLiveTopicSync(reason: "start") }
    }

    func stopLiveTopicSync() {
        liveSyncTimer?.invalidate()
        liveSyncTimer = nil
        if let appForegroundObserver {
            NotificationCenter.default.removeObserver(appForegroundObserver)
            self.appForegroundObserver = nil
        }
    }

    func isReadingNearBottomForLiveSync() -> Bool {
        let total = tableView.numberOfRows(inSection: 0)
        guard total > 0 else { return true }
        let threshold = TopicDetailPaginationPolicy.liveSyncNearBottomRows
        let maxVisible = tableView.indexPathsForVisibleRows?.map(\.row).max() ?? 0
        return maxVisible >= total - threshold
    }

    @MainActor
    func performLiveTopicSync(reason: String) async {
        guard viewModel.isReady, !viewModel.isJumping else { return }
        let autoAppend = isReadingNearBottomForLiveSync()
        let pending = await viewModel.syncLiveTopicStream(
            autoAppend: autoAppend,
            containerWidth: view.bounds.width
        )
        updateNewRepliesBanner(forcePending: pending)
        #if DEBUG
        if pending > 0 {
            print("[TopicDetail] live sync reason=\(reason) pending=\(pending) autoAppend=\(autoAppend)")
        }
        #endif
    }

    func updateNewRepliesBanner(forcePending: Int? = nil) {
        let count = forcePending ?? viewModel.pendingNewReplyCount
        let shouldShow = viewModel.isReady && count > 0
        let title: String
        if count <= 0 {
            title = ""
        } else if count == 1 {
            title = String(localized: "topic_detail.new_replies.one", defaultValue: "1 条新回复")
        } else {
            title = String(
                format: String(localized: "topic_detail.new_replies.many", defaultValue: "%lld 条新回复"),
                locale: .current,
                count
            )
        }

        var config = newRepliesBanner.configuration ?? .filled()
        config.title = title
        config.baseBackgroundColor = AppSettings.shared.themeStyle.accentColor
        newRepliesBanner.configuration = config

        let currentlyVisible = !newRepliesBanner.isHidden && newRepliesBanner.alpha > 0.01
        guard shouldShow != currentlyVisible else {
            if shouldShow {
                newRepliesBanner.isHidden = false
                newRepliesBanner.alpha = 1
            }
            return
        }

        if shouldShow {
            newRepliesBanner.isHidden = false
            view.bringSubviewToFront(newRepliesBanner)
            UIView.animate(withDuration: 0.22) {
                self.newRepliesBanner.alpha = 1
                self.newRepliesBanner.transform = .identity
            }
        } else {
            UIView.animate(withDuration: 0.18, animations: {
                self.newRepliesBanner.alpha = 0
                self.newRepliesBanner.transform = CGAffineTransform(translationX: 0, y: 8)
            }, completion: { _ in
                self.newRepliesBanner.isHidden = true
                self.newRepliesBanner.transform = .identity
            })
        }
    }

    func handleNewRepliesBannerTapped() {
        Task { @MainActor in
            let floor = await viewModel.consumePendingNewReplies(containerWidth: view.bounds.width)
            updateNewRepliesBanner()
            if let floor {
                jumpToFloor(floor)
            } else if viewModel.totalFloors > 0 {
                jumpToFloor(viewModel.totalFloors)
            }
        }
    }
}
